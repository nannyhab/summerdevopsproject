#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

gh variable set NODE_COUNT --body 0
run_tf_workflow
rm -f kubeconfig ansible/inventory.ini

aws_env
alive="$(aws ec2 describe-instances --region us-east-2 \
  --filters Name=tag:Project,Values=cluster-week \
            Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped \
  --query 'Reservations[].Instances[].InstanceId' --output text)"
if [ -n "$alive" ]; then
  echo "These cluster-week instances are still alive: $alive" >&2
  exit 1
fi
echo "No cluster-week instances are running."
