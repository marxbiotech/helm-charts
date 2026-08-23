# cronjob

A reusable Helm chart for scheduled Kubernetes workloads. The chart renders a
normal `batch/v1` CronJob and is safe to include in an umbrella chart because
`enabled` defaults to `false`.

It is the scheduled counterpart to [`standalone-job`](../standalone-job): same
image, environment, security, and scheduling surface, with a schedule and the
CronJob-specific controls on top.

In the commands and dependency declaration below, replace `<chart-version>`
with the intended published chart version before running or copying the example.

## Safety model

- No resources are rendered until `enabled=true`. The key is top-level, so a
  parent chart may also gate the dependency with `condition: <alias>.enabled`.
- `enabled` and `suspend` are different switches, and both are useful:
  - `enabled=false` — the CronJob object does not exist.
  - `suspend=true` — it exists, holds its name and history, and does not fire.
    This is the rollout posture: install suspended, confirm the image really
    carries the subcommand, then flip `suspend` to `false`.
- `schedule` has no default. An enabled release without one fails at template
  time rather than quietly adopting some chart author's idea of a good hour.
- An explicit image tag or digest is required; there is no floating default
  image. A digest takes precedence when both are set.
- `job.backoffLimit` defaults to `0`, not the Kubernetes default of `6`. See
  [Retries](#retries).

## Naming

The CronJob name is stable — `fullname`, with no behavior hash.

This is a deliberate difference from `standalone-job`. A Job's
`spec.template` is immutable, so `standalone-job` has to rename itself whenever
the run configuration changes. A CronJob is fully mutable, so a stable name is
what lets a schedule, image, or environment change be an in-place update
instead of a delete-and-recreate that discards job history and any manual
`kubectl patch ... suspend`.

The name is truncated to **52** characters, not the usual 63. Kubernetes
validates CronJob names against `DNS1035LabelMaxLength - 11`, because each run
is named `<cronjob-name>-<unix-minutes>`. A 63-character name renders fine and
is then rejected by the API server at apply time, so `fullnameOverride` is
capped at 52 in the schema.

## Retries

`job.backoffLimit` defaults to `0`.

For a scheduled job, a non-zero exit usually means an upstream dependency was
unreachable or answered short — a condition that does not fix itself within the
seconds a backoff waits, and one where an immediate retry repeats the whole
walk and consumes a second helping of any shared rate budget. The next
scheduled run is the retry. Raise it deliberately for workloads where a retry
really does help.

Set `job.activeDeadlineSeconds` for anything that must not overrun into the
next scheduled slot. `concurrencyPolicy` defaults to `Forbid`, so a run that
overruns anyway suppresses the next one rather than doubling up.

## Time zone

`timeZone` is the native Kubernetes `spec.timeZone` field (GA since 1.27) and
takes an IANA name such as `Asia/Taipei`. It is omitted from the manifest when
empty, in which case the cluster's controller-manager time zone — normally UTC
— applies.

Note the capital `Z`. `timezone` is the Argo CronWorkflow spelling and is
rejected by this chart's schema.

## Daily sweep

Create `values-sweep.yaml`:

```yaml
enabled: true
schedule: "0 3 * * *"
timeZone: "Asia/Taipei"
suspend: true                # flip to false once the image is verified
concurrencyPolicy: Forbid

job:
  backoffLimit: 0
  activeDeadlineSeconds: 900

image:
  repository: ghcr.io/example/ordersync
  digest: sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

command: ["/app/ordersync"]
args: ["consignment", "sweep"]

envFrom:
  - configMapRef:
      name: stocksync-env
  - secretRef:
      name: stocksync-secret

podLabels:
  ordersync/purpose: backfill   # selected by the namespace egress NetworkPolicy

resources:
  requests:
    cpu: 50m
    memory: 128Mi
  limits:
    memory: 512Mi
```

Install and inspect:

```bash
helm upgrade --install ordersync-sweep \
  oci://ghcr.io/marxbiotech/helm-charts/cronjob \
  --version <chart-version> \
  --namespace ordersync \
  -f values-sweep.yaml

kubectl get cronjob -n ordersync \
  --selector app.kubernetes.io/instance=ordersync-sweep

# Prove it out before letting the schedule drive it
kubectl create job --from=cronjob/ordersync-sweep-cronjob \
  ordersync-sweep-manual -n ordersync
kubectl logs -f job/ordersync-sweep-manual -n ordersync
```

Then set `suspend: false` and upgrade.

## Pod labels and NetworkPolicy

`podLabels` reaches `spec.jobTemplate.spec.template.metadata.labels`, which is
the only place a NetworkPolicy `podSelector` looks. Annotations are never
matched by a selector, so a policy-bound workload that carries its purpose in
`podAnnotations` instead will be admitted, scheduled, and then fail at its
first outbound connection under a default-deny namespace.

Verify it lands in the right place before shipping:

```bash
helm template check charts/cronjob -f values-sweep.yaml \
  --show-only templates/cronjob.yaml \
  | yq '.spec.jobTemplate.spec.template.metadata.labels'
```

## Environment

`env` is a list, so `valueFrom` works:

```yaml
env:
  - name: COMMIT
    value: "false"
  - name: POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: ordersync
        key: database-url

envFrom:
  - configMapRef:
      name: stocksync-env
  - secretRef:
      name: backfill-secret
```

## Umbrella chart dependency

```yaml
# Chart.yaml
dependencies:
  - name: cronjob
    version: <chart-version>
    repository: oci://ghcr.io/marxbiotech/helm-charts
    alias: consignmentSweep
    condition: consignmentSweep.enabled
```

```yaml
# values.yaml
consignmentSweep:
  enabled: true
  schedule: "0 3 * * *"
  timeZone: "Asia/Taipei"
  suspend: false
  image:
    repository: ghcr.io/example/ordersync
    digest: sha256:...
  args: ["consignment", "sweep"]
  podLabels:
    ordersync/purpose: backfill
```

Add a second scheduled workload by declaring the same chart again under a
different alias.

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
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/scheduled-job
```

## Testing

`ct install` renders and applies every file under `ci/`:

| File | Covers |
|---|---|
| `disabled-values.yaml` | nothing renders when `enabled=false` |
| `default-values.yaml` | minimal enabled release, `backoffLimit` default of `0` |
| `full-values.yaml` | `podLabels` on the pod template, `env` with `valueFrom`, `envFrom` with both ref kinds, `timeZone`, ServiceAccount creation, scheduling and security surface |
| `digest-values.yaml` | digest wins when a tag is also set, `@daily` macro schedule |
| `suspended-values.yaml` | `suspend: true`, and null optional fields omitted from the manifest |

The Helm test pod verifies test-hook plumbing only. A scheduled CronJob creates
no pod at install time, so observing a real run would mean waiting for the
schedule or granting the test pod RBAC to create a Job from the CronJob — both
are deferred. Until then, the API server's rejection of a malformed spec during
`ct install` is what backs the `ci/` matrix above.
