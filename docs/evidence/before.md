# Before the fix: one web pod cut off from the database

Captured 2026-09-25 06:17 UTC with `scripts/cut.sh before`.
Image: `958486868913.dkr.ecr.us-east-2.amazonaws.com/cluster-week/web:969f6e8`

The pod `web-65fcb799df-9mfdp` was labelled `chaos=cut`. The NetworkPolicy in `k8s/cut-one-pod.yaml` then blocked everything it sends except DNS, so it could no longer reach Postgres. The load pod kept calling `http://web/api` twice a second the whole time.

**The cut pod was never marked not ready. It stayed Ready for the whole 61 seconds.**

## Status codes in the 15 seconds before the cut

```text
  30 200
```

## Status codes in the 61 seconds after the cut

```text
  63 200
  58 500
```

## kubectl get pods -l app=web

```text
NAME                   READY   STATUS    RESTARTS   AGE
web-65fcb799df-9mfdp   1/1     Running   0          94s
web-65fcb799df-bh8q7   1/1     Running   0          94s
```

## Endpoint slice for the web service (address, ready flag, pod)

Kubernetes keeps a not-ready pod in the endpoint slice but flips its ready flag to false, and the Service only sends traffic to endpoints marked ready=true.

```text
10.42.0.5	ready=true	web-65fcb799df-bh8q7
10.42.1.3	ready=true	web-65fcb799df-9mfdp
```

## What this shows

About half of all requests failed, because the Service kept sending every other request to a pod that could not reach the database. Kubernetes had no idea anything was wrong: `/readyz` answered "ok" without checking anything, so the broken pod stayed Ready and stayed in the endpoint slice with `ready=true`. That readiness probe is the bug.
