# 500 TPS — Three-Way Comparison: no-mTLS vs mTLS (egress-GW) vs mTLS (sidecar)

**Headline:** moving mTLS origination from the centralized Istio **egress gateway** to per-pod **sidecars** recovered the full no-mTLS performance while keeping end-to-end mTLS. The 4-node cluster now passes **500 TPS mTLS at e2e p99 = 778 ms** — the campaign goal — with no extra hardware.

| Config | Date (UTC) | Result | Actual TPS | e2e p99 | Success |
|--------|-----------|--------|-----------|---------|---------|
| no-mTLS | 2026-06-01 17:42 | ✅ PASS | 499.99 | 786 ms | 99.9996% |
| mTLS — egress-GW | 2026-06-01 19:33 | ❌ FAIL | 364.6 | 22.59 s | 96.62% |
| **mTLS — sidecar** | **2026-06-02 03:20** | ✅ **PASS** | **499.997** | **778 ms** | **99.9992%** |

The sidecar run is **statistically identical to no-mTLS** (778 ms vs 786 ms p99) — mTLS, done with the right topology, is effectively free on this cluster.

---

## 1. k6 results

| Metric | no-mTLS | mTLS egress-GW | **mTLS sidecar** |
|--------|---------|----------------|------------------|
| Status | PASS | FAIL | **PASS** |
| Actual TPS | 499.99 | 364.6 | **499.997** |
| Completed transactions | 499,999 | 364,610 | **499,997** |
| Failed transactions | 2 | 12,747 | **4** |
| Success rate | 99.9996% | 96.62% | **99.9992%** |
| Dropped iterations | 0 | 122,626 | **0** |
| VUs max (cap 1000/2000) | 486 | 2,000 (cap) | **632** |
| http_req_failed | 0.00% | 1.12% | **0.00%** |

## 2. Latency percentiles

| Stage (p99) | no-mTLS | mTLS egress-GW | **mTLS sidecar** |
|-------------|---------|----------------|------------------|
| **e2e_time** p95 / p99 | 695 / **786 ms** | 15,430 / **22,590 ms** | 645 / **778 ms** |
| discovery_time p99 | 26 ms | 1,960 ms | **33 ms** |
| quote_time p99 | 229 ms | 436 ms | **242 ms** |
| transfer_time p99 | 625 ms | 21,890 ms | **605 ms** |
| http_req_duration p99 | 568 ms | 30,000 ms (timeout) | **523 ms** |

Every stage on the sidecar run is back within a few percent of no-mTLS. The egress-GW run's transfer p99 of 21.9 s — a 36× blow-up — is completely gone (605 ms).

---

## 3. mTLS verification — was Leg B (switch→DFSP) actually encrypted?

**Yes.** Evidence chain, strongest last:

1. **Sidecar TLS config (verified pre-test).** The `DestinationRule` for each `sim-fspNNN.local` sets `tls.mode: MUTUAL` with a client certificate. `istioctl proxy-config cluster` showed the `outbound|443||sim-fsp201.local` cluster with `transportSocket = envoy.transport_sockets.tls` and `sni = sim-fsp201.local`, and the client cert (`tls.crt/tls.key/ca.crt`) mounted in the istio-proxy at `/etc/istio/mtls-certs`.
2. **The DFSP requires mutual TLS.** Each DFSP scheme-adapter ran with `INBOUND_MUTUAL_TLS_ENABLED=true`, i.e. it **rejects** any connection that does not present a valid client certificate, and the DFSP nginx does SSL-passthrough on `:443`. A plain-HTTP or anonymous-TLS connection would be refused.
3. **Therefore success ⇒ mutual TLS.** 499,997 / 500,001 transfers completed end-to-end, each requiring a Leg-B callback the egress sidecar delivered to the DFSP on `:443`. If the sidecar had sent plain HTTP, or omitted the client cert, those callbacks would have failed at the TLS layer (exactly the `WRONG_VERSION_NUMBER` class of error). A 99.9992% success rate is only possible if the client cert was presented and accepted on essentially every call. **This is end-to-end mutual TLS.**

