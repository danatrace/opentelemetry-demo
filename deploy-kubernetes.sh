#!/usr/bin/env bash
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$ROOT_DIR/charts/astroshop"
RELEASE="${RELEASE:-astroshop}"
NAMESPACE="${NAMESPACE:-otel-demo}"

for command in helm kubectl sudo; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

KUBECONFIG_FILE="${KUBECONFIG:-$HOME/.kube/config}"
kubectl_sudo() {
  sudo env KUBECONFIG="$KUBECONFIG_FILE" kubectl "$@"
}

KUBE_CONTEXT="${KUBE_CONTEXT:-$(kubectl_sudo config current-context)}"
: "${DT_ENDPOINT:?Set DT_ENDPOINT to your Dynatrace OTLP endpoint}"
: "${DT_API_TOKEN:?Set DT_API_TOKEN to a Dynatrace API token with ingest permissions}"

printf 'Deploying %s to namespace %s on context %s\n' \
  "$RELEASE" "$NAMESPACE" "$KUBE_CONTEXT"

kubectl_sudo --context "$KUBE_CONTEXT" create namespace "$NAMESPACE" \
  --dry-run=client -o yaml \
  | kubectl_sudo --context "$KUBE_CONTEXT" apply -f -

SECRET_ENV_FILE="$(mktemp)"
trap 'rm -f "$SECRET_ENV_FILE"' EXIT
printf 'DT_ENDPOINT=%s\nDT_API_TOKEN=%s\n' \
  "$DT_ENDPOINT" "$DT_API_TOKEN" > "$SECRET_ENV_FILE"
kubectl_sudo create secret generic dt-credentials \
  --namespace "$NAMESPACE" \
  --from-env-file="$SECRET_ENV_FILE" \
  --dry-run=client -o yaml \
  | kubectl_sudo --context "$KUBE_CONTEXT" apply -f -

helm dependency update "$CHART_DIR"
helm upgrade --install "$RELEASE" "$CHART_DIR" \
  --kube-context "$KUBE_CONTEXT" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --wait \
  --timeout 15m

kubectl_sudo --context "$KUBE_CONTEXT" -n "$NAMESPACE" get pods,services