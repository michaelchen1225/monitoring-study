這份文件已經為你整理成結構清晰、易於閱讀且方便複製貼上的 Markdown 格式。

---

# AKS 監控系統部署指南 (Grafana + Loki + Alloy + Prometheus)

### 快速存取資訊
* **Grafana Dashboard:** [http://40.115.204.157:3000/](http://40.115.204.157:3000/)
* **帳號:** `admin`
* **密碼:** `changeme123`

---

## 🏗️ 系統架構說明

| 組件 | 角色 | 運作邏輯 |
| :--- | :--- | :--- |
| **Alloy** | 收集者 | 以 **DaemonSet** 跑在每個 Node 上。持續監看 `cdp` namespace 的 Pod Log 並即時推送到 Loki。 |
| **Loki** | 儲存者 | 接收 Log 並存入 **PVC**。基於 Label（namespace, pod）建立索引，但不解析內文，確保高效儲存。 |
| **Grafana** | 展示者 | 負責查詢與視覺化。向 Loki 請求資料並繪製圖表，同時執行每分鐘一次的告警規則掃描。 |

---

## 🛠️ 第一階段：基礎環境準備

### Step 1：申請 Slack Webhook
1. 進入 [Slack API Apps](https://api.slack.com/apps)。
2. 點擊 **Create New App** -> **From scratch**。
3. App Name 填 `DevOps Alerts`，選擇公司 Workspace。
4. 在左側選單進入 **Incoming Webhooks**，將開關切至 **On**。
5. 點擊 **Add New Webhook to Workspace**，選擇頻道並獲得 URL。
    * *格式範例：`https://hooks.slack.com/services/XXXX/YYYY/ZZZZ`*

### Step 2：建立 Namespace
```bash
kubectl create namespace monitoring
```

---

## 📦 第二階段：組件安裝 (Helm)

### Step 3：安裝 Loki
```bash
# 準備目錄
mkdir grafana-poc && cd grafana-poc

# 加入 Helm Repo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 安裝 (請確保目錄下已有 loki-values.yaml)
helm install loki grafana/loki \
  --namespace monitoring \
  --values loki-values.yaml

# 確認 Service 名稱以便後續串接
kubectl get svc -n monitoring
```

### Step 4：安裝 Alloy
```bash
# 安裝 (請確保目錄下已有 alloy-values.yaml)
helm install alloy grafana/alloy \
  --namespace monitoring \
  --values alloy-values.yaml
```

### Step 5：安裝 Grafana
```bash
# 安裝 (請確保目錄下已有 grafana-values.yaml)
helm install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values.yaml
```

### Step 6：本地存取 Grafana
```bash
kubectl port-forward \
    --address 0.0.0.0 \
    -n monitoring \
    svc/grafana 3000:80
```
> 瀏覽器開啟 `http://localhost:3000`，使用 `admin / changeme123` 登入。

---

## 📊 第三階段：Dashboard 與告警設定

### Step 7：驗證 Loki 資料
在 Explore 頁面，選擇 **Loki** 作為資料源，輸入查詢：
```logql
{namespace="cdp"}
```

### Step 8：建立自定義 Dashboard
1. **Panel 1: ERROR Log 列表**
    * Visualization: `Logs`
    * Query: `{namespace="cdp"} |= "ERROR"`
    * Title: `CDP Error Logs`
2. **Panel 2: 各 Pod ERROR 趨勢**
    * Visualization: `Time series`
    * Query: `sum by (pod) (count_over_time({namespace="cdp"} |= "ERROR" [5m]))`
    * Title: `Error Count by Pod`

### Step 9：設定 Slack 告警
1. **設定 Contact Point**:
    * 路徑：`Alerting` -> `Contact points` -> `Add contact point`
    * Integration: `Slack` | URL: `貼上 Step 1 的 Webhook URL`
2. **建立 Alert Rule**:
    * Rule name: `CDP ERROR Alert`
    * Query: `sum(count_over_time({namespace="cdp"} |= "ERROR" [1h]))`
    * Evaluation interval: `1m`
    * Contact point: `Slack Testing`

---

## 🔍 第四階段：進階優化 (Variables)

若要讓 Dashboard 支援下拉選單篩選 Pod，請在 Dashboard Settings 設定 **Variables**:
* **Name**: `pod`
* **Query**: `label_values(pod)`
* **更新 Panel Query**: `{namespace="cdp", pod=~"$pod"} |= "ERROR"`

---

## 📈 第五階段：監控指標 (Prometheus)

### 安裝 Prometheus Stack
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values prometheus-values.yaml \
  --version 82.14.1
```

### 加入 Data Source
在 Grafana UI 中：`Connections` -> `Data sources` -> `Add Prometheus`
* **URL 範例**: `http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090`

### 導入預設 Cluster Dashboards (Import ID)
| ID | 名稱 | 說明 |
| :--- | :--- | :--- |
| `15757` | **Global View** | 整個 Cluster 總覽 |
| `15758` | **Namespaces View** | 可篩選 cdp namespace |
| `15759` | **Nodes View** | 節點資源耗用狀況 |
| `15760` | **Pods View** | Pod 層級細節監控 |