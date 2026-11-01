# ssh-tunnel

A first-party, port-forwarding-only SSH endpoint for database maintenance. Clients can continue using `kubectl port-forward` plus `ssh -N -L`, or TablePlus/DBeaver's SSH tunnel feature. Only explicitly allowed destination strings can be reached.

Unlike `k8s-ssh`, this chart never writes SSH keys to Kubernetes nodes. It uses a Deployment and ClusterIP Service, without host namespaces, hostPath mounts, privileged containers, or a mounted ServiceAccount token. The existing `k8s-ssh` chart is separate and unchanged.

## Install and connect

Create values with your **public** keys and exact destinations (both lists are required; empty defaults deliberately fail validation):

```yaml
user: tunnel
authorizedKeys:
  - ssh-ed25519 AAAA... operator@example
permitOpen:
  - my-db.example.rds.amazonaws.com:5432
hostKeys:
  existingSecret: ssh-tunnel-host-keys
```

Provision a stable host identity out of band. Protect and back up this Secret as a private key; do not commit its contents:

```bash
ssh-keygen -t ed25519 -N '' -f ./ssh_host_ed25519_key
kubectl create namespace bastion
kubectl create secret generic ssh-tunnel-host-keys -n bastion \
  --from-file=ssh_host_ed25519_key=./ssh_host_ed25519_key \
  --from-file=ssh_host_ed25519_key.pub=./ssh_host_ed25519_key.pub
ssh-keygen -lf ./ssh_host_ed25519_key.pub
# Remove the local private key after storing any required backup securely.
rm ./ssh_host_ed25519_key ./ssh_host_ed25519_key.pub

helm install ssh-tunnel oci://ghcr.io/marxbiotech/helm-charts/ssh-tunnel \
  --version 0.1.0 -n bastion -f my-values.yaml
kubectl port-forward -n bastion svc/ssh-tunnel 2222:2222
```

In another terminal (verify the presented host fingerprint through the trusted channel above):

```bash
ssh -i ~/.ssh/id_ed25519 -p 2222 -N \
  -L 15432:my-db.example.rds.amazonaws.com:5432 tunnel@localhost
```

Connect your database client to `127.0.0.1:15432`. Keep the SSH and kubectl processes running. Use the database's TLS options as usual: the SSH tunnel ends at the Pod, and the Pod-to-database connection still needs database TLS if encryption is required on that segment.

For a GUI's built-in SSH tunnel, keep `kubectl port-forward` running; set SSH host `localhost`, SSH port `2222`, user `tunnel`, and your private key. Set the database destination to the allowed RDS hostname and database port. Do not select an option that opens a remote shell or runs a remote helper command. Alternatively, use the external `ssh -N -L` command and point the GUI directly at `127.0.0.1:15432`.

**The destination host string must match `permitOpen` exactly.** OpenSSH compares the requested string, without resolving aliases for this check. A DNS alias, IP, `localhost`, and the canonical hostname are distinct. Wildcards are rejected by the schema; IPv6 destinations use `[address]:port`. Operators should trust and control the DNS names they allow. Every authorized key shares the same destination allowlist.

## Security and image initialization

The image is `lscr.io/linuxserver/openssh-server`, pinned to the multi-platform digest in `values.yaml`; `image.tag` is informational and does not select the image. The pinned index supports amd64 and arm64. No custom image is built.

The container starts as root because LinuxServer's s6 initialization renames its `abc` account, sets UID/GID 1000, creates host keys, and adjusts ownership. Its SSH listener and sessions then run as the unprivileged `tunnel` user (or `user`), with sudo disabled. Choose a user name that does not already exist in the image; `root` is rejected. The root filesystem must remain writable for this upstream initialization. This chart requires a namespace policy that permits that root startup and the listed capabilities; it does not meet Kubernetes Restricted Pod Security requirements.

All capabilities are dropped, with only these restored for image initialization and supervision:

| Capability | Purpose |
|------------|---------|
| CHOWN | Upstream adjusts account/configuration ownership |
| DAC_OVERRIDE | Initialization traverses and updates files owned by the SSH account |
| FOWNER | Initialization adjusts permissions after ownership changes |
| SETUID / SETGID | s6 changes to the SSH account and sets supplementary groups |
| KILL | s6 supervision signals services running as the SSH account on shutdown |

`allowPrivilegeEscalation: false` and `seccompProfile: RuntimeDefault` are fixed, as are the security settings; they cannot be weakened through values. No low-port bind capability is needed: sshd listens on 2222. SSH sessions cannot acquire root privileges.

The ConfigMap contains public keys, a complete `sshd_config`, and a short startup script. Before `/init`, the script copies the configuration into writable `/config/sshd/sshd_config`. The pinned image's `init-openssh-server-config` only copies a default when this file is absent; it then edits port/password settings and ownership. Our complete file contains no `Include` or `Match`, uses the same port and password policy as those edits, and cannot inherit weaker defaults from another file. Mounting the ConfigMap read-only directly at the mutable destination would break upstream `sed`/`chown`, so it is mounted separately at `/chart-config`. `PUBLIC_KEY_FILE` imports the mounted keys into the account's authorized_keys. A ConfigMap checksum triggers Pod replacement when configuration or public keys change.

