# standalone-job

A reusable Helm chart for manual, on-demand, and operator-triggered Kubernetes
Jobs. The chart renders a normal `batch/v1` Job and is safe to include in an
umbrella chart because `job.enabled` defaults to `false`.

## Safety model

- No resources are rendered until `job.enabled=true`.
- Every enabled run requires either a unique `job.runId` or an explicit,
  unique operator-readable name base in `job.name`.
- `job.name` takes precedence over `job.runId` when both are set. The top-level
  `nameOverride` retains its standard Helm meaning and only changes the chart
  base name used with `job.runId`.
- The generated Job name is the readable base plus an 8-character behavior
  hash. The base is either `job.name` or `fullname` + `-` + `job.runId`.
  Only the base is safely truncated when necessary, so the final DNS label
  remains at most 63 characters and always retains the hash.
- The hash includes the original untruncated base and the Job/Pod execution
  settings. Changing the image, command, arguments, environment, resources,
  service account, security or scheduling configuration therefore creates a
  new name and avoids immutable Job pod-template collisions.
- Naming is deterministic: the same readable base and execution settings
  produce the same name. Choose a new `job.runId` or `job.name` when repeating
  an otherwise identical run.
- An explicit image tag or digest is required; there is no floating default
  image.

In the commands and dependency declaration below, replace `<chart-version>`
with the intended published chart version before running or copying the example.

## Simple one-off Job

Create `values-one-off.yaml`:

```yaml
job:
  enabled: true
  runId: reconcile-20260719

image:
  repository: ghcr.io/example/reconcile
  tag: "2.4.1"

command: ["/app/reconcile"]
args: ["--tenant", "store-123"]

resources:
  requests:
    cpu: 100m
    memory: 128Mi
```

Run it and inspect the result:

```bash
helm upgrade --install reconcile \
  oci://ghcr.io/marxbiotech/helm-charts/standalone-job \
  --version <chart-version> \
  --namespace operations \
  --create-namespace \
  -f values-one-off.yaml

kubectl get jobs \
  --selector app.kubernetes.io/instance=reconcile,app.kubernetes.io/component=standalone-job \
  --namespace operations
kubectl wait --for=condition=complete job \
  --selector app.kubernetes.io/instance=reconcile,app.kubernetes.io/component=standalone-job \
  --namespace operations \
  --timeout=30m
kubectl logs \
  --selector app.kubernetes.io/name=standalone-job,app.kubernetes.io/instance=reconcile \
  --namespace operations
```

After reviewing the result, set `job.enabled=false` and apply the values again.

## Ordersync backfill dry-run

Use a run ID that records both the purpose and execution mode:

```yaml
job:
  enabled: true
  runId: dry-20260719
  backoffLimit: 1
  activeDeadlineSeconds: 7200

image:
  repository: ghcr.io/example/ordersync
  digest: sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

command: ["/app/ordersync"]
args: ["backfill", "--store-id", "store-123"]

env:
  - name: COMMIT
    value: "false"
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: ordersync
        key: database-url
```

Render and inspect before applying:

```bash
helm template ordersync-backfill \
  oci://ghcr.io/marxbiotech/helm-charts/standalone-job \
  --version <chart-version> \
  -f values-dry-run.yaml
```

## Ordersync backfill commit run

Use the same reviewed image and inputs, change `COMMIT`, and choose a distinct
run ID:

```yaml
job:
  enabled: true
  runId: commit-20260726
  backoffLimit: 1
  activeDeadlineSeconds: 7200

image:
  repository: ghcr.io/example/ordersync
  digest: sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

command: ["/app/ordersync"]
args: ["backfill", "--store-id", "store-123"]

env:
  - name: COMMIT
    value: "true"
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: ordersync
        key: database-url
```

The different `runId` produces a different readable prefix and hash. A change
to the execution settings also produces a different hash, avoiding immutable
Job spec collisions with the dry-run.

## Umbrella chart dependency

Declare the dependency in the umbrella chart:

```yaml
# Chart.yaml
dependencies:
  - name: standalone-job
    version: <chart-version>
    repository: oci://ghcr.io/marxbiotech/helm-charts
    alias: ordersyncBackfill
```

Keep it disabled in normal environment values:

```yaml
# values.yaml
ordersyncBackfill:
  job:
    enabled: false
```

For a planned run, use a temporary values file or reviewed environment change:

```yaml
# values-backfill.yaml
ordersyncBackfill:
  job:
    enabled: true
    runId: ordersync-backfill-dry-20260719
  image:
    repository: ghcr.io/example/ordersync
    tag: "2.4.1"
  args: ["backfill", "--store-id", "store-123"]
  env:
    - name: COMMIT
      value: "false"
```

```bash
helm dependency update ./umbrella
helm upgrade --install my-app ./umbrella -f values-backfill.yaml
```

Wait for completion, inspect logs, and then apply `job.enabled=false` again.
The reviewed enable/disable changes and run-specific values provide the audit
trail.

## ServiceAccount

Use an existing ServiceAccount:

```yaml
serviceAccount:
  create: false
  name: batch-operator
```

Or create one with the chart:

```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/batch-job
```