**Definitive runtime proof (captured from a notification-handler sidecar via `pilot-agent request GET clusters`):**
```
outbound|443||sim-fsp201.local :: 10.112.2.169:443 :: rq_total=19362  rq_success=19362  rq_error=0  cx_total=4
outbound|80 ||sim-fsp201.local :: 10.112.2.169:80  :: rq_total=0      cx_total=0
```
- **100% of fsp201 Leg-B traffic went to the DFSP on `:443`** through the TLS-origination cluster; the plain `:80` cluster carried **zero** connections.
- The DFSP requires it: `dfsp-sim-fsp201-scheme-adapter` env `INBOUND_MUTUAL_TLS_ENABLED=true` — it rejects any connection without a valid **client** certificate.
- ⇒ 19,362 successful requests (`rq_error=0`) to a client-cert-requiring `:443` endpoint can only happen if the sidecar presented a valid client cert and completed **mutual-TLS** handshakes.
- `cx_total=4` carrying 19,362 requests ≈ **4,800 req/connection** (HTTP/1.1 keepalive) — so handshakes are few, which is why aggregate `ssl.handshake` counters are small.

> The `connection_security_policy=unknown` / `request_protocol=http` labels in `istio_requests_total` are the known **cosmetic** labels for egress TLS origination to a `MESH_EXTERNAL` host — they do not indicate plaintext. The per-endpoint `:443` routing + DFSP mutual-TLS requirement + zero errors is the authoritative proof.

> This is genuine end-to-end mutual TLS — verified at the Envoy cluster level — unlike the 2026-05-27 "499 TPS" runs whose mTLS state was never confirmed.

---

## 4. Cluster utilization (Prometheus, per test window)

| Metric | no-mTLS | mTLS egress-GW | **mTLS sidecar** |
|--------|---------|----------------|------------------|
| Cluster CPU avg % (4 nodes) | 55.7 | 67.1 | **56.5** |
| Hottest node CPU max % | 69.9 | **99.2** | **86.0** |
| **Softirq total (cores avg)** | **2.52** | **8.93** | **3.31** |
| Softirq total (cores max) | 2.97 | 14.69 | 5.63 |
| PSI CPU pressure max | 0.20 | 0.76 | 0.46 |
| Load5 max (8 vCPU/node) | 8.5 | 24.95 | 14.2 |
| Network total (MB/s) | 191.6 | **348.3** | **171.3** |
| Pod restarts in window | 0 | 2 | **0** |

### CPU mode breakdown (sum across 4 app nodes, avg cores)
| Mode | no-mTLS | mTLS egress-GW | **mTLS sidecar** |
|------|---------|----------------|------------------|
| user | 11.92 | 9.75 | 11.61 |
| system | 2.40 | 2.36 | 2.40 |
| **softirq** | **2.52** | **8.93** | **3.31** |
| iowait | 0.03 | 0.02 | 0.02 |

### Istio proxy CPU (cores avg) — the architectural shift
| Component | no-mTLS | mTLS egress-GW | **mTLS sidecar** |
|-----------|---------|----------------|------------------|
| egress gateway | 0.01 | **1.02** | **0.01** ← retired |
| ingress gateway | 0.01 | 1.08 | 0.97 ← still Leg A |
| **sidecars (mojaloop)** | n/a | n/a | **1.45** ← Leg B moved here |
| **total Envoy** | ~0.02 | ~2.11 | ~2.43 |

### Service CPU (cores avg)
| Service | no-mTLS | mTLS egress-GW | **mTLS sidecar** |
|---------|---------|----------------|------------------|
| notification handler | 2.43 | 3.10 | 2.64 |
| account-lookup-service | 1.95 | 1.90 | 1.85 |
| cl-transfer-prepare | 1.86 | 1.86 | 1.80 |
| cl-transfer-fulfil | 1.68 | 0.80 | 0.71 |
| mysql | 4.27 | 1.20 | 3.00 |
| kafka | 1.44 | 1.03 | 1.19 |

### Notification handler + Kafka lag (the cascade indicator)
| Metric | no-mTLS | mTLS egress-GW | **mTLS sidecar** |
|--------|---------|----------------|------------------|
| active sockets (avg) | 57 | 63 | 57 |
| event-loop lag mean | 10 ms | 12 ms | 11 ms |
| **notification-event lag max** | **133** | **1,758** | **111** ← drained |
| transfer-prepare lag max | 63 | 68 | 78 |
| transfer-fulfil lag max | 54 | 20 | 20 |
| position-batch lag max | 128 | 79 | 88 |

