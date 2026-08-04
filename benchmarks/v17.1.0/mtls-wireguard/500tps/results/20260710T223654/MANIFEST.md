# Run 20260710T223654 — Scenario #2 at 500 TPS: mTLS + full encryption (WireGuard, double-encrypted datastores)

**HEADLINE: steady-state e2e p99 = 1077ms (σ 128ms), 1,079,992 transfers in
steady state, 99.995% success — FAILS the <1s goal. Full-run aggregate p99
1936ms. Root cause: Kafka-TLS + MySQL-TLS traffic gets encrypted a second
time by Cilium WireGuard (no per-workload exclusion mechanism, unlike
ambient mesh's `dataplane-mode: none`), and Kafka's own JMX metrics show its
I/O threads 99.99% idle — the bottleneck is kernel-level WireGuard crypto
overhead, not Kafka request handling. See the 450tps run (20260710T235901)
for the passing rate under this same configuration.**

## Security composition

| Layer | Mechanism |
|---|---|
| DFSP ↔ switch (both directions) | Istio sidecar mTLS, file-mounted certs |
| service ↔ service | Cilium WireGuard only — no workload-identity mesh |
| apps ↔ Kafka | Kafka protocol TLS **+** WireGuard (double-encrypted) |
| apps ↔ MySQL | MySQL protocol TLS **+** WireGuard (double-encrypted) |

## Node CPU (steady window)

kafka 88.8%, mysql 69.2%, sw1-n1 59.6%, sw1-n2 86.9%, sw1-n3 85.5%,
sw1-n4 75.8%, sw1-n5 87.2% — Kafka and 3 of 5 switch nodes running much
hotter than mtls-mesh's equivalent run (peak 71%).

Full data: `steady-state.md`, `summary.json`, raw k6 logs in this directory.
