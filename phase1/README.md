# Phase 1 — archived scenarios (500 / 1000 / 1000-replication / 2000 TPS)

Archive of the first testing phase: per-TPS scenario configs and their raw
results, preserved as-is. These predate the phase-2 benchmark structure and
are **not runnable** via the current `make` workflow — they are reference
material only.

- `500tps/`, `1000tps/`, `1000tps-replication/`, `2000tps/` — each holds the
  scenario's overrides, configmaps, onboarding files, and `results/` from its
  runs.
- `k6-metrics.md` — definitions of the k6 metrics captured in these results.

Current work lives in [benchmarks/](../benchmarks/README.md).
