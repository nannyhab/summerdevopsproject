# What happened

A running log of the build, one short paragraph per milestone, written for someone new to this.

## 1. Stopped the servers from being replaced by surprise

The servers boot from the "current" Ubuntu image, which Canonical updates every few days. Terraform would treat a newer image as a reason to throw away and rebuild both servers the next time the pipeline ran. I added a `lifecycle { ignore_changes = [ami] }` block so a running server keeps the image it started with, and a brand new server still gets the latest one. Because this is an infrastructure change, it went through a pull request: GitHub Actions ran `terraform plan` on the PR, and once it passed I merged it, which ran `terraform apply` on main.

## 2. Session scripts

Every work session starts with `scripts/up.sh` and ends with `scripts/down.sh`, so the servers only cost money while I'm using them. `up.sh` tells GitHub my current IP address (the firewall only lets that address in), asks for two servers, runs the Terraform pipeline and waits for it, then reads the server addresses from Terraform and hands them to Ansible to set up Kubernetes. `down.sh` asks for zero servers, runs the pipeline again, and then checks with AWS directly that nothing is left running. The step-by-step explanation is in [scripts.md](scripts.md).

## 3. Two servers running Kubernetes

`up.sh` created two small ARM servers and Ansible turned them into a k3s cluster, a lightweight version of Kubernetes. One node is the server (it runs the control plane, the part that makes decisions) and the other is an agent that joins it with a secret token. Ansible also installed security updates, switched off password and root logins over SSH, and set up a timer that fetches a fresh 12-hour login for the private image registry (ECR) every six hours. Running the playbook a second time reported `changed=0` on both nodes. That proves it is idempotent: running it again only fixes what is missing and never redoes work.

## 4. The app, its image and the deployment

The app is a small Flask web service. `/api` asks Postgres for the current time, `/healthz` says the process is alive, `/readyz` is supposed to say whether it can do useful work, and `/metrics` counts responses by status code for Prometheus. I tested it locally in Docker first. `push.sh` built an ARM image, tagged it with the commit hash and pushed it to ECR. `deploy.sh` created a random database password as a Kubernetes Secret, started Postgres and two copies of the web app, and waited until they were ready.

## 5. Breaking it on purpose

A NetworkPolicy (a firewall rule inside the cluster) cut one web pod off from the database, while a load pod called the API twice a second. About half the requests failed with 500 errors, yet Kubernetes still showed both pods as Ready and kept sending traffic to the broken one. The reason is that `/readyz` said "ok" without checking anything. The proof is in [evidence/before.md](evidence/before.md).

## 6. Watching it with Prometheus

I installed kube-prometheus-stack with Helm. It bundles Prometheus (collects and stores numbers over time), Alertmanager (handles alerts), kube-state-metrics (turns Kubernetes objects into numbers) and node-exporter (server stats). Grafana and the scrape jobs for control-plane parts that k3s hides were switched off, so everything fits in 2 GiB per server. A ServiceMonitor tells Prometheus to scrape the app's `/metrics`, and a PrometheusRule adds two alerts: one when more than 5% of API requests fail, and one when no web pod is ready. Prometheus confirmed both web pods as healthy scrape targets.
