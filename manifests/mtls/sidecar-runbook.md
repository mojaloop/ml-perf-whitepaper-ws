# Leg B mTLS: gateway → sidecar cutover runbook

> **This is now automated.** The `mtls_switch` ansible role (`make mtls-switch` /
> `ansible/playbooks/mtls-switch.yml`) deploys the sidecar approach end-to-end and
> idempotently: it copies the cert into `mojaloop`, renders
> `switch-outbound-sidecar.yaml` from the live DFSP IPs, injects the 3 sidecars
> (ALS keeps inbound interception; the 2 handlers get `includeInboundPorts:""`),
> file-mounts the certs, repoints hostAliases at the real DFSP nodes, and retires
> the egress gateway. Use the manual steps below only for ad-hoc cutover/debugging
> on an already-provisioned cluster, or for the §5 rollback.

Run all `kubectl` / `istioctl` commands **from sw1-n1**. The `make load`
step runs from the workstation. Do this in a **non-test window** (it rolls 3 deployments).

Targets: `moja-account-lookup-service`, `moja-ml-api-adapter-handler-notification`,
`moja-quoting-service-handler` (the 3 deployments that call DFSPs on Leg B).

DFSP IP ranges (used for sidecar interception):
```
10.112.2.169/32,10.112.2.84/32,10.112.2.171/32,10.112.2.193/32,10.112.2.225/32,10.112.2.201/32,10.112.2.55/32,10.112.2.54/32
```

---

## 0. Pre-flight (no changes)

```bash
# 0a. istiod version — need >= 1.10 for sidecar DestinationRule credentialName.
kubectl -n istio-system get deploy istiod \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo

# 0b. Confirm the injector supports per-pod LABEL selection (object selector on
#     sidecar.istio.io/inject). Expect a webhook whose objectSelector matches
#     sidecar.istio.io/inject: "true". If absent, see "Fallback" at the bottom.
kubectl get mutatingwebhookconfiguration istio-sidecar-injector \
  -o jsonpath='{range .webhooks[*]}{.name}{" -> "}{.objectSelector}{"\n"}{end}'

# 0c. Inspect the mTLS secret structure (which keys it has) and copy it into mojaloop.
kubectl -n istio-system get secret switch-mtls-creds \
  -o jsonpath='{.type}{"\n"}{range .data}{"\n"}{end}'; \
kubectl -n istio-system get secret switch-mtls-creds -o json | jq '.data | keys'

kubectl -n istio-system get secret switch-mtls-creds -o json \
  | jq 'del(.metadata.namespace,.metadata.resourceVersion,.metadata.uid,
            .metadata.creationTimestamp,.metadata.ownerReferences,.metadata.managedFields,.status)' \
  | kubectl -n mojaloop apply -f -
kubectl -n mojaloop get secret switch-mtls-creds

# 0d. Confirm we are starting from mTLS-ON (so DFSP side needs no change):
#     - DFSP scheme-adapter env should be INBOUND/OUTBOUND/TEST_MUTUAL_TLS_ENABLED=true
#     - switch deployments currently have the 10.152.183.253 (egress GW) hostAlias.
kubectl -n mojaloop get deploy moja-ml-api-adapter-handler-notification -o json \
  | jq '.spec.template.spec.hostAliases[] | select(.ip=="10.152.183.253")'
```

---

## 1. Apply the sidecar SE/VS (replaces the gateway-bound ones)

```bash
kubectl apply -f manifests/mtls/switch-outbound-sidecar.yaml

# Sanity: VS should now show gateways: [mesh]; SE should have ports 80 + 443.
kubectl -n mojaloop get vs sim-fsp201 -o jsonpath='{.spec.gateways}'; echo
kubectl -n mojaloop get se sim-fsp201 -o jsonpath='{.spec.ports}'; echo
```

---

## 2. Inject sidecars + scope interception + drop the egress-GW hostAlias

