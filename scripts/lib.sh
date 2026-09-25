#!/usr/bin/env bash

aws_env() {
  local creds
  if ! creds="$(aws configure export-credentials --format env 2>/dev/null)"; then
    echo "Your AWS session is missing or expired. Run: aws login" >&2
    exit 1
  fi
  eval "$creds"
}

ssh_key_ready() {
  ssh-keygen -y -P "" -f "$HOME/.ssh/id_ed25519" >/dev/null 2>&1 && return 0
  ssh-add -l >/dev/null 2>&1 && return 0
  echo "Your SSH key is locked. Run: ssh-add --apple-use-keychain ~/.ssh/id_ed25519" >&2
  exit 1
}

run_tf_workflow() {
  local before id=""
  before="$(gh run list --workflow terraform.yml --limit 1 --json databaseId --jq '.[0].databaseId // 0')"
  gh workflow run terraform.yml --ref main
  for _ in $(seq 1 30); do
    id="$(gh run list --workflow terraform.yml --event workflow_dispatch --limit 5 --json databaseId \
      --jq "[.[] | select(.databaseId > $before)] | .[0].databaseId // empty")"
    [ -n "$id" ] && break
    sleep 3
  done
  if [ -z "$id" ]; then
    echo "The terraform workflow did not start." >&2
    exit 1
  fi
  echo "Waiting for terraform run $id"
  gh run watch "$id" --exit-status --interval 15 >/dev/null
  echo "Terraform run $id finished"
}
