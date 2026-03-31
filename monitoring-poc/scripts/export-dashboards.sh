#!/bin/bash

GRAFANA_URL="http://localhost:3000"
GRAFANA_AUTH="admin:changeme123"
DASHBOARD_DIR=~/monitoring-poc/dashboards

declare -A DASHBOARDS=(
  ["dashboard-pod-health.json"]="ad2rl89"
  ["dashboard-log-monitor.json"]="adj6zlr"
)

for filename in "${!DASHBOARDS[@]}"; do
  uid=${DASHBOARDS[$filename]}
  echo "Exporting $filename (uid: $uid)..."
  curl -s -u "$GRAFANA_AUTH" \
    "$GRAFANA_URL/api/dashboards/uid/$uid" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d['dashboard'], indent=2))" \
    > "$DASHBOARD_DIR/$filename"
  echo "Done: $DASHBOARD_DIR/$filename"
done

echo "All dashboards exported."
