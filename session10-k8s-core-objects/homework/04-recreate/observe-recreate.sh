#!/bin/bash
# Observe the Recreate strategy: sample pod status + HTTP responses while updating v1 -> v2.
# Usage: ./observe-recreate.sh   (run after deployment-v1.yaml + service.yaml are applied)
URL="http://$(minikube ip):30040"

( for i in $(seq 1 16); do
    echo "--- $(date +%T.%2N)"
    kubectl get pods -l app=app-recreate -L version --no-headers 2>&1 \
      | awk '{printf "   %-32s %-18s %s\n", $1, $3, $6}'
    sleep 0.4
  done > /tmp/recreate-pods.log ) &
P=$!
( for i in $(seq 1 30); do
    r=$(curl -s -m 1 "$URL" | grep -oE 'v[0-9]' | head -1)
    echo "$(date +%T.%2N) ${r:-DOWN}"
    sleep 0.3
  done > /tmp/recreate-curl.log ) &
C=$!

sleep 1
kubectl apply -f deployment-v2.yaml
wait $P $C

echo; echo "===== Pod timeline (old pods are gone BEFORE new ones start) ====="
awk '/^---/{t=$2; next} {print t, $0}' /tmp/recreate-pods.log | uniq -f1 | head -24
echo; echo "===== HTTP responses during the update ====="
awk '{print $2}' /tmp/recreate-curl.log | uniq -c
