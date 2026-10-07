#!/bin/bash
# Generate realistic API traffic (reads, writes, a few 404s) against the TaskBoard ingress.
URL=${1:-http://taskboard.192.168.49.2.nip.io}
DURATION=${2:-300}
end=$((SECONDS + DURATION))
while [ $SECONDS -lt $end ]; do
  for i in $(seq 1 10); do curl -s -o /dev/null "$URL/api/tasks" & done
  curl -s -o /dev/null "$URL/api/tasks/stats"
  curl -s -o /dev/null "$URL/api/tasks/999999"            # 404
  curl -s -o /dev/null -X POST "$URL/api/tasks" -H 'Content-Type: application/json' -d '{"title":"load-test task"}'
  wait
done
