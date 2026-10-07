#!/bin/bash
# Print HPA status + replica count every 15s for the given number of minutes (default 4).
MIN=${1:-4}
printf "%-9s %-22s %-9s %s\n" TIME "TARGETS(cpu)" REPLICAS PODS-READY
for i in $(seq 1 $((MIN * 4))); do
  t=$(kubectl get hpa hpa-demo -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}')
  r=$(kubectl get hpa hpa-demo -o jsonpath='{.status.currentReplicas}')
  ready=$(kubectl get deploy hpa-demo -o jsonpath='{.status.readyReplicas}')
  printf "%-9s %-22s %-9s %s\n" "$(date +%T)" "${t:-<unknown>}%/50%" "$r" "${ready:-0}"
  sleep 15
done
