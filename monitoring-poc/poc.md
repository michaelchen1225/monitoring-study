# AKS Monitoring Stack Deployment Guide

> Grafana + Loki + Alloy + Prometheus on AKS

---

## Quick Access

| Item | Value |
| :--- | :--- |
| Grafana URL | http://40.115.204.157:3000/ |
| Username | `admin` |
| Password | `changeme123` |

---

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│               AKS Cluster                   │
│                                             │
│  cdp / rabbitmq-system namespace            │
│  ┌──────────┐                               │
│  │   Pods   │──logs──► Alloy (DaemonSet)    │
│  └──────────┘               │               │
│                             ▼               │
│                     Loki (PVC 2Gi)          │
│                             │               │
│                             ▼               │
│                    Grafana (PVC 2Gi)        │
│                             ▲               │
│                    Prometheus               │
│                  (kube-state-metrics,       │
│                   node-exporter)            │
└─────────────────────────────────────────────┘
```

| Component | Role | Notes |
| :--- | :--- | :--- |
| **Alloy** | Log collector | DaemonSet on every node. Collects logs from `cdp` and `rabbitmq-system` namespaces and pushes to Loki. |
| **Loki** | Log storage | Stores logs in PVC. Indexes by label (namespace, pod) without parsing content. 7-day retention. |
| **Prometheus** | Metrics collection | kube-prometheus-stack. Scrapes cluster metrics via kube-state-metrics and node-exporter. |
| **Grafana** | Visualization | Queries Loki and Prometheus. Runs alert rule evaluation every minute. |

---

## Repository Structure

```
monitoring-study/
└── monitoring-poc/
    ├── values/
    │   ├── loki-values.yaml
    │   ├── alloy-values.yaml
    │   ├── grafana-values.yaml
    │   └── prometheus-values.yaml
    ├── dashboard/
    │   ├── dashboard-cdp-pod-health.json
    │   └── dashboard-cdp-log-monitor.json
    └── scripts/
        ├── export-dashboards.sh
        ├── import-dashboards.sh
        └── setup-grafana.sh
```

---

## Phase 1: Prerequisites

### Step 1: Create Namespace

```bash
kubectl create namespace monitoring
```

### Step 2: Add Helm Repos

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### Step 3: Clone Repository

```bash
git clone https://github.com/michaelchen1225/monitoring-study.git ~/monitoring-study
cd ~/monitoring-study/monitoring-poc
```

### Step 4: Set GitHub Token (for pushing changes)

```bash
echo 'export GITHUB_TOKEN=your_token_here' >> ~/.bashrc
source ~/.bashrc
```

---

## Phase 2: Install Components

All commands should be run from `~/monitoring-study/monitoring-poc`.

### Step 5: Install Loki

```bash
helm install loki grafana/loki \
  --namespace monitoring \
  --values values/loki-values.yaml
```

Verify:

```bash
kubectl get pods -n monitoring | grep loki
```

### Step 6: Install Alloy

```bash
helm install alloy grafana/alloy \
  --namespace monitoring \
  --values values/alloy-values.yaml
```

Alloy collects logs from `cdp` and `rabbitmq-system` namespaces and forwards to Loki.

### Step 7: Install Prometheus

```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values values/prometheus-values.yaml
```

Verify the Prometheus service name:

```bash
kubectl get svc -n monitoring | grep prometheus
```

Expected: `prometheus-kube-prometheus-prometheus` on port `9090`.

### Step 8: Install Grafana

```bash
bash scripts/setup-grafana.sh
```

`setup-grafana.sh` installs Grafana via Helm. Loki and Prometheus are pre-configured as datasources in `grafana-values.yaml` with fixed UIDs:

| Datasource | UID |
| :--- | :--- |
| Loki | `loki` |
| Prometheus | `prometheus` |

No manual datasource setup required.

### Step 9: Access Grafana

```bash
kubectl port-forward \
  --address 0.0.0.0 \
  -n monitoring \
  svc/grafana 3000:80
```

Open `http://localhost:3000` and log in with `admin / changeme123`.

---

## Phase 3: Import Dashboards

### CDP Dashboards (custom)

Run the import script to load all CDP dashboards from the `dashboard/` directory:

```bash
bash scripts/import-dashboards.sh
```

This imports the following:

| File | Dashboard |
| :--- | :--- |
| `dashboard-cdp-pod-health.json` | CDP - Pod Health |
| `dashboard-cdp-log-monitor.json` | CDP - Log Monitor |

> The import script uses the Grafana API. Make sure port-forward is running before executing.

### Kubernetes Cluster Dashboards (dotdc)

Import these via Grafana UI: `Dashboards → Import → Enter ID`

