#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -n "$(git status --porcelain -- app)" ]; then
  echo "app/ has uncommitted changes. Commit them first so the image tag matches the code." >&2
  exit 1
fi

region=us-east-2
repo_name=cluster-week/web
repo="$(aws ecr describe-repositories --region "$region" --repository-names "$repo_name" \
  --query 'repositories[0].repositoryUri' --output text)"
tag="$(git rev-parse --short HEAD)"
image="$repo:$tag"

aws ecr get-login-password --region "$region" \
  | docker login --username AWS --password-stdin "${repo%%/*}" >/dev/null

if aws ecr describe-images --region "$region" --repository-name "$repo_name" \
     --image-ids imageTag="$tag" >/dev/null 2>&1; then
  echo "$image is already in ECR, skipping the build." >&2
else
  docker build --platform linux/arm64 -t "$image" app >&2
  docker push "$image" >&2
fi

echo "$image"
