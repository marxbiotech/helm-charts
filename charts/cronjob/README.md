# cronjob

A reusable Helm chart for scheduled Kubernetes workloads. The chart renders a
normal `batch/v1` CronJob and is safe to include in an umbrella chart because
`cronJob.enabled` defaults to `false`.

It is the scheduled counterpart to [`standalone-job`](../standalone-job): same
image, environment, security, and scheduling surface, with a schedule and the
CronJob-specific controls on top.

In the commands and dependency declaration below, replace `<chart-version>`
with the intended published chart version before running or copying the example.

## Safety model

- No resources are rendered until `cronJob.enabled=true`. A parent chart may
  also gate the dependency with `condition: <alias>.cronJob.enabled`.
- `cronJob.enabled` and `cronJob.suspend` are different switches, and both are
  useful:
  - `cronJob.enabled=false` — the CronJob object does not exist.
  - `cronJob.suspend=true` — it exists, holds its name and history, and does
    not fire. This is the rollout posture: install suspended, confirm the image
    really carries the subcommand, then flip `cronJob.suspend` to `false`.
- `cronJob.schedule` has no default. An enabled release without one fails at
  template time rather than quietly adopting some chart author's idea of a good
  hour.
- An explicit image tag or digest is required; there is no floating default
  image. A digest takes precedence when both are set, and that precedence is
  what makes leaving a stale digest in place while bumping the tag a silent
  no-op: the digest wins in the image string, so the rendered manifest is
  byte-identical, `helm upgrade` succeeds, and the schedule keeps running the
  old image. Pin one or the other, and blank the tag when moving a release to
  digest pinning.
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

The name is capped at **52** characters, not the usual 63. Kubernetes
validates CronJob names against `DNS1035LabelMaxLength - 11`, because each run
is named `<cronjob-name>-<unix-minutes>`. A 63-character name renders fine and
is then rejected by the API server at apply time, so `fullnameOverride` is
capped at 52 in the schema.

Dropping the behavior hash gave something up. `standalone-job` truncates its
name safely because the hash it appends guarantees that different long bases
cannot collide after truncation; a stable name has no such guarantee, and two
releases sharing a 52-character prefix would silently become one CronJob. The
chart therefore refuses an over-length name at template time instead of
truncating it. A release name must leave the generated name at or under 52
characters — `<release>-cronjob`, or the release name alone when it already
contains `cronjob` — and `fullnameOverride` is how to take control when it does
not.

## Retries

`job.backoffLimit` defaults to `0`.

For a scheduled job, a non-zero exit usually means an upstream dependency was
unreachable or answered short — a condition that does not fix itself within the
seconds a backoff waits, and one where an immediate retry repeats the whole
walk and consumes a second helping of any shared rate budget. The next
scheduled run is the retry. Raise it deliberately for workloads where a retry
really does help.

Set `job.activeDeadlineSeconds` for anything that must not overrun into the
next scheduled slot. `cronJob.concurrencyPolicy` defaults to `Forbid`, so a run
that overruns anyway suppresses the next one rather than doubling up.

Be careful setting `job.ttlSecondsAfterFinished` for tidiness. The TTL and the
history limits both delete finished Jobs, and whichever fires first wins, so a
TTL shorter than the period `cronJob.failedJobsHistoryLimit` spans quietly
overrides it — a one-hour TTL on a daily schedule leaves at most one failure
behind, not the week of failures the default of `7` was chosen to preserve.
Keep the TTL longer than that window, or leave it unset and let the history
limits do the cleanup.

`cronJob.startingDeadlineSeconds` is unset by default, so a missed run has no
deadline at all and the controller starts it whenever it next gets the chance.
Once more than 100 starts have been missed since the last one, the controller
stops backfilling them and schedules only the most recent slot, recording a
warning on the CronJob:

```
Warning  TooManyMissedTimes  too many missed start times. Set or decrease .spec.startingDeadlineSeconds or check clock skew
```

Scheduling continues from that point on; nothing latches off. Suspending is not
a way to accumulate missed starts either — while `cronJob.suspend` is `true` the
controller returns before computing any schedule, and on resume it runs the most
recent slot once. Set `cronJob.startingDeadlineSeconds` when a run that starts
long after its slot is worse than no run at all: it bounds how late a missed run
may start, and a run missed outside that window is dropped with a `MissSchedule`
event rather than started late.

## Schedule

`cronJob.schedule` accepts standard five-field cron syntax (`0 3 * * *`), the
named macros (`@daily`, `@hourly`, and friends), and `@every <duration>` —
`@every 90m` being the only way to express an interval that five-field cron
cannot represent at all.

The schema checks arity only: five whitespace-separated fields, a named macro,
or `@every <duration>`. It never inspects what a field contains, so a six-field
Quartz-style schedule is rejected by `helm template`, while a semantically
impossible one such as `99 99 * * *` passes and is rejected by the API server at
apply time, where the standard cron parser reads it.

## Time zone

`cronJob.timeZone` is the native Kubernetes `spec.timeZone` field (GA since
1.27) and takes an IANA name such as `Asia/Taipei`. It is omitted from the
manifest when empty, in which case the cluster's controller-manager time zone —
normally UTC — applies.

The field is honoured from 1.25 onward, where the feature gate is enabled by
default; the `CronJobTimeZone` gate was removed in 1.29, so from then on there
is no gate to turn off. Where it is not honoured — an older cluster, or one with
the gate turned off — the API server does not reject the field; it prunes
`spec.timeZone` from the object. The release installs cleanly and the schedule
then runs in the cluster time zone, so the `0 3 * * *` sweep below fires at
03:00 UTC — 11:00 in Taipei — with no error, event, or warning to say so.

Note the capital `Z`. `cronJob.timezone` is the Argo CronWorkflow spelling and
is rejected by this chart's schema.

## Daily sweep

Create `values-sweep.yaml`:

```yaml
cronJob:
  enabled: true
  schedule: "0 3 * * *"
  timeZone: "Asia/Taipei"
  suspend: true              # flip to false once the image is verified
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

Then set `cronJob.suspend: false` and upgrade.

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
    condition: consignmentSweep.cronJob.enabled
```

```yaml
# values.yaml
consignmentSweep:
  cronJob:
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

| File | Exercises |
|---|---|
| `disabled-values.yaml` | nothing renders when `cronJob.enabled=false` |
| `default-values.yaml` | minimal enabled release, `backoffLimit` default of `0` |
| `full-values.yaml` | `podLabels` on the pod template, `env` with `valueFrom`, `envFrom` with both ref kinds, `cronJob.timeZone`, ServiceAccount creation, scheduling and security surface |
| `digest-values.yaml` | a digest and a tag set together render successfully and yield a digest reference, `@daily` macro schedule |
| `suspended-values.yaml` | `cronJob.suspend: true`, and null optional fields omitted from the manifest |

`ct install` proves the API server accepts each of these configurations. It does
not prove that any field landed where it belongs. A CronJob's pod template has
no selector that must match its labels — the Job controller generates its own —
so a pod label moved up to the CronJob's own `metadata.labels` renders, lints,
and is admitted without complaint. A Deployment gets that check for free because
`spec.selector.matchLabels` must match `spec.template.metadata.labels`; there is
no equivalent surface here. Field placement is verified by hand, with the
`helm template --show-only ... | yq` command under
[Pod labels and NetworkPolicy](#pod-labels-and-networkpolicy).

The Helm test pod verifies test-hook plumbing only. A scheduled CronJob creates
no pod at install time, so observing a real run would mean waiting for the
schedule or granting the test pod RBAC to create a Job from the CronJob — both
are deferred.
