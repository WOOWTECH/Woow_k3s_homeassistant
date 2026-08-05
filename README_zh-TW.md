# Woow_k3s_homeassistant — Home Assistant K3s/Kubernetes Helm Chart

[English](README.md)

在 K3s/Kubernetes 上部署 [Home Assistant](https://www.home-assistant.io/) 的
Helm chart，內建 [PostgreSQL 16](https://www.postgresql.org/) 作為記錄器
（Recorder）資料庫，取代預設的 SQLite，提升效能與擴充性。

> **要找其他平台的版本？**
> Docker / Podman Compose → [Woow_podman_homeassistant](https://github.com/WOOWTECH/Woow_podman_homeassistant)
>
> Home Assistant 本身就是智慧家庭平台，因此不會有「Home Assistant add-on 版」的本組合包。

## 架構

| 元件 | 映像檔 | Service | NodePort |
|---|---|---|---|
| Home Assistant | `ghcr.io/home-assistant/home-assistant:stable` | `homeassistant:8123` | `31812` |
| PostgreSQL (recorder) | `postgres:16-alpine` (StatefulSet) | `postgres:5432` | —（ClusterIP） |

- 儲存：兩個 `local-path` PVC —— `ha-config`（5Gi）存 HA 設定與狀態，`postgres-data`（10Gi）存 recorder 資料庫。
- Home Assistant Deployment 使用 `Recreate` 策略（`/config` 單一寫入者），並透過 initContainer 等待 PostgreSQL 就緒。
- `hostNetwork` 預設關閉；若需要 LAN 裝置探索（mDNS、SSDP），請把 `homeassistant.hostNetwork` 設為 `true`。

## 快速開始

```bash
# 直接從 GitHub tarball 安裝（不需 clone）
helm install homeassistant \
  https://github.com/WOOWTECH/Woow_k3s_homeassistant/archive/refs/heads/main.tar.gz

# 或從本地 clone 安裝
git clone https://github.com/WOOWTECH/Woow_k3s_homeassistant.git
cd Woow_k3s_homeassistant
helm install homeassistant .
```

> **正式部署前務必修改 PostgreSQL 密碼：**
>
> ```bash
> helm install homeassistant . \
>   --set secrets.postgresPassword="$(openssl rand -base64 24)"
> ```
>
> 同一組密碼也要寫進 Home Assistant 的 `config/secrets.yaml`，作為 `recorder_db_url`：
> `postgresql://homeassistant:你的密碼@postgres.homeassistant.svc.cluster.local:5432/homeassistant?client_encoding=utf8`

然後開啟瀏覽器連到 `http://<node-ip>:31812`，完成初始設定精靈。

## 常用參數

| 參數 | 預設值 | 說明 |
|---|---|---|
| `namespace.create` / `namespace.name` | `true` / `homeassistant` | 目標 namespace |
| `homeassistant.image.tag` | `stable` | Home Assistant 版本 |
| `homeassistant.service.type` / `nodePort` | `NodePort` / `31812` | HA 對外方式 |
| `homeassistant.hostNetwork` | `false` | mDNS/SSDP 探索需求時設為 `true` |
| `homeassistant.persistence.size` | `5Gi` | `/config` PVC 大小（`local-path`） |
| `homeassistant.config.TZ` | `Asia/Taipei` | 時區（postgres 共用） |
| `postgres.enabled` | `true` | 是否部署內建的 PostgreSQL StatefulSet |
| `postgres.persistence.size` | `10Gi` | Postgres 資料 PVC（`local-path`） |
| `secrets.postgresPassword` | `changeme` | PostgreSQL 密碼（請務必修改） |

完整清單：[`values.yaml`](values.yaml)

## 驗證

```bash
kubectl get pods -n homeassistant          # homeassistant + postgres 都 Ready
kubectl exec -n homeassistant deploy/homeassistant -- wget -qO- -S http://localhost:8123/ 2>&1 | head -5
# 預期：HTTP/1.1 302 Found → /onboarding.html（首次安裝）
```

## 移除

```bash
helm uninstall homeassistant
# Helm 不會自動刪除 PVC；如果連資料都要清乾淨：
kubectl delete pvc -n homeassistant ha-config postgres-data
```

## 從舊 Kustomize 版本遷移

本倉庫取代已封存的
[Woow_ha_docker_compose_all](https://github.com/WOOWTECH/Woow_ha_docker_compose_all)
的 `k3s` 分支。Chart 預設輸出與原 manifests 資源等價（相同名稱、namespace、
labels、ports、PVC）。刻意保留的兩個差異：

- HA 容器明寫 `imagePullPolicy: Always`（舊 manifests 靠 `:stable` mutable tag
  的 Kubernetes 隱性預設行為，本 chart 明寫出來以避免歧義）。
- Namespace 加上 `managed-by: helm` label，讓 `helm list -A` 找得到。

兩者皆為無害差異，既有 Kustomize 部署可以直接被 Helm adopt，或原封不動繼續
使用。原 `k8s-manifests/` 目錄在本倉庫的 git 歷史中可查。

## 授權條款

MIT
