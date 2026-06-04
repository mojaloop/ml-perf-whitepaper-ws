# 500 TPS mTLS Failure Investigation — Session Summary (2026-06-03)

**Goal:** the rebuilt env (`feat/restructure`) fails a 500 TPS mTLS run that **passed on 2026-06-02** (e2e p99 778 ms, 99.9992%). Find why.

**Bottom line so far:** No config/IaC regression exists (verified). The failure is a **CPU/softirq saturation cascade** on the switch nodes that starves the notification handler. The most likely root is **environmental/dynamic** — a *softirq-cost-per-packet degradation under load* (kernel/ENA-driver behavior), not a static setting. Two reruns failed identically; a third is only worthwhile **instrumented under a controlled ramp**.

---

## ⚑ UPDATE (2026-06-04) — root cause found, fixed, and a residual identified

1. **Primary root cause = switch-node RX backlog gap (FIXED).** `net.core.netdev_max_backlog` was the kernel default **1000** on switch nodes (FSP nodes had 65535 via playbook 03; the restructure left the switch sysctl block at somaxconn-only). Under VXLAN load the per-CPU softnet backlog overflowed → **~26% packet drops (282k/s drop storm)** → TCP-retransmit amplification → softirq saturation → notification cascade. Diagnosed via `node_softnet_dropped_total` (282k/s) with `time_squeeze≈0` and conntrack flat. **Fix:** `netdev_max_backlog=65535` + `netdev_budget=600`, live on sw1-n1..n4 and baked into `01-install-microk8s.yml`. **Verified:** 400 TPS post-fix drops 282k/s → **0**, notif lag bounded ~1600 (was 66k), e2e p99 821→700ms, PASSED.

2. **Residual = VXLAN re-injection "process storm" (FIX PREPARED).** The backlog fix removed the *drop* symptom but not the cause: under load `node_softnet_processed` runs at **~1.14M pkts/s vs ~40k/s on the wire = 28.8× amplification** — every cross-node pod packet is VXLAN-decapsulated → `netif_rx` → backlog (plus veth hops), re-processed ~29×. Burns ~4.4 softirq cores, persists ~40 min post-load. **This is a MicroK8s+Calico-VXLAN dataplane artifact** (EKS+VPC-CNI native routing would not have it). **Fix prepared** (apply + test pending): EC2 `source_dest_check=false` (terraform `instances.tf`) + Calico `vxlanMode: CrossSubnet` (ansible `02-configure-switch-cluster.yml`) ⇒ native pod routing, no overlay. Runbook: **docs/2026-06-04-vxlan-to-native-routing.md**.

**Don't run tests back-to-back** until the residual is fixed — softirq sits at ~4.4 cores for ~40 min after a run; a second test starting from that degraded baseline gives misleading results.

---

## ⚑ FINAL (2026-06-04) — sustained 500 TPS test + the structural verdict

A 500 TPS / 1M-transfer / 2000s run (01:13Z) with backlog-fix + native-routing in place: **held true 500 TPS for ~24 min, then the hottest node (n3) crossed ~93% CPU, k6's VU pool drained (`vus_max=2000` capped, `dropped_iterations=221,292`), and offered load collapsed to ~90/s via backpressure.** Result: `actual_tps=371`, `success 95.27%`, FAILED. No crash, no restarts, Mojaloop healthy (quote p99 245ms, transfer p99 1.49s) — a **backpressure collapse from host softirq saturation**, not an app fault.

**The decisive metric** — over the run, `node_softnet_processed` climbed **0.16M → 1.97M/s (~12×)** at **flat wire PPS (~195k), flat conntrack (~11k), flat TCP sockets (~900)**. softirq tracks softnet_processed 1:1. ⇒ **no growing kernel table to tune; the re-injection is structural** to the iptables/veth/Istio-sidecar dataplane. The cheap-tunable path is closed.

**Durable fix = re-platform the dataplane:** Cilium eBPF CNI (kube-proxy replacement, native routing — bypasses iptables/netfilter `netif_rx` re-injection) + Istio ambient mesh (removes per-pod sidecar `REDIRECT`). This is the only path to sustained 500 TPS 24×7 on this footprint; everything else (more nodes, RPS, lower TPS) only delays the creep. To be attempted on a **fresh branch**. Full plan: **docs/2026-06-04-durable-fix-ebpf-ambient.md**.

**Redefine "pass" (whitepaper):** not a 16-min green run — a multi-hour hold where `softnet_processed/wire_PPS ≈ 1×` and softirq stays flat (no creep).

---

## 1. Runs analyzed

| Run | Window (UTC) | Result | Actual TPS | e2e p99 | Success | notif-event lag peak |
|-----|--------------|--------|-----------|---------|---------|----------------------|
| PASS baseline | 2026-06-02 03:20 | ✅ | 499.997 | 778 ms | 99.9992% | 111 (drained) |
| Run 1 | 17:34–17:51 | ❌ | 487.3 | 8.66 s | 99.79% | 213,437 |
| Run 2 | 18:49–19:07 | ❌ | 475.9 | 4.26 s | 98.73% (6,097 fail) | 625,122 |

