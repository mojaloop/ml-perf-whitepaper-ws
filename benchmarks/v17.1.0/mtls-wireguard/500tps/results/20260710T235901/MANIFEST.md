# Run 20260710T235901 — Scenario #2 at 450 TPS: mTLS + full encryption (WireGuard, double-encrypted datastores)

**HEADLINE: steady-state e2e p99 = 918ms (σ 109ms), 999,810 transfers in
steady state, 99.99% success — MEETS the <1s goal. Full-run aggregate p99
959ms (also <1s). This is the passing rate for this configuration — the
same setup FAILS at the 500 TPS design target (see run 20260710T223654,
p99 1077ms). Kafka node CPU is still 87.4% at this reduced rate (barely
below its 88.8% at 500 TPS), confirming Kafka is the tightest resource
under the double-encryption cost.**

## Security composition

| Layer | Mechanism |
|---|---|
| DFSP ↔ switch (both directions) | Istio sidecar mTLS, file-mounted certs |
| service ↔ service | Cilium WireGuard only — no workload-identity mesh |
| apps ↔ Kafka | Kafka protocol TLS **+** WireGuard (double-encrypted) |
| apps ↔ MySQL | MySQL protocol TLS **+** WireGuard (double-encrypted) |

## Node CPU (steady window)

kafka 87.4%, mysql 64.7%, sw1-n1 53.8%, sw1-n2 79.1%, sw1-n3 78.0%,
sw1-n4 66.9%, sw1-n5 78.8%.

Full data: `steady-state.md`, `summary.json`, raw k6 logs — note the local
log-capture step produced no raw k6 pod logs for this particular run; the
raw summary block was recovered from terminal scrollback and is recorded
in `../../../README.md` §11 instead.