```bash
DFSP_RANGES="10.112.2.169/32,10.112.2.84/32,10.112.2.171/32,10.112.2.193/32,10.112.2.225/32,10.112.2.201/32,10.112.2.55/32,10.112.2.54/32"
DEPLOYS="moja-account-lookup-service moja-ml-api-adapter-handler-notification moja-quoting-service-handler"

# 2a. Enable injection (pod LABEL) + scope OUTBOUND interception to DFSP egress only.
#     Do NOT disable inbound interception (includeInboundPorts:"") on frontends that
#     receive ingress-GW traffic (e.g. account-lookup-service): once a workload has a
#     sidecar, auto-mTLS makes the ingress GW originate mTLS to it, and the sidecar must
#     terminate that inbound -> disabling inbound => Leg A 503 TLS WRONG_VERSION_NUMBER.
#     (Pure Kafka-consumer handlers receive no ingress traffic, so it is harmless there.)
for d in moja-account-lookup-service moja-ml-api-adapter-handler-notification moja-quoting-service-handler; do
  kubectl -n mojaloop patch deployment $d --type=merge -p "{
    \"spec\": { \"template\": {
      \"metadata\": {
        \"labels\": { \"sidecar.istio.io/inject\": \"true\" },
        \"annotations\": {
          \"traffic.sidecar.istio.io/includeOutboundIPRanges\": \"${DFSP_RANGES}\",
          \"proxy.istio.io/config\": \"{\\\"holdApplicationUntilProxyStarts\\\":true}\"
        }
      }
    } }
  }"
done

# 2a.2 Mount switch-mtls-creds INTO the istio-proxy sidecar. Required because sidecar
#       SDS does NOT load a DestinationRule credentialName secret (gateways do, sidecars
#       don't — verified on istiod 1.24.1: the cluster stayed tls:none and the secret was
#       absent from `istioctl proxy-config secret`). The DRs in switch-outbound-sidecar.yaml
#       reference /etc/istio/mtls-certs/{tls.crt,tls.key,ca.crt} accordingly.
for d in moja-account-lookup-service moja-ml-api-adapter-handler-notification moja-quoting-service-handler; do
  kubectl -n mojaloop patch deployment $d --type=merge -p '{
    "spec": {"template": {"metadata": {"annotations": {
      "sidecar.istio.io/userVolume": "[{\"name\":\"mtls-certs\",\"secret\":{\"secretName\":\"switch-mtls-creds\"}}]",
      "sidecar.istio.io/userVolumeMount": "[{\"name\":\"mtls-certs\",\"mountPath\":\"/etc/istio/mtls-certs\",\"readOnly\":true}]"
    }}}}
  }'
done

# 2b. Remove the egress-GW hostAlias (10.152.183.253) so sim-fspNNN.local resolves
#     to the DFSP node IP -> sidecar intercepts it. Leaves the 8 direct-IP entries.
for d in moja-account-lookup-service moja-ml-api-adapter-handler-notification moja-quoting-service-handler; do
  NEW_HA=$(kubectl get deployment $d -n mojaloop -o json | \
    jq -c '.spec.template.spec.hostAliases | map(select(.ip != "10.152.183.253"))')
  kubectl patch deployment $d -n mojaloop --type=json \
    -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/hostAliases\",\"value\":${NEW_HA}}]"
done
```

---

## 3. Wait for rollout + verify the data path

```bash
for d in moja-account-lookup-service moja-ml-api-adapter-handler-notification moja-quoting-service-handler; do kubectl -n mojaloop rollout status deploy $d --timeout=240s; done

# 3a. Each pod should now have 2 containers (app + istio-proxy).
kubectl -n mojaloop get pod | grep -E '^moja-(account-lookup-service|ml-api-adapter-handler-notification|quoting-service-handler)-' \
  | awk '{print $1, $2}'    # READY column should be 2/2

# 3b. hostAliases: no 10.152.183.253, 8 direct DFSP IPs present.
kubectl -n mojaloop get deploy moja-ml-api-adapter-handler-notification -o json \
  | jq '.spec.template.spec.hostAliases | {count: length, hasEgressGW: (map(.ip) | index("10.152.183.253") != null)}'

# 3c. Sidecar must have the certs mounted AND a TLS transport socket on the :443 cluster.
POD=$(kubectl -n mojaloop get pod | grep '^moja-ml-api-adapter-handler-notification-' | head -1 | awk '{print $1}')
kubectl -n mojaloop exec $POD -c istio-proxy -- ls -l /etc/istio/mtls-certs   # tls.crt tls.key ca.crt
istioctl proxy-config cluster $POD.mojaloop --fqdn sim-fsp201.local --port 443 -o json \
  | jq '.[0] | {name, tls: (.transportSocket.name // "none"), sni: (.transportSocket.typedConfig.sni // "none")}'
# expect: tls = "envoy.transport_sockets.tls", sni = "sim-fsp201.local"  (NOT "none")

# 3d. Listeners: a 0.0.0.0:80 outbound HTTP route for sim-fsp201.local should exist.
istioctl proxy-config route $POD.mojaloop -o json \
  | jq -r '.[].virtualHosts[]?.name' | grep -i sim-fsp || echo "no sim-fsp route (investigate)"

# 3e. Egress GW should now receive ~zero Leg B traffic (it is bypassed).
```

