# Durable fix for sustained 500 TPS — eBPF dataplane + node-level mTLS (handoff for the new branch)

> **UPDATE 2026-06-10 — Phase A is BUILT** on branch `feat/500-mtls-ambient` (`ansible/roles/cilium` + `make cilium`). The operational reality — the 5 MicroK8s↔Cilium integration gotchas, the finding that hostPort needs full kube-proxy replacement, and the resulting NodePort-ingress pivot — is in **[docs/2026-06-10-cilium-microk8s-runbook.md](2026-06-10-cilium-microk8s-runbook.md)**. The text below is the original *strategy*; the runbook supersedes the operational details. Phase B (ambient) still pending; the Cilium install is already ambient-ready.

**Status:** plan / next approach. The `feat/restructure` branch contains the *diagnosis* and the *partial* fixes (below). The permanent fix is a dataplane re-platform, to be attempted on a **fresh branch**.

**Goal (the real one):** sustain **500 TPS, 1M+ transfers, 24×7** with e2e p99 < 1s — not a 16-minute green run.

---

## 1. The problem, proven
On MicroK8s + Calico(iptables) + per-pod Istio sidecars, the switch nodes hit a **self-amplifying softirq ceiling** under sustained load. A 500 TPS / 1M run (2026-06-04 01:13Z):
- Held true 500 TPS for **~24 min**, then the hottest node (n3, +1 notification pod) crossed **~93% CPU**, latency knee'd, **k6 VU pool drained** (`vus_max=2000` capped, `dropped_iterations=221,292`), offered load collapsed to ~90/s. `actual_tps=371`, FAILED. No pod restarts, no NotReady — **backpressure collapse, not a crash or a Mojaloop fault** (quote p99 245ms, transfer p99 1.49s throughout).

## 2. Root cause (final, evidence-backed)
Per-packet **softirq cost rises the longer load runs**, because packets are re-injected through the in-kernel software path (`netif_rx` → per-CPU backlog → netfilter/Calico chains → Istio sidecar `REDIRECT` → loopback) an **increasing number of times**.

Decisive trajectory over the run (Prometheus, node-exporter):
| metric | 01:13 | 01:25 | 01:38 |
|---|---|---|---|
| softirq (4 nodes, cores) | 0.29 | 4.29 | **8.61** |
| wire PPS | 59k | 194k | 178k |
| **softnet_processed/s** | 0.16M | 0.99M | **1.97M** |
| conntrack entries | 7,011 | 10,386 | 11,452 |
| TCP sockets | 903 | 837 | 983 |

**softnet_processed (re-injection) climbs ~12× at flat wire PPS, while conntrack / sockets / PPS stay flat.** ⇒ no growing kernel table to tune; the amplification is **structural** to the iptables/veth/sidecar dataplane. This rules out the cheap-tunable path.

## 3. What's already fixed on `feat/restructure` (carry forward — keep these)
1. **`net.core.netdev_max_backlog=65535` + `netdev_budget=600`** on switch nodes — [01-install-microk8s.yml](../ansible/playbooks/01-install-microk8s.yml). Removed the **282k/s softnet drop storm** (was the kernel-default 1000; FSP nodes already had 65535). This converted a 2-minute catastrophic cascade into a 24-minute creep. **Essential.**
2. **EC2 `source_dest_check=false`** ([terraform/instances.tf](../terraform/instances.tf)) + **Calico `vxlanMode: CrossSubnet`** ([02-configure-switch-cluster.yml](../ansible/playbooks/02-configure-switch-cluster.yml)) — native pod routing, eliminated the VXLAN decap leg (vxlan.calico PPS → 0). Helped (~15% of re-injection), softirq ~half at idle. **Keep** — it's also the right direction for eBPF native routing.
3. **Observability:** `dfsp_monitoring` role (per-DFSP node/cadvisor → remote_write) + `istio_telemetry` role (PodMonitor :15020). Keep.

These got us from "fails in 2 min" to "saturates in ~24 min." The remaining ceiling is the iptables/veth/sidecar re-injection.

## 4. The durable fix (do on the fresh branch)