| ID | Dashboard |
| :--- | :--- |
| `15757` | Kubernetes / Views / Global |
| `15758` | Kubernetes / Views / Namespaces |
| `15759` | Kubernetes / Views / Nodes |
| `15760` | Kubernetes / Views / Pods |

Select `Prometheus` as the datasource when prompted.

---

## Phase 4: Slack Alert Setup

### Step 10: Get Slack Webhook URL

1. Go to [Slack API Apps](https://api.slack.com/apps)
2. Create New App → From scratch
3. App Name: `DevOps Alerts`, select your workspace
4. Go to **Incoming Webhooks** → Enable → Add New Webhook to Workspace
5. Select the target channel and copy the webhook URL
   - Format: `https://hooks.slack.com/services/XXXX/YYYY/ZZZZ`

### Step 11: Configure Contact Point in Grafana

`Alerting → Contact points → Add contact point`

| Field | Value |
| :--- | :--- |
| Name | `Slack` |
| Integration | `Slack` |
| Webhook URL | paste from Step 10 |

### Step 12: Alert Rule (CDP ERROR)

`Alerting → Alert rules → New alert rule`

| Field | Value |
| :--- | :--- |
| Rule name | `CDP ERROR Alert` |
| Query | `sum(count_over_time({namespace="cdp"} \|= "ERROR" [1h]))` |
| Condition | `> threshold` |
| Evaluation interval | `1m` |
| Contact point | `Slack` |

---

## Phase 5: Dashboard Reference

### CDP - Log Monitor

Monitors error logs across `cdp` and `rabbitmq-system` namespaces.

**Variables:**

| Variable | Type | Description |
| :--- | :--- | :--- |
| `namespace` | Custom | `cdp`, `rabbitmq-system` |
| `Pod` | Label values | Filters by pod name |
| `log_level` | Custom | `ERROR`, `WARN`, `INFO`, `DEBUG`, `All` |

**Panels:**

| Panel | Type | Query |
| :--- | :--- | :--- |
| CDP Error Logs | Logs | `{namespace="$namespace", pod=~"$Pod"} \|~ "(?i)$log_level"` |
| Error Count by Pod | Time series | `sum by (pod) (count_over_time({namespace="$namespace"} \|= "ERROR" [5m]))` |

---

### CDP - Pod Health

Monitors pod status and restart frequency in the `cdp` namespace.

**Panels:**

**Pod Status Table**

| Column | Source |
| :--- | :--- |
| Pod | `kube_pod_status_phase{namespace="cdp"} == 1` |
| Status | phase label |
| Restarts (1h) | `changes(kube_pod_container_status_restarts_total{namespace="cdp"}[1h])` |

- Rows with Restarts >= 2 are highlighted red
- Clicking a Pod name links to the corresponding logs in CDP - Log Monitor

**Pod Restart Trend (1h)**

```promql
changes(kube_pod_container_status_restarts_total{namespace="cdp"}[1h])
```

Time series showing restart frequency per pod over the selected time range.

---

## Phase 6: Day-to-Day Operations

Use the management script at `~/monitoring.sh`:

```bash
~/monitoring.sh
```

Options:

| Option | Action |
| :--- | :--- |
| `1. Work` | Pull latest from GitHub, cd to monitoring-poc |
| `2. Push` | Export dashboards + commit + push to GitHub |
| `3. Import` | Import dashboards into Grafana via API |
| `4. Status` | Show pod and PVC status in monitoring namespace |

### Dashboard Export Details

`export-dashboards.sh` exports all dashboards with `CDP` in the title from Grafana API. During export, datasource UIDs (`prometheus`, `loki`) are automatically stripped from the JSON so dashboards can be imported into any environment without UID mismatch issues.

Exported files:

| File | Dashboard |
| :--- | :--- |
| `dashboard-cdp-pod-health.json` | CDP - Pod Health |
| `dashboard-cdp-log-monitor.json` | CDP - Log Monitor |

> dotdc K8s dashboards (15757–15760) are not exported — use Import ID to restore them in a new environment.

---

## Troubleshooting

### Loki PVC usage

```promql
kubelet_volume_stats_used_bytes{namespace="monitoring", persistentvolumeclaim="storage-loki-0", service="prome-loki-kube-prometheus-stack-kubelet"}
```

### Check Alloy log collection

```bash
kubectl logs -n monitoring $(kubectl get pod -n monitoring -l app.kubernetes.io/name=alloy -o jsonpath='{.items[0].metadata.name}') | grep -i error | tail -20
```

### Verify Prometheus service

```bash
kubectl get svc -n monitoring | grep prometheus
```

### Restart port-forward if Grafana is unreachable

```bash
pkill -f "kubectl port-forward"
kubectl port-forward --address 0.0.0.0 -n monitoring svc/grafana 3000:80
```