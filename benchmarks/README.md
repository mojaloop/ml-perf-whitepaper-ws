# Mojaloop Performance Benchmarks

Reproducible performance measurements of the Mojaloop switch across
different chart versions, security postures, and configurations. Every
scenario is validated with the same steady-state methodology (start+5min
.. end−2min trim, Kafka topic-rate validity gate, ≥1M transfers measured
per run). See each scenario's own README for its exact version, hardware,
and configuration.

## Security postures

| Posture | Description |
|---|---|
| **mtls-off** | Plaintext baseline — no encryption anywhere; the comparison floor. |
| **mtls-wireguard** | Edge mTLS (Istio sidecars) + Kafka/MySQL protocol TLS + Cilium WireGuard pod-pod encryption. Quantifies the cost of double-encrypting datastore traffic (WireGuard has no per-workload exclusion). |
| **mtls-mesh** | Edge mTLS (Istio sidecars) + Kafka/MySQL protocol TLS + Istio ambient mesh (ztunnel HBONE, SPIFFE workload identity, STRICT) with datastores excluded from the mesh. Every transaction-path byte encrypted. |

A given security posture may be run at different chart versions, TPS
targets, hardware profiles, or message-format modes (see the Results
table's Mode column) over time — each such run is one row in the Results
table below, with its own writeup. Each scenario's README is
self-contained: scenario definition, hardware,
security setup (crypto + traffic flows), tuning, deploy sequence, k6 +
steady-state results, capacity data, caveats, reproduction gotchas, and
dashboard screenshots.

## Scenarios

| Version | Security posture | Mode | Run TPS | Status | Actual TPS | Success % | e2e p99 (ms) | Financial transactions | Writeup |
|---------|------|---------|---------|--------|-----------|-----------|--------------|---------|---------|
| v17.1.0 | mtls-off | FSPIOP | 650 | PASS | 649.6 | 99.97 | 946 | ~1M | [README](v17.1.0/mtls-off/500tps/README.md) |
| v17.1.0 | mtls-wireguard | FSPIOP | 450 | PASS | 449.8 | 99.99 | 918 | ~1M | [README](v17.1.0/mtls-wireguard/500tps/README.md) |
| v17.1.0 | mtls-mesh | FSPIOP | 500 | PASS | 499.9 | 99.93 | 910 | ~1M | [README](v17.1.0/mtls-mesh/500tps/README.md) |
| v17.1.0 | mtls-mesh | ISO20022 | 500 | PASS | 499.7 | 99.96 | 951 | ~1M | [README](v17.1.0/mtls-mesh/500tps-iso20022/README.md) |

The e2e p99 goal is **<1s at the steady-state percentile** (the k6 full-run
aggregate is also recorded but is inflated by ramp edges). Note the "Run TPS"
column: each scenario is recorded at the highest rate it sustains under the
goal on this hardware, so the TPS differences between rows are themselves a
finding — plaintext holds 650, the ambient mesh holds the 500 design target,
and WireGuard-with-datastore-TLS (double encryption) needs to back off to 450.

## How to run a scenario

The full command sequence (terraform → k8s → app stack → onboard → smoke →
load) lives in the [repo-level README](../README.md#run-a-benchmark-scenario-from-scratch)
— identical for every scenario except the mTLS-related stages, which each
scenario's own README §10 spells out. After a run:

```bash
benchmarks/tools/steady-state.sh   # steady-state report from Prometheus — paste
                                    # the output into the scenario's README §12/§13
```

## Directory layout

```
benchmarks/
├── README.md                     # this file — scenarios, results, layout, tooling
├── tools/                        # steady-state.sh
└── <version>/
    └── <mtls>/                   # mtls-off / mtls-wireguard / mtls-mesh
        └── <tps>/
            ├── README.md         # the scenario reference — setup, results, deviations, screenshots
            ├── screenshots/      # per-dashboard Grafana captures from the recorded run
            ├── overrides/        # helm value diffs vs common/<chart>/<version>.yaml + aws.yaml; dfsp.yaml also carries DFSP replica counts (ansible vars, not forwarded to Helm)
            ├── configmaps/       # per-service Mojaloop configmap patches (replace default.json wholesale)
            ├── onboard.yaml      # TTK onboarding manifest (collections live in ttk-collections/ at repo root)
            ├── versions.yml      # chart versions: mojaloop/backend/simulator
            └── artifacts/        # INFRA — provisioned once (git-ignored)
```

**infra** is provisioned once into `artifacts/` (terraform state isolated per
scenario via `TF_WORKSPACE=<slug>`). Test runs are not committed as separate
files — the scenario's own README §11-13 is the single recorded result per
scenario, updated in place when a new run supersedes it.

`make` finds the scenario directory by naming convention — no registry, no wiring:

```
SCENARIO=v<version>-<mtls>-<N>tps   ->   benchmarks/<version>/<mtls>/<N>tps/
```

so `make <target> SCENARIO=v17.1.0-mtls-off-500tps` reads and writes this
directory directly; config edits take effect on the next make target.

### Chart versions (mojaloop / backend / simulator)

A scenario's `versions.yml` sets `scenario_chart_versions:` — the ansible
`_common` role merges it onto the pinned defaults, so a scenario overrides
only what differs. Base values files are version-specific:
`common/mojaloop/<version>.yaml` and `common/backend/<version>.yaml` (the
switch/backend roles fail fast if missing — create one per new version).

```yaml
# versions.yml
scenario_chart_versions:
  mojaloop: "17.1.0"
  mojaloop_backend: "17.1.0"
  mojaloop_simulator: "15.10.0"
```

## Extending

New scenario (version, mode, or TPS): copy an existing scenario dir, drop its
`artifacts/` + `screenshots/` content, adjust `versions.yml` and overrides,
and add a row to the Scenarios/Results tables above. The directory path must
follow `benchmarks/<version>/<mtls>/<N>tps/` — that's what the `SCENARIO`
name resolves to.
