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
