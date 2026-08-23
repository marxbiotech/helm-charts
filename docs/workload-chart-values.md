# Workload Chart Values 慣例

## 背景

本 repo 的 workload chart（`standalone-job`、`pre-hook-job`、`cronjob`，以及
Deployment-type 的 `sample-app`）在 values surface 的形狀上其實已有一致慣例——有些慣例涵蓋
全部四個 chart，有些只適用於 Job-shaped 的前三個（見各條的適用範圍）——但這套慣例從未被寫
下來。新增 `cronjob` chart 時因此是照猜測建起來的，事後被 review 要求重構了兩次——同一個
根因出現兩遍。本文件把這套慣例記錄下來，讓下一個 workload chart 不必重來。

本文件只談 **values surface 的形狀**與**與它直接相關的 template 慣例**，不重複
CLAUDE.md「新增 Chart 慣例」已涵蓋的目錄結構、`Chart.yaml` 欄位與 `_helpers.tpl` 命名。

## 慣例

### 1. Values 分組：主物件的 spec 欄位與 enablement gate 同組，pod-level 欄位攤平在頂層

**適用範圍：Job-shaped chart（`standalone-job`、`pre-hook-job`、`cronjob`）。** Deployment-type
的 `sample-app` 不適用——它沒有 `deployment:` 分組、沒有 enablement gate，`replicaCount` /
`containerPort` / `service` 全部攤平在頂層。新增 Deployment chart 時請以 `sample-app` 為準
（CLAUDE.md「新增 Chart 慣例」第 2 條指定它為 Deployment-type 參考範本），不要套用本條。

以**資源 kind 命名的 map** 收納該物件自己的 spec 欄位，**enablement gate（`enabled`）
也放在同一個 map 裡**；pod-level（PodSpec / container）的欄位則一律攤平在 values 頂層。

現況（三個 Job-shaped chart 完全一致）：

| Chart | 主物件分組 | 內含 key |
| --- | --- | --- |
| `standalone-job` | `job:` | `enabled`, `runId`, `name`, `backoffLimit`, `ttlSecondsAfterFinished`, `activeDeadlineSeconds`, `annotations`, `labels` |
| `pre-hook-job` | `job:` | `enabled`, `hash`, `hookWeight`, `hookDeletePolicy`, `backoffLimit`, `ttlSecondsAfterFinished`, `activeDeadlineSeconds`, `annotations`, `labels` |
| `cronjob` | `cronJob:` | `enabled`, `schedule`, `timeZone`, `suspend`, `concurrencyPolicy`, `startingDeadlineSeconds`, `successfulJobsHistoryLimit`, `failedJobsHistoryLimit`, `annotations`, `labels` |
| `cronjob` | `job:` | `backoffLimit`, `activeDeadlineSeconds`, `ttlSecondsAfterFinished`, `annotations`, `labels` |

CronJob 巢狀了兩個物件，所以 `cronjob` 有兩個分組：`cronJob:` 對應 CronJob 自己的 spec，
`job:` 對應 `spec.jobTemplate.spec`。**一個分組對應一個 K8s 物件**，不要把兩層欄位混在一起。

以下 key 在上述三個 chart 中一律攤平在頂層，不要包進分組裡：

```
image, command, args, env, envFrom, resources,
podSecurityContext, securityContext, volumeMounts, volumes,
nodeSelector, tolerations, affinity, restartPolicy,
podAnnotations, podLabels, nameOverride, fullnameOverride
```

**`enabled` 屬於分組內部，不要另外開一個頂層 `enabled`。** 這個錯誤在 `cronjob` 上真的
犯過並且被回退掉：當時的理由是「頂層 `enabled` 才方便 parent chart 寫 dependency
`condition`」，但這不成立——Helm 的 dependency `condition` 接受任意 dotted path，parent
直接寫 `condition: <alias>.cronJob.enabled` 即可，頂層 `enabled` 換不到任何東西，只是讓
gate 與它所控制的物件 spec 分家。

### 2. `imagePullPolicy` / `imagePullSecrets` 沒有單一規則，是個陷阱

`imagePullPolicy` 在本 repo 中確實是分裂的，兩種寫法都有現役 chart：

| 寫法 | Chart |
| --- | --- |
| 巢狀 `image.pullPolicy` | `sample-app`、`pre-hook-job`、`k8s-ssh` |
| 頂層 `imagePullPolicy` | `standalone-job`、`cronjob` |

兩個頂層寫法的 chart 都在 `values.yaml` 留了 Design Decision 註解說明理由：
`standalone-job` 是為了維持既有 values contract（搬進 `image` 會是 breaking major-version
change）；`cronjob` 則是為了與 sibling one-off-Job chart 對齊，讓 values 檔在兩者間搬移時
不必再改寫這個 key，並明確承認自己是刻意的少數派（連自己的 `tests.image.pullPolicy`
都是巢狀的）。

`imagePullSecrets` 則沒有分裂：`sample-app`、`pre-hook-job`、`standalone-job`、`cronjob`
四個有這個 key 的 chart **一律攤平在頂層**（`k8s-ssh` 沒有這個 key）。

因此：**不要假設有單一規則。** 新 chart 動到這兩個 key 時，先看你要對齊的 sibling chart
怎麼寫，然後**不論選哪一種，都在 `values.yaml` 留下註解說明理由**——這是 repo 現況要求的，
兩個少數派 chart 都有留。

### 3. Template 開頭的 guard block

