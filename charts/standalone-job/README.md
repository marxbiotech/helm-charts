# standalone-job

A reusable Helm chart for manual, on-demand, and operator-triggered Kubernetes
Jobs. The chart renders a normal `batch/v1` Job and is safe to include in an
umbrella chart because `job.enabled` defaults to `false`.

## Safety model

- No resources are rendered until `job.enabled=true`.
- The Job is not a Helm lifecycle hook unless `job.hook.enabled=true`.
- Every enabled run requires either a unique `job.runId` or an explicit,
  unique `job.nameOverride`. Kubernetes Job pod templates are immutable, so use
  a new identifier whenever the command, arguments, image, or configuration
  changes.
- An explicit image tag or digest is required; there is no floating default
  image.

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
  --version 0.1.0 \
  --namespace operations \
  --create-namespace \
  -f values-one-off.yaml

kubectl wait --for=condition=complete \
  job/reconcile-standalone-job-reconcile-20260719 \
  --namespace operations \
  --timeout=30m
kubectl logs job/reconcile-standalone-job-reconcile-20260719 \
  --namespace operations
```

After reviewing the result, set `job.enabled=false` and apply the values again.

## Ordersync backfill dry-run

Use a run ID that records both the purpose and execution mode:

```yaml
job:
  enabled: true
  runId: ordersync-backfill-dry-20260719
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
  --version 0.1.0 \
  -f values-dry-run.yaml
```

## Ordersync backfill commit run

Use the same reviewed image and inputs, change `COMMIT`, and choose a distinct
run ID:

```yaml
job:
  enabled: true
  runId: ordersync-backfill-commit-20260726
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

The different `runId` produces a different Job name and avoids immutable Job
spec collisions with the dry-run.

## Umbrella chart dependency

Declare the dependency in the umbrella chart:

```yaml
# Chart.yaml
dependencies:
  - name: standalone-job
    version: 0.1.0
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

## Optional Helm hook mode

Normal Jobs are recommended for operator-triggered runs. If lifecycle hook
behavior is intentionally required, opt in explicitly:

```yaml
job:
  enabled: true
  runId: post-upgrade-20260719
  hook:
    enabled: true
    events: [post-upgrade]
    weight: "0"
    deletePolicy: [before-hook-creation]
```

Only this mode adds `helm.sh/hook` annotations to the Job.
