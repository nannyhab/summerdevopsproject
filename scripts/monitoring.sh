#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

export KUBECONFIG="${KUBECONFIG:-$PWD/kubeconfig}"
chart_version=91.5.2
prom=/api/v1/namespaces/monitoring/services/monitoring-kube-prometheus-prometheus:http-web/proxy

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "$chart_version" --namespace monitoring --create-namespace \
  --values monitoring/values.yaml --wait --timeout 10m
kubectl apply -f monitoring/servicemonitor.yaml -f monitoring/rules.yaml

up=0
for _ in $(seq 1 40); do
  up="$(kubectl get --raw "$prom/api/v1/targets?state=active" 2>/dev/null \
    | jq '[.data.activeTargets[] | select(.labels.namespace == "demo" and .labels.service == "web" and .health == "up")] | length' \
    || echo 0)"
  [ "$up" -ge 2 ] && break
  sleep 15
done

echo "Web targets Prometheus is scraping successfully: $up"
kubectl get --raw "$prom/api/v1/rules" \
  | jq -r '.data.groups[] | select(.name == "web") | .rules[] | "Rule loaded: \(.name) (\(.state))"'
[ "$up" -ge 2 ]
