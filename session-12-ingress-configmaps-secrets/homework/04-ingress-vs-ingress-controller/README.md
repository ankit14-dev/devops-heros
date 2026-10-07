# Task 4 – Ingress vs Ingress Controller

**Author:** Ankit Kumar

The names sound like the same thing, but one is a **set of rules** and the other is the **software that enforces them**. This is my write-up of the difference.

---

## 1. What is an Ingress?

An **Ingress** is a Kubernetes **API object** (`networking.k8s.io/v1`) that describes how external **HTTP/HTTPS (Layer 7)** traffic should be routed to Services inside the cluster.

It can express:

- **Host-based routing** – `shop.example.com` → `shop-svc`, `api.example.com` → `api-svc`
- **Path-based routing** – `/api` → `api-svc`, `/` → `web-svc` (with `pathType`: `Prefix`, `Exact` or `ImplementationSpecific`)
- **TLS termination** – which hostnames use which certificate (stored in a `kubernetes.io/tls` Secret)
- **`ingressClassName`** – which controller should implement this Ingress
- an optional **default backend** for requests that match no rule

On its own it is just data stored in etcd, like a ConfigMap. Nothing listens on a port because of it.

## 2. What is an Ingress Controller?

An **Ingress Controller** is an actual **running application** (Pods, usually a Deployment or DaemonSet + a Service) that:

1. **watches** the API server for Ingress objects (and the Services/EndpointSlices/Secrets they reference),
2. **translates** them into configuration for a reverse proxy / load balancer,
3. **receives** the real traffic and proxies it to the backend Pods.

Common implementations:

| Controller | Data plane | Notes |
|---|---|---|
| ingress-nginx | NGINX | Kubernetes community project; what the minikube `ingress` addon installs. The project announced its retirement (best-effort maintenance ended March 2026), so new clusters should look at alternatives / Gateway API |
| Traefik | Traefik | Default in k3s; also supports Gateway API |
| HAProxy Ingress | HAProxy | High-performance L7 proxy |
| AWS Load Balancer Controller | AWS ALB | Creates a real ALB per Ingress (or group); no proxy Pods in the data path |
| GKE Ingress | Google Cloud HTTP(S) LB | Built in to GKE |
| Istio Ingress Gateway | Envoy | Part of the service mesh; also supports Kubernetes Ingress and Gateway API |

Kubernetes ships **no** controller by default – the cluster admin must install one.

---

## 3. Difference table

| | Ingress | Ingress Controller |
|---|---|---|
| What it is | API resource (YAML) | Running software (Pods) |
| Role | Declares routing **rules** | **Implements** the rules and carries traffic |
| Created by | App developer (`kubectl apply`) | Cluster admin (Helm, addon, manifest) |
| Count | Many – usually one per app/team | Usually one (or a few) per cluster |
| Handles traffic? | No | Yes |
| Built into Kubernetes? | Yes (API type) | No, must be installed |
| Selected via | `spec.ingressClassName` | Registers an `IngressClass` (e.g. `nginx`) |
| Analogy | The routing table / receptionist's instruction sheet | The receptionist who reads the sheet and directs visitors |

## 4. Why both are required

- **Ingress without a controller:** `kubectl apply` succeeds, `kubectl get ingress` shows the object, but the **ADDRESS column stays empty** and no request ever reaches the app. Nothing is reading the rules.
- **Controller without Ingress objects:** the proxy is running and reachable, but it has no rules, so every request gets the default backend (for ingress-nginx a `404 Not Found`).

The split is deliberate: developers write portable rules, and the platform team chooses the implementation (NGINX, cloud LB, Envoy...) without changing app manifests.

---

## 5. Examples

Enable a controller on minikube:

```bash
minikube addons enable ingress
kubectl get pods -n ingress-nginx
kubectl get ingressclass
```

<!-- REAL-OUTPUT: kubectl get pods -n ingress-nginx; kubectl get ingressclass -->

