#!/bin/bash
# Fixes for the 5 faults injected by break.sh (each one is the minimal, correct fix)
set -e
NS=taskboard-lab

# 1) image typo -> roll back the frontend Deployment to its last good ReplicaSet
kubectl -n $NS rollout undo deploy/lab-frontend

# 2) password rotation was only half done -> finish it properly:
#    set the NEW secret value inside PostgreSQL, then restart the backend so it reads it
NEW=$(kubectl -n $NS get secret lab-db -o jsonpath='{.data.postgres-password}' | base64 -d)
kubectl -n $NS exec lab-postgres-0 -- psql -U taskboard -d taskboard -c "ALTER USER taskboard PASSWORD '$NEW';"
kubectl -n $NS rollout restart deploy/lab-backend

# 3) Service selector typo -> restore the label the pods really have
kubectl -n $NS patch svc lab-backend --type merge -p '{"spec":{"selector":{"app.kubernetes.io/component":"backend"}}}'

# 4) Ingress -> point /api at the Service port that exists (8000)
kubectl -n $NS patch ingress lab --type json \
  -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/port/number","value":8000}]'

# 5) HPA -> target the real Deployment
kubectl -n $NS patch hpa lab-backend --type merge -p '{"spec":{"scaleTargetRef":{"name":"lab-backend"}}}'
