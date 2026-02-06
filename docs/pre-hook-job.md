# pre-hook-job Design Knowledge

This document records non-obvious domain knowledge and design decisions for the `pre-hook-job` chart. It is intended for both human contributors and AI agents working on this codebase.

## Hash-Based Job Naming

**Problem:** Kubernetes Jobs are immutable. Once created, their `spec` cannot be updated. If Helm tries to upgrade a release and a Job with the same name already exists, the API server rejects the update.

**Solution:** The Job name includes a user-provided hash suffix: `<fullname>-<hash>`. When the Job's content changes (e.g., a new migration), the user provides a new hash, which produces a new Job name. Kubernetes sees it as a new resource and creates it.

**Idempotency:** If the hash is unchanged between upgrades, the Job name stays the same. Helm's `pre-install,pre-upgrade` hook will see the existing Job and skip recreation — the migration doesn't re-run unnecessarily.

**Why `required`:** The hash is mandatory (`required` in template) because omitting it would produce a static name, defeating the entire purpose. There is no sane default.

## hookDeletePolicy and ttlSecondsAfterFinished Interaction

These two mechanisms handle Job cleanup at different layers:

| Mechanism | Layer | When it acts | Default |
|-----------|-------|-------------|---------|
| `helm.sh/hook-delete-policy` | Helm | During `helm upgrade/install` | `hook-failed` |
| `ttlSecondsAfterFinished` | Kubernetes | After Job finishes | `86400` (24h) |

**Default strategy (`hook-failed` + `ttl=86400`):**
- If the Job **fails**: Helm deletes it immediately (so the next attempt can create a fresh Job with the same name).
- If the Job **succeeds**: Helm leaves it. Kubernetes TTL controller cleans it up after 24 hours. During those 24 hours, operators can inspect logs.

**Setting `ttlSecondsAfterFinished: null`:** Omits the field entirely from the rendered YAML. The Job persists until manually deleted or Helm deletes it. The template uses `kindIs "invalid"` to detect `null`.

**Other hookDeletePolicy options:**
- `hook-succeeded`: Deletes succeeded Jobs immediately (no log inspection window).
- `before-hook-creation`: Deletes the previous Job before creating the new one (useful if you don't use hash-based naming, but we do).

## Subchart Composition Pattern

This chart is designed to be used as a **subchart** (dependency), not standalone. The typical pattern:

```yaml
# Parent Chart.yaml
dependencies:
  - name: pre-hook-job
    alias: migration          # Each alias creates an independent instance
    version: "0.1.0"
    repository: "oci://ghcr.io/marxbiotech/helm-charts"
  - name: pre-hook-job
    alias: seeding
    version: "0.1.0"
    repository: "oci://ghcr.io/marxbiotech/helm-charts"
```

**Key points:**
- `alias` maps to a top-level key in the parent's `values.yaml`.
- `nameOverride` should be set per alias (e.g., `"migration"`, `"seeding"`) for readable resource names.
- `hookWeight` controls execution order across aliases: lower weight runs first (e.g., `-2` for migration, `-1` for seeding).
- `job.enabled: false` by default — the parent chart must explicitly enable each instance.

## Required Fields Design Rationale

Three fields use `required` and have no defaults:

| Field | Why no default |
|-------|---------------|
| `image.repository` | No universally correct image. An empty default produces `":tag"` which is invalid. |
| `image.tag` | Helm best practices prohibit floating tags (`:latest`). Forcing an explicit tag prevents accidental use of mutable tags. |
| `job.hash` | See "Hash-Based Job Naming" above. A static default defeats the purpose. |

Using `required` gives clear error messages at `helm template` / `helm install` time, rather than producing invalid YAML that fails at the Kubernetes API level.

## CI Fixture Testing for Hook Jobs

Hook Jobs have special CI considerations:

- **`ct install` skips hooks by default.** Chart-testing (`ct`) runs `helm install` which creates hooks, but `ct` doesn't verify hook execution. The test pod (`tests/test-job-render.yaml`) only renders when `job.enabled: true` to avoid errors when disabled.
- **`ci/disabled-values.yaml`** verifies that `job.enabled: false` produces zero resources — important because subchart defaults should be inert.
- **`ci/default-values.yaml`** uses `busybox:1.37` with a simple `echo` command — lightweight, no external dependencies, fast to pull.
- **`ci/full-values.yaml`** exercises every configurable field to catch template rendering issues.

## Template Design Patterns

- **`{{- with .Values.X }}`** wraps all optional sections. When the value is empty/nil, the entire block is omitted from output (no empty `env: []` or `volumes: []`).
- **`kindIs "invalid"`** checks for Go template nil (which is what YAML `null` maps to). Used for `ttlSecondsAfterFinished` to distinguish "not set" from "set to 0".
- **`| quote`** on all annotation values ensures they render as strings (Helm hook-weight must be a string).
- **`| nindent N`** for consistent YAML indentation in nested contexts.
