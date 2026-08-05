# Woow_k3s_homeassistant — Home Assistant Helm Chart for K3s/Kubernetes

[繁體中文](README_zh-TW.md)

Helm chart deploying [Home Assistant](https://www.home-assistant.io/) on
K3s/Kubernetes with an integrated [PostgreSQL 16](https://www.postgresql.org/)
recorder database (replaces the default SQLite for better performance and
scale).

> **Looking for another platform?**
> Docker/Podman Compose → [Woow_podman_homeassistant](https://github.com/WOOWTECH/Woow_podman_homeassistant)
>
> Home Assistant *is* the smart-home platform, so there is no Home Assistant
> add-on variant of this stack.

## Architecture

| Component | Image | Service | NodePort |
|---|---|---|---|
| Home Assistant | `ghcr.io/home-assistant/home-assistant:stable` | `homeassistant:8123` | `31812` |
| PostgreSQL (recorder) | `postgres:16-alpine` (StatefulSet) | `postgres:5432` | — (ClusterIP) |

- Storage: two `local-path` PVCs — `ha-config` (5Gi) for HA state and
  `postgres-data` (10Gi) for the recorder database.
- Home Assistant Deployment uses `Recreate` strategy (single writer for the
  `/config` volume) and waits for PostgreSQL via an init container.
- `hostNetwork` is disabled by default; set `homeassistant.hostNetwork=true` if
  you need LAN device discovery (mDNS, SSDP).

## Quick start

```bash
# Install straight from the repo tarball (no clone needed)
helm install homeassistant \
  https://github.com/WOOWTECH/Woow_k3s_homeassistant/archive/refs/heads/main.tar.gz

# Or from a local clone
git clone https://github.com/WOOWTECH/Woow_k3s_homeassistant.git
cd Woow_k3s_homeassistant
helm install homeassistant .
```

> **Change the PostgreSQL password before any non-test deployment:**
>
> ```bash
> helm install homeassistant . \
>   --set secrets.postgresPassword="$(openssl rand -base64 24)"
> ```
>
> The same password must appear in Home Assistant's `config/secrets.yaml`
> as `recorder_db_url`:
> `postgresql://homeassistant:YOUR_PASSWORD@postgres.homeassistant.svc.cluster.local:5432/homeassistant?client_encoding=utf8`

Then open `http://<node-ip>:31812` and complete the onboarding wizard.

## Key values

| Value | Default | Description |
|---|---|---|
| `namespace.create` / `namespace.name` | `true` / `homeassistant` | Target namespace |
| `homeassistant.image.tag` | `stable` | Home Assistant version |
| `homeassistant.service.type` / `nodePort` | `NodePort` / `31812` | How HA is exposed |
| `homeassistant.hostNetwork` | `false` | Set `true` for mDNS/SSDP discovery |
| `homeassistant.persistence.size` | `5Gi` | `/config` PVC (`local-path`) |
| `homeassistant.config.TZ` | `Asia/Taipei` | Timezone (shared with postgres) |
| `postgres.enabled` | `true` | Deploy the bundled PostgreSQL StatefulSet |
| `postgres.persistence.size` | `10Gi` | Postgres data PVC (`local-path`) |
| `secrets.postgresPassword` | `changeme` | PostgreSQL password (change me!) |

Full list: [`values.yaml`](values.yaml)

## Verify

```bash
kubectl get pods -n homeassistant          # homeassistant + postgres Ready
kubectl exec -n homeassistant deploy/homeassistant -- wget -qO- -S http://localhost:8123/ 2>&1 | head -5
# Expect: HTTP/1.1 302 Found  → /onboarding.html (fresh install)
```

## Uninstall

```bash
helm uninstall homeassistant
# PVCs are kept by Helm; remove them (and your data!) with:
kubectl delete pvc -n homeassistant ha-config postgres-data
```

## Migrating from the old Kustomize deployment

This repository replaces the `k3s` branch of the archived
[Woow_ha_docker_compose_all](https://github.com/WOOWTECH/Woow_ha_docker_compose_all)
repo. The chart's default rendering is resource-equivalent to those manifests
(same names, namespace, labels, ports, PVCs). The only intentional deltas are:

- `imagePullPolicy: Always` is set explicitly on the HA container (the old
  manifests relied on Kubernetes' implicit default for the mutable `:stable` tag).
- The namespace gets an extra `managed-by: helm` label so `helm list -A` can
  find the release.

Both differences are cosmetic; an existing Kustomize deployment can be adopted
by Helm or simply left as-is. The original `k8s-manifests/` directory remains
available in this repo's git history.

## License

MIT