### 5.1 Path-based routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-paths
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2   # controller-specific annotation
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /api(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: api-svc
                port:
                  number: 80
          - path: /()(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: web-svc
                port:
                  number: 80
```

Simpler version without rewriting (the backend receives the full path):

```yaml
      paths:
        - path: /api
          pathType: Prefix
          backend: { service: { name: api-svc, port: { number: 80 } } }
        - path: /
          pathType: Prefix
          backend: { service: { name: web-svc, port: { number: 80 } } }
```

### 5.2 Host-based routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-hosts
spec:
  ingressClassName: nginx
  rules:
    - host: shop.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: shop-svc, port: { number: 80 } } }
    - host: api.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: api-svc, port: { number: 80 } } }
```

Testing without editing `/etc/hosts`:

```bash
curl -H "Host: shop.local" http://$(minikube ip)/
curl --resolve api.local:80:$(minikube ip) http://api.local/
```

### 5.3 TLS

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=shop.local"
kubectl create secret tls shop-tls --cert=tls.crt --key=tls.key
```

```yaml
spec:
  ingressClassName: nginx
  tls:
    - hosts: ["shop.local"]
      secretName: shop-tls          # Secret must be in the same namespace as the Ingress
  rules:
    - host: shop.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: shop-svc, port: { number: 80 } } }
```

```bash
curl -k --resolve shop.local:443:$(minikube ip) https://shop.local/
```

<!-- REAL-OUTPUT: kubectl get ingress (showing CLASS, HOSTS, ADDRESS, PORTS 80,443) and curl results -->
<!-- REAL-OUTPUT: kubectl describe ingress app-hosts (rules and backends) -->

---

## 6. Request flow

```text
 Browser: https://shop.local/cart
     |
     | DNS / Host header -> minikube IP or cloud LB
     v
 +------------------------------+
 | LoadBalancer / NodePort Svc  |   ingress-nginx-controller (namespace ingress-nginx)
 +--------------+---------------+
                v
 +------------------------------+      watches      +---------------------------+
 | Ingress Controller Pod       | <---------------- | Ingress objects (rules)   |
 | (NGINX: TLS termination,     |                   | Services, EndpointSlices, |
 |  match host + path)          |                   | TLS Secrets  (API server) |
 +--------------+---------------+                   +---------------------------+
                | host=shop.local, path=/  ->  shop-svc:80
                v
 +------------------------------+
 | shop-svc (ClusterIP)         |   ingress-nginx actually proxies straight to the
 +--------------+---------------+   Pod IPs from the EndpointSlices (skips kube-proxy)
                v
        shop Pods (10.244.x.x:8080)
```

---

## 7. Note: Gateway API, the successor

The **Gateway API** (`gateway.networking.k8s.io`, v1 GA since late 2023) is the newer, more expressive replacement for Ingress:

| Ingress | Gateway API |
|---|---|
| One object mixes infra + routing | Split by role: `GatewayClass` (infra provider) → `Gateway` (listeners, ports, TLS) → `HTTPRoute`/`GRPCRoute`/`TLSRoute`... (app routes) |
| HTTP/HTTPS only (officially) | HTTP, gRPC, TLS, TCP/UDP routes |
| Advanced features via vendor-specific **annotations** | Header matching, traffic splitting/weights, redirects, rewrites are part of the **spec** |
| Single namespace model | Cross-namespace routes with explicit permission (`ReferenceGrant`) |

The Ingress API itself is frozen (stable, not removed, but not getting new features). The same "API object + controller" idea still applies: a `Gateway` also does nothing without a Gateway controller (Envoy Gateway, Istio, Traefik, NGINX Gateway Fabric, cloud providers...).

---

## 8. Summary

- **Ingress** = the rules (YAML). **Ingress Controller** = the proxy that reads and enforces them.
- You need both: rules without a controller do nothing; a controller without rules routes nothing.
- `ingressClassName` connects an Ingress to a specific controller.
- For new designs, the Gateway API is the direction Kubernetes networking is going.
