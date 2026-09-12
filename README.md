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

> **Status:** this chart is not installed anywhere yet (no Helm release on any
> cluster). Phase 1 only fixes the chart itself — see
> [Chart quality fixes (phase 1)](#chart-quality-fixes-phase-1) below. Resource
> names, images, ports and pod templates are unchanged from before.

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

| Template | Objects | Toggle |
|---|---|---|
| `templates/namespace.yaml` | Namespace `namespace.name`, only when it differs from the release namespace | `namespace.create` |
| `templates/secret.yaml` | Secret `secrets.existingSecretName` (default `postgres-secret`) | `secrets.create` |
| `templates/configmap.yaml` | ConfigMap `homeassistant-config` (TZ) | always |
| `templates/pvc.yaml` | PVCs `ha-config`, `postgres-data` | `postgres.enabled` for the second one |
| `templates/homeassistant-deployment.yaml` | Deployment `homeassistant`, Service `homeassistant` (`homeassistant-service.yaml`) | always |
| `templates/postgres-statefulset.yaml`, `postgres-service.yaml` | StatefulSet + Service `postgres` | `postgres.enabled` |
| `templates/tests/smoke.yaml` | `helm test` pod | `tests.enabled` |

## Secrets

By default (`secrets.create: false`) the chart never renders or touches a
Secret — it only references one by name (`secrets.existingSecretName`, default
`postgres-secret`), so a `helm upgrade` can never overwrite a real password.
Create it yourself before installing:

```bash
kubectl --context <ctx> create namespace homeassistant
cp examples/secrets.example.yaml /secure/path/postgres-secret.yaml   # fill in the password
kubectl --context <ctx> apply -f /secure/path/postgres-secret.yaml
helm --kube-context <ctx> install homeassistant . -n homeassistant
```

For a fresh/test install, let the chart create the Secret instead
(`secrets.create=true` requires every field — a `helm template`/`install`
without them fails with a `required()` error, so there is no weak default
password to forget to change):

```bash
helm install homeassistant . \
  --set secrets.create=true \
  --set secrets.postgresUser=homeassistant \
  --set secrets.postgresPassword="$(openssl rand -base64 24)" \
  --set secrets.postgresDb=homeassistant
```

The same password must also appear in Home Assistant's `config/secrets.yaml`
as `recorder_db_url` (the recorder reads it from there, not from the
environment):
`postgresql://homeassistant:YOUR_PASSWORD@postgres.homeassistant.svc.cluster.local:5432/homeassistant?client_encoding=utf8`

**Do not change `secrets.postgresUser` / `secrets.postgresDb` from
`homeassistant`** unless you also update every hardcoded probe: the
`wait-for-postgres` initContainer
(`templates/homeassistant-deployment.yaml`) and the StatefulSet's
`pg_isready` probes (`templates/postgres-statefulset.yaml`) both hardcode
`-U homeassistant -d homeassistant`. This is a pre-existing limitation, not
new in phase 1 — see [Known limitations](#known-limitations).

## Quick start

```bash
# Install straight from the repo tarball (no clone needed)
helm install homeassistant \
  https://github.com/WOOWTECH/Woow_k3s_homeassistant/archive/refs/heads/main.tar.gz \
  -n homeassistant --create-namespace \
  --set secrets.create=true,secrets.postgresUser=homeassistant,secrets.postgresDb=homeassistant \
  --set secrets.postgresPassword="$(openssl rand -base64 24)"

# Or from a local clone, with the Secret managed outside Helm (see Secrets above)
git clone https://github.com/WOOWTECH/Woow_k3s_homeassistant.git
cd Woow_k3s_homeassistant
helm install homeassistant . -n homeassistant --create-namespace
```

Then open `http://<node-ip>:31812` and complete the onboarding wizard.

### Test install (own namespace, disposable storage, generated password)

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

Setting `namespace.name` equal to `-n` keeps `templates/namespace.yaml` from
rendering a second Namespace object — Helm's `--create-namespace` already made
the one it needs.

## Key values

| Value | Default | Description |
|---|---|---|
| `namespace.create` / `namespace.name` | `true` / `homeassistant` | Target namespace; rendered as an object only when it differs from `-n` |
| `keepOnUninstall` | `true` | `helm.sh/resource-policy: keep` on the Namespace (when rendered), both PVCs and the chart-created Secret |
| `secrets.create` | `false` | Render the Secret from `secrets.*` instead of using an existing one |
| `secrets.existingSecretName` | `postgres-secret` | Name of the Postgres credentials Secret, existing or chart-created |
| `homeassistant.image.tag` | `stable` | Home Assistant version |
| `homeassistant.service.type` / `nodePort` | `NodePort` / `31812` | How HA is exposed |
| `homeassistant.hostNetwork` | `false` | Set `true` for mDNS/SSDP discovery |
| `homeassistant.persistence.size` | `5Gi` | `/config` PVC (`local-path`) |
| `homeassistant.config.TZ` | `Asia/Taipei` | Timezone (shared with postgres) |
| `postgres.enabled` | `true` | Deploy the bundled PostgreSQL StatefulSet |
| `postgres.persistence.size` | `10Gi` | Postgres data PVC (`local-path`) |
| `tests.enabled` | `true` | `helm test` smoke pod |

Full list: [`values.yaml`](values.yaml)

## Verify

```bash
kubectl get pods -n homeassistant          # homeassistant + postgres Ready
helm test homeassistant -n homeassistant --logs
# The smoke pod checks: HA responds on its Service port with a 2xx/3xx status
# (onboarding wizard or login page), and (if postgres.enabled) pg_isready
# against the postgres Service using the same Secret the app reads. Read-only.
```

## Uninstall

```bash
helm uninstall homeassistant -n homeassistant
```

This removes the Deployment, StatefulSet, Services and ConfigMap. Data stays:

- both PVCs (`ha-config`, `postgres-data`) and the chart-created Secret carry
  `helm.sh/resource-policy: keep` (when `keepOnUninstall: true`, the default);
- the `homeassistant` namespace is the release namespace in the examples
  above and is therefore never rendered as an object, so it is never deleted
  either. A Namespace the chart does render (`namespace.name` different from
  `-n`) also carries the keep policy.

To really delete everything, including the data:

```bash
kubectl delete pvc -n homeassistant ha-config postgres-data
kubectl delete secret -n homeassistant postgres-secret   # only if secrets.create=true was used
kubectl delete namespace homeassistant                    # only if it is not shared with anything else
```

## Chart quality fixes (phase 1)

This phase changed only the chart, not the running application. Rendered
with default values, this chart is field-for-field identical to chart 1.0.0
(the previous `main` HEAD) except for:

1. **Namespace not rendered when it equals the release namespace.** Before,
   `templates/namespace.yaml` always rendered `Namespace homeassistant`
   whenever `namespace.create=true`, regardless of `-n`; `helm uninstall`
   would then delete that namespace and everything in it, including both
   PVCs. Now a namespace equal to `-n` is skipped (create it with
   `--create-namespace` instead), and a namespace the chart does render
   carries the keep policy.
2. **`helm.sh/resource-policy: keep`** added to the Namespace (when
   rendered), both PVCs, and the chart-created Secret, controlled by
   `keepOnUninstall` (default `true`).
3. **Secrets out of `values.yaml`.** `secrets.create` defaults to `false`;
   the chart only references an existing Secret by name
   (`secrets.existingSecretName`). The previous chart always rendered
   `postgres-secret` from `values.yaml`, which shipped a weak default
   password (`changeme`) baked into the repo. `secrets.create=true` now
   renders it from values, but every field is guarded with Helm's
   `required()`, so there is no default to forget to override.
4. **`securityContext.privileged: true` removed** from the Home Assistant
   container. It was hardcoded with no values toggle even though
   `hostNetwork` defaults to `false` and no USB/host device is mounted, so it
   only ever granted unnecessary root-level node access.
5. Added a read-only `helm test` smoke pod, this README's Secrets/CI/uninstall
   sections, and CI (`helm lint`, `helm template` across every values
   combination, `kubeconform -strict`, a check that the `required()` guards
   fire, a check that no secret is committed, and a check that every
   template is tracked in git and renders from a fresh clone).

No v2 redesign: resource names, labels, selectors, images, ports and pod
templates are byte-for-byte the same as before (aside from removing
`privileged: true`). `_helpers.tpl` only adds two small named templates
(namespace name, keep-annotation block); it does not derive any name from
`.Release.Name`.

## Known limitations (not fixed in phase 1)

These are pre-existing issues, out of scope for this pass, and not changed
by it:

- **`hostNetwork: true` + `dnsPolicy: ClusterFirst`.** Kubernetes requires
  `dnsPolicy: ClusterFirstWithHostNet` for a hostNetwork pod to resolve
  cluster-internal names; with `ClusterFirstWithHostNet` unset, the pod falls
  back to the node's own resolv.conf and the `wait-for-postgres`
  initContainer's `postgres.<ns>.svc.cluster.local` lookup never resolves.
  `homeassistant.hostNetwork=true` is therefore effectively broken today.
- **`pg_isready` and the recorder connection string hardcode user/db
  `homeassistant`**, independent of `secrets.postgresUser` /
  `secrets.postgresDb`. Only change those two values together with the
  probes in `templates/homeassistant-deployment.yaml` and
  `templates/postgres-statefulset.yaml`.
- **Default namespace name `homeassistant`** can collide with an unrelated
  `homeassistant` namespace already present on some clusters (e.g. a KubeVirt
  HAOS VM setup). Nothing in this chart auto-adopts an existing namespace —
  `helm install` fails cleanly with an ownership-metadata error if one exists
  — but pick a different `namespace.name` when that is the case.
- **Mutable image tags**: `homeassistant.image.tag: stable` and
  `postgres.image.tag: 16-alpine` both float. Pin a specific version if you
  need reproducible upgrades.
- **No configuration/secrets.yaml seeding.** The chart does not create
  Home Assistant's `config/configuration.yaml` or `config/secrets.yaml`; you
  still configure the recorder by hand after onboarding.

## Migrating from the old Kustomize deployment

This repository replaces the `k3s` branch of the archived
[Woow_ha_docker_compose_all](https://github.com/WOOWTECH/Woow_ha_docker_compose_all)
repo. Chart 1.0.0's default rendering was resource-equivalent to those
manifests (same names, namespace, labels, ports, PVCs), aside from
`imagePullPolicy: Always` on the HA container and a `managed-by: helm`
namespace label. This phase 1 pass changes the chart further — see
[Chart quality fixes](#chart-quality-fixes-phase-1) above for the complete,
current list of intentional differences from the original manifests.

This chart is not deployed anywhere today (checked on both the local laptop
cluster and woow-k3s — see the repo's git history for the Kustomize-era
manifests, which remain available). There is therefore no live release to
take over in this phase.

## License

MIT