### Phase A — Cilium eBPF CNI (biggest lever; replaces Calico + kube-proxy)
The bulk of the re-injection is the Calico-iptables + netfilter path. Cilium processes packets in eBPF (tc/XDP), bypassing the `netif_rx` backlog + iptables chains.
Target Cilium config (single subnet 10.112.2.0/24, pod CIDR 10.1.0.0/16):
```yaml
kubeProxyReplacement: true          # service LB in eBPF maps — no KUBE-SVC iptables
routingMode: native                  # no overlay
ipv4NativeRoutingCIDR: 10.1.0.0/16
autoDirectNodeRoutes: true           # direct node routes (all nodes same L2 subnet)
endpointRoutes.enabled: true
bpf.masquerade: true
bpf.hostLegacyRouting: false
installNoConntrackIptablesRules: true
# loadBalancer.acceleration: native  # XDP, if the ENA driver supports it
```
Expected: `softnet_processed/wire_PPS → ~1×`, softirq flat & proportional to PPS.
**Open integration question:** MicroK8s ships Calico by default. Either (a) `microk8s enable cilium` (check it gives a recent Cilium + the above flags), or (b) provision microk8s with `--cni=none`/disable default CNI and install Cilium via cilium-cli/Helm. Resolve this first on the fresh branch. Keep `source_dest_check=false` (Cilium native routing needs it too).

### Phase B — Istio ambient mesh (removes per-pod sidecar redirect)
Secondary contributor: the `iptables REDIRECT` to per-pod Envoy on ALS / quoting-handler / notification (38 sidecars). Ambient moves mTLS to one **ztunnel per node** (HBONE), no per-pod redirect.
- `istioctl install --set profile=ambient`; label `mojaloop` ns `istio.io/dataplane-mode=ambient`; `PeerAuthentication STRICT` for Leg A.
- **Design question (must solve):** Leg-B mTLS is **egress to EXTERNAL DFSPs on :443 with file-mounted client certs** (current sidecar approach). Ambient handles in-mesh mTLS, but external-egress mTLS needs a **waypoint proxy** (Envoy) for that path, or a retained egress mechanism. Decide: waypoint for the 3 egress workloads, or keep a thin egress sidecar only for Leg B. Cilium alone (Phase A) may already give enough headroom — measure after A before committing to B.

### Phase C — right-size (only if A+B still tight)
Scale app tier 4 → 6 nodes for margin. With the re-injection gone this likely isn't needed for 500 TPS.

## 5. Immediate mitigations (optional, on current branch — buy headroom, not a cure)
- **Enable RPS/RFS** (currently off, `rps_cpus=00`) to spread backlog softirq across all 8 CPUs → raises the saturation ceiling.
- Run sustained at **~350–400 TPS** (below the creep-to-saturation rate) if you need a stable number before the migration.

## 6. Acceptance criteria (put in the whitepaper — redefine "pass")
A sustained-throughput pass is **NOT** a 16-min run. It is:
> Over a **multi-hour hold at target TPS**: `softnet_processed_total / wire_PPS ≈ 1×` (flat), **softirq flat/proportional to PPS (no upward creep)**, hottest-node CPU < ~80%, notif-event lag bounded, k6 `dropped_iterations ≈ 0`.

Current stack: ratio → ~12×, softirq creeps, fails at ~24 min. Cilium+ambient target: ratio ~1×, flat.

## 7. Validation queries / commands
```promql
# THE metric — must stay ~1x and flat under load
sum(rate(node_softnet_processed_total{instance=~"10.112.2.102:9100|10.112.2.115:9100|10.112.2.30:9100|10.112.2.234:9100"}[1m]))
  / (sum(rate(node_network_receive_packets_total{...,device!="lo"}[1m]))+sum(rate(node_network_transmit_packets_total{...,device!="lo"}[1m])))
# softirq must be flat, not creeping
sum(rate(node_cpu_seconds_total{mode="softirq",...app nodes...}[1m]))
# drops must stay 0
sum(rate(node_softnet_dropped_total{...}[1m]))
```
```bash
# Confirm the call stack BEFORE migrating (1 cmd during a 400 TPS hold):
ssh -F scenarios/500tps/artifacts/ssh-config sw1-n4 'sudo perf top -e cycles -d 5'
#   expect time in nf_hook_slow / ip_forward / veth_xmit / __netif_receive_skb (iptables+veth+sidecar)
```

## 8. Key context pointers
- Full investigation: [docs/2026-06-03-500tps-failure-investigation.md](2026-06-03-500tps-failure-investigation.md)
- VXLAN→native runbook: [docs/2026-06-04-vxlan-to-native-routing.md](2026-06-04-vxlan-to-native-routing.md)
- Measurement traps (cadvisor resets, Istio stat suppression, gauges): memory `reference_perf_measurement_traps`
- Prior eBPF attempt **bricked the cluster** (memory `project_calico_ebpf_migration_state`) — do Cilium on a **fresh provision**, not in-place, with console/SSM access ready.
- App-node node-exporter instances: n1=10.112.2.102, n2=10.112.2.115, n3=10.112.2.30, n4=10.112.2.234 (`:9100`). Kernel `6.8.0-1029-aws`.
