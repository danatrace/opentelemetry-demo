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

usage() {
  cat <<'EOF'
Continue the interrupted Docker Hub image run with only its remaining images.

Usage: ./continue-dockerhub-push.sh [--dry-run] [--no-push] [--help]

Environment variables:
  DOCKERHUB_USERNAME     Docker Hub username (default: danatrace)
  DOCKERHUB_REPOSITORY   Docker Hub repository (default: opentelemetry-demo)
  IMAGE_TAG              Base tag used for every image (default: latest)
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

configured_build_arg() {
  local name="$1"
  local value="${!name:-}"

  if [[ -z "$value" && -f "$ROOT_DIR/.env" ]]; then
    value="$(awk -F= -v key="$name" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$ROOT_DIR/.env")"
  fi

  if [[ -z "$value" ]]; then
    printf 'Missing required build argument: %s (set it in the environment or %s/.env)\n' \
      "$name" "$ROOT_DIR" >&2
    return 1
  fi

  printf '%s' "$value"
}

build_image() {
  local dockerfile="$1"
  local image_name="$2"
  shift 2

  local image="${DOCKERHUB_USERNAME}/${DOCKERHUB_REPOSITORY}:${IMAGE_TAG}-${image_name}"
  local command=(docker buildx build --file "$ROOT_DIR/$dockerfile" --tag "$image")
  command+=("$@")
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
    printf 'Building and pushing %s\n' "$image"
    "${command[@]}"
  fi
}

build_image src/quote/Dockerfile quote
build_image src/recommendation/Dockerfile recommendation
build_image src/recommendation/genproto/Dockerfile recommendation-genproto
build_image src/shipping/Dockerfile shipping
tracetest_version="$(configured_build_arg TRACETEST_IMAGE_VERSION)"
build_image test/tracetesting/Dockerfile test-tracetesting \
  --build-arg "TRACETEST_IMAGE_VERSION=$tracetest_version"
