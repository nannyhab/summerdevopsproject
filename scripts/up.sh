#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

aws_env
ssh_key_ready

my_ip="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
gh secret set MY_IP --body "$my_ip/32"
gh variable set NODE_COUNT --body 2
run_tf_workflow

[ -d infra/.terraform ] || terraform -chdir=infra init -input=false -lockfile=readonly >/dev/null
outputs="$(terraform -chdir=infra output -json)"
count="$(jq '.node_public_ips.value | length' <<<"$outputs")"
if [ "$count" -lt 1 ]; then
  echo "Terraform reports no nodes." >&2
  exit 1
fi

jq -r '
  .node_public_ips.value as $pub
  | .node_private_ips.value as $priv
  | "[server]",
    "k3s-server ansible_host=\($pub[0]) private_ip=\($priv[0])",
    "",
    "[agents]",
    (range(1; $pub | length) | "k3s-agent-\(.) ansible_host=\($pub[.]) private_ip=\($priv[.])"),
    "",
    "[all:vars]",
    "ecr_registry=\(.ecr_url.value | split("/")[0])",
    "aws_region=us-east-2"
' <<<"$outputs" > ansible/inventory.ini

(cd ansible && ansible-playbook site.yml)

export KUBECONFIG="$PWD/kubeconfig"
for _ in $(seq 1 60); do
  [ "$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')" = "$count" ] && break
  sleep 5
done
kubectl wait --for=condition=Ready node --all --timeout=300s >/dev/null
kubectl get nodes -o wide
