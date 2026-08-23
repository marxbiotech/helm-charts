# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

工作前先讀 `README.md` 了解本 repo 的使用方式與貢獻流程。

## Overview

Helm charts monorepo for **marxbiotech**，所有 chart 位於 `charts/` 下，以 OCI artifact 形式發布至 GHCR（`oci://ghcr.io/marxbiotech/helm-charts/<chart-name>`）。

## CI 強制規則

每次修改 chart 時必須遵守，否則 CI 會失敗：

- `Chart.yaml` 的 `version` 必須遞增（`check-version-increment`）
- `Chart.yaml` 必須包含 `maintainers` 欄位（`validate-maintainers`）
- `helm lint` 與模板語法必須通過
- Chart 必須能在 Kind 叢集上成功安裝並通過 `helm test`

## 常用指令

```bash
helm lint charts/<chart-name>                                    # Lint 驗證
helm template my-release charts/<chart-name>                     # 本地渲染模板
helm template my-release charts/<chart-name> -f my-values.yaml   # 使用自訂 values 渲染
helm install my-release charts/<chart-name>                      # 安裝（需要 K8s 叢集）
helm test my-release                                             # 執行 chart 測試
```

## 新增 Chart 慣例

1. 建立 `charts/<chart-name>/`，包含 `Chart.yaml`、`values.yaml`、`templates/`；Helm test 放在 `templates/tests/`（非頂層 `tests/`），以確保 `helm template --show-only` 可正確找到
2. 以 `charts/sample-app/` 為 Deployment-type 參考範本；以 `charts/pre-hook-job/` 為 Job-type（hook）參考範本；以 `charts/standalone-job/` 為 one-off Job 參考範本；以 `charts/cronjob/` 為 CronJob-type 參考範本
3. `Chart.yaml` 使用 `apiVersion: v2`，必須含 `maintainers`
4. `_helpers.tpl` 命名慣例：`<chart-name>.name`、`<chart-name>.fullname`、`<chart-name>.labels`、`<chart-name>.selectorLabels`；若 chart 需要 ServiceAccount 則另加 `<chart-name>.serviceAccountName`
5. Job-type chart 額外慣例：hash-based naming（`<chart-name>.jobName`）、`app.kubernetes.io/component` label、`required` 強制必填欄位

## Workload Chart Values 慣例

Workload chart（Job/CronJob/Deployment）的 values surface 形狀有既定慣例，詳見 [`docs/workload-chart-values.md`](docs/workload-chart-values.md)。

**核心原則**：主物件的 spec 欄位與 `enabled` gate 同組（`job:`/`cronJob:`），pod-level 欄位攤平在頂層。

**必須參考的情境：**
1. 新增或修改 workload chart 的 values surface 時——先決定 key 該進分組還是留頂層，再寫 template。
2. 動到 `imagePullPolicy`/`imagePullSecrets`，或想把 image 字串抽成 helper 時——沒有單一規則，且抽 helper 會讓 template guard 綁的變數變成 dead code。
3. 為新 workload 物件設計資源名稱時——hash-based naming 只適用於 spec immutable 的 Job。

## Vendored Chart 慣例

從上游匯入的 vendored chart（如 `simple`）與第一方 chart 處理方式不同，詳見 [`docs/vendored-charts.md`](docs/vendored-charts.md)。

**核心原則**：template 邏輯與 values surface 屬於上游，不要硬套第一方慣例。

**必須參考的情境：**
1. 匯入新的 vendored chart 時——附 `UPSTREAM.md` 記錄 published package 與 matching source commit。
2. 為 vendored chart 補 `values.schema.json`——用 `additionalProperties: true` 只驗自己新增的 key，勿 schematize 整個上游 surface（否則會擋掉既有 key）。
3. helm test 可延後，但理由與 follow-up 計畫要寫進 `UPSTREAM.md` 的 Maintenance Decisions。

## 發布流程

- **PR 階段**（`lint-test.yaml`，觸發：`pull_request` → `main`）：`ct list-changed` 偵測變更 → `ct lint` 驗證 → Kind 叢集上 `ct install` 安裝測試
- **合併後**（`release.yaml`，觸發：`push main` + `charts/**`）：GHCR 登入 → `ct list-changed --target-branch HEAD~1` → 對每個變更的 chart 執行 `helm dependency build` → `helm package` → `helm push` 至 GHCR

## ct.yaml

- `chart-dirs: [charts]`
- `check-version-increment: true`
- `validate-maintainers: true`
