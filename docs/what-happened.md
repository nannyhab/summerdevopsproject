# What happened

A running log of the build, one short paragraph per milestone, written for someone new to this.

## 1. Stopped the servers from being replaced by surprise

The servers boot from the "current" Ubuntu image, which Canonical updates every few days. Terraform would treat a newer image as a reason to throw away and rebuild both servers the next time the pipeline ran. I added a `lifecycle { ignore_changes = [ami] }` block so a running server keeps the image it started with, and a brand new server still gets the latest one. Because this is an infrastructure change, it went through a pull request: GitHub Actions ran `terraform plan` on the PR, and once it passed I merged it, which ran `terraform apply` on main.

## 2. Session scripts

Every work session starts with `scripts/up.sh` and ends with `scripts/down.sh`, so the servers only cost money while I'm using them. `up.sh` tells GitHub my current IP address (the firewall only lets that address in), asks for two servers, runs the Terraform pipeline and waits for it, then reads the server addresses from Terraform and hands them to Ansible to set up Kubernetes. `down.sh` asks for zero servers, runs the pipeline again, and then checks with AWS directly that nothing is left running. The step-by-step explanation is in [scripts.md](scripts.md).
