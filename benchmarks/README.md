# Mojaloop Performance Benchmarks — Security-Posture Comparison

Reproducible measurements of the Mojaloop switch (v17.1.0) under three
security configurations on **identical hardware** (5× m7i.2xlarge switch
nodes + dedicated Kafka/MySQL nodes + 8 DFSP simulators), all validated with
the same steady-state methodology (start+5min .. end−2min trim, Kafka
topic-rate validity gate, ≥1M transfers measured per run).

## Scenarios

| Scenario | Security posture | Full writeup |
|---|---|---|
| **mtls-off** | Plaintext baseline — no encryption anywhere; the comparison floor. Also carries the max-TPS exploration for this hardware (650 TPS verified <1s; 700 sustains but misses). | [README](v17.1.0/mtls-off/500tps/README.md) |
| **mtls-wireguard** | Edge mTLS (Istio sidecars) + Kafka/MySQL protocol TLS + Cilium WireGuard pod-pod encryption. Quantifies the cost of double-encrypting datastore traffic (WireGuard has no per-workload exclusion). | [README](v17.1.0/mtls-wireguard/500tps/README.md) |
| **mtls-mesh** | Edge mTLS (Istio sidecars) + Kafka/MySQL protocol TLS + Istio ambient mesh (ztunnel HBONE, SPIFFE workload identity, STRICT) with datastores excluded from the mesh. Every transaction-path byte encrypted. | [README](v17.1.0/mtls-mesh/500tps/README.md) |

Each scenario's README is self-contained: scenario definition, hardware,
security setup (crypto + traffic flows), tuning, deploy sequence, k6 +
steady-state results, capacity data, caveats, reproduction gotchas, and
dashboard screenshots.

## Results

| Version | mTLS | Run TPS | Status | Actual TPS | Success % | e2e p99 (ms) | Recorded run |
|---------|------|---------|--------|-----------|-----------|--------------|--------------|
| v17.1.0 | off | 650 | PASS | 649.6 | 99.97 | 946 | [20260713T143556](v17.1.0/mtls-off/500tps/results/20260713T143556/) |
| v17.1.0 | wireguard | 450 | PASS | 449.8 | 99.99 | 918 | [20260710T235901](v17.1.0/mtls-wireguard/500tps/results/20260710T235901/) |
| v17.1.0 | mesh | 500 | PASS | 499.9 | 99.93 | 910 | [20260707T153631](v17.1.0/mtls-mesh/500tps/results/20260707T153631/) |

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
benchmarks/tools/steady-state.sh              # steady-state report from Prometheus
benchmarks/tools/finalize-run.sh <scenario>   # write summary.json + MANIFEST.md into results/<UTC>/
```

## Directory layout

```
benchmarks/
├── README.md                     # this file — scenarios, results, layout, tooling
├── tools/                        # steady-state / finalize-run
└── <version>/
    └── <mtls>/                   # mtls-off / mtls-wireguard / mtls-mesh
        └── <tps>/
            ├── README.md         # the scenario reference — setup, results, deviations, screenshots
            ├── screenshots/      # per-dashboard Grafana captures from the recorded run
            ├── overrides/        # helm value diffs vs common/<chart>/<version>.yaml + aws.yaml; dfsp.yaml also carries DFSP replica counts (ansible vars, not forwarded to Helm)
            ├── configmaps/       # per-service Mojaloop configmap patches (replace default.json wholesale)
            ├── onboard.yaml      # TTK onboarding manifest (collections live in ttk-collections/ at repo root)
            ├── versions.yml      # chart versions: mojaloop/backend/simulator
            ├── artifacts/        # INFRA — provisioned once (git-ignored)
            └── results/<UTC>/                             # ONE recorded run per scenario:
                ├── steady-state.md                        #   authoritative percentiles + gate + node CPU
                ├── MANIFEST.md                            #   human record
                └── summary.json                           #   machine record
                                                             #   (raw k6 pod logs are not committed — *.log is git-ignored)
```

Two lifecycles per scenario: **infra** is provisioned once into `artifacts/`
(terraform state isolated per scenario via `TF_WORKSPACE=<slug>`); **test
runs** land in `results/<UTC>/`, many per provision, with exactly one kept +
recorded per scenario.

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
`artifacts/` + `results/` + `screenshots/` content, adjust `versions.yml` and
overrides, and add a row to the Scenarios/Results tables above. The directory
path must follow `benchmarks/<version>/<mtls>/<N>tps/` — that's what the
`SCENARIO` name resolves to.