---

## 4. Run the 500 TPS mTLS test (from workstation)

```bash
make load SCENARIO=500tps
```
**Capture UTC start/end** for the Prometheus pull. Expected if the diagnosis holds:
softirq drops materially (the egress-GW hop is gone), node CPU falls below saturation,
notification lag drains, e2e p99 < 1 s, TPS ~500.

Watch during/after:
- handler delivery rate (`moja_notification_event_delivery_count`) + `ml-group-notification-event` lag
- node CPU + softirq per app node (the win lives here)
- per-DFSP transfer errors — fsp203–208 (4 SDK replicas) are the first place a new ceiling shows
- `istioctl proxy-config` / pod logs for any TLS or routing errors

---

## 5. Rollback (back to gateway mode)

```bash
DEPLOYS="moja-account-lookup-service moja-ml-api-adapter-handler-notification moja-quoting-service-handler"

# 5a. Restore gateway-bound SE/VS.
kubectl apply -f manifests/mtls/switch-outbound.yaml

# 5b. Remove injection + interception annotations (JSON-pointer escapes: / -> ~1).
for d in moja-account-lookup-service moja-ml-api-adapter-handler-notification moja-quoting-service-handler; do
  kubectl -n mojaloop patch deployment $d --type=json -p '[
    {"op":"remove","path":"/spec/template/metadata/labels/sidecar.istio.io~1inject"},
    {"op":"remove","path":"/spec/template/metadata/annotations/traffic.sidecar.istio.io~1includeOutboundIPRanges"},
    {"op":"remove","path":"/spec/template/metadata/annotations/traffic.sidecar.istio.io~1includeInboundPorts"},
    {"op":"remove","path":"/spec/template/metadata/annotations/proxy.istio.io~1config"}
  ]' || true
done

# 5c. Restore the egress-GW hostAlias as the FIRST entry.
for d in moja-account-lookup-service moja-ml-api-adapter-handler-notification moja-quoting-service-handler; do
  NEW_HA=$(kubectl get deployment $d -n mojaloop -o json | jq -c '
    [{ip:"10.152.183.253",hostnames:["sim-fsp201.local","sim-fsp202.local","sim-fsp203.local","sim-fsp204.local","sim-fsp205.local","sim-fsp206.local","sim-fsp207.local","sim-fsp208.local"]}]
    + (.spec.template.spec.hostAliases | map(select(.ip != "10.152.183.253")))')
  kubectl patch deployment $d -n mojaloop --type=json \
    -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/hostAliases\",\"value\":${NEW_HA}}]"
done

for d in moja-account-lookup-service moja-ml-api-adapter-handler-notification moja-quoting-service-handler; do kubectl -n mojaloop rollout status deploy $d --timeout=240s; done
```

---

## Fallback — if step 0b shows no object-selector webhook

The injector won't honor the per-pod label in an unlabeled namespace. Then either:
- **Preferred:** add an objectSelector to the injector webhook, or use a revisioned
  injector and put `istio.io/rev=<rev>` as a pod label; **or**
- Label the namespace `istio-injection=enabled` (injects on restart) **and** annotate
  every *other* mojaloop deployment with `sidecar.istio.io/inject: "false"` to keep the
  blast radius to these 3. Heavier; verify the "false" annotations before any rollout.

## If `credentialName` doesn't load on the sidecar (older istiod)

Switch the DRs to **file-mounted certs**: mount `switch-mtls-creds` as a volume in the 3
deployments and change each DR's `portLevelSettings[0].tls` from `credentialName` to
`clientCertificate`/`privateKey`/`caCertificates` file paths. (Confirm the secret's key
names from step 0c first — tls.crt/tls.key plus the CA key.)