In both failing runs: **discovery (p99 ~52 ms) and quote (p99 ~288 ms) stayed healthy**; the **transfer leg blew up** (p99 4–8.5 s, 30 s timeouts). The 965 / 6,086 transfer failures are k6's 30 s timeout — fulfil notifications never came back in time.

## 2. Confirmed failure mechanism (solid — node-exporter + kafka-exporter + k6)

1. `topic-notification-event` consumer lag **runs away monotonically** from T+0 (1.4K → 213K → 625K), never drains during load. Core-ledger topics (prepare/fulfil/position) stay tiny (<300).
2. The notification handler drains a **hard ~900/s** while production is ~1000+/s → backlog grows unbounded → payer-side `PUT /transfers` callbacks queue 100K+ deep → time out at 30 s.
3. The handler is **not internally bottlenecked** (0.18 cores/pod, 17 ms event-loop, sidecar 0.036) and **not CFS-throttled** (0%). It is **starved by node CPU contention** — switch app nodes at 73–96%, softirq 5.22 cores (vs PASS 3.31).
4. **DFSPs are idle** (fsp201 ~30% CPU, the 70%-callback target). They accept callbacks instantly — not the bottleneck.

## 3. Ruled out

- **Ingress gateway** — initially (wrongly) blamed at "2.83 cores tripled." That was a **measurement artifact**. Gateway is healthy and on-path.
- **DFSPs** — idle, ruled out via new per-DFSP host metrics.
- **CFS throttling** — 0% on all app services.
- **Config regression** — replica counts (notif 18 / prep 12 / fulfil 12 / q-handler 12 / ml-api 12 / ALS 8 / pos 8), Kafka consumer tuning (`fetch.min.bytes=1024`, `fetch.wait.max.ms=5`, `queue.buffering.max.ms=0`), sidecar scope (3 deployments), Calico encap — **all identical to PASS**. Git history confirms Calico encap + Kafka tuning were **never** changed.
- **Calico VXLAN-Always as a regression** — it's a constant (MicroK8s default, never set in git; same in PASS).
- **TCP connection count** — flat at ~137 throughout the load anomaly. Not a connection storm.
- **ENA network allowances** — `bw_in/out`, `pps`, `conntrack`, `linklocal` allowance_exceeded all **0**. No AWS throttling.
- **conntrack pressure** — 2105 / 262144, trivial.

## 4. Confirmed TRUE facts (corrections of earlier wrong conclusions)

- **Leg A mTLS works through the ingress gateway.** Proof: a `node` https probe from the fsp201 scheme-adapter (with its outbound client cert) to `account-lookup-service.local:443` → **HTTP 200**; gateway `istio_requests_total` shows **~450–477K requests/service**. Routing: **nginx owns hostPort :80, istio-ingressgateway owns hostPort :443**; NLB:443 → node:443 → gateway. SDK dials :443 (11 established conns observed). mTLS is genuine (`connection_security_policy="unknown"` is the cosmetic gateway-TLS label).
- **Idle softirq baseline is ~0.27 cores (cool).** The "4.57 cores idle" I measured was the tail of a transient (see §5).

## 5. The key dynamic finding — softirq-per-packet hysteresis

2h trajectory (node-exporter, reliable):
```
UTC     softirq   PPSk  vxlank  TCPest
21:03      0.28   84.4    28.0     137   <- baseline: cheap per-packet
21:08      1.20  217.2    65.3     136   <- pod-to-pod packet BURST begins
21:23      6.12  274.8    80.1     138   <- peak softirq 6.1 @ 275k PPS
21:28      4.54   79.3    25.4     137   <- PPS back to baseline, softirq STAYS 4.5
22:08      4.58   79.6    25.4     139   <- same PPS as 21:03, 16x the softirq
22:28      0.27   85.3    28.3     138   <- recovered to baseline
```
- A **pod-to-pod (VXLAN) packet burst** (84k→290k PPS, ~17 min, cause unidentified — possibly a rebalance/replication or even heavy investigation traffic) drove softirq to 6 cores.
- **Softirq stayed ~4.5 cores for ~45 min at normal PPS**, then self-recovered. **Same PPS → 16× softirq cost** depending on recent history.
- This is a **dynamic kernel/ENA stack effect**, not static config — and is the leading mechanism for why *sustained* 500 TPS tips into runaway softirq (5.22 vs PASS 3.31) that saturates nodes and starves the notification handler.

## 6. Environmental drift (the "changed-without-git" lead)

