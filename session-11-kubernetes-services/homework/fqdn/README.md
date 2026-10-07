# Task 3 – FQDN in Kubernetes

**Author:** Ankit Kumar

---

## 1. What is an FQDN?

A **Fully Qualified Domain Name** is a domain name that specifies the *complete* path from a host up to the DNS root, so it can't be ambiguous.

```text
www.example.com.
 |     |     |  └── root (the trailing dot)
 |     |     └───── top-level domain (TLD)
 |     └─────────── second-level domain
 └───────────────── host label
```

- A name is made of **labels** separated by dots. Each label is max 63 characters; the full name is max 253 characters.
- Strictly, an FQDN ends with a **trailing dot** (`www.example.com.`), which means "this is absolute, don't append any search domain". Browsers and most tools hide the dot, but it matters a lot inside Kubernetes (see `ndots` below).
- A name *without* the full path (e.g. `backend`) is a **relative / short name**; the resolver completes it using search domains.

---

## 2. Kubernetes Service DNS

Every Kubernetes cluster runs a DNS server (**CoreDNS**, Service name `kube-dns` in `kube-system`). It watches the API and automatically creates records for every Service:

| Service type | Record type | What it returns |
|---|---|---|
| ClusterIP / NodePort / LoadBalancer | `A` / `AAAA` | The Service's ClusterIP |
| Headless (`clusterIP: None`) | `A` / `AAAA` | The IPs of all **Ready** Pods behind it |
| ExternalName | `CNAME` | The external name, e.g. `db.example.com` |
| Any Service with **named** ports | `SRV` | Port number + target name |

### Naming convention

```text
<service>.<namespace>.svc.<cluster-domain>

backend   .   dev    .  svc  .  cluster.local
   |           |         |          |
 Service    Namespace  "this is   cluster domain
  name                 a Service" (default cluster.local)
```

The cluster domain is set on the kubelet (`clusterDomain`) and in the CoreDNS `kubernetes` plugin. It's `cluster.local` by default, including on minikube.

---

## 3. Namespace-based DNS

A short name like `backend` works **only from Pods in the same namespace**. The reason is the Pod's `/etc/resolv.conf`, which the kubelet writes for every Pod (with the default `dnsPolicy: ClusterFirst`):

```text
search dev.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

- `nameserver` – the ClusterIP of the `kube-dns` Service.
- `search` – suffixes to try for relative names. The first one contains **the Pod's own namespace** (`dev` here).
- `ndots:5` – if the name has **fewer than 5 dots**, try it with each search suffix *before* trying it as-is.

So from a Pod in namespace `dev`:

| Name I use | Expanded/tried as | Works? |
|---|---|---|
| `backend` | `backend.dev.svc.cluster.local` | Yes, if `backend` is in `dev` |
| `backend.prod` | `backend.prod.dev.svc...` (miss), then `backend.prod.svc.cluster.local` | Yes – reaches `prod` |
| `backend.prod.svc` | ... then `backend.prod.svc.cluster.local` | Yes |
| `backend.prod.svc.cluster.local` | 4 dots < 5, so search suffixes tried first, then as-is | Yes (a few wasted lookups) |
| `backend.prod.svc.cluster.local.` | Absolute – no search list | Yes, single lookup |
| `backend` (but it lives in `prod`) | `backend.dev.svc...`, `backend.svc...`, ... all NXDOMAIN | **No** |

Rule I'll follow: same namespace → short name; cross namespace → at least `<svc>.<ns>`, ideally the full FQDN in config files.

---

## 4. Pod DNS records

### 4.1 Plain Pods

Pods get an `A` record based on their IP with dots replaced by dashes:

```text
<pod-ip-dashed>.<namespace>.pod.<cluster-domain>
10-244-1-5.default.pod.cluster.local   ->  10.244.1.5
```

This is rarely useful by itself (you already need to know the IP), and it depends on the CoreDNS `pods` option (`pods insecure` in the default Corefile).

### 4.2 StatefulSet Pods (via a headless Service)

This is the useful one. A StatefulSet with `serviceName: mysql` and a headless Service `mysql` gives every Pod a stable name:

```text
<pod-name>.<headless-service>.<namespace>.svc.<cluster-domain>
mysql-0.mysql.default.svc.cluster.local
mysql-1.mysql.default.svc.cluster.local
```

The name stays the same even when `mysql-0` is rescheduled and its IP changes. The same mechanism works for any Pod that sets `spec.hostname` and `spec.subdomain` matching a headless Service.

### 4.3 SRV records

For each **named port** on a Service, CoreDNS creates an SRV record:

```text
_<port-name>._<protocol>.<service>.<namespace>.svc.<cluster-domain>
_http._tcp.backend.dev.svc.cluster.local   ->  0 100 80 backend.dev.svc.cluster.local.
```

For a headless Service the SRV answer contains one entry per Pod (e.g. `mysql-0.mysql.default.svc.cluster.local`). Clients that understand SRV (some DBs, gRPC resolvers, Kafka/Zookeeper setups) can discover port + host from DNS alone.

---

## 5. Pod-to-Service communication walkthrough

Scenario: `frontend` Pod in namespace `dev` calls `http://backend:80/api`.

