# Task 4 – CoreDNS

**Author:** Ankit Kumar

---

## 1. What is CoreDNS?

**CoreDNS** is a flexible DNS server written in Go. It's a single binary whose behaviour is defined entirely by a chain of **plugins** configured in a file called the **Corefile**. It's a **CNCF graduated** project (graduated in 2019) and is the default cluster DNS in Kubernetes.

In a cluster it runs as:

- a **Deployment** `coredns` in `kube-system` (usually 2 replicas; 1 on minikube),
- exposed by a **Service** that is still called **`kube-dns`** (for backward compatibility) with a fixed ClusterIP, typically `10.96.0.10`,
- configured by the **ConfigMap** `coredns` in `kube-system`.

```bash
kubectl -n kube-system get deploy coredns
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
kubectl -n kube-system get svc kube-dns
```

<!-- REAL-OUTPUT: kubectl -n kube-system get deploy,pods,svc for coredns / kube-dns -->

---

## 2. Why Kubernetes uses CoreDNS

| | kube-dns (old) | CoreDNS |
|---|---|---|
| Architecture | 3 containers per Pod: `kubedns`, `dnsmasq`, `sidecar` | 1 container, 1 binary |
| Extensibility | Hard to change | Plugin chain – enable/disable features in the Corefile |
| Language / security | Mixed (dnsmasq in C) | Go, memory-safe, smaller attack surface |
| Status | Deprecated | GA in Kubernetes 1.11, default since 1.13 |

Other reasons: built-in Prometheus metrics, live config reload, caching, stub domains and rewrites without extra components, and it's a general-purpose DNS server, not something Kubernetes-only.

---

## 3. How service discovery works

The **`kubernetes` plugin** is what makes CoreDNS "Kubernetes-aware":

1. On startup it opens **watches** on the API server for **Services**, **EndpointSlices** and **Namespaces** (and Pods if `pods verified` is used).
2. It keeps an in-memory cache of these objects, updated in near real time as things change.
3. When a query for `*.svc.cluster.local` arrives, it answers **from that cache**, building the record on the fly:
   - normal Service → ClusterIP,
   - headless Service → Ready Pod IPs from the EndpointSlices,
   - ExternalName → CNAME,
   - named ports → SRV.

So there is no "registration" step: create a Service with `kubectl apply` and the DNS name works within seconds.

---

## 4. How DNS queries are resolved

### 4.1 The path of a query

```text
 App in Pod (namespace dev)
    |  getaddrinfo("backend")
    v
 /etc/resolv.conf   nameserver 10.96.0.10, search dev.svc.cluster.local svc.cluster.local cluster.local, ndots:5
    |
    v  UDP/TCP 53 to 10.96.0.10 (kube-dns Service)
 kube-proxy DNAT  ------------------------------->  CoreDNS Pod (10.244.0.3:53)
                                                         |
                                     plugin chain: errors -> cache -> kubernetes -> forward
                                                         |
                    cluster.local name? ---- yes ----> answer from API cache
                                                         |
                                                         no
                                                         v
                                    forward to upstream (node's /etc/resolv.conf, e.g. 8.8.8.8)
```

### 4.2 ndots / search expansion walkthrough

With `ndots:5`, any name with fewer than 5 dots is tried with every search suffix **before** being tried as-is. Each step is usually two queries (A and AAAA).

**Example 1: `backend` from namespace `dev`** (0 dots)

| # | Query | Result |
|---|---|---|
| 1 | `backend.dev.svc.cluster.local` | **Found** – stop |

**Example 2: `google.com` from namespace `dev`** (1 dot)

| # | Query | Result |
|---|---|---|
| 1 | `google.com.dev.svc.cluster.local` | NXDOMAIN |
| 2 | `google.com.svc.cluster.local` | NXDOMAIN |
| 3 | `google.com.cluster.local` | NXDOMAIN |
| 4 | `google.com` | **Found** (forwarded upstream) |

