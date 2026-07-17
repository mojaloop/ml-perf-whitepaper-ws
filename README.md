# Mojaloop Performance Testing Workstream

End-to-end perf lab: Terraform on AWS → Ansible deploys MicroK8s + Mojaloop
+ 8 DFSP simulators → k6 drives load, with independently-layerable security
options (edge sidecar mTLS, Cilium WireGuard pod-pod encryption, Istio
ambient mesh).

**📊 Benchmark results and scenario writeups live in
[benchmarks/README.md](benchmarks/README.md)** — the security-posture
comparison (plaintext / WireGuard / ambient mesh), with the results table and
links to each scenario's full report.

Each `make` stage is idempotent — re-run any failing stage in place.

## Repository layout

| Path | Contents |
|---|---|
| [benchmarks/](benchmarks/README.md) | **Scenario configs, results, reports** |
| `ansible/` | All deploy automation (roles: cilium, backend, switch, dfsp, mtls, ambient, monitoring, k6, onboarding, load_test…) |
| `terraform/` | AWS infra (VPC, nodes, NLB); per-scenario state via `TF_WORKSPACE` |
| `common/` | Version-specific base helm values (`mojaloop/<ver>.yaml`, `backend/<ver>.yaml`), DFSP values, Istio values |
| `phase1/` | Archived phase-1 scenarios + results (500/1000/2000 TPS) — reference only |
| `ttk-collections/` | Shared TTK onboarding collections (hub setup, sims onboarding) |
| `manifests/` | Raw k8s manifests (mTLS gateway/routes, nginx NodePort, …) |
| `certs/` | Lab CA/leaf generation for edge mTLS (`regen-certs.sh`) |
| `performance-tests/` | k6 scripts + k6-operator values |
| `docs/` | Architecture, mTLS design, tuning notes, cheatsheet |

## Prerequisites

- AWS account; profile `<AWS_PROFILE>` in `~/.aws/credentials`
- SSH key pair in AWS named `<SSH_KEY_NAME>`; private key at
  `~/.ssh/<SSH_KEY_NAME>.pem` (mode 0600)
- Local: `terraform`, `ansible`, `kubectl`, `helm`, `make`, `ssh`, `git`, `jq`, `yq`

## Setup once

```bash
cp .env.example .env
# edit .env: set AWS_PROFILE, AWS_DEFAULT_REGION, SSH_KEY_NAME,
#            DOCKERHUB_{USERNAME,TOKEN,EMAIL}, MYSQL_ROOT_PASSWORD
```

## Selecting a scenario

`SCENARIO=<name>` selects the scenario on every `make` target. The name
resolves to a directory by convention: `v<version>-<mtls>-<N>tps` maps to
`benchmarks/<version>/<mtls>/<N>tps/`; any other name maps to
`scenarios/<name>/` (ad-hoc, hand-authored). See
[benchmarks/README.md](benchmarks/README.md) for the scenarios.

## Run a benchmark scenario from scratch

```bash
SLUG=v17.1.0-mtls-wireguard-500tps

# 1. infra (provisioned ONCE → the scenario's artifacts/)
unset HTTPS_PROXY https_proxy                     # terraform talks to AWS directly, NOT via the bastion proxy
make terraform-init
make terraform-plan   SCENARIO=$SLUG              # always plan fresh — a leftover plan from a prior/destroyed run fails apply
make terraform-apply  SCENARIO=$SLUG              # ~10 min   AWS infra
make tunnel           SCENARIO=$SLUG              # SOCKS5 via bastion. To stop: lsof -ti :1080 | xargs kill
make k8s              SCENARIO=$SLUG              # ~15 min   MicroK8s + kubeconfigs
make cilium           SCENARIO=$SLUG              # ~3 min    swap Calico → Cilium eBPF (run on the EMPTY cluster, before app stages)

# 2. app stack — ORDER MATTERS (mtls patches the already-deployed sims, so it runs AFTER dfsp)
make monitoring       SCENARIO=$SLUG              # ~5 min    Prometheus + Grafana (promfana)
make backend          SCENARIO=$SLUG              # ~5 min    Kafka/MySQL/MongoDB/Redis
make switch           SCENARIO=$SLUG              # ~3 min    Mojaloop core (+ NODE_OPTIONS, configmap + topology patches)
make dfsp             SCENARIO=$SLUG              # ~5 min    8 sims (plain HTTP)
make mtls             SCENARIO=$SLUG              # ~2 min    sidecar mTLS: mtls_switch + mtls_dfsp (SKIP for mtls-off scenarios)
make dfsp-monitoring  SCENARIO=$SLUG              #           per-DFSP node/cAdvisor metrics → switch Prometheus
make istio-telemetry  SCENARIO=$SLUG              #           scrape Istio sidecar/proxy metrics (SKIP for mtls-off)
make k6               SCENARIO=$SLUG              #           k6-operator + CoreDNS

# 3. data + validate
make onboard          SCENARIO=$SLUG              # ~1 min    TTK Jobs (see onboard.yaml)
make provision        SCENARIO=$SLUG              # ~1 min    1000 MSISDNs/FSP
make smoke            SCENARIO=$SLUG              # MUST PASS — single transfer COMPLETED

# 4. load — as many times as you like; each lands in the scenario's results/<UTC>/
make load             SCENARIO=$SLUG
```

