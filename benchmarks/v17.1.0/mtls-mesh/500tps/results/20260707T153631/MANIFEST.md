# Run 20260707T153631 — Scenario #3 FINAL: mTLS + service mesh (ambient, gap-free)

**HEADLINE: steady-state e2e p99 = 910ms (σ 109ms), 1,109,292 transfers in
steady state, 99.93% success — GOAL <1s MET. Full-run aggregate p99 963ms
(also <1s). Statistically identical to scenario #2 (909ms) — workload-identity
mesh with protocol-TLS datastores costs ~nothing over transparent encryption
at this scale.**

## Security composition (every transaction-path byte encrypted)

| Layer | Mechanism |
|---|---|
| DFSP ↔ switch (both directions) | Istio sidecar mTLS, file-mounted certs |
| service ↔ service | Istio ambient (ztunnel HBONE, SPIFFE identity), STRICT PeerAuthentication |
| apps ↔ Kafka | **Kafka protocol TLS (SSL-only listener, encrypt-only)** — broker outside the mesh |
| apps ↔ MySQL | MySQL protocol TLS (encrypt-only) — outside the mesh |
| Mongo/Redis | removed (no clients in this profile); ttk-mongodb retained for TTK |
| WireGuard | off — ambient + protocol TLS replace it |

## Dataplane cost (steady window)

- ztunnel: 1.57c total (5 app nodes; zero on datastore nodes — un-enrolled)
- Edge sidecars (istio-proxy): 2.30c
- Kafka broker (incl. protocol TLS): 2.28c — node 68.8% (vs 80.1% when ztunnel-wrapped)
- MySQL (incl. protocol TLS): 1.93c — node 55.3%
- Node CPU: n1 72.5 / n2 73.2 / n3 83.4 / n4 85.4 / n5 50.8 (pod spread drifted
  through the deploy-fix restarts; result achieved despite imbalance — a
  re-spread would add margin)

## Comparison (same 5× m7i.2xlarge, info logging, steady-state ≥1M)

| | #2 WireGuard stack | #3 ambient mesh (this run) |
|---|---|---|
| e2e p99 | 909ms | 910ms |
| σ | 115ms | 109ms |
| transfer p99 | 737ms | 698ms |
| quote p99 | 243ms | 288ms |
| discovery p99 | 53ms | 53ms |
| kafka node | 78.3% | 68.8% |
| mysql node | 69.7% | 55.3% |

## Provenance

Config: this scenario (kafka TLS + datastore un-enrollment + ambient) — see
../../README.md §15 for the deviations that MUST be reported alongside results
(wait-for-kafka TCP check, provisioning preScript, sslClientAuth, helm-wait
ordering, auto-create disabled + complete topic list, dead overrideConfiguration
key discovery). Steady-state window: start+5min .. end−2min; validity gate PASS
(prepare=fulfil=500.0/s, notif=position=2×).
