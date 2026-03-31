#!/bin/bash
# only export the dashboard that it's title with "CDP"



GRAFANA_URL="http://localhost:3000"
GRAFANA_AUTH="admin:changeme123"
DASHBOARD_DIR=/home/lndata-daas/monitoring-study/monitoring-poc/dashboard

python3 << 'PYEOF'
import json, os, urllib.request, base64

GRAFANA_URL = "http://localhost:3000"
GRAFANA_AUTH = "admin:changeme123"
DASHBOARD_DIR = "/home/lndata-daas/monitoring-study/monitoring-poc/dashboard"

def fetch(url):
    req = urllib.request.Request(url)
    creds = base64.b64encode(GRAFANA_AUTH.encode()).decode()
    req.add_header("Authorization", f"Basic {creds}")
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())

def remove_datasource_uid(obj):
    if isinstance(obj, dict):
        if 'type' in obj and 'uid' in obj and obj['type'] in ('prometheus', 'loki'):
            del obj['uid']
        for v in obj.values():
            remove_datasource_uid(v)
    elif isinstance(obj, list):
        for v in obj:
            remove_datasource_uid(v)

dashboards = fetch(f"{GRAFANA_URL}/api/search?type=dash-db")
cdp_dashboards = [d for d in dashboards if 'CDP' in d.get('title', '')]

for d in cdp_dashboards:
    uid = d['uid']
    title = d['title'].lower().replace(' - ', '-').replace(' ', '-').replace('/', '-')
    filename = f"dashboard-{title}.json"
    filepath = os.path.join(DASHBOARD_DIR, filename)
    print(f"Exporting {filename} (uid: {uid})...")
    detail = fetch(f"{GRAFANA_URL}/api/dashboards/uid/{uid}")
    dash = detail['dashboard']
    remove_datasource_uid(dash)
    with open(filepath, 'w') as f:
        json.dump(dash, f, indent=2)
    print(f"Done: {filepath}")

print("All dashboards exported.")
PYEOF