1. **App resolves `backend`.** The libc/Go resolver reads `/etc/resolv.conf`. `backend` has 0 dots (< 5), so it first asks for `backend.dev.svc.cluster.local`.
2. **Query goes to `10.96.0.10:53`** (the `kube-dns` ClusterIP). kube-proxy rules DNAT it to one of the CoreDNS Pods.
3. **CoreDNS answers** from its in-memory view of Services: `backend.dev.svc.cluster.local A 10.96.120.15` (TTL 30s by default).
4. **App opens TCP to `10.96.120.15:80`.** No Pod owns this IP; kube-proxy's iptables/IPVS rules on the frontend's node DNAT it to a Ready backend Pod, e.g. `10.244.1.7:8080`.
5. **CNI delivers** the packet to that Pod (same node or across nodes), and the reply is un-NATed on the way back.

```text
frontend Pod (dev)
   | 1. "backend" -> backend.dev.svc.cluster.local ?
   v
kube-dns Service 10.96.0.10:53 --> CoreDNS Pod
   | 2. A 10.96.120.15
   v
frontend --> 10.96.120.15:80 --(kube-proxy DNAT)--> backend Pod 10.244.1.7:8080
```

---

## 6. Example Kubernetes FQDNs

| FQDN | What it is |
|---|---|
| `kubernetes.default.svc.cluster.local` | The API server's Service in `default` |
| `kube-dns.kube-system.svc.cluster.local` | The cluster DNS Service (CoreDNS) |
| `backend.dev.svc.cluster.local` | My `backend` Service in namespace `dev` |
| `frontend.prod.svc.cluster.local` | Same app name in a different namespace – different record |
| `mysql.default.svc.cluster.local` | Headless Service → returns all MySQL Pod IPs |
| `mysql-0.mysql.default.svc.cluster.local` | One specific StatefulSet Pod |
| `_http._tcp.backend.dev.svc.cluster.local` | SRV record for the `http` named port |
| `10-244-1-5.default.pod.cluster.local` | Pod `A` record for IP 10.244.1.5 |
| `ingress-nginx-controller.ingress-nginx.svc.cluster.local` | The ingress controller Service (minikube addon) |
| `metrics-server.kube-system.svc.cluster.local` | Metrics API backend used by HPA |

---

## 7. Hands-on tests from a Pod

```bash
# Two namespaces with the same service name to prove namespace scoping
kubectl create namespace dev
kubectl create namespace prod
kubectl -n dev  create deployment backend --image=nginx
kubectl -n dev  expose deployment backend --port=80
kubectl -n prod create deployment backend --image=nginx
kubectl -n prod expose deployment backend --port=80

# Test pod in "dev" (busybox:1.28 has a reliable nslookup)
kubectl -n dev run dnstest --image=busybox:1.28 --restart=Never -- sleep 3600

kubectl -n dev exec dnstest -- cat /etc/resolv.conf
kubectl -n dev exec dnstest -- nslookup backend
kubectl -n dev exec dnstest -- nslookup backend.prod
kubectl -n dev exec dnstest -- nslookup backend.prod.svc.cluster.local
kubectl -n dev exec dnstest -- nslookup kubernetes.default
kubectl -n dev exec dnstest -- nslookup kube-dns.kube-system.svc.cluster.local
kubectl -n dev exec dnstest -- wget -qO- http://backend.prod.svc.cluster.local | head -n 4
```

<!-- REAL-OUTPUT: cat /etc/resolv.conf from the dnstest pod -->
<!-- REAL-OUTPUT: nslookup tests from a pod (backend, backend.prod, full FQDN, kubernetes.default, kube-dns.kube-system) with matching kubectl get svc -A ClusterIPs -->

SRV lookup (needs `dig`, e.g. the `registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3` image):

```bash
kubectl -n dev run dnsutils --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 --restart=Never -- sleep 3600
kubectl -n dev exec dnsutils -- dig +short SRV _http._tcp.backend.dev.svc.cluster.local
```

(This only returns a record if the Service port is **named**, e.g. `name: http`.)

<!-- REAL-OUTPUT: dig SRV result for a Service with a named port -->

Cleanup:

```bash
kubectl delete namespace dev prod
```

---

## 8. Key points

- FQDN = complete, absolute name; the trailing dot makes it truly absolute.
- Service FQDN = `<service>.<namespace>.svc.cluster.local`.
- Short names resolve only within the same namespace because of the `search` line; cross-namespace needs at least `<svc>.<ns>`.
- `ndots:5` means most names go through the search list first – using a full FQDN with a trailing dot avoids extra lookups.
- StatefulSet Pods get stable DNS via a headless Service: `<pod>.<svc>.<ns>.svc.cluster.local`.
