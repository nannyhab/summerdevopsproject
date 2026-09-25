#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-}"
if [ "$mode" != before ] && [ "$mode" != after ]; then
  echo "Usage: scripts/cut.sh before|after" >&2
  exit 1
fi
export KUBECONFIG="${KUBECONFIG:-$PWD/kubeconfig}"
out="docs/evidence/$mode.md"
title=Before
[ "$mode" = after ] && title=After
mkdir -p docs/evidence

k() { kubectl -n demo "$@"; }
codes() { k logs load --since="$1" | awk 'NF == 2 {print $2}' | sort | uniq -c | sort -rn; }
ready() { k get pod "$pod" -o jsonpath='{.status.containerStatuses[0].ready}'; }
slice() {
  k get endpointslice -l kubernetes.io/service-name=web \
    -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\t"}ready={.conditions.ready}{"\t"}{.targetRef.name}{"\n"}{end}'
}

k apply -f k8s/cut-one-pod.yaml >/dev/null
k apply -f k8s/load.yaml >/dev/null
k wait --for=condition=Ready pod/load --timeout=120s >/dev/null
k wait --for=condition=Ready pod -l app=web --timeout=120s >/dev/null
sleep 15

pod="$(k get pods -l app=web -o jsonpath='{.items[0].metadata.name}')"
image="$(k get deployment web -o jsonpath='{.spec.template.spec.containers[0].image}')"
baseline="$(codes 15s)"
captured="$(date -u '+%Y-%m-%d %H:%M UTC')"

k label pod "$pod" chaos=cut --overwrite >/dev/null
start="$(date +%s)"
unready_after=""
while [ $(( $(date +%s) - start )) -lt 60 ]; do
  if [ -z "$unready_after" ] && [ "$(ready)" = false ]; then
    unready_after=$(( $(date +%s) - start ))
    [ "$mode" = after ] && break
  fi
  sleep 1
done

pods="$(k get pods -l app=web)"
endpoints="$(slice)"

if [ "$mode" = after ]; then
  sleep 30
  window=$(( $(date +%s) - start ))
  settled="$(codes 30s)"
  during="$(codes "${window}s")"
else
  window=$(( $(date +%s) - start ))
  during="$(codes "${window}s")"
fi

k label pod "$pod" chaos- >/dev/null

if [ -n "$unready_after" ]; then
  verdict="The cut pod was marked not ready ${unready_after} seconds after the cut."
else
  verdict="The cut pod was never marked not ready. It stayed Ready for the whole ${window} seconds."
fi

{
  echo "# $title the fix: one web pod cut off from the database"
  echo
  echo "Captured $captured with \`scripts/cut.sh $mode\`."
  echo "Image: \`$image\`"
  echo
  echo "The pod \`$pod\` was labelled \`chaos=cut\`. The NetworkPolicy in \`k8s/cut-one-pod.yaml\` then blocked everything it sends except DNS, so it could no longer reach Postgres. The load pod kept calling \`http://web/api\` twice a second the whole time."
  echo
  echo "**$verdict**"
  echo
  echo "## Status codes in the 15 seconds before the cut"
  echo
  echo '```text'
  echo "$baseline"
  echo '```'
  echo
  echo "## Status codes in the ${window} seconds after the cut"
  echo
  echo '```text'
  echo "$during"
  echo '```'
  if [ "$mode" = after ]; then
    echo
    echo "## Status codes in the last 30 seconds, once the cut pod was out of rotation"
    echo
    echo '```text'
    echo "$settled"
    echo '```'
  fi
  echo
  echo "## kubectl get pods -l app=web"
  echo
  echo '```text'
  echo "$pods"
  echo '```'
  echo
  echo "## Endpoint slice for the web service (address, ready flag, pod)"
  echo
  echo "Kubernetes keeps a not-ready pod in the endpoint slice but flips its ready flag to false, and the Service only sends traffic to endpoints marked ready=true."
  echo
  echo '```text'
  echo "$endpoints"
  echo '```'
} > "$out"

echo "Wrote $out"