Compress stages 2–3 into one: `make deploy SCENARIO=$SLUG` runs
`monitoring → backend → switch → dfsp → mtls → dfsp-monitoring → istio-telemetry → k6 → onboard → provision → smoke`.

> **mtls-off scenarios:** skip `make mtls` and `make istio-telemetry`. mTLS is
> enabled purely by *running* those stages — not by config. Onboarding must
> register `http://` DFSP endpoints in that case.

`make help` lists every target. Tear down (frees nodes before the next
scenario — sizes differ, so scenarios don't coexist):

```bash
make terraform-destroy SCENARIO=$SLUG
```

## Optional security layers

Each layer is independent and measurable on its own; enable incrementally and
run `make load` per layer to isolate its cost.

- **Edge mTLS (DFSP ↔ switch, both directions)** — `make mtls` (sidecar-based;
  see [docs/mtls.md](docs/mtls.md)). Prerequisite: generate the shared CA/leaf
  cert Secrets once per clone — `./certs/regen-certs.sh` (git-ignored output,
  private key material). Re-run any time to rotate or change the SAN list.
- **Database TLS** — `db_ssl_enabled` in the mojaloop overrides + the
  `ADDITIONAL_CONNECTION_OPTIONS.ssl` block in patched configmaps.
- **Pod-pod encryption (WireGuard)** — encrypts all cross-node pod traffic
  in-kernel via Cilium (covers Kafka, MySQL, Mongo, Redis, inter-service HTTP;
  no app changes). Same-node pod traffic never leaves the host and is not
  encrypted:

  ```bash
  make cilium SCENARIO=$SLUG EXTRA='-e cilium_encryption_enabled=true'
  # verify on any switch node:
  #   microk8s kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status | grep -i encryption
  ```

`EXTRA` passes ad-hoc ansible args through any ansible-backed target.

### Gotchas

- **`unset HTTPS_PROXY` before any terraform command** — otherwise the AWS API
  call routes through the (possibly dead) bastion SOCKS proxy.
- **`terraform-apply` reuses a saved plan** — `<scenario>/artifacts/terraform.plan`,
  if present. Always run `make terraform-plan SCENARIO=$SLUG` immediately
  before it (see step 1 above); an old plan from a prior/destroyed state
  fails apply with `Error: Saved plan does not match the given state`.
- **kubectl/helm need the tunnel** — clusters are private; `make tunnel` first,
  then `export HTTPS_PROXY=socks5://127.0.0.1:1080` for ad-hoc `kubectl`.
- **Re-running `make dfsp` wipes sim state** — it restarts the mojaloop-simulator
  backend, dropping registered parties. Re-run `onboard → provision → smoke`
  (and `mtls` for mtls-wireguard) before `load`.
- **`make switch` skips helm when nothing changed** — it stamps a checksum of
  the chart version + values files in `artifacts/switch-helm.sum` and
  only runs helm when they differ (a full helm pass costs two switch-wide
  rollouts). Configmap and patch changes still apply and roll only the affected
  deployments. Force a full helm run: delete the stamp file, or
  `EXTRA='-e switch_helm_force=true'`.

> **Note:** `make monitoring` clones `https://github.com/mojaloop/helm` into
> the scenario's `artifacts/mojaloop-helm/` at deploy time because the
> `promfana` chart is not yet published to the Mojaloop Helm repo.

## Scenario customization

A benchmark scenario authors its config directly under
`benchmarks/<version>/<mtls>/<tps>/` — see
[benchmarks/README.md § Directory layout](benchmarks/README.md#directory-layout)
for the full layout, the two lifecycles (infra vs test runs), and how results
are recorded. One repo-wide sharp edge worth knowing before editing any
scenario: `configmaps/*.json` patches **replace the service's `default.json`
wholesale**, so a patched service must carry every setting there, not in helm
values.

## Documentation

- [benchmarks/README.md](benchmarks/README.md) — **scenarios, results, directory layout, tooling**
- [docs/architecture.md](docs/architecture.md) — topology + components
- [docs/mtls.md](docs/mtls.md) — cert chain + sidecar mTLS legs
- [docs/parameter-tuning.md](docs/parameter-tuning.md) — per-TPS sizing
- [docs/cheatsheet.md](docs/cheatsheet.md) — ad-hoc ops

> **Observability:** `make dfsp-monitoring` ships per-DFSP host/container metrics
> to the switch Prometheus (remote_write); `make istio-telemetry` scrapes Istio
> proxy/sidecar metrics. Both are included in `make deploy`.

## License

[LICENSE.md](LICENSE.md)
