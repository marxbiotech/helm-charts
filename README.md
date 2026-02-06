# Helm Charts

Production-ready Helm charts published as OCI artifacts to [GitHub Container Registry (GHCR)](https://ghcr.io).

## Charts

| Chart | Description |
|-------|-------------|
| [sample-app](./charts/sample-app) | A sample Helm chart for Kubernetes |
| [pre-hook-job](./charts/pre-hook-job) | A generic chart for pre-install/pre-upgrade hook Jobs (DB migrations, seeding) |

## Install a Chart

```bash
# Install
helm install my-release oci://ghcr.io/marxbiotech/helm-charts/sample-app --version 0.1.0

# Pull without installing
helm pull oci://ghcr.io/marxbiotech/helm-charts/sample-app --version 0.1.0
```

## Add a New Chart

1. Create a new directory under `charts/`:
   ```bash
   mkdir -p charts/my-chart/templates
   ```
2. Add `Chart.yaml`, `values.yaml`, and templates following the [sample-app](./charts/sample-app) structure.
3. Include `maintainers` in `Chart.yaml` (validated by CI).
4. Open a PR — the lint-test workflow will automatically validate your chart.
5. After merge to `main`, the release workflow publishes the chart to GHCR.

## Local Development

```bash
# Lint a chart
helm lint charts/sample-app

# Render templates locally
helm template my-release charts/sample-app

# Render with custom values
helm template my-release charts/sample-app -f my-values.yaml

# Run chart tests (requires a Kubernetes cluster)
helm install my-release charts/sample-app
helm test my-release
```

## Release Pipeline

```
修改 chart + 遞增 version
         |
         v
    開 PR → main
         |
         |  lint-test.yaml (pull_request)
         |
         v
 ct list-changed ── 無變更 ──> 跳過
         |
       有變更
         |
         v
     ct lint .............. 格式 / version 遞增 / maintainers
         |
         v
   Kind 叢集建立
         |
         v
    ct install ............ helm install + helm test
         |
         v
   CI 通過，合併 PR
         |
         |  release.yaml (push main, charts/**)
         |
         v
   GHCR 登入 (GITHUB_TOKEN)
         |
         v
 ct list-changed .......... --target-branch HEAD~1
         |
         v
   對每個變更的 chart:
   helm dependency build
   helm package ──> .tgz
   helm push ────> oci://ghcr.io/marxbiotech/helm-charts/<chart-name>
```

### PR Validation (`lint-test.yaml`)

Triggered on `pull_request` targeting `main`.

| Step | Action | Detail |
|------|--------|--------|
| 1 | `ct list-changed` | Detect changes under `charts/`; skip all subsequent steps if none |
| 2 | `ct lint` | Validate Chart.yaml format, version increment, maintainers, template syntax |
| 3 | Kind cluster | Spin up a temporary Kubernetes-in-Docker cluster |
| 4 | `ct install` | Install changed charts on Kind and run `helm test` |

### Release to GHCR (`release.yaml`)

Triggered on `push` to `main` with changes in `charts/**`. Permissions: `contents: read`, `packages: write`.

| Step | Action | Detail |
|------|--------|--------|
| 1 | GHCR login | Authenticate with `github.actor` + `GITHUB_TOKEN` |
| 2 | `ct list-changed --target-branch HEAD~1` | Detect charts changed in this merge |
| 3 | `helm dependency build` | Build sub-chart dependencies (silently skipped if none) |
| 4 | `helm package` | Package into `<chart-name>-<version>.tgz` |
| 5 | `helm push` | Push to `oci://ghcr.io/marxbiotech/helm-charts` |

### Post-release Verification

```bash
helm pull oci://ghcr.io/marxbiotech/helm-charts/<chart-name> --version <version>
helm install my-release oci://ghcr.io/marxbiotech/helm-charts/<chart-name> --version <version>
```

## Contributing

1. Fork this repository.
2. Create a feature branch from `main`.
3. Make your changes under `charts/`.
4. Bump the `version` in `Chart.yaml` — CI enforces version increment on every change.
5. Run `helm lint` locally before pushing.
6. Open a Pull Request targeting `main`.
7. CI will lint and install-test your chart on a Kind cluster.
8. Once approved and merged, the chart is automatically published to GHCR.