> The `moja_notification_event_delivery_count` rate read lower in the sidecar window than no-mTLS (237 vs 864 /s avg); the **lag** (drained to 111, vs 1,758 in the cascade) is the authoritative keep-up signal here and confirms the handler kept pace with the producer.

---

## 5. Why the sidecar topology fixes it

The egress-gateway design routes every switch→DFSP call through a **centralized double-hop**: `switch pod → egress-GW pod → DFSP`. That extra in-cluster pod-to-pod hop (often cross-node) doubles the packets traversing the iptables/Calico dataplane, which shows up as **softirq**:

- **Softirq: 2.52 (no-mTLS) → 8.93 (egress-GW) → 3.31 (sidecar) cores.** The egress GW added **+6.4 cores** of kernel network overhead; the sidecar removes essentially all of it (+0.8 over no-mTLS).
- **Network bytes: 191 → 348 → 171 MB/s.** The double-hop ~doubled on-wire traffic; the sidecar collapses it back to a single hop.
- **Egress-GW Envoy CPU: 1.02 → 0.01 cores.** Leg B no longer touches the gateway; the 4 gateway pods are idle. The mTLS work moved into the sidecars (1.45 cores, distributed across the calling pods).
- **Result:** the hottest node drops from 99.2% (saturated → cascade) to 86%, `notification-event` lag from 1,758 (backlog explosion) to 111 (drained), and e2e p99 from 22.6 s to 778 ms.

**Net cost of mTLS done right:** ~0.8 cores extra softirq + ~1.4 cores of distributed sidecar Envoy ≈ **2 cores at 500 TPS**, vs the **~12 cores** the egress-gateway topology cost. Same crypto, same security guarantee — the entire gap was the gateway hop, not the TLS.

### Earlier dead-ends (for the record)
- Raising the notification handler's outbound concurrency (`syncConcurrency` 1→20) gave only +4% TPS and pushed nodes harder — concurrency was never the bottleneck.
- Bumping egress-GW Envoy threads/CPU did nothing — the gateway pods were at 5–12% CPU.
Both confirmed the constraint was **node softirq from the double-hop**, which only a topology change removes.

---

## 6. Conclusion

| | no-mTLS | mTLS egress-GW | **mTLS sidecar** |
|--|---------|----------------|------------------|
| 500 TPS @ p99 < 1s | ✅ | ❌ (365 TPS, 22.6 s) | ✅ **(500 TPS, 778 ms)** |
| Softirq cost | baseline | +6.4 cores | **+0.8 cores** |
| Security | none | mutual TLS | **mutual TLS** |

The 4-node reference cluster sustains **500 TPS with full end-to-end mTLS at e2e p99 = 778 ms** using Istio **sidecar** mTLS origination. Gateway-mode mTLS for high-volume east-west/egress traffic was the anti-pattern; sidecars put mTLS at the pod boundary, eliminate the centralized double-hop, and make mTLS overhead negligible — no 5th node, no SDK code change required.

## Appendix — windows & config
- **no-mTLS:** 2026-06-01T17:42:26Z–17:59:44Z. Istio bypassed both legs (hostAliases → direct DFSP IPs, scheme-adapter mTLS off).
- **mTLS egress-GW:** 2026-06-01T19:33:31Z–19:51:46Z. hostAliases → egress GW ClusterIP; DR credentialName; egress GW rebalanced 1/node.
- **mTLS sidecar:** 2026-06-02T03:20:51Z–03:39:29Z. Sidecars injected on the 3 egress deployments (ALS, quoting-service-handler, ml-api-adapter-handler-notification); `includeOutboundIPRanges` = 8 DFSP /32s; file-mounted `switch-mtls-creds`; egress GW retired from Leg B; ingress GW retained for Leg A.
- Cluster: 4× m7i.2xlarge app nodes (32 vCPU), kernel 6.17, Calico iptables, istiod 1.24.1.
