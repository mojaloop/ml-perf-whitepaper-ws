# Mojaloop Performance Testing Workstream

End-to-end performance lab for the Mojaloop switch: Terraform provisions AWS
infrastructure, Ansible deploys MicroK8s clusters running Mojaloop and eight
DFSP simulators, and k6 drives load against the stack. Security posture is
independently layerable — edge sidecar mTLS, Cilium WireGuard pod-pod
encryption, and Istio ambient service mesh can each be enabled or omitted per
scenario, so their individual performance cost can be measured in isolation.

Benchmark results and scenario writeups live in
[benchmarks/README.md](benchmarks/README.md) — the security-posture
comparison across scenarios, with a results table and links to each
scenario's full report.

Every `make` stage is idempotent; re-run any failing stage in place without
restarting the whole sequence.

## Repository layout

| Path | Contents |
|---|---|
| [benchmarks/](benchmarks/README.md) | Scenario configs, results, and per-scenario reports |
| `ansible/` | Deploy automation — roles, playbooks, and group_vars (see [Ansible roles](#ansible-roles) below) |
| `terraform/` | AWS infrastructure (VPC, EC2 nodes, NLB); per-scenario state via `TF_WORKSPACE` |
| `charts/` | Helm chart for the k6 load-test runner (`charts/k6/`) |
| `common/` | Version-specific base Helm values (`mojaloop/<version>.yaml`, `backend/<version>.yaml`), DFSP values, and Istio values |
| `ttk-collections/` | Shared Mojaloop Testing Toolkit onboarding collections (hub setup, DFSP sim onboarding) |
| `manifests/` | Raw Kubernetes manifests (mTLS gateway/routes, nginx NodePort, network policy) |
| `certs/` | Lab CA/leaf certificate generation for edge mTLS (`regen-certs.sh`) |
| `docs/` | Architecture, mTLS design, parameter tuning, operational cheatsheet |
| `phase1/` | Archived phase-1 scenarios and results (500/1000/2000 TPS) — reference only, not runnable |

## Prerequisites

- An AWS account, with a named profile in `~/.aws/credentials`
- An SSH key pair registered in AWS, with the private key available locally
  (mode `0600`)
- Local tooling: `terraform`, `ansible`, `kubectl`, `helm`, `make`, `ssh`,
  `git`, `jq`, `yq`

## Setup once

```bash
cp .env.example .env
```

Edit `.env` and set:

| Variable | Purpose |
|---|---|
| `AWS_PROFILE` | AWS CLI/Terraform profile to use |
| `AWS_DEFAULT_REGION` | AWS region for all infrastructure |
| `SSH_KEY_NAME` | Name of the SSH key pair registered in AWS |
| `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `DOCKERHUB_EMAIL` | Docker Hub credentials, used to avoid pull-rate limits on cluster nodes |
| `MYSQL_ROOT_PASSWORD` | Root password for the deployed MySQL instance |

## Selecting a scenario

`SCENARIO=<name>` selects the scenario on every `make` target. The name
resolves to a directory by naming convention:

```
v<version>-<mtls>-<N>tps   ->   benchmarks/<version>/<mtls>/<N>tps/
```

For example, `SCENARIO=v17.1.0-mtls-wireguard-500tps` resolves to
`benchmarks/v17.1.0/mtls-wireguard/500tps/`. See
[benchmarks/README.md](benchmarks/README.md) for the current set of
scenarios.

A scenario's configuration lives directly in that directory — see
[benchmarks/README.md, Directory layout](benchmarks/README.md#directory-layout)
for the full structure and how results are recorded. One sharp edge worth
knowing before editing any scenario: `configmaps/*.json` patches **replace
the target service's `default.json` wholesale**, so a patched service must
carry every setting there, not rely on values also present in the Helm
values files.

## Run a benchmark scenario from scratch

```bash
SLUG=v17.1.0-mtls-wireguard-500tps

# 1. Infrastructure (provisioned ONCE, into the scenario's artifacts/)
unset HTTPS_PROXY https_proxy                     # terraform talks to AWS directly, not via the bastion proxy
make terraform-init
make terraform-plan   SCENARIO=$SLUG              # always plan fresh — a leftover plan from a prior/destroyed run fails apply
make terraform-apply  SCENARIO=$SLUG              # ~10 min   AWS infra
make tunnel           SCENARIO=$SLUG              # SOCKS5 via bastion. To stop: lsof -ti :1080 | xargs kill
make k8s              SCENARIO=$SLUG              # ~15 min   MicroK8s clusters + kubeconfigs
make cilium           SCENARIO=$SLUG              # ~3 min    swap Calico for Cilium eBPF (run on the empty cluster, before app stages)

# 2. Application stack — order matters (mtls patches the already-deployed sims, so it runs AFTER dfsp)
make monitoring       SCENARIO=$SLUG              # ~5 min    Prometheus + Grafana (promfana)
make backend          SCENARIO=$SLUG              # ~5 min    Kafka / MySQL / MongoDB / Redis
make switch           SCENARIO=$SLUG              # ~3 min    Mojaloop core services (+ NODE_OPTIONS, configmap, and topology patches)
make dfsp             SCENARIO=$SLUG              # ~5 min    8 DFSP simulators (plain HTTP)
make mtls             SCENARIO=$SLUG              # ~2 min    sidecar mTLS: mtls_switch + mtls_dfsp (skip for mtls-off scenarios)
make dfsp-monitoring  SCENARIO=$SLUG              #           per-DFSP node/container metrics, remote-written to the switch Prometheus
make istio-telemetry  SCENARIO=$SLUG              #           scrape Istio sidecar/proxy metrics (skip for mtls-off scenarios)
make k6               SCENARIO=$SLUG              #           k6 operator + CoreDNS

# 3. Data and validation
make onboard          SCENARIO=$SLUG              # ~1 min    TTK onboarding Jobs (see the scenario's onboard.yaml)
make provision        SCENARIO=$SLUG              # ~1 min    seed MSISDNs/parties on each DFSP simulator
make smoke            SCENARIO=$SLUG              # must pass — a single transfer completes end to end

# 4. Load — repeatable as many times as needed
make load             SCENARIO=$SLUG
```

Stages 2 and 3 can be compressed into a single command:
`make deploy SCENARIO=$SLUG`, which runs
`monitoring -> backend -> switch -> dfsp -> mtls -> dfsp-monitoring -> istio-telemetry -> k6 -> onboard -> provision -> smoke`.
`make deploy` does not include `cilium` or `ambient` — those remain separate,
opt-in steps (see [Optional security layers](#optional-security-layers)).

> **mtls-off scenarios:** skip `make mtls` and `make istio-telemetry`. mTLS
> is enabled purely by *running* those stages, not by configuration alone.
> Onboarding must register `http://` DFSP endpoints in that case.

`make help` lists every target. Tear down infrastructure once a scenario is
done with (frees the nodes before starting the next scenario — sizes differ
across scenarios, so they don't coexist on the same infrastructure):

```bash
make terraform-destroy SCENARIO=$SLUG
```

`make clean SCENARIO=$SLUG` removes a scenario's generated artifacts
(kubeconfigs, rendered manifests) without touching Terraform state — run
`terraform-destroy` first if the goal is a full teardown.

## Creating a new scenario

There is no scenario registry to update — a scenario is just a directory
following the naming convention from
[Selecting a scenario](#selecting-a-scenario). To test a new chart version,
a new TPS target, or a new security/mode combination that doesn't exist
yet:

```bash
# 1. Copy the closest existing scenario as a starting point
NEW=benchmarks/v17.2.0/mtls-mesh/2000tps
cp -r benchmarks/v17.1.0/mtls-mesh/500tps "$NEW"

# 2. Drop everything that's specific to the run you copied from —
#    a new scenario starts with none of this
rm -rf "$NEW"/artifacts "$NEW"/screenshots "$NEW"/results
```

Update chart versions in `versions.yml`, if they differ from what was copied:

```yaml
# versions.yml
scenario_chart_versions:
  mojaloop: "17.2.0"
  mojaloop_backend: "17.2.0"
  mojaloop_simulator: "15.10.0"
```

A version referenced here needs a matching base values file —
`common/mojaloop/<version>.yaml` and `common/backend/<version>.yaml` — the
switch/backend roles fail fast at deploy time if one is missing. Copy the
closest existing one and adjust for what actually changed in that chart
release.

Then adjust the new scenario's own overrides for the target load and mode:

| File | Adjust |
|---|---|
| `overrides/aws.yaml` | Node sizing, if the TPS target needs different hardware |
| `overrides/k6.yaml` | Target TPS, FSP pair weights, transaction count |
| `overrides/mojaloop.yaml` | Replica counts, log level, any mode toggles (see benchmarks/README.md for the multiples-of-node-count sizing note) |
| `overrides/backend.yaml` | Kafka partition counts (keep these matched 1:1 to their consumer's replica count), MySQL tuning |
| `overrides/dfsp.yaml` | DFSP simulator replica counts, scheme-adapter image/env |
| `onboard.yaml` | Which TTK collections and env file to onboard with |

Then run the full sequence from
[Run a benchmark scenario from scratch](#run-a-benchmark-scenario-from-scratch)
against the new `SCENARIO` name. Once a result is recorded, write the new
scenario's `README.md` (use an existing scenario's as the template — see
[benchmarks/README.md](benchmarks/README.md) for the section structure
every scenario report follows) and add a row to
[benchmarks/README.md](benchmarks/README.md)'s Security postures and
Results tables.

## Optional security layers

Each layer is independent and separately measurable; enable incrementally
and run `make load` after each to isolate its cost.

- **Edge mTLS** (DFSP <-> switch, both directions) — `make mtls`
  (sidecar-based; see [docs/mtls.md](docs/mtls.md)). Prerequisite: generate
  the shared CA/leaf certificate Secrets once per clone with
  `./certs/regen-certs.sh` (output is git-ignored, since it's private key
  material). Re-run any time to rotate certificates or change the SAN list.
- **Database TLS (MySQL)** — controlled by `db_ssl_enabled` in the Mojaloop
  overrides plus the `ADDITIONAL_CONNECTION_OPTIONS.ssl` block in the
  patched configmaps.
- **Kafka protocol TLS** — controlled by `tls.type`/`listeners.client.protocol`
  in `overrides/backend.yaml`; encrypt-only by default (`sslClientAuth: none`,
  matching the MySQL posture — clients connect without certificates). Every
  rdkafka client's `security.protocol` must be set to `ssl` to match, in the
  scenario's configmap patches.
- **Pod-pod encryption (Cilium WireGuard)** — encrypts all cross-node pod
  traffic in-kernel (covers Kafka, MySQL, MongoDB, Redis, and inter-service
  HTTP; no application changes required). Same-node pod traffic never
  leaves the host and is not encrypted by this layer:

  ```bash
  make cilium SCENARIO=$SLUG EXTRA='-e cilium_encryption_enabled=true'
  # verify on any switch node:
  #   microk8s kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status | grep -i encryption
  ```

- **Istio ambient service mesh** (pod-pod mTLS via per-node ztunnel proxies,
  SPIFFE workload identity, STRICT peer authentication) — `make ambient`.
  Must run after `make mtls` (or after `make deploy`, which includes it):

  ```bash
  make ambient SCENARIO=$SLUG
  ```

`EXTRA` passes ad-hoc Ansible arguments through any Ansible-backed target.

## Ansible roles

Deploy automation lives under `ansible/roles/`:

- `_common` — shared scenario-resolution logic
- `cilium` — CNI swap (Calico to Cilium eBPF)
- `backend` — Kafka / MySQL / MongoDB / Redis
- `switch` — Mojaloop core services
- `dfsp` — DFSP simulators
- `mtls_switch` / `mtls_dfsp` — sidecar mTLS, switch side and DFSP side
- `ambient` — Istio ambient mesh enrollment
- `monitoring` — Prometheus / Grafana
- `dfsp_monitoring` — per-DFSP metrics
- `istio_telemetry` — Istio proxy metrics
- `k6` — load-test runner
- `onboard` — TTK onboarding Jobs
- `sim_provision` / `als_provision` — party / MSISDN seeding
- `smoke_test` — end-to-end transfer validation
- `load_test` — k6 TestRun execution

## Observability

`make monitoring` deploys Prometheus, Grafana, and Alertmanager (the
`promfana` chart, release name `promfana`, namespace `monitoring`) onto the
switch cluster. Dashboards are provisioned from
`ansible/roles/monitoring/files/dashboards/` (see
`monitoring_custom_dashboards` in that role's `defaults/main.yml` for the
list actually wired in). This chart is cloned from
`https://github.com/mojaloop/helm` into the scenario's
`artifacts/mojaloop-helm/` at deploy time, because `promfana` is not yet
published to the Mojaloop Helm repository.

`make dfsp-monitoring` ships per-DFSP host/container metrics to this same
Prometheus via remote_write; `make istio-telemetry` scrapes Istio
proxy/sidecar metrics into it. Both are included in `make deploy`.

### Accessing Prometheus and Grafana

Clusters are private — start the tunnel first, then port-forward through
the switch cluster's kubeconfig:

```bash
make tunnel SCENARIO=$SLUG
export HTTPS_PROXY=socks5://127.0.0.1:1080

KCFG=benchmarks/<version>/<mtls>/<tps>/artifacts/kubeconfigs/kubeconfig-mojaloop-switch.yaml

# Prometheus
kubectl --kubeconfig "$KCFG" -n monitoring port-forward svc/promfana-kps-prometheus 9090:9090
# -> http://localhost:9090

# Grafana
kubectl --kubeconfig "$KCFG" -n monitoring port-forward svc/promfana-kps-grafana 3000:80
# -> http://localhost:3000
```

If the exact service names differ from a chart version bump, list what's
actually running: `kubectl --kubeconfig "$KCFG" -n monitoring get svc`.

Grafana admin credentials are in the chart-generated secret, not committed
anywhere:

```bash
kubectl --kubeconfig "$KCFG" -n monitoring get secret promfana-kps-grafana \
  -o jsonpath='{.data.admin-user}' | base64 -d; echo
kubectl --kubeconfig "$KCFG" -n monitoring get secret promfana-kps-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Prometheus is also reachable without a port-forward from any node already
on the tunnel network, via NodePort `30090` (`kps.prometheus.service` in
`common/monitoring.yaml`).

## Gotchas

- **`unset HTTPS_PROXY` before any Terraform command** — otherwise the AWS
  API call is routed through the (possibly dead) bastion SOCKS proxy.
- **`terraform-apply` reuses a saved plan** —
  `<scenario>/artifacts/terraform.plan`, if present. Always run
  `make terraform-plan SCENARIO=$SLUG` immediately before it; an old plan
  left over from a prior or destroyed state fails apply with
  `Error: Saved plan does not match the given state`.
- **`kubectl`/`helm` need the tunnel** — clusters are private; run
  `make tunnel` first, then `export HTTPS_PROXY=socks5://127.0.0.1:1080`
  for ad-hoc `kubectl` use.
- **Re-running `make dfsp` wipes simulator state** — it restarts the
  mojaloop-simulator backend, dropping registered parties. Re-run
  `onboard -> provision -> smoke` (and `mtls` for mtls-wireguard scenarios)
  before the next `load`.
- **`make switch` skips Helm when nothing changed** — it stamps a checksum
  of the chart version plus values files in `artifacts/switch-helm.sum` and
  only runs Helm when they differ (a full Helm pass triggers two
  switch-wide rollouts). Configmap and topology-patch changes still apply
  and roll only the affected deployments. Force a full Helm run by deleting
  the stamp file, or with `EXTRA='-e switch_helm_force=true'`.

## Phase 1

[phase1/](phase1/README.md) holds the first testing phase's scenarios and
raw results (500/1000/1000-replication/2000 TPS), preserved as-is. They
predate the current benchmark structure and are not runnable against the
`make` workflow described above — that workflow has since moved on. They
are runnable at the
[v1.0.0](https://github.com/mojaloop/ml-perf-whitepaper-ws/releases/tag/v1.0.0)
tag, which matches the tooling they were built against. Current work
lives under `benchmarks/`.

## Documentation

- [benchmarks/README.md](benchmarks/README.md) — scenarios, results,
  directory layout, tooling
- [docs/architecture.md](docs/architecture.md) — topology and components
- [docs/mtls.md](docs/mtls.md) — certificate chain and sidecar mTLS legs
- [docs/parameter-tuning.md](docs/parameter-tuning.md) — per-TPS sizing
- [docs/cheatsheet.md](docs/cheatsheet.md) — ad-hoc operational commands

## License

[LICENSE.md](LICENSE.md)
