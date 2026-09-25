# What each script does

The scripts have no comments on purpose. This page explains them in the order you run them. All of them start by moving to the repo root, and they stop at the first command that fails (`set -euo pipefail`).

## scripts/lib.sh (shared helpers)

- `aws_env` turns your `aws login` session into environment variables that Terraform can read. If the session has expired, it tells you to run `aws login` and stops.
- `ssh_key_ready` checks that Ansible can use `~/.ssh/id_ed25519` without a password prompt. If the key is locked, it tells you to run `ssh-add --apple-use-keychain ~/.ssh/id_ed25519`.
- `run_tf_workflow` presses the "Run workflow" button on the Terraform pipeline (`gh workflow run`). It notes the newest run ID first, so it can pick out the run it just started, then waits for that run and fails if the run fails.

## scripts/up.sh (start a work session)

1. Checks the AWS session and the SSH key before anything costs money.
2. Looks up your public IP address and stores it as the `MY_IP` secret. The firewall only allows SSH and the Kubernetes API from that address.
3. Sets `NODE_COUNT` to 2 and runs the pipeline, which creates two servers.
4. Reads the Terraform outputs (public IPs, private IPs, ECR address) and writes `ansible/inventory.ini`. The first server goes in the `server` group, the rest in `agents`.
5. Runs the Ansible playbook, which installs Kubernetes (k3s) and saves a `kubeconfig` file in the repo root.
6. Waits until every server has joined and reports Ready, then prints them.

`kubeconfig` and `inventory.ini` are in `.gitignore` because they hold addresses and credentials.

## scripts/down.sh (end a work session)

1. Sets `NODE_COUNT` to 0 and runs the pipeline, which deletes the servers.
2. Deletes the now-useless `kubeconfig` and inventory.
3. Asks EC2 directly for any instance tagged `Project=cluster-week` that isn't terminated. If it finds one, it prints the ID and exits with an error, so you know money is still being spent.

The teardown only needs GitHub, so it still works if your AWS session has expired. Only the final check needs AWS.

## scripts/push.sh (build and upload the app image)

1. Refuses to continue if anything in `app/` isn't committed. The image tag is the commit hash, so it must match the code exactly.
2. Logs Docker in to ECR with a temporary token from the AWS CLI.
3. ECR tags are immutable (a tag can never point at a different image), so if this commit's tag is already there it skips the build.
4. Otherwise it builds for `linux/arm64` (the servers are ARM-based Graviton machines) and pushes.
5. Prints the full image name, for example `…amazonaws.com/cluster-week/web:2f6667e`.

## scripts/deploy.sh <image>

1. Creates the `demo` namespace.
2. Creates a random database password as a Kubernetes Secret, only if one doesn't exist yet. The password is never printed or saved in a file.
3. Applies Postgres, then the web app with the image name filled in.
4. Waits until both are running and ready.

## scripts/monitoring.sh

1. Installs the kube-prometheus-stack Helm chart (Prometheus, Alertmanager, kube-state-metrics and node-exporter) at a pinned version into the `monitoring` namespace, using `monitoring/values.yaml`. That file turns off Grafana and the scrape jobs for control-plane parts that k3s doesn't expose, and keeps memory requests small because each server only has 2 GiB.
2. Applies the ServiceMonitor (tells Prometheus to scrape the web app's `/metrics`) and the alert rules.
3. Waits until Prometheus reports both web pods as scrape targets that are up, and lists the loaded rules.

It talks to Prometheus through the Kubernetes API (`kubectl get --raw …/proxy/…`), so no extra ports need opening.

## scripts/cut.sh before|after

This is the experiment that proves the bug and the fix.

1. Applies the `cut-one-pod` NetworkPolicy. It only affects pods labelled `chaos=cut`, blocking everything they send except DNS.
2. Starts the `load` pod, which calls `http://web/api` twice a second and logs the time and HTTP status code of every answer.
3. Records 15 seconds of normal traffic, then labels one web pod `chaos=cut`, which cuts it off from Postgres.
4. Checks every second whether Kubernetes has marked that pod not ready.
5. Writes `docs/evidence/before.md` or `after.md` with the status code counts, `kubectl get pods`, and the endpoint slice (the list of pod addresses the Service sends traffic to, each with a ready flag).
6. Removes the label so the pod recovers.

## scripts/db-outage.sh

Scales Postgres to zero, waits a minute, then asks Prometheus every 10 seconds whether the `WebNoReadyPods` alert is firing. It appends the result to `docs/evidence/after.md` and brings Postgres back.
