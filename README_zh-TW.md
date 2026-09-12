# Woow_k3s_homeassistant — Home Assistant K3s/Kubernetes Helm Chart

[English](README.md)

在 K3s/Kubernetes 上部署 [Home Assistant](https://www.home-assistant.io/) 的
Helm chart，內建 [PostgreSQL 16](https://www.postgresql.org/) 作為記錄器
（Recorder）資料庫，取代預設的 SQLite，提升效能與擴充性。

> **要找其他平台的版本？**
> Docker / Podman Compose → [Woow_podman_homeassistant](https://github.com/WOOWTECH/Woow_podman_homeassistant)
>
> Home Assistant 本身就是智慧家庭平台，因此不會有「Home Assistant add-on 版」的本組合包。

> **現況：** 這個 chart 目前沒有裝在任何叢集上（哪個叢集都沒有對應的 Helm
> release）。這一階段（phase 1）只修 chart 本身，見下方
> [Chart 品質修正（phase 1）](#chart-品質修正phase-1)。資源名稱、映像檔、
> port、pod template 都沒有改變。

## 架構

| 元件 | 映像檔 | Service | NodePort |
|---|---|---|---|
| Home Assistant | `ghcr.io/home-assistant/home-assistant:stable` | `homeassistant:8123` | `31812` |
| PostgreSQL (recorder) | `postgres:16-alpine` (StatefulSet) | `postgres:5432` | —（ClusterIP） |

- 儲存：兩個 `local-path` PVC —— `ha-config`（5Gi）存 HA 設定與狀態，`postgres-data`（10Gi）存 recorder 資料庫。
- Home Assistant Deployment 使用 `Recreate` 策略（`/config` 單一寫入者），並透過 initContainer 等待 PostgreSQL 就緒。
- `hostNetwork` 預設關閉；若需要 LAN 裝置探索（mDNS、SSDP），請把 `homeassistant.hostNetwork` 設為 `true`。

| Template | 產出物件 | 開關 |
|---|---|---|
| `templates/namespace.yaml` | Namespace `namespace.name`，只有跟 release namespace 不同時才 render | `namespace.create` |
| `templates/secret.yaml` | Secret `secrets.existingSecretName`（預設 `postgres-secret`） | `secrets.create` |
| `templates/configmap.yaml` | ConfigMap `homeassistant-config`（TZ） | 一定 render |
| `templates/pvc.yaml` | PVC `ha-config`、`postgres-data` | 第二個看 `postgres.enabled` |
| `templates/homeassistant-deployment.yaml` | Deployment `homeassistant`、Service `homeassistant`（`homeassistant-service.yaml`） | 一定 render |
| `templates/postgres-statefulset.yaml`、`postgres-service.yaml` | StatefulSet + Service `postgres` | `postgres.enabled` |
| `templates/tests/smoke.yaml` | `helm test` pod | `tests.enabled` |

## 密鑰（Secrets）

預設（`secrets.create: false`）下，chart 完全不會產生或動到 Secret ——
只用名稱（`secrets.existingSecretName`，預設 `postgres-secret`）去參照，
所以 `helm upgrade` 永遠不會把真實密碼覆蓋掉。安裝前自己先建立：

```bash
kubectl --context <ctx> create namespace homeassistant
cp examples/secrets.example.yaml /secure/path/postgres-secret.yaml   # 填入密碼
kubectl --context <ctx> apply -f /secure/path/postgres-secret.yaml
helm --kube-context <ctx> install homeassistant . -n homeassistant
```

如果是測試安裝，也可以讓 chart 自己產生 Secret（`secrets.create=true` 時每個
欄位都是必填 —— 沒填的話 `helm template`/`install` 會直接因為 `required()`
報錯失敗，所以不會有弱預設密碼可以忘記改）：

```bash
helm install homeassistant . \
  --set secrets.create=true \
  --set secrets.postgresUser=homeassistant \
  --set secrets.postgresPassword="$(openssl rand -base64 24)" \
  --set secrets.postgresDb=homeassistant
```

同一組密碼也要寫進 Home Assistant 的 `config/secrets.yaml`，作為
`recorder_db_url`（recorder 是從那裡讀密碼，不是從環境變數）：
`postgresql://homeassistant:你的密碼@postgres.homeassistant.svc.cluster.local:5432/homeassistant?client_encoding=utf8`

**不要單獨改動 `secrets.postgresUser` / `secrets.postgresDb`**（預設都是
`homeassistant`），除非你也同步改掉所有寫死的探測：`wait-for-postgres`
initContainer（`templates/homeassistant-deployment.yaml`）和 StatefulSet 的
`pg_isready` 探測（`templates/postgres-statefulset.yaml`）都寫死
`-U homeassistant -d homeassistant`。這是既有限制，phase 1 沒有動它 ——
見下方[已知限制](#已知限制未在-phase-1-修正)。

## 快速開始

```bash
# 直接從 GitHub tarball 安裝（不需 clone）
helm install homeassistant \
  https://github.com/WOOWTECH/Woow_k3s_homeassistant/archive/refs/heads/main.tar.gz \
  -n homeassistant --create-namespace \
  --set secrets.create=true,secrets.postgresUser=homeassistant,secrets.postgresDb=homeassistant \
  --set secrets.postgresPassword="$(openssl rand -base64 24)"

# 或從本地 clone 安裝，Secret 交給 Helm 以外管理（見上面「密鑰」）
git clone https://github.com/WOOWTECH/Woow_k3s_homeassistant.git
cd Woow_k3s_homeassistant
helm install homeassistant . -n homeassistant --create-namespace
```

然後開啟瀏覽器連到 `http://<node-ip>:31812`，完成初始設定精靈。

### 測試安裝（獨立 namespace、可拋棄的儲存、隨機密碼）

```bash
NS=ht-homeassistant
helm install homeassistant . -n "$NS" --create-namespace \
  --set namespace.name="$NS" \
  --set homeassistant.persistence.storageClassName=longhorn-delete \
  --set postgres.persistence.storageClassName=longhorn-delete \
  --set secrets.create=true,secrets.postgresUser=homeassistant,secrets.postgresDb=homeassistant \
  --set secrets.postgresPassword="$(openssl rand -hex 16)"
kubectl -n "$NS" rollout status deploy/homeassistant --timeout=5m
kubectl -n "$NS" rollout status statefulset/postgres --timeout=5m
helm test homeassistant -n "$NS" --logs
```

把 `namespace.name` 設成跟 `-n` 一樣，`templates/namespace.yaml` 就不會再
render 出第二個 Namespace 物件 —— Helm 的 `--create-namespace` 已經建立好了。

## 常用參數

| 參數 | 預設值 | 說明 |
|---|---|---|
| `namespace.create` / `namespace.name` | `true` / `homeassistant` | 目標 namespace；只有跟 `-n` 不同時才會被 render 成物件 |
| `keepOnUninstall` | `true` | 給 Namespace（有 render 時）、兩個 PVC 和 chart 建立的 Secret 加上 `helm.sh/resource-policy: keep` |
| `secrets.create` | `false` | 用 `secrets.*` render Secret，而不是使用既有的 |
| `secrets.existingSecretName` | `postgres-secret` | Postgres 憑證 Secret 的名稱，不論既有或 chart 建立 |
| `homeassistant.image.tag` | `stable` | Home Assistant 版本 |
| `homeassistant.service.type` / `nodePort` | `NodePort` / `31812` | HA 對外方式 |
| `homeassistant.hostNetwork` | `false` | mDNS/SSDP 探索需求時設為 `true` |
| `homeassistant.persistence.size` | `5Gi` | `/config` PVC 大小（`local-path`） |
| `homeassistant.config.TZ` | `Asia/Taipei` | 時區（postgres 共用） |
| `postgres.enabled` | `true` | 是否部署內建的 PostgreSQL StatefulSet |
| `postgres.persistence.size` | `10Gi` | Postgres 資料 PVC（`local-path`） |
| `tests.enabled` | `true` | `helm test` 讀取用探測 pod |

完整清單：[`values.yaml`](values.yaml)

## 驗證

```bash
kubectl get pods -n homeassistant          # homeassistant + postgres 都 Ready
helm test homeassistant -n homeassistant --logs
# 探測 pod 會檢查：HA 在自己的 Service port 上回應 2xx/3xx（設定精靈或登入頁），
# 以及（若 postgres.enabled）用跟 app 相同的 Secret 對 postgres Service 做
# pg_isready。全程只讀，不寫入任何東西。
```

## 移除

```bash
helm uninstall homeassistant -n homeassistant
```

這會移除 Deployment、StatefulSet、Service 和 ConfigMap。資料會留下來：

- 兩個 PVC（`ha-config`、`postgres-data`）和 chart 建立的 Secret 都帶有
  `helm.sh/resource-policy: keep`（預設 `keepOnUninstall: true`）；
- 上面範例中 `homeassistant` namespace 就是 release namespace，本來就不會被
  render 成物件，所以也不會被刪除。如果 chart 有 render 出 Namespace
  （`namespace.name` 跟 `-n` 不同），那個 Namespace 也帶有 keep policy。

如果真的要連資料一起刪乾淨：

```bash
kubectl delete pvc -n homeassistant ha-config postgres-data
kubectl delete secret -n homeassistant postgres-secret   # 只有用過 secrets.create=true 才需要
kubectl delete namespace homeassistant                    # 確定沒有其他東西共用這個 namespace 才刪
```

## Chart 品質修正（phase 1）

這一階段只改了 chart 本身，沒有動到正在跑的應用程式。用預設值 render，
這個 chart 跟前一個 `main` HEAD（chart 1.0.0）逐欄位完全相同，只有以下
刻意的差異：

1. **跟 release namespace 相同的 Namespace 不再 render。** 以前
   `templates/namespace.yaml` 只要 `namespace.create=true` 就一定會 render
   出 `Namespace homeassistant`，不管 `-n` 是什麼；`helm uninstall` 因此會把
   整個 namespace 連同兩個 PVC 一起刪掉。現在跟 `-n` 相同的 namespace 會被
   跳過（改用 `--create-namespace` 建立），而 chart 真的有 render 出來的
   Namespace 則帶有 keep policy。
2. **加上 `helm.sh/resource-policy: keep`**：Namespace（有 render 時）、兩個
   PVC，以及 chart 建立的 Secret，由 `keepOnUninstall`（預設 `true`）控制。
3. **密鑰移出 `values.yaml`。** `secrets.create` 預設改成 `false`；chart
   只用名稱（`secrets.existingSecretName`）參照既有 Secret。以前的 chart
   永遠會從 `values.yaml` render 出 `postgres-secret`，裡面內建一個弱預設
   密碼（`changeme`），直接寫進 repo。現在 `secrets.create=true` 時才會
   從 values render，而且每個欄位都用 Helm 的 `required()` 擋住，不會有
   預設值可以忘記改。
4. **移除 `securityContext.privileged: true`。** 以前寫死在 Home Assistant
   容器上，沒有對應的 values 開關，但 `hostNetwork` 預設是 `false`、也沒
   掛任何 USB/host 裝置，等於白白多給了不必要的 root 等級節點存取權。
5. 新增一個唯讀的 `helm test` 探測 pod、這份 README 的密鑰／CI／移除章節，
   以及 CI（`helm lint`、跨所有 values 組合的 `helm template`、
   `kubeconform -strict`、確認 `required()` 有生效、確認沒有密鑰被 commit、
   確認每個 template 都有進 git 而且從乾淨 clone render 得出來）。

沒有做 v2 重新設計：資源名稱、labels、selector、映像檔、port 和 pod
template 都跟以前逐位元組相同（除了移除 `privileged: true`）。
`_helpers.tpl` 只加了兩個小的 named template（namespace 名稱、keep
annotation 區塊），沒有用 `.Release.Name` 去推導任何名稱。

## 已知限制（未在 phase 1 修正）

以下是既有問題，這次不處理，也沒有被這次改動影響：

- **`hostNetwork: true` 搭配 `dnsPolicy: ClusterFirst`。** Kubernetes 規定
  hostNetwork pod 要用 `ClusterFirstWithHostNet` 才能解析叢集內部名稱；
  沒設的話會退回節點自己的 resolv.conf，`wait-for-postgres` initContainer
  查 `postgres.<ns>.svc.cluster.local` 永遠解析不出來。所以
  `homeassistant.hostNetwork=true` 目前其實是壞的。
- **`pg_isready` 和 recorder 連線字串都寫死使用者/資料庫名稱
  `homeassistant`**，跟 `secrets.postgresUser` / `secrets.postgresDb` 無關。
  要改這兩個值的話，一定要同步改
  `templates/homeassistant-deployment.yaml` 和
  `templates/postgres-statefulset.yaml` 裡所有寫死的探測。
- **預設 namespace 名稱 `homeassistant`** 在某些叢集上可能會撞到別的、
  無關的 `homeassistant` namespace（例如 KubeVirt HAOS VM 那一套）。這個
  chart 不會自動 adopt 既有 namespace —— 如果真的撞名，`helm install`
  會因為 ownership metadata 不符而乾淨地失敗 —— 但撞名時請改用別的
  `namespace.name`。
- **映像檔 tag 是浮動的**：`homeassistant.image.tag: stable` 和
  `postgres.image.tag: 16-alpine` 都會隨時間移動。要可重現的升級行為，
  請自行釘住版本。
- **不會 seed configuration.yaml / secrets.yaml。** chart 不會建立 Home
  Assistant 的 `config/configuration.yaml` 或 `config/secrets.yaml`，
  recorder 設定仍要在完成設定精靈之後手動加上去。

## 從舊 Kustomize 版本遷移

本倉庫取代已封存的
[Woow_ha_docker_compose_all](https://github.com/WOOWTECH/Woow_ha_docker_compose_all)
的 `k3s` 分支。Chart 1.0.0 預設輸出與原 manifests 資源等價（相同名稱、
namespace、labels、ports、PVC），差異只有 HA 容器的
`imagePullPolicy: Always` 和 namespace 的 `managed-by: helm` label。這次
phase 1 又進一步改了 chart —— 完整、最新的刻意差異清單見上方
[Chart 品質修正](#chart-品質修正phase-1)。

這個 chart 目前沒有部署在任何地方（本機叢集和 woow-k3s 都確認過）——
Kustomize 時代的 manifests 仍留在本倉庫的 git 歷史中可查。這一階段因此
沒有任何既有 release 需要 take over。

## 授權條款

MIT
