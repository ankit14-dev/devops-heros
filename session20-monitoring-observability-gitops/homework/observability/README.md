# Task 2 – Observability

**Author:** Ankit Kumar

## What is observability?

Observability is the ability to understand the **internal state** of a system by looking at the data it produces from the outside. If a system is observable, I can answer a new question about its behaviour ("why are only Android users in Mumbai seeing slow checkouts?") without shipping new code to collect more data.

That data is usually grouped into three **pillars**: metrics, logs and traces.

## The three pillars

### 1. Metrics

**What:** numeric measurements sampled over time and identified by a name and a set of labels.

**Data shape:** `name{labels} value @timestamp`, for example:

```
http_requests_total{method="GET", route="/api/orders", status="200"}  10423  @1759900000
node_memory_MemAvailable_bytes{instance="node-1"}                    2.1e9  @1759900000
```

**Metric types (Prometheus):** `counter` (only goes up: requests, errors), `gauge` (up and down: memory, queue length), `histogram` (bucketed observations: latency) and `summary`.

**Strengths:** cheap to store, fast to query, ideal for dashboards, trends and **alerts**.
**Limits:** aggregated, so they tell me *that* something is wrong, rarely *why*. High-cardinality labels (user IDs, request IDs) blow up storage.

**Tools:** Prometheus, Grafana Mimir / Thanos, CloudWatch Metrics, Datadog.

### 2. Logs

**What:** timestamped records of discrete events, written by applications and infrastructure.

**Data shape:** plain text or, better, **structured** (JSON) lines:

```json
{"ts":"2026-10-08T10:15:32Z","level":"error","service":"checkout","trace_id":"4bf92f35...","msg":"payment declined","order_id":"O-517"}
```

**Strengths:** the richest context: error messages, stack traces, business events, audit trails.
**Limits:** large volume, so expensive to store and index; hard to aggregate without structure.

**Tools:** Loki, Elasticsearch/OpenSearch (ELK/EFK), Fluent Bit / Fluentd, CloudWatch Logs.

### 3. Traces

**What:** the end-to-end path of a single request through a distributed system. A **trace** is a tree of **spans**. Each span is one unit of work (an HTTP call, a DB query) with a start time, a duration, attributes and a parent span. **Context propagation** (W3C `traceparent` header) carries the trace ID between services.

**Data shape:**

```
trace_id 4bf92f35...                                     total 820 ms
└─ api-gateway  GET /checkout                            820 ms
   ├─ auth-service  verify-token                          40 ms
   └─ checkout-service  create-order                     760 ms
      ├─ postgres  INSERT orders                          25 ms
      └─ payment-service  POST /charge                   700 ms   <- bottleneck
```

**Strengths:** show *where* time is spent and *which* service failed in a microservice call chain.
**Limits:** need instrumentation in every service; usually **sampled** to control cost.

**Tools:** OpenTelemetry (instrumentation), Jaeger, Grafana Tempo, Zipkin, AWS X-Ray.

### How the pillars work together

| | Metrics | Logs | Traces |
|---|---|---|---|
| Answers | Is something wrong? How much? | What exactly happened? | Where in the request path? |
| Data | Numbers + labels | Text/JSON events | Spans with timing and parent IDs |
| Volume / cost | Low | High | Medium (sampled) |
| Typical use | Dashboards, alerts, SLOs | Debugging, audit | Latency analysis, dependency maps |

A typical investigation: a **metric** alert fires (p95 latency high) → an **exemplar** or trace search finds slow **traces** → the trace ID leads to the matching **logs**. Putting `trace_id` into every log line is what makes this jump possible.

## Why observability is required

Modern systems are distributed: dozens of microservices, containers that live for minutes, autoscaling, managed cloud services. Failures are often partial and new every time.

| | Monitoring | Observability |
|---|---|---|
| Question | "Is the system working?" | "**Why** is it not working?" |
| Covers | **Known unknowns**: failure modes I predicted (disk full, CPU high) | **Unknown unknowns**: problems nobody predicted |
| Approach | Predefined dashboards and threshold alerts | Explore rich, correlated, high-context telemetry |
| Relationship | A subset of observability | Builds on monitoring |

Benefits:

- Lower **MTTD/MTTR** (mean time to detect/resolve).
- Measurable reliability via **SLIs/SLOs** and error budgets.
- Safer deployments: compare telemetry before and after a release.
- Capacity planning and cost optimization from real usage data.

## Common tools