(If the node's own resolv.conf adds extra search domains, they appear here as well.) That's 4 round-trips × A/AAAA = up to 8 queries for one external name. Ways to reduce it:

- use a trailing dot: `google.com.`
- lower `ndots` for that Pod:

```yaml
spec:
  dnsConfig:
    options:
      - name: ndots
        value: "2"
```

---

## 5. CoreDNS configuration (Corefile)

```bash
kubectl -n kube-system get configmap coredns -o yaml
```

<!-- REAL-OUTPUT: kubectl -n kube-system get configmap coredns -o yaml (minikube's version, which also has a hosts block for host.minikube.internal) -->

A typical kubeadm-style Corefile:

```text
.:53 {
    errors
    health {
       lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30
    loop
    reload
    loadbalance
}
```

| Plugin | What it does |
|---|---|
| `.:53` | Server block: serve the root zone (all names) on port 53 |
| `errors` | Log errors to stdout (shows up in `kubectl logs`) |
| `health` | HTTP `:8080/health` for the liveness probe; `lameduck 5s` keeps answering 5s during shutdown |
| `ready` | HTTP `:8181/ready` for the readiness probe – ready once all plugins are ready |
| `kubernetes` | Answers `cluster.local` and reverse (PTR) zones from the API; `pods insecure` enables Pod A records; `fallthrough` passes unknown reverse lookups to the next plugin; `ttl 30` sets record TTL |
| `prometheus :9153` | Exposes metrics (`coredns_dns_requests_total`, latency, cache hits...) |
| `forward . /etc/resolv.conf` | Anything not answered above goes to the upstream resolvers from the **node's** resolv.conf |
| `cache 30` | Cache answers up to 30 seconds |
| `loop` | Detects forwarding loops (e.g. upstream pointing back to CoreDNS) and stops the process instead of looping forever |
| `reload` | Re-reads the Corefile when the ConfigMap changes (takes ~1–2 min to propagate) |
| `loadbalance` | Randomizes the order of A/AAAA records (round-robin DNS) |

Note: the order of plugins in the file doesn't decide execution order – CoreDNS has a fixed compile-time order – but readability-wise this is the standard layout.

### 5.1 Custom examples

Stub domain – send `corp.internal` to a company DNS server, and add a static host entry:

```text
corp.internal:53 {
    errors
    cache 30
    forward . 10.0.0.53
}

.:53 {
    ...
    hosts {
       192.168.49.1 host.minikube.internal
       10.0.0.25    legacy-db.example.com
       fallthrough
    }
    kubernetes cluster.local in-addr.arpa ip6.arpa { ... }
    forward . /etc/resolv.conf
    ...
}
```

Apply with `kubectl -n kube-system edit configmap coredns`; the `reload` plugin picks it up (or `kubectl -n kube-system rollout restart deploy coredns` to apply immediately).

---

## 6. Troubleshooting DNS – my checklist

**Step 1 – Is CoreDNS running and healthy?**

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50
```

Look for `CrashLoopBackOff`, `[FATAL] plugin/loop: Loop ... detected`, or `i/o timeout` to upstream.

**Step 2 – Does the Service have endpoints?**

```bash
kubectl -n kube-system get svc kube-dns
kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns
```

No endpoints = CoreDNS Pods are not Ready.

**Step 3 – Test from inside a Pod.**

```bash
kubectl run dnsutils --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 --restart=Never -- sleep 3600
kubectl exec dnsutils -- nslookup kubernetes.default
kubectl exec dnsutils -- nslookup google.com
kubectl exec dnsutils -- dig @10.96.0.10 backend.default.svc.cluster.local
```

If `kubernetes.default` works but `google.com` fails → upstream/forward problem. If both fail → CoreDNS or network path problem.

<!-- REAL-OUTPUT: nslookup kubernetes.default and google.com from the dnsutils pod -->

**Step 4 – Check the Pod's resolv.conf.**

```bash
kubectl exec dnsutils -- cat /etc/resolv.conf
```

`nameserver` must equal the `kube-dns` ClusterIP. If the Pod uses `hostNetwork: true`, set `dnsPolicy: ClusterFirstWithHostNet`, otherwise it gets the node's resolver.

**Step 5 – Turn on query logging** by adding `log` to the `.:53` block, then watch:

```bash
kubectl -n kube-system logs -f -l k8s-app=kube-dns
```

Remove it afterwards – it's noisy.

**Step 6 – Common causes**

| Symptom | Likely cause | Fix |
|---|---|---|
| All lookups time out from one namespace | A **NetworkPolicy** with default-deny egress blocks **UDP/TCP 53** to `kube-system` | Allow egress to `k8s-app: kube-dns` on port 53 UDP+TCP |
| `NXDOMAIN` for a Service that exists | **Wrong namespace** – short name used across namespaces | Use `<svc>.<ns>` or the full FQDN |
| `NXDOMAIN` | Typo / Service not created / wrong cluster domain | `kubectl get svc -A`, check name |
| External names slow (seconds) | `ndots:5` search expansion, plus AAAA queries | Trailing dot, lower `ndots`, NodeLocal DNSCache |
| External names fail, internal OK | Upstream DNS unreachable, or `loop` detected | Check node `/etc/resolv.conf`, set `forward . 8.8.8.8` explicitly |
| Intermittent failures under load | Too few CoreDNS replicas, conntrack races on UDP | Scale CoreDNS, NodeLocal DNSCache |
| Headless Service returns nothing | No Ready Pods (readiness probe failing) | Fix the Pods / probe |

```bash
kubectl exec dnsutils -- nc -vz -u 10.96.0.10 53   # basic reachability check (if nc is available)
kubectl get networkpolicy -A
```

Cleanup:

```bash
kubectl delete pod dnsutils
```

---

## 7. Summary

- CoreDNS = plugin-based DNS server; runs as `coredns` Deployment behind the `kube-dns` Service in `kube-system`.
- The `kubernetes` plugin watches Services/EndpointSlices and answers `*.cluster.local` from memory; everything else is `forward`ed upstream and `cache`d.
- Pods find it via `/etc/resolv.conf`; `search` + `ndots:5` explain why short names work and why external lookups can be slow.
- Troubleshoot top-down: CoreDNS Pods → kube-dns endpoints → test Pod → resolv.conf → logs → NetworkPolicy/upstream.
