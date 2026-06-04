# Vendored Chart 慣例

## 背景

本 repo 除了第一方（first-party）自行撰寫的 chart（如 `sample-app`、`pre-hook-job`、
`k8s-ssh`）外，也會從上游（upstream）匯入 vendored chart——例如 `simple` 來自
Shopline 的 `simple` chart。Vendored chart 的 template 邏輯與 values surface 屬於
上游，不是我們維護的；硬套第一方 chart 的慣例（例如完整 schema、強制 helm test）反而
會破壞既有行為或增加不成比例的維護負擔。本文件記錄 vendored chart 的處理慣例。

## 慣例

### 1. 保留 provenance（`UPSTREAM.md`）

每個 vendored chart 都應在 chart 根目錄放一份 `UPSTREAM.md`，記錄：

- 上游 published Helm repository 與 chart package 檔名（例如 `simple-0.18.0.tgz`）
- 上游 source repository 與**確切的 matching source commit hash**
- 任何 tag 與 published package 之間的差異（這類差異會無聲地腐化，pin 住雙方才能稽核重現）

`UPSTREAM.md` 也作為「為何此 chart 偏離 repo 慣例」的權威說明處——把 vendored chart
的 design decisions 寫在這裡（見下方 helm test 慣例）。`.helmignore` 的 `*.md` 會讓它
不被打包，正好作為純維護者文件。

### 2. Schema：加性式（additive），不要接管上游契約

為 vendored chart 補 `values.schema.json` 時，**用 `additionalProperties: true`，
只列出你自己新增的 key**，不要 schematize 整個上游 values surface。

理由：第一方 chart（如 `sample-app`）用 `additionalProperties: false` 是好事，能擋下
所有 typo；但同樣的設定套在 vendored chart 上，會反過來擋掉整個上游既有的 values
surface，破壞所有既有 key。改用加性式 schema，就能在「不接管上游契約」的前提下，把你
新增欄位的型別錯誤從 apply-time（`kubectl apply` 才被 server 拒絕、訊息晦澀）提前到
template-time（`helm template`/`install` 即報出清楚錯誤）。

範例（只驗證自己新增的 `enableServiceLinks`）：

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "additionalProperties": true,
  "properties": {
    "enableServiceLinks": { "type": "boolean" }
  }
}
```

驗證確實生效：`helm template ... --set-string enableServiceLinks=banana` 應在
template 階段失敗並回報 `at '/enableServiceLinks': got string, want boolean`。

### 3. Helm test 可延後，但要記錄理由

第一方 chart 慣例要求 `templates/tests/` 下要有 helm test。對 vendored 的 pass-through
Deployment/Service chart，補 helm test 可能需要讓 CI fixture 長出完整的 `service:`
定義與 port，純粹只為了給 test pod 一個連線目標，訊號收益有限。此時可**延後**，但必須在
`UPSTREAM.md` 的 Maintenance Decisions 段落留下自包含的理由與 follow-up 計畫。在補上之前，
`ct install` 仍會在 Kind 上驗證 chart 能安裝與渲染。

## 使用時機

- 從上游匯入新的 vendored chart 時。
- 在 vendored chart 上新增第一方欄位（如新的 values key）時——用加性式 schema 驗證該欄位。

## 例外

- 第一方自行撰寫的 chart **不適用**本文件；它們應遵循 CLAUDE.md「新增 Chart 慣例」，包含
  `additionalProperties: false` 的完整 schema 與 `templates/tests/` helm test。
