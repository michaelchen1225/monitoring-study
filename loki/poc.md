grafana dashboard：http://40.115.204.157:3000/
account: admin
password: changeme123

---
Alloy 是收集者。它以 DaemonSet 的方式跑在你的 AKS 上，意思是每一個 Node 上都有一個 Alloy 的 Pod 在運行。它的工作就是持續監視這個 Node 上所有 cdp namespace 的 Pod，把它們的 Log 即時抓下來，然後推送給 Loki。

Loki 是儲存者。它接收 Alloy 推過來的 Log，把內容存在 PVC 裡，同時幫每一筆 Log 建立索引，索引的依據就是 label，也就是 namespace、pod、container 這些欄位。它不解析 Log 的內容，只管收和存。

Grafana 是展示者。它本身不碰 Log，只負責在你查詢的時候去問 Loki「給我符合這個條件的 Log」，然後把結果畫出來。告警也是同樣道理，它每隔 1 分鐘問 Loki 一次「過去 1 小時有幾筆 ERROR」，如果超過閾值就發 Slack。
---


Step 1：前置作業：申請 Slack Webhook

打開瀏覽器，進入這個網址：https://api.slack.com/apps

點右上角 Create New App，選 From scratch

App Name 填 DevOps Alerts，選你們公司的 Workspace

建立後進入 app 設定頁，左側選單找到 Incoming Webhooks，把它開啟（toggle 切到 On）

頁面下方點 Add New Webhook to Workspace，選一個 channel（建議先選你自己的 DM 測試就好，之後再換正式 channel）

確認後會拿到一個 URL，格式是：https://hooks.slack.com/services/XXXX/YYYY/ZZZZ

把這個 URL 存起來，之後第七步會用到。

---

Step 2：建立 monitoring namespace

```bash
kubectl create namespace monitoring
```
---

Step 3：安裝 Loki

```bash
mkdir grafana-poc && cd grafana-poc
```

建立 [loki-values.yaml](./loki-values.yaml)：

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install loki grafana/loki \
  --namespace monitoring \
  --values loki-values.yaml
```

```bash
# 確認 loki svc name
kubectl get svc -n monitoring
```

---

Step 4：安裝 Alloy

建立 [alloy-values.yaml](./alloy-values.yaml)：

```bash
helm install alloy grafana/alloy \
  --namespace monitoring \
  --values alloy-values.yaml
```

---

Step 5：安裝 Grafana

建立 [grafana-values.yaml](./grafana-values.yaml):

```bash
helm install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values.yaml
```

Step 6：登入 Grafana

```bash
 kubectl port-forward \
        --address 0.0.0.0 \
        -n monitoring \
        svc/grafana 3000:80 \
```

> 打開瀏覽器，進入 http://<IP>:3000/，使用 admin/changeme123 登入


Step 7：確認 Loki 有用

左側選單點 Explore，確認上方資料來源選的是 Loki，然後在查詢框輸入：

```logql
{namespace="cdp"}
```

**Step 8：建立基本的 Dashboard**

左側選單點 Dashboards → New → New dashboard，點 Add visualization，選 Loki。

**Panel 1：ERROR Log 即時列表：**

右上角 Visualization 選 Logs
Query 填：{namespace="cdp"} |= "ERROR" (記得切換到 code)
Panel 標題設為 CDP Error Logs
右上角點 Apply 儲存這個 Panel

**Panel 2：各 Pod ERROR 趨勢：**

點 Add → Visualization，再加一個 Panel：

Visualization 選 Time series
Query 填：sum by (pod) (count_over_time({namespace="cdp"} |= "ERROR" [5m]))
Panel 標題設為 Error Count by Pod
點 Apply

兩個 Panel 都加完之後，右上角點 Save dashboard，名稱填 CDP Services - Log Monitor。

---

設定 Slack 告警：


第一部分：設定 Contact Point
左側選單點 Alerting → Contact points，點 Add contact point：

Name 填 Slack Testing
Integration 選 Slack
Webhook URL 填入你之前申請的那個 URL
點 Test 確認 Slack 有收到測試訊息
確認後點 Save contact point

---

左側選單點 Alerting → Alert rules，點 New alert rule：

Rule name 填 CDP ERROR Alert

往下找到 Define query and alert condition：

Data source 選 Loki
點 Code 模式
Query 填：

sum(count_over_time({namespace="cdp"} |= "ERROR" [1h])) 
往下找到 Set alert evaluation behavior：

Folder 建立一個新的，名稱可填 CDP Services
Evaluation group 點 New evaluation group，名稱填 cdp-alerts，Evaluation interval 填 1m
Pending period 填 0s（POC 測試用，之後再調）

往下找到 Configure notifications：

Contact point 選 Slack Testing