#!/usr/bin/env bash
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-danatrace}"
DOCKERHUB_REPOSITORY="${DOCKERHUB_REPOSITORY:-opentelemetry-demo}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
PUSH_IMAGES=true
DRY_RUN=false
BUILT_IMAGES=0

usage() {
  cat <<'EOF'
Build and push only the frontend images to Docker Hub.

Usage: ./build-and-push-frontend.sh [--dry-run] [--no-push] [--help]

Environment variables:
  DOCKERHUB_USERNAME     Docker Hub username (default: danatrace)
  DOCKERHUB_REPOSITORY   Docker Hub repository (default: opentelemetry-demo)
  IMAGE_TAG              Base tag used for every image (default: latest)

Log in first with: docker login --username "$DOCKERHUB_USERNAME"
EOF
}

while (($#)); do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      ;;
    --no-push)
      PUSH_IMAGES=false
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

build_image() {
  local dockerfile="$1"
  local image_name="$2"
  local image="${DOCKERHUB_USERNAME}/${DOCKERHUB_REPOSITORY}:${IMAGE_TAG}-${image_name}"
  local command=(docker buildx build --file "$ROOT_DIR/$dockerfile" --tag "$image")

  if [[ "$PUSH_IMAGES" == true ]]; then
    command+=(--push)
  else
    command+=(--load)
  fi
  command+=("$ROOT_DIR")

  if [[ "$DRY_RUN" == true ]]; then
    printf 'Would run:'
    printf ' %q' "${command[@]}"
    printf '\n'
  else
    printf 'Building %s\n' "$image"
    "${command[@]}"
  fi
  BUILT_IMAGES=$((BUILT_IMAGES + 1))
}

build_image src/frontend/Dockerfile frontend
build_image dynatrace/Dockerfile.frontend dynatrace-frontend

if [[ "$DRY_RUN" == true ]]; then
  printf 'Dry run listed %d frontend image build(s) for %s/%s.\n' \
    "$BUILT_IMAGES" "$DOCKERHUB_USERNAME" "$DOCKERHUB_REPOSITORY"
elif [[ "$PUSH_IMAGES" == true ]]; then
  printf 'Built and pushed %d frontend image(s) to %s/%s.\n' \
    "$BUILT_IMAGES" "$DOCKERHUB_USERNAME" "$DOCKERHUB_REPOSITORY"
else
  printf 'Built %d frontend image(s) locally for %s/%s.\n' \
    "$BUILT_IMAGES" "$DOCKERHUB_USERNAME" "$DOCKERHUB_REPOSITORY"
fi