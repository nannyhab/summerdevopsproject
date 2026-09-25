#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

image="${1:?Usage: scripts/deploy.sh <image>}"
export KUBECONFIG="${KUBECONFIG:-$PWD/kubeconfig}"

kubectl apply -f k8s/namespace.yaml
if ! kubectl -n demo get secret db >/dev/null 2>&1; then
  kubectl -n demo create secret generic db --from-literal=password="$(openssl rand -hex 24)"
fi
kubectl apply -f k8s/postgres.yaml
sed "s|WEB_IMAGE_PLACEHOLDER|$image|" k8s/web.yaml | kubectl apply -f -

kubectl -n demo rollout status deployment/postgres --timeout=180s
kubectl -n demo rollout status deployment/web --timeout=180s