| Tool | Pillar(s) | Description |
|------|-----------|-------------|
| **Prometheus** | Metrics | CNCF graduated; pull-based scraping, time-series DB, PromQL, Alertmanager |
| **Grafana** | Visualization | Dashboards and alerting over Prometheus, Loki, Tempo, CloudWatch and many other sources |
| **Loki** | Logs | Log aggregation that indexes only labels (not full text), so it's cheap; queried with LogQL |
| **ELK / EFK** | Logs | Elasticsearch + Logstash (or Fluentd/Fluent Bit) + Kibana; full-text search |
| **Jaeger** | Traces | CNCF graduated distributed tracing backend and UI |
| **Tempo** | Traces | Grafana's trace backend, stores traces in object storage, TraceQL |
| **OpenTelemetry** | All three | CNCF vendor-neutral standard: APIs, SDKs, OTLP protocol and the Collector |
| **Datadog** | All three | Commercial SaaS: APM, logs, metrics, RUM, security |
| **CloudWatch** | All three (AWS) | AWS-native metrics, logs, alarms, Container Insights; X-Ray / Application Signals for traces |

## Kubernetes observability

Kubernetes adds layers that all need visibility: **cluster → nodes → pods → containers → application**.

### Building blocks

| Component | What it provides |
|-----------|------------------|
| **metrics-server** | Lightweight, in-memory CPU/memory from the kubelet. Powers `kubectl top` and the **HPA**. Not for long-term storage |
| **kube-state-metrics** | Metrics about the *state of Kubernetes objects*: desired vs available replicas, pod phase, restarts, resource requests/limits |
| **node-exporter** | Host-level metrics from each node (CPU, memory, disk, network, filesystem). Runs as a DaemonSet |
| **cAdvisor** (in kubelet) | Per-container CPU, memory, network usage (`container_*` metrics) |
| **kube-prometheus-stack** | Helm chart bundling the Prometheus Operator, Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics, and ready-made dashboards/alerts. Uses `ServiceMonitor` / `PodMonitor` CRDs |
| **Fluent Bit** | DaemonSet log collector: tails `/var/log/containers/*.log`, adds pod metadata, ships to Loki/Elasticsearch/CloudWatch |
| **OpenTelemetry Collector** | Receives, processes and exports metrics, logs and traces (OTLP) to any backend; runs as an agent (DaemonSet) and/or gateway |

```bash
kubectl top nodes
kubectl top pods -A --sort-by=memory
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

<!-- REAL-OUTPUT: kubectl top / kube-prometheus-stack pods output -->

### What to measure: Golden signals, RED and USE

| Method | Applies to | Signals |
|--------|-----------|---------|
| **Four golden signals** (Google SRE) | User-facing services | **Latency**, **Traffic**, **Errors**, **Saturation** |
| **RED** (Tom Wilkie) | Request-driven services | **Rate**, **Errors**, **Duration** |
| **USE** (Brendan Gregg) | Resources (CPU, memory, disk, network) | **Utilization**, **Saturation**, **Errors** |

I use RED for my services and USE for nodes and other resources.

### PromQL examples

```promql
# CPU: cores used per pod (cAdvisor)
sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))

# CPU: node utilization % (node-exporter)
100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))

# Memory: working set per pod (what the OOM killer looks at)
sum by (namespace, pod) (container_memory_working_set_bytes{container!=""})

# Memory: node utilization %
100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)

# Requests (RED - rate): requests per second per service
sum by (service) (rate(http_requests_total[5m]))

# Errors (RED - errors): 5xx ratio
sum by (service) (rate(http_requests_total{status=~"5.."}[5m]))
  / sum by (service) (rate(http_requests_total[5m]))

# Duration (RED): p95 latency from a histogram
histogram_quantile(0.95, sum by (le, service) (rate(http_request_duration_seconds_bucket[5m])))

# Kubernetes state: containers restarting in the last hour
increase(kube_pod_container_status_restarts_total[1h]) > 0

# Deployments with fewer available replicas than desired
kube_deployment_spec_replicas != kube_deployment_status_replicas_available
```

`http_requests_total` and `http_request_duration_seconds` are the conventional names an instrumented app exposes; the exact names depend on the client library.

## What I learned

- Metrics tell me *that* something is wrong, traces tell me *where*, logs tell me *why*. The value comes from linking them (labels, trace IDs).
- Monitoring covers the failures I can predict; observability is for the ones I can't.
- In Kubernetes, metrics-server, kube-state-metrics and node-exporter answer different questions and are not substitutes for each other.
- OpenTelemetry keeps instrumentation vendor-neutral, so the backend can change later.
