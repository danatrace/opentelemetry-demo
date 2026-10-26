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
SKIPPED_ONEAGENT=false

usage() {
  cat <<'EOF'
Build every repository Dockerfile and push the resulting images to Docker Hub.

Usage: ./build-and-push-dockerhub.sh [--dry-run] [--no-push] [--help]

Environment variables:
  DOCKERHUB_USERNAME     Docker Hub username (default: danatrace)
  DOCKERHUB_REPOSITORY   Docker Hub repository (default: opentelemetry-demo)
  IMAGE_TAG              Base tag used for every image (default: latest)

Log in first with: docker login --username "$DOCKERHUB_USERNAME"
Images use tags like <base-tag>-<service-name>.
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

image_for() {
  local dockerfile="$1"
  local relative_path="${dockerfile#"$ROOT_DIR"/}"
  local directory="${relative_path%/*}"
  local filename="${relative_path##*/}"
  local suffix=""

  case "$directory" in
    src/*)
      directory="${directory#src/}"
      ;;
    src-dt/*)
      directory="src-dt-${directory#src-dt/}"
      ;;
  esac

  if [[ "$filename" != Dockerfile ]]; then
    local filename_suffix="${filename#Dockerfile.}"
    if [[ "$filename_suffix" != "${directory##*/}" ]]; then
      suffix="-$filename_suffix"
    fi
  fi

  directory="${directory%/src}"
  local slug="${directory//\//-}${suffix}"
  slug="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')"
  printf '%s/%s:%s-%s' \
    "$DOCKERHUB_USERNAME" "$DOCKERHUB_REPOSITORY" "$IMAGE_TAG" "$slug"
}

context_for() {
  local dockerfile="$1"
  local relative_path="${dockerfile#"$ROOT_DIR"/}"

  case "$relative_path" in
    src-dt/consumer-service/Dockerfile)
      printf '%s' "$ROOT_DIR/src-dt/consumer-service"
      ;;
    src-dt/load-generator/Dockerfile)
      printf '%s' "$ROOT_DIR/src-dt/load-generator"
      ;;
    src-dt/cloud-backend/data-processing/src/Dockerfile)
      printf '%s' "$ROOT_DIR/src-dt/cloud-backend/data-processing/src"
      ;;
    src-dt/cloud-backend/processed-data-persistence/src/Dockerfile)
      printf '%s' "$ROOT_DIR/src-dt/cloud-backend/processed-data-persistence/src"
      ;;
    src-dt/cloud-backend/product-catalog-lambda-image/Dockerfile.*)
      printf '%s' "$ROOT_DIR/src-dt/cloud-backend/product-catalog-lambda-image"
      ;;
    *)
      printf '%s' "$ROOT_DIR"
      ;;
  esac
}

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
  local context="$2"
  local image="$3"
  shift 3

  local command=(docker buildx build --file "$dockerfile" --tag "$image")
  command+=("$@")
  if [[ "$PUSH_IMAGES" == true ]]; then
    command+=(--push)
  else
    command+=(--load)
  fi
  command+=("$context")

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

mapfile -t dockerfiles < <(
  find "$ROOT_DIR" -type f -name 'Dockerfile*' \
    -not -path "$ROOT_DIR/.git/*" \
    -not -path '*/node_modules/*' \
    -print | sort
)

if ((${#dockerfiles[@]} == 0)); then
  printf 'No Dockerfiles found under %s\n' "$ROOT_DIR" >&2
  exit 1
fi

oneagent_dockerfile=''
for dockerfile in "${dockerfiles[@]}"; do
  relative_path="${dockerfile#"$ROOT_DIR"/}"
  if [[ "$relative_path" == src-dt/cloud-backend/product-catalog-lambda-image/Dockerfile.oneagent ]]; then
    oneagent_dockerfile="$dockerfile"
    continue
  fi

  build_args=()
  case "$relative_path" in
    src/ad/Dockerfile|src/fraud-detection/Dockerfile|src/kafka/Dockerfile)
      build_arg_value="$(configured_build_arg OTEL_JAVA_AGENT_VERSION)"
      build_args+=(--build-arg "OTEL_JAVA_AGENT_VERSION=$build_arg_value")
      ;;
    src/currency/Dockerfile)
      build_arg_value="$(configured_build_arg OPENTELEMETRY_CPP_VERSION)"
      build_args+=(--build-arg "OPENTELEMETRY_CPP_VERSION=$build_arg_value")
      ;;
    test/tracetesting/Dockerfile)
      build_arg_value="$(configured_build_arg TRACETEST_IMAGE_VERSION)"
      build_args+=(--build-arg "TRACETEST_IMAGE_VERSION=$build_arg_value")
      ;;
  esac

  build_image "$dockerfile" "$(context_for "$dockerfile")" \
    "$(image_for "$dockerfile")" "${build_args[@]}"
done

if [[ -n "$oneagent_dockerfile" ]]; then
  oneagent_context="$(context_for "$oneagent_dockerfile")"
  missing_stages=()
  for stage in dev hardening prod; do
    if [[ ! -d "$oneagent_context/DynatraceOneAgentExtension/$stage" ]]; then
      missing_stages+=("$stage")
    fi
  done

  if ((${#missing_stages[@]})); then
    SKIPPED_ONEAGENT=true
    printf 'Skipping OneAgent stage images; missing generated layer assets for: %s\n' \
      "${missing_stages[*]}" >&2
    printf 'Download the OneAgent layer assets before rerunning this script.\n' >&2
  else
    server_dockerfile="$oneagent_context/Dockerfile.server"
    base_image="$(image_for "$server_dockerfile")"
    for stage in dev hardening prod; do
      image="${DOCKERHUB_USERNAME}/${DOCKERHUB_REPOSITORY}:$IMAGE_TAG-src-dt-cloud-backend-product-catalog-lambda-image-$stage"
      build_image "$oneagent_dockerfile" "$oneagent_context" "$image" \
        --build-context "base_image=docker-image://$base_image" \
        --build-arg "STAGE_NAME=$stage"
    done
  fi
fi

if [[ "$DRY_RUN" == true ]]; then
  printf 'Dry run listed %d image build(s) for %s/%s.\n' \
    "$BUILT_IMAGES" "$DOCKERHUB_USERNAME" "$DOCKERHUB_REPOSITORY"
elif [[ "$PUSH_IMAGES" == true ]]; then
  printf 'Built and pushed %d image(s) to %s/%s.\n' \
    "$BUILT_IMAGES" "$DOCKERHUB_USERNAME" "$DOCKERHUB_REPOSITORY"
else
  printf 'Built %d image(s) locally for %s/%s.\n' \
    "$BUILT_IMAGES" "$DOCKERHUB_USERNAME" "$DOCKERHUB_REPOSITORY"
fi

if [[ "$SKIPPED_ONEAGENT" == true ]]; then
  printf 'OneAgent stage images were skipped because their generated layer assets are missing.\n'
fi