兩個 Job chart 與 `cronjob` 都在 template 最前面、`apiVersion:` **之前**放 `required` /
`fail` 驗證，並把 repository **綁進變數**，之後在組 image 字串時直接吃這個變數：

```gotemplate
{{- if .Values.cronJob.enabled }}
{{- $image := .Values.image | default dict }}
{{- $repository := required "image.repository is required when cronJob.enabled=true" $image.repository }}
{{- if not (or $image.digest $image.tag) }}
{{- fail "image.tag or image.digest is required when cronJob.enabled=true" }}
{{- end }}
```

```gotemplate
image: "{{ $repository }}{{ if $image.digest }}@{{ $image.digest }}{{ else }}:{{ $image.tag }}{{ end }}"
```

`standalone-job`（`$repository`）、`pre-hook-job`（`$repo`）、`cronjob`（`$repository`）
三者形狀相同。

**這些 guard 不是 `values.schema.json` 的冗餘。** 正常使用下 schema 先擋，但：

- `helm template --skip-schema-validation` 會整份跳過 schema，此時 template guard 是**唯一**
  還站著的防線。
- guard 的訊息可操作得多。實測同一份 values（`--set cronJob.enabled=true`）：

  ```
  # 走 schema
  Error: values don't meet the specifications of the schema(s) ...
    - at '/image': validation failed

  # 加 --skip-schema-validation，走 template guard
  Error: execution error at (cronjob/templates/cronjob.yaml:3:19):
    image.repository is required when cronJob.enabled=true
  ```

**推論：不要把 image 字串抽成 helper。** 抽走之後 template 頂端綁的 `$repository` 就沒有
消費者、變成 dead variable，guard 也就退化成純副作用。`cronjob` 原本有一個
`cronjob.image` helper，正是踩到這點，最後把 helper 拿掉、改成與 sibling 一致的 inline
寫法解決。

### 4. Hash-based naming 只適用於 Job

CLAUDE.md「新增 Chart 慣例」第 5 條的 hash-based naming（`<chart-name>.jobName`）**只適用
於 Job-type chart**，CronJob 不適用，理由如下：

- **Job 需要 hash**：Job 的 `spec.template` 是 immutable 的，改了設定就不能原地更新，所以
  `standalone-job` 把整份 Job/Pod behavior 雜湊成 8 字元後綴——behavior 一變，名字就變，
  等於自動 delete + recreate。`pre-hook-job` 則是由呼叫端傳入 `job.hash`。
- **CronJob 需要穩定名稱**：CronJob 整份 spec 是可變更的。若名字帶 hash，改 schedule /
  image / env 都會變成 delete + recreate，丟掉 job history 與手動 `suspend` 狀態。因此
  `cronjob.cronJobName` 直接回傳 `cronjob.fullname`，不加任何後綴。
- **失去 hash 也失去截斷安全性**：三個 chart 裡只有 `standalone-job` 能安全 `trunc`，因為
  它的 8 字元 behavior hash 涵蓋**未截斷**的 base，不同的長 base 截斷後不會撞在一起。穩定
  名稱扛不動這個保證，所以 `cronjob` **不截斷、直接報錯**。若容許截斷，兩個前 52 字元相同
  的 release 會塌成同一個 CronJob，事後只會以難解的 Helm ownership conflict 浮現，而不是在
  犯錯的當下。`pre-hook-job` 早就是同樣的政策：它的 hash 由呼叫端傳入、長度不定，也擔不起
  截斷保證，超過 63 字元就 `fail`。換句話說，三個 chart 裡有兩個把過長名稱視為**錯誤**而非
  截斷對象——`standalone-job` 的 `trunc` 才是那個需要 hash 撐腰的特例。

CronJob 名稱上限是 **52** 字元，不是一般的 63：Kubernetes 以 `DNS1035LabelMaxLength - 11`
驗證 CronJob 名稱，因為每次執行的 Job 叫 `<cronjob-name>-<unix-minutes>`。63 字元的名稱能
通過 `helm template`，然後在 apply 時才被 API server 拒絕。`cronjob` 把這個上限同時放在
`cronjob.cronJobName` 的 `fail` 與 `values.schema.json` 的 `fullnameOverride.maxLength: 52`。

## 使用時機

- 新增 Job-shaped workload chart（Job / CronJob）時——先照慣例 1 決定 values 形狀，再開始寫
  template。Deployment-type chart 不適用慣例 1，請以 `sample-app` 為範本，見慣例 1 的適用範圍。
- 為既有 Job-shaped workload chart 新增主物件 spec 欄位時——判斷它該進分組還是留頂層。
- 動到 image 相關 key，或想把 image 字串抽成 helper 時——見慣例 2 與 3。
- 為 workload chart 設計資源名稱時——見慣例 4，先確認該物件的 spec 是否 immutable。

## 例外

- Vendored chart（如 `simple`）**不適用**本文件；它們的 values surface 屬於上游，見
  [`docs/vendored-charts.md`](vendored-charts.md)。
- `k8s-ssh` 只有部分符合（沒有 `imagePullSecrets`、沒有 enablement gate），它不是
  workload chart 的參考範本；請以 CLAUDE.md「新增 Chart 慣例」第 2 條列出的範本 chart 為準。
- 已發布 chart 的既有 values contract 優先於本文件。要改形狀請走 breaking major-version
  change，並在 `values.yaml` 留 Design Decision 註解（`standalone-job` 的
  `imagePullPolicy` 就是這種情況）。
