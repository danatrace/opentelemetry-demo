#!/usr/bin/env bash
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-danatrace}"
DOCKERHUB_REPOSITORY="${DOCKERHUB_REPOSITORY:-opentelemetry-demo}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
PUSH_IMAGE=true
DRY_RUN=false

usage() {
  cat <<'EOF'
Build and push only the Kafka image to Docker Hub.

Usage: ./build-and-push-kafka.sh [--dry-run] [--no-push] [--help]

Environment variables:
  DOCKERHUB_USERNAME     Docker Hub username (default: danatrace)
  DOCKERHUB_REPOSITORY   Docker Hub repository (default: opentelemetry-demo)
  IMAGE_TAG              Base tag used for the image (default: latest)

Log in first with: docker login --username "$DOCKERHUB_USERNAME"
The resulting image tag is <base-tag>-kafka.
EOF
}

while (($#)); do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      ;;
    --no-push)
      PUSH_IMAGE=false
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ ! "$DOCKERHUB_USERNAME/$DOCKERHUB_REPOSITORY" =~ ^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)?$ ]]; then
  printf 'Invalid Docker Hub image repository: %s/%s\n' \
    "$DOCKERHUB_USERNAME" "$DOCKERHUB_REPOSITORY" >&2
  exit 2
fi

if [[ ! "$IMAGE_TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]]; then
  printf 'Invalid base image tag: %s\n' "$IMAGE_TAG" >&2
  exit 2
fi

if [[ "$DRY_RUN" != true ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    printf 'Required command not found: docker\n' >&2
    exit 1
  fi
  if ! docker buildx version >/dev/null 2>&1; then
    printf 'Docker Buildx is required. Install or enable the Docker Buildx plugin.\n' >&2
    exit 1
  fi
fi

OTEL_JAVA_AGENT_VERSION="${OTEL_JAVA_AGENT_VERSION:-}"
if [[ -z "$OTEL_JAVA_AGENT_VERSION" && -f "$ROOT_DIR/.env" ]]; then
  OTEL_JAVA_AGENT_VERSION="$(awk -F= '$1 == "OTEL_JAVA_AGENT_VERSION" { sub(/^[^=]*=/, ""); print; exit }' "$ROOT_DIR/.env")"
fi
if [[ -z "$OTEL_JAVA_AGENT_VERSION" ]]; then
  printf 'Missing required build argument: OTEL_JAVA_AGENT_VERSION (set it in the environment or %s/.env)\n' \
    "$ROOT_DIR" >&2
  exit 1
fi

image="${DOCKERHUB_USERNAME}/${DOCKERHUB_REPOSITORY}:${IMAGE_TAG}-kafka"
command=(docker buildx build
  --file "$ROOT_DIR/src/kafka/Dockerfile"
  --tag "$image"
  --build-arg "OTEL_JAVA_AGENT_VERSION=$OTEL_JAVA_AGENT_VERSION"
)
if [[ "$PUSH_IMAGE" == true ]]; then
  command+=(--push)
else
  command+=(--load)
fi
command+=("$ROOT_DIR")

if [[ "$DRY_RUN" == true ]]; then
  printf 'Would run:'
  printf ' %q' "${command[@]}"
  printf '\n'
elif [[ "$PUSH_IMAGE" == true ]]; then
  printf 'Building and pushing %s\n' "$image"
  "${command[@]}"
  printf 'Built and pushed %s.\n' "$image"
else
  printf 'Building %s locally\n' "$image"
  "${command[@]}"
  printf 'Built %s locally.\n' "$image"
fi