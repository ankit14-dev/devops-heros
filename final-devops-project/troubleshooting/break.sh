#!/bin/bash
# Final troubleshooting challenge: break a healthy TaskBoard release in 5 different ways at once.
# Usage: ./break.sh   (expects: helm install lab ../helm/taskboard -n taskboard-lab ... to be healthy)
set -e
NS=taskboard-lab

# 1) Frontend rolled out with a typo in the image tag
kubectl -n $NS set image deploy/lab-frontend frontend=ghcr.io/ankit14-dev/taskboard-frontend:v1.0.0-typo

# 2) Someone "rotated" the DB password in the Secret but PostgreSQL still uses the old one
kubectl -n $NS patch secret lab-db -p '{"stringData":{"postgres-password":"rotated-but-not-in-postgres"}}'
kubectl -n $NS rollout restart deploy/lab-backend

# 3) Backend Service selector typo
kubectl -n $NS patch svc lab-backend --type merge -p '{"spec":{"selector":{"app.kubernetes.io/component":"backed"}}}'

# 4) Ingress points /api at the wrong Service port
kubectl -n $NS patch ingress lab --type json \
  -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/port/number","value":8080}]'

# 5) HPA target references a deployment name that does not exist
kubectl -n $NS patch hpa lab-backend --type merge -p '{"spec":{"scaleTargetRef":{"name":"lab-backend-v2"}}}'

echo "5 faults injected into $NS"
