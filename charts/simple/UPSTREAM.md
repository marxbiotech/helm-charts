# Upstream Provenance

This chart was imported from Shopline's `simple` chart version `0.18.0`.

- Published Helm repository: `https://shoplineapp.github.io/helm-charts`
- Published chart package: `simple-0.18.0.tgz`
- Source repository: `https://github.com/shoplineapp/helm-charts`
- Matching source commit: `55497ae67c504b3b2e94209277dd2e358966ed91`

The upstream repository tag named `0.18.0` points at repository commit
`46853981a7e65759671bdcca9e9ae7eebf4bc4a5`, but that commit contains
`simple/Chart.yaml` version `0.11.0`, so it does not match the published
`simple` chart package consumed downstream.

The imported files are from the published `simple-0.18.0` package because it
is the authoritative artifact currently consumed by downstream deployments.
The matching source commit differs from the published package only in
`Chart.yaml`: the source includes Helm 2 `tillerVersion` metadata that is not
present in the package.

## Maintenance Decisions

### No `helm test` under `templates/tests/` yet (deferred)

Unlike the repo's first-party charts (`sample-app`, `pre-hook-job`, `k8s-ssh`),
this chart does not yet ship a `templates/tests/` connection test. Adding one is
deferred to a dedicated follow-up rather than done in the import PR, because it
is a chart-wide convention task independent of any single feature and would
require the CI fixtures to grow a full `service:` definition and container port
purely to give the test something to reach. In the meantime `ct install` on Kind
still validates that the chart installs and renders on a live cluster. When the
follow-up lands, add a `templates/tests/test-connection.yaml` mirroring
`charts/sample-app/templates/tests/test-connection.yaml`, adapted to this
chart's conventions (Service name is `.Values.name`; no `simple.fullname` helper
exists, and the connecting fixture must define `service:` + a port).

### First-party pod-level keys added on top of upstream

Upstream `simple` has no pod-level `automountServiceAccountToken`. Version
`0.20.0` adds it next to `enableServiceLinks`, with the same shape: a top-level
boolean, rendered only when the key is present (`hasKey` guard), validated by
the additive `values.schema.json`. Absent keeps the Kubernetes default, so every
existing consumer renders byte-identical manifests.

Motivation: lander-marxbio-tech-env's `api-query` never calls the Kubernetes
API and used to render `automountServiceAccountToken: false` from a hand-written
template; moving it onto this chart must not lose that. IRSA workloads are not
affected by the flag, because the EKS pod identity webhook injects its own
projected token volume rather than relying on the default ServiceAccount mount.

CI: `ci/automount-false-values.yaml` installs the chart with the key set to
`false`, so the branch is exercised on Kind, not only by local `helm template`.

### Optional Kubernetes IngressClass

Version `0.21.0` adds `ingressClassName` to the single Ingress values and to
each named Ingress in multiple mode. AWS Load Balancer Controller can use
this field to select a shared ALB's IngressClass and settings. The templates
keep the existing annotations and rules. An omitted or empty class leaves
the rendered Ingress unchanged. The existing schema validates the new
field as a string in each mode.

Remove the legacy `kubernetes.io/ingress.class` annotation when setting
`ingressClassName`. The Kubernetes API rejects new Ingresses when both values
are present and differ.

`ci/ingress-class-single-values.yaml` and
`ci/ingress-class-multiple-values.yaml` exercise API acceptance in Kind.
Hosts, backend Services, and controller-specific annotations remain ordinary
chart values.

### Route existing workloads

Version `0.22.0` adds `deploymentEnabled`. It defaults to `true`; set it to
`false` to use the chart for Ingresses that reference Services managed
elsewhere. The boolean is validated by the additive values schema.

On upgrade, changing to `false` removes the Deployment previously managed
by that release. Deploy the external backends and verify the Service
endpoints before making that change.

Explicitly configured resources still render. A Rollout with a
`workloadRef` needs an existing Deployment named by `name` in the release
namespace. HPA and KEDA likewise need their scale target, either the Rollout
or that Deployment. A chart-managed Service or PodDisruptionBudget must
select the intended external pods. Check their rendered selectors before
enabling either one.

`ci/ingress-only-values.yaml` installs an Ingress and no Deployment in Kind.
The existing workload fixtures omit the key and exercise the enabled
behavior in the same check.

### Upstream 0.19.0–0.20.1 additions

Version `0.23.0` ports the additive changes upstream made after the imported
`0.18.0` package, so deployments still on the published Shopline `0.20.1`
package can move to this chart without losing behavior:

- The Deployment's pod template carries the `businessid` label (the
  Deployment metadata already had it).
- `envFromFieldRefs` on each container in `deployment.containers` renders
  `valueFrom.fieldRef` env vars (for example `status.hostIP`).
- `KEDA.ScaledObject.annotations` renders annotations on the ScaledObject.

The pod-template label changes the pod template, so existing consumers roll
their pods once when they upgrade to `0.23.0`. It is not part of the selector,
so the upgrade does not hit the immutable-selector error.

Two upstream changes are not ported because they would change manifests for
existing consumers of this chart: the Service/Ingress label rendering rewrite,
and the default
`alb.ingress.kubernetes.io/ssl-policy` that upstream adds when
`load-balancer-name` is set without an ssl-policy. Set the ssl-policy
annotation explicitly if you need it.

### `compute_checksum` for maps

Upstream `compute_checksum::<path>` only works when the path points at a
string; a map fails to render (`sha256sum` expects a string). Version `0.23.0`
hashes non-string values as JSON (`toJson` sorts map keys, so the result is
stable). String values keep the original hash, so existing annotations render
the same value. A path segment that does not exist fails the render
(`compute_checksum: <path>: missing key "<segment>"`) instead of hashing
`null`, so a typo cannot produce a checksum that never changes. An explicit
`null` value is still hashed.

Typical use: `deployment.annotations` with
`checksum/configmaps: compute_checksum::configmaps`, so any change to the
chart's ConfigMaps changes the pod template and rolls the pods. Do not point it
at `secrets`: the annotation is readable by anyone who can read the
Deployment, and an unsalted hash of secret values can be guessed offline when a
secret is short.

`ci/checksum-map-values.yaml` exercises the map branch and
`envFromFieldRefs` on Kind.

