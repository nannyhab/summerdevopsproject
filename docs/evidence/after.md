# After the fix: one web pod cut off from the database

Captured 2026-09-25 06:21 UTC with `scripts/cut.sh after`.
Image: `958486868913.dkr.ecr.us-east-2.amazonaws.com/cluster-week/web:e766196`

The pod `web-7f75984d6-6httg` was labelled `chaos=cut`. The NetworkPolicy in `k8s/cut-one-pod.yaml` then blocked everything it sends except DNS, so it could no longer reach Postgres. The load pod kept calling `http://web/api` twice a second the whole time.

**The cut pod was marked not ready 6 seconds after the cut.**

## Status codes in the 15 seconds before the cut

```text
  30 200
```

## Status codes in the 37 seconds after the cut

```text
  71 200
   3 500
```

## Status codes in the last 30 seconds, once the cut pod was out of rotation

```text
  60 200
```

## kubectl get pods -l app=web

```text
NAME                  READY   STATUS    RESTARTS   AGE
web-7f75984d6-6httg   0/1     Running   0          33s
web-7f75984d6-hwnxf   1/1     Running   0          40s
```

## Endpoint slice for the web service (address, ready flag, pod)

Kubernetes keeps a not-ready pod in the endpoint slice but flips its ready flag to false, and the Service only sends traffic to endpoints marked ready=true.

```text
10.42.0.7	ready=true	web-7f75984d6-hwnxf
10.42.1.10	ready=false	web-7f75984d6-6httg
```

## Postgres scaled to zero: the no-ready-pods alert

At 2026-09-25 06:22:25 UTC Postgres was scaled to zero replicas with `scripts/db-outage.sh`. Every web pod's readiness check now fails, so no pod is ready. The `WebNoReadyPods` alert was **firing** 60 seconds later.

### kubectl get pods -l app=web

```text
NAME                  READY   STATUS    RESTARTS   AGE
web-7f75984d6-6httg   0/1     Running   0          2m10s
web-7f75984d6-hwnxf   0/1     Running   0          2m17s
```

### Alert as reported by Prometheus

```json
[
  {
    "alertname": "WebNoReadyPods",
    "severity": "critical",
    "state": "firing",
    "activeAt": "2026-09-25T06:22:38.961619327Z"
  }
]
```

Postgres was then scaled back to one replica and both web pods became ready again.

## What this shows

With `/readyz` actually opening a database connection (two-second timeout, 503 on failure), Kubernetes noticed the cut pod within 6 seconds, flipped it to `ready=false` in the endpoint slice and stopped sending it traffic. Only 3 requests failed during those seconds. Every request after that succeeded. When the whole database went away, both pods went not ready and the `WebNoReadyPods` alert fired, so a person would be told instead of users silently getting errors.