- **Kernel: `6.8.0-1029-aws`** on the current nodes vs **`6.17`** recorded in the PASS doc (`docs/500tps-mtls-sidecar-result.md`). Kernel = ENA driver + GRO + softirq behavior → prime suspect.
- NIC state (sw1-n4, ENA): GRO **on**, GSO on, TSO/LRO off[fixed], RSS across **8 combined queues**, adaptive-RX on, `rx-usecs=0`. **RPS off** (all `rps_cpus=00`); NET_RX slightly skewed to CPU5/6 — secondary.
- iptables view is nearly empty under the nft backend (rules in native nftables); per-packet rule-traversal cost not cleanly measured, but conntrack is trivial.

## 7. Measurement traps discovered (reusable — these burned hours)

1. **cadvisor `rate()` across counter resets → phantom CPU.** Gave a fake "2.83 cores" gateway and "3.57 cores" fsp scheme-adapter (> the node's real total). Use `increase()` or, best, **node-exporter** for ground truth. Aggregate cadvisor (node sum) reconciles with node-exporter; only per-pod `rate()` near resets lies.
2. **`server.total_connections` (Envoy) is a live gauge, not a cumulative counter.** Misread as "only 191 requests ever."
3. **Istio suppresses raw `envoy_http_downstream_rq_total`** by default (proxyStatsMatcher). Gateway/sidecar request volume lives only in **`istio_requests_total`** on the merged `:15020` endpoint — which promfana **did not scrape** (now fixed, §8).
4. **`kubectl exec ... GET stats` output truncates (~240 lines).** Use `GET stats/prometheus` (~1105 lines) for the full set.
5. **Comparing a *failing* run's softirq to a *passing* run's under-load softirq is invalid** — the cascade self-inflicts extra packet/work load. Need an apples-to-apples (stable-TPS) comparison.

## 8. Tooling built today (reproducible, in `feat/restructure`)

- **`dfsp_monitoring` role + `make dfsp-monitoring`** — per-DFSP Prometheus **agent** (node-exporter + kubelet/cAdvisor) `remote_write` → switch Prometheus `:30090` (`enableRemoteWriteReceiver` already on), `external_labels: {cluster: fspNNN}`. Sidesteps the isolated pod networks. Includes the cAdvisor **`honor_timestamps: false`** fix (out-of-order drops). Files under `ansible/roles/dfsp_monitoring/`, playbook `dfsp-monitoring.yml`.
- **`istio_telemetry` role + `make istio-telemetry`** — PodMonitor scraping all istio-proxy (gateways + sidecars) on `:15020/stats/prometheus` via Istio annotations; istiod ServiceMonitor. Surfaces per-leg `istio_requests_total` / `istio_request_duration`. Optional `widen_envoy_stats` flag for raw envoy stats (rolls workloads; default off). Files under `ansible/roles/istio_telemetry/`, playbook `istio-telemetry.yml`. **Applied to the live cluster.**
- Both added to the `make deploy` chain (after `dfsp` / `dfsp-monitoring`).

## 9. Open items / next steps

1. **Confirm the PASS-env kernel** (any saved artifact/AMI id) to firm up the kernel-drift hypothesis. If real, pin the AMI/kernel.
2. **Instrumented load ramp** (200→300→400→500) watching, per node, **softirq cores vs PPS (cost-per-packet)** live + per-leg `istio_request_duration` + `topic-notification-event` lag. If softirq-per-packet tips at some TPS → dynamic degradation confirmed (kernel suspect). If flat → pure capacity at the 4-node edge → capacity lever (5th node / IPVS).
3. Identify the 21:08 packet-burst cause (rebalance? replication? investigation traffic?).
4. The new telemetry (§8) makes the next run fully diagnosable on the per-leg + per-DFSP axes.

## 10. Useful queries (Prometheus)

```promql
# notification cascade
sum(kafka_consumergroup_lag{topic="topic-notification-event"})
# softirq cost-per-packet (the dynamic signal) — app nodes
sum(rate(node_cpu_seconds_total{mode="softirq",instance=~"10.112.2.102:9100|10.112.2.115:9100|10.112.2.30:9100|10.112.2.234:9100"}[3m]))
  / (sum(rate(node_network_receive_packets_total{...app...}[3m]))+sum(rate(node_network_transmit_packets_total{...app...}[3m])))
# per-leg (after istio_telemetry)
sum by(destination_service_name)(rate(istio_requests_total{reporter="destination"}[1m]))
histogram_quantile(0.99, sum by(le,destination_service_name)(rate(istio_request_duration_milliseconds_bucket[1m])))
# reset-safe container CPU attribution
sum by(pod)(increase(container_cpu_usage_seconds_total{namespace="mojaloop",container!="",container!="POD"}[17m]))
```
App-node node-exporter instances: n1=10.112.2.102, n2=10.112.2.115, n3=10.112.2.30, n4=10.112.2.234 (all `:9100`); cAdvisor `:10250`.
