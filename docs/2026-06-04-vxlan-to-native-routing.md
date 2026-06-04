# Switch cluster: VXLAN overlay → native Calico routing (runbook)

**Why:** under load the Calico **VXLAN overlay** on the switch nodes drives a ~**28× softnet "process storm"** — `softnet_processed ≈ 1.14M pkts/s` vs ~40k/s on the wire — because every cross-node pod packet is VXLAN-decapsulated in software and re-injected via `netif_rx` into the per-CPU backlog (plus veth hops). That burns ~4.4 cores of **softirq** and persists ~40 min after load. It was the root of the 500 TPS softirq saturation (the `netdev_max_backlog=65535` fix removed the *drop* symptom but not the re-injection itself). See `docs/2026-06-03-500tps-failure-investigation.md`.

All switch nodes share **one subnet (10.112.2.0/24)**, so an overlay is unnecessary: Calico can route pod CIDRs (10.1.0.0/16) **directly node-to-node**, exactly like EKS's VPC CNI does for native pod IPs — **no encapsulation, no decap re-injection.**

## The two coupled changes (already in the repo)
1. **`terraform/instances.tf`** — `source_dest_check = false` on `aws_instance.switch` and `aws_instance.dfsp`. AWS otherwise drops packets whose src/dst isn't the instance's own IP, so this is required before pods route natively.
2. **`ansible/playbooks/02-configure-switch-cluster.yml`** — patches the Calico IPPool `default-ipv4-ippool` to `vxlanMode: CrossSubnet` (single subnet ⇒ zero encap). Runs on rebuilds automatically.

## Apply ORDER matters (do not reverse)
`source_dest_check=false` is harmless on its own (VXLAN still works). Flipping Calico to CrossSubnet **while source/dest check is still on will drop all cross-node pod traffic** (this is the failure mode that broke the cluster during the earlier eBPF migration). So:

### Apply to the existing live cluster (no rebuild)
**Do it with NO load test running.** A brief (seconds) pod-network blip is expected as Felix reprograms routes.

```bash
# 1) Disable EC2 source/dest check.  REVIEW THE PLAN — it must show only
#    "~ source_dest_check = true -> false" (in-place update, no replace).
cd terraform && TF_WORKSPACE=500tps terraform plan -out /tmp/sdc.plan
terraform apply /tmp/sdc.plan
cd ..
#    (alternative, terraform-free / targeted:)
#    for id in <switch instance ids>; do aws ec2 modify-instance-attribute \
#        --no-source-dest-check --instance-id $id --region eu-west-2; done

# 2) Flip Calico to native routing on the switch cluster
export HTTPS_PROXY=socks5h://127.0.0.1:1080
export KUBECONFIG=scenarios/500tps/artifacts/kubeconfigs/kubeconfig-mojaloop-switch.yaml
kubectl patch ippool default-ipv4-ippool --type=merge -p '{"spec":{"vxlanMode":"CrossSubnet"}}'
kubectl get ippool default-ipv4-ippool -o jsonpath='{.spec.vxlanMode}{"\n"}'   # => CrossSubnet
```

## Validate (the fix worked)
- **Cluster still healthy:** `kubectl get nodes` (all Ready), `kubectl get pods -A` (all Running), and a smoke transfer (`make smoke SCENARIO=500tps`) succeeds.
- **Overlay is gone:** on a node, `vxlan.calico` PPS → ~0 (`ip -s link show vxlan.calico`), and the `vxlan.calico` device may disappear from `node_network_*` rates in Prometheus.
- **Re-injection collapsed:** during a load run, `sum(rate(node_softnet_processed_total[1m]))` should track wire PPS ~**1×** (was 28.8×), and softirq cores should scale ~linearly with PPS instead of creeping to ~4.4 cores and persisting post-load.
- PromQL: `sum(rate(node_softnet_processed_total{instance=~"10.112.2.102:9100|10.112.2.115:9100|10.112.2.30:9100|10.112.2.234:9100"}[1m]))` vs the wire-PPS query.

## Rollback (if pod networking breaks)
```bash
kubectl patch ippool default-ipv4-ippool --type=merge -p '{"spec":{"vxlanMode":"Always"}}'
```
(Leave `source_dest_check=false` — it's harmless with VXLAN back on.)

## Notes
- DFSP clusters are single-node ⇒ they never VXLAN-encapsulate; the change is switch-cluster-only in effect (`source_dest_check=false` on dfsp is just uniformity).
- This makes the lab's dataplane match a production **EKS + VPC CNI** target (native pod routing), so the softirq ceiling we were hitting — partly a MicroK8s+Calico-VXLAN artifact — is removed rather than just mitigated.
- Kernel on these nodes is `6.8.0-1029-aws` (PASS doc recorded `6.17`); the 28× was likely overlay cost amplified by a kernel/Calico-version factor. Native routing sidesteps the overlay path entirely.
