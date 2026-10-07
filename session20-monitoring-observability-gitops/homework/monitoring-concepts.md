# Task 1 – Monitoring Concepts

**Author:** Ankit Kumar

Monitoring means continuously collecting and checking data about a system so that I know whether it's healthy and get notified when it isn't.

## Metrics

Numeric values recorded over time, with labels, e.g. `http_requests_total{status="500"}`. Prometheus **pulls** (scrapes) them from `/metrics` endpoints every few seconds and stores them as time series.

| Type | Behaviour | Example |
|------|-----------|---------|
| Counter | Only increases (resets on restart) | `http_requests_total` |
| Gauge | Goes up and down | `node_memory_MemAvailable_bytes` |
| Histogram | Counts observations in buckets | `http_request_duration_seconds_bucket` |

Counters are almost always queried with `rate()` or `increase()`, not as raw values.

## Logs

Timestamped event records (`stdout`/`stderr` in containers). Structured JSON logs with `level`, `service` and `trace_id` fields are much easier to filter. Logs explain **why** a metric changed. Typical stack: Fluent Bit or Promtail → Loki → Grafana.

## Alerts

An alert is a rule evaluated against metrics that notifies a human when a condition holds **for a period of time**. Prometheus evaluates the rules, and **Alertmanager** groups, deduplicates, silences and routes them (Slack, email, PagerDuty).

Good alerts are **actionable**, alert on **symptoms** users feel (errors, latency) rather than every cause, and use `for:` to avoid flapping.

```yaml
groups:
  - name: node-and-app
    rules:
      - alert: HighCPUUsage
        expr: 100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) > 80
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "CPU above 80% on {{ $labels.instance }}"
      - alert: HighMemoryUsage
        expr: 100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Memory above 90% on {{ $labels.instance }}"
      - alert: TargetDown
        expr: up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.job }} target {{ $labels.instance }} is down"
```

## CPU utilization

The percentage of time the CPU is busy (not idle). Sustained high CPU causes latency. In Kubernetes, a container that hits its CPU **limit** gets **throttled** (slowed down), not killed.

```promql
# Node CPU %
100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))
# Container CPU cores used
sum by (pod) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))
```

## Memory utilization

Memory in use vs total. Unlike CPU, memory can't be throttled: a container that exceeds its memory **limit** is **OOMKilled**, and a node under pressure evicts pods. On Linux, "free" memory is misleading because the page cache uses it, so `MemAvailable` is the right metric.

```promql
# Node memory %
100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
# Container working set (what limits and OOM decisions use)
sum by (pod) (container_memory_working_set_bytes{container!=""})
```

## Application health

- **Health endpoints**: the app exposes e.g. `/healthz` (process alive) and `/ready` (dependencies such as the DB reachable), returning `200` or `503`.
- **Liveness probe**: if it fails, the kubelet **restarts** the container (recovers from deadlocks).
- **Readiness probe**: if it fails, the pod is **removed from Service endpoints** but not restarted (warming up, dependency down).
- **Startup probe**: holds off liveness checks while a slow app starts.

```yaml
livenessProbe:
  httpGet: { path: /healthz, port: 8080 }
  initialDelaySeconds: 10
  periodSeconds: 10
readinessProbe:
  httpGet: { path: /ready, port: 8080 }
  periodSeconds: 5
```

**SLI / SLO / SLA**:

| Term | Meaning | Example |
|------|---------|---------|
| SLI (indicator) | A measured value | % of requests answered successfully in under 300 ms |
| SLO (objective) | Internal target for the SLI | 99.9% over 30 days (error budget ≈ 43 min) |
| SLA (agreement) | Contract with customers, with penalties | 99.5% monthly uptime |

```promql
# Availability SLI: share of non-5xx requests over 30 days
sum(rate(http_requests_total{status!~"5.."}[30d])) / sum(rate(http_requests_total[30d]))
```

## Hands-on demo

<!-- REAL-OUTPUT: monitoring demo -->
