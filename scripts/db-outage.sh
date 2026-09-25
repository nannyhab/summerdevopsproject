#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

export KUBECONFIG="${KUBECONFIG:-$PWD/kubeconfig}"
out=docs/evidence/after.md
prom=/api/v1/namespaces/monitoring/services/monitoring-kube-prometheus-prometheus:http-web/proxy

alert() {
  kubectl get --raw "$prom/api/v1/alerts" \
    | jq '[.data.alerts[] | select(.labels.alertname == "WebNoReadyPods") | {alertname: .labels.alertname, severity: .labels.severity, state, activeAt}]'
}

started="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
kubectl -n demo scale deployment/postgres --replicas=0 >/dev/null
start="$(date +%s)"
sleep 60

state=inactive
for _ in $(seq 1 24); do
  state="$(alert | jq -r '.[0].state // "inactive"')"
  [ "$state" = firing ] && break
  sleep 10
done
elapsed=$(( $(date +%s) - start ))
pods="$(kubectl -n demo get pods -l app=web)"
alert_json="$(alert)"

kubectl -n demo scale deployment/postgres --replicas=1 >/dev/null
kubectl -n demo rollout status deployment/postgres --timeout=180s >/dev/null
kubectl -n demo wait --for=condition=Ready pod -l app=web --timeout=180s >/dev/null

{
  echo
  echo "## Postgres scaled to zero: the no-ready-pods alert"
  echo
  echo "At $started Postgres was scaled to zero replicas with \`scripts/db-outage.sh\`. Every web pod's readiness check now fails, so no pod is ready. The \`WebNoReadyPods\` alert was **$state** ${elapsed} seconds later."
  echo
  echo "### kubectl get pods -l app=web"
  echo
  echo '```text'
  echo "$pods"
  echo '```'
  echo
  echo "### Alert as reported by Prometheus"
  echo
  echo '```json'
  echo "$alert_json"
  echo '```'
  echo
  echo "Postgres was then scaled back to one replica and both web pods became ready again."
} >> "$out"

echo "Alert state: $state after ${elapsed}s. Appended to $out"
[ "$state" = firing ]