Public-key authentication is mandatory. Password, keyboard-interactive, root login, agent/X11/Unix-socket forwarding, remote TCP forwarding, tunnels, TTY, user RC, and user environment are disabled. `AllowUsers` limits login to the configured account. `ForceCommand echo "port forwarding only"` replaces shell and command sessions; `ssh -N -L` opens no session and keeps working. There is no SFTP subsystem. Local TCP forwarding is restricted with `PermitOpen`. Keepalives use 60 seconds / 3 failures. `LogLevel VERBOSE`, upstream `sshd -e`, and `LOG_STDOUT=true` send SSH connection, key fingerprint, and denial logs to `kubectl logs`; this is connection auditing, not database query auditing.

## Host keys and lifecycle

`hostKeys.existingSecret` must contain `ssh_host_ed25519_key` (unencrypted OpenSSH private key); `ssh_host_ed25519_key.pub` is optional. The chart copies the private key to a writable directory with mode 0600 and derives its public key. Upstream uses this directory and does not generate replacement keys. Pods use the same host identity across restarts and replacements. Secret updates require `kubectl rollout restart deployment/<release-name>`; external Secret contents cannot be included in the ConfigMap checksum.

Without an existing Secret, the image generates keys in `/config` (`emptyDir`). A container restart within that Pod retains them, but Pod replacement, rollout, rescheduling, or reinstall changes them, triggering SSH/GUI host-key warnings. Provision the Secret before production use. Verify intended rotations before updating client known_hosts entries.

The Deployment uses `Recreate` (default one replica), accepting brief downtime during updates to avoid overlapping old and new authorized-key policies. `replicaCount > 1` should use a shared host-key Secret. Existing tunnels are interrupted on replacement. Without a PVC, no account or authorized-key state survives Pod replacement.

## Values

| Value | Default | Purpose |
|-------|---------|---------|
| `authorizedKeys` | `[]` (required) | Single-line OpenSSH public keys, one per entry |
| `permitOpen` | `[]` (required) | Exact allowed `host:port` destination strings |
| `user` | `tunnel` | SSH account (UID/GID 1000) |
| `hostKeys.existingSecret` | `""` | Stable host-key Secret |
| `replicaCount` | `1` | Number of replicas |
| `image.repository` / `image.digest` | See values.yaml | Immutable upstream image selection |
| `image.tag` | `10.3_p1-r1-ls241` | Informational version only |
| `image.pullPolicy` / `imagePullSecrets` | `IfNotPresent` / `[]` | Image pull configuration |
| `service.port` | `2222` | ClusterIP port, targeting fixed container port 2222 |
| `networkPolicy.enabled` | `false` | Create ingress/egress policy |
| `networkPolicy.egressCIDRs` | `[]` | Allowed destination CIDRs (TCP ports); sshd still restricts exact host/port |
| `resources` | Requests: 10m CPU / 64Mi; memory limit: 128Mi | Container resources |
| `nodeSelector` / `tolerations` / `affinity` | `{}` / `[]` / `{}` | Scheduling |
| `podAnnotations` / `podLabels` | `{}` / `{}` | Extra metadata; checksum and selector labels are reserved |
| `nameOverride` / `fullnameOverride` | `""` / `""` | Resource naming |

When NetworkPolicy is enabled, ingress permits only TCP 2222 (from any source), and egress permits TCP/UDP 53 to cluster Pods plus TCP to `egressCIDRs`. Specify the database's actual destination CIDRs; DNS names in `permitOpen` do not automatically allow egress. DNS with a node-local IP or an external resolver needs a separate policy allowing that resolver. NetworkPolicy needs a supporting CNI; default Kind networking does not enforce it. Other policies selecting the Pod can add permissions. ClusterIP is reachable by other cluster workloads unless restricted by additional policies. Kubernetes RBAC should separately restrict who can port-forward; SSH keys are still required to authenticate.

## Validation

```bash
helm lint charts/ssh-tunnel -f charts/ssh-tunnel/ci/default-values.yaml
helm template ssh-tunnel charts/ssh-tunnel -f charts/ssh-tunnel/ci/default-values.yaml
# Expected failures: required keys and destinations have no safe defaults.
helm lint charts/ssh-tunnel
helm template ssh-tunnel charts/ssh-tunnel
```

CI's `ct install` uses `ci/default-values.yaml`, which contains a generated public key whose private key was discarded. `helm test` starts a non-root BusyBox Pod and requires an `SSH-2.0` Service banner; it checks reachability without needing private credentials or an external database. The CI destination is illustrative and is never contacted by that test.

For image updates, inspect the pinned init/service scripts again and verify `sshd.pam -T -f /config/sshd/sshd_config -h /config/ssh_host_keys/ssh_host_ed25519_key` in the running container. Exercise an allowed local tunnel, a disallowed destination, shell/command sessions, and rejected remote forwarding under the same capability and no-new-privileges constraints. Actual validation evidence for this version is recorded in the PR description.

Upstream references: [image documentation](https://docs.linuxserver.io/images/docker-openssh-server/), [pinned init script](https://github.com/linuxserver/docker-openssh-server/blob/fbd276f233403477e9a02559a12f462be71f90e8/root/etc/s6-overlay/s6-rc.d/init-openssh-server-config/run), and [pinned SSH service](https://github.com/linuxserver/docker-openssh-server/blob/fbd276f233403477e9a02559a12f462be71f90e8/root/etc/s6-overlay/s6-rc.d/svc-openssh-server/run).
