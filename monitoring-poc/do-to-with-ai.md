## 新對話需要提供的資訊

直接把以下這段貼給我就夠了：

---

環境：
AKS cluster，4 個 node，每個 4 CPU / 16GB RAM，namespace 主要是 cdp，服務包含 Airflow、Presto、Hive、MongoDB、MySQL、RabbitMQ 和一系列 cdp-*-api。

已完成的 POC：
在 monitoring namespace 裝了 Loki + Grafana Alloy + Grafana，全部用 Helm 安裝。Alloy 收集 cdp namespace 的 Log 推給 Loki，Grafana 透過 port foward 對外開放。已建立 CDP Services - Log Monitor Dashboard，有 ERROR Log 列表和各 Pod ERROR 趨勢圖。Slack 告警已設定，條件是過去 1 小時 ERROR 數超過閾值就發通知。

工作目錄：~/monitoring-poc，裡面有 values 目錄，存放 loki-values.yaml、alloy-values.yaml、grafana-values.yaml。

另外還有一個 dashboard 目錄，裡面有 dashboard-*.json，用來做 grafana dashboard provisioning
。

下一步目標：安裝 Prometheus，建立 Cluster 層級 Dashboard。


目前：已安裝 prometheus，但還沒在 grafana 確認

---

## 未來 Dashboard 規劃

根據你的三個需求，我建議建立兩個新的 Dashboard。

---

### Dashboard 1：Pod 健康狀態（需要 Prometheus）

目的是一眼看出哪個 Pod 有問題，並能快速跳到對應的 Log。

包含以下 Panel：

**Pod 狀態總覽**，用表格列出所有 `cdp` namespace 的 Pod，顯示狀態（Running / CrashLooping / Pending）和重啟次數，重啟次數超過閾值的行自動標紅。

**CrashLooping Pod 告警**，專門偵測 `KubePodCrashLooping` 事件，有 Pod 進入 CrashLoop 立刻發 Slack，通知內容帶上 Pod 名稱。

**Log 快速連結**，點擊表格裡的 Pod 名稱，直接跳到 Log Dashboard 並自動帶入該 Pod 的篩選條件，這就是你說的「快速找到對應 Log」。

---

### Dashboard 2：資源使用效率（需要 Prometheus）

目的是找出浪費錢的資源。

包含以下 Panel：

**CPU / Memory 實際使用 vs 申請量**，列出每個 Pod 申請了多少資源、實際用了多少，如果申請量遠高於實際使用量，代表資源被浪費了。

**長期閒置的 Pod**，顯示哪些 Pod 的 CPU 使用率長期低於 5%，這些是可以考慮縮減規格或合併的候選。

**PVC 使用率**，列出每個 PVC 的容量和實際使用量，避免不知不覺塞滿然後服務掛掉。

**Node 資源壓力**，顯示每個 Node 的 CPU 和 Memory 使用率趨勢，如果某個 Node 長期過載代表需要擴充，如果普遍很低代表可以縮減 Node 節省費用。

---

### 現有 Log Dashboard 的補強

在現有的 `CDP Services - Log Monitor` 上加一個 Pod 下拉選單，這個我們上次已經討論過做法，讓你能依 Pod 名稱篩選 Log，不需要新建 Dashboard。

---

以上這些都需要先安裝 Prometheus 才能做，新對話開啟後告訴我你準備好了，我們從安裝 Prometheus 開始。

Prometheus 安裝狀態： 已加好 prometheus-community repo，版本確認是 82.14.1，prometheus-values.yaml 已建立在 ~/grafana-poc/，但尚未執行安裝指令。新對話開始後直接從安裝 Prometheus 繼續。