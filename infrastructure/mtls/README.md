# mTLS between the switch and DFSPs (lab)

Enables mTLS on both legs of traffic between the Mojaloop switch and 8 DFSP
simulators (`fsp201`…`fsp208`). Single shared CA + leaf cert (lab only — no
PKI, no per-entity identities).

## Status (as of 2026-04-30)

| Phase | State | Notes |
|---|---|---|
| Phase 0 — cert + values prep | ✅ complete in repo | `regen-certs.sh` + values files committed. |
| Phase 1 — switch Istio + DFSP passthrough | ✅ verified working | Idempotent; re-runnable on a fresh cluster. |
| Phase 2 — DFSP → switch mTLS (Leg A) | ✅ verified working | Envoy config dump shows `require_client_certificate: True`; smoke green. |
| Phase 3 — switch → DFSP mTLS (Leg B) | ✅ verified working | Egress gateway pattern. Smoke transfer reaches `COMPLETED`; per-DFSP Envoy cluster stats show successful mTLS handshakes; DFSP SDK enforces client cert (`Request CERT (13)` in TLS handshake). |

## Architecture (target state)

- **Switch — Leg A (DFSP → switch).** Istio 1.24.1 `istio-ingressgateway`
  (DaemonSet on `CORE-API-ADAPTERS` nodes) terminates DFSP → switch mTLS on
  `:443` and routes to `moja-*` services on `:80`. nginx keeps `:80`.
  **Implemented and working.**
- **Switch — Leg B (switch → DFSP).** Istio 1.24.1 `istio-egressgateway`
  (Deployment in `istio-system`, pinned ClusterIP `10.152.183.200`) originates
  switch → DFSP mTLS. The four callback Deployments
  (`moja-ml-api-adapter-handler-notification`, `moja-account-lookup-service`,
  `moja-quoting-service`, `moja-quoting-service-handler`) carry `hostAliases`
  mapping `sim-fspNNN.local` to the egress gateway's ClusterIP. They send
  plain HTTP `:80` to the gateway; the gateway resolves the real DFSP IP via
  CoreDNS (the switch CoreDNS `hosts{}` block lists DFSP node IPs) and opens
  mTLS `:443`. Resources in `07-switch-outbound-mtls.yaml`: 1× `Gateway`
  (port 80, hosts `sim-fsp*.local`), 8× `ServiceEntry` (`resolution: DNS`),
  8× `VirtualService` (URI prefix `/sim/fspNNN/inbound/` rewritten to `/`),
  8× `DestinationRule` (`MUTUAL` origination on `:443`, SNI = DFSP host).
  ALS callback URLs registered with the switch stay as
  `http://sim-fspNNN.local/sim/…/inbound/…`; the rewrite happens at the
  gateway. **No ambient labels on app pods, no waypoint, no namespace-wide
  mesh enrolment** — only the egress gateway pod runs Envoy.
- **DFSPs** — `sdk-scheme-adapter` terminates and originates mTLS on
  `:4000`. Nginx keeps the existing multi-path Ingress on `:80`; a new
  single-rule `ssl-passthrough` Ingress serves `:443` → SDK `:4000` on the
  same hostname (Phase 1 output; dormant until Phase 3 enables INBOUND mTLS).
- **Certs** — one CA (`mojaloop-perf-lab-ca`) signs one leaf
  (`CN=mojaloop-perf-mtls`) with SANs for all 3 switch + 8 DFSP hostnames.
  Same bundle used as server cert (inbound) and client cert (outbound) on
  both sides.

Pod-to-pod mesh mTLS inside `mojaloop` is deferred (`PeerAuthentication`
`PERMISSIVE`).

## Files

| File | Purpose |
|---|---|
| `regen-certs.sh` | Regenerates the CA + SAN leaf, emits the two Secret manifests below. Re-run to rotate. |
| `04-switch-tls-secret.yaml` | Secret `switch-mtls-creds` (`istio-system`). Generated. |
| `04-dfsp-tls-secret.yaml` | Secret `mtls-shared-creds` (`dfsps`). Generated. Applied on all 8 DFSP clusters. |
| `05-switch-inbound-mtls.yaml` | Istio `Gateway` + 3× `VirtualService` on `:443` (DFSP → switch). |
| `06-istio-egressgateway-values.yaml` | Helm values for Istio EgressGateway. Disables the chart-managed Service (the `istio/gateway` chart has no `service.clusterIP` field) so we ship our own. |
| `06-istio-egressgateway-service.yaml` | Standalone `Service` for the egress gateway with **pinned ClusterIP `10.152.183.200`**. The switch callback Deployments' `hostAliases` reference this IP as a config-time constant. |
| `07-switch-outbound-mtls.yaml` | `Gateway` (in `istio-system`, port 80) + 8× `ServiceEntry` (`resolution: DNS`) + 8× `VirtualService` (URI rewrite, bound to the egress gateway) + 8× `DestinationRule` (MUTUAL origination on `:443`). |
| `hostaliases-mtls.json` | `hostAliases` patch that routes all `sim-fsp*.local` to the egress gateway ClusterIP. Applied to the four switch callback Deployments in Phase 3 (replaces the per-DFSP `hostaliases.json` from Phase 0). |
| `08-dfsp-mtls-passthrough.yaml.template` | Per-DFSP passthrough Ingress, `fspNNN` placeholder. |
| `istio-ingressgateway-values.yaml` | Helm values for Istio IngressGateway (DaemonSet, nodeSelector). |

## Prerequisites

Tools on laptop: `kubectl`, `helm`, `yq`, `jq`, `openssl`, `curl`, `python3`, `sed`, `ssh`.

### Env vars (set in every shell you use)

```bash
export SCENARIO=500tps
export REPO_ROOT=$(git rev-parse --show-toplevel)       # run from inside the repo
export KCDIR=${REPO_ROOT}/performance-tests/results/${SCENARIO}/artifacts/kubeconfigs
export KC_SWITCH=${KCDIR}/kubeconfig-mojaloop-switch.yaml
export HTTPS_PROXY=socks5://127.0.0.1:1080
```

### SOCKS tunnel to the bastion

The bastion's SSH config is generated by Terraform provisioning:

```bash
ssh -F ${REPO_ROOT}/performance-tests/results/${SCENARIO}/artifacts/ssh-config \
  -D 1080 perf-jump-host -N &
```

Leave the tunnel running in the background. Verify with
`lsof -iTCP:1080 -sTCP:LISTEN`.

### Helm repos

The upstream Mojaloop and Istio chart repos must be registered:

```bash
helm repo add mojaloop https://mojaloop.io/helm/repo/
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
```

### Baseline check

```bash
${REPO_ROOT}/performance-tests/src/utils/smoke-transfer.sh    # expect green
```

This is the regression check after every phase.

## Phase 0 — repo preparation

Phase 0 edits live in the repo. This section is both the "what's committed"
reference and the "how to rebuild from scratch" reproduction.

### Step 1 — generate the cert bundle

```bash
${REPO_ROOT}/infrastructure/mtls/regen-certs.sh
```

Emits `04-switch-tls-secret.yaml` (Secret for `istio-system`) and
`04-dfsp-tls-secret.yaml` (Secret for `dfsps`). Single leaf, SANs cover the 3
switch + 8 sim hostnames. Re-run to rotate; commit the regenerated files.

To change the SAN list (e.g. new DFSP, different switch hostname), edit the
`[alt_names]` block in `regen-certs.sh` and re-run.

### Step 2 — patch the 8 values-fspNNN.yaml files

Two additions per file. The exact reproducible patches:

```bash
cd ${REPO_ROOT}
python3 - <<'PY'
import re
from pathlib import Path

# A) Add tlsSecretName sibling of jws under the surviving `secrets:` block.
#    The values file has two `secrets:` keys at the same level; Helm's YAML
#    parser keeps the last one (with `jws:` inside), so we inject there.
a_marker  = "        secrets:\n          jws:\n"
a_replace = "        secrets:\n          tlsSecretName: mtls-shared-creds\n          jws:\n"

# B) Inject MUTUAL_TLS toggles in the top-level env block (overrides `defaults`).
b_pattern = re.compile(r"(          CACHE_EXPIRY_SECONDS: 3600)[ \t]*\n")
b_inject  = (r"\1" "\n\n"
             "          # mTLS toggles — flipped by Phase 2 / Phase 3 of infrastructure/mtls/README.md\n"
             "          OUTBOUND_MUTUAL_TLS_ENABLED: false\n"
             "          INBOUND_MUTUAL_TLS_ENABLED: false\n")

for i in range(201, 209):
    p = Path(f"infrastructure/dfsp/values-fsp{i}.yaml")
    t = p.read_text()
    if a_replace not in t:
        assert t.count(a_marker) == 1, f"{p.name}: A marker not unique"
        t = t.replace(a_marker, a_replace, 1)
    sentinel = "\n          OUTBOUND_MUTUAL_TLS_ENABLED: false\n"
    if sentinel not in t:
        t, n = b_pattern.subn(b_inject, t, count=1)
        assert n == 1, f"{p.name}: B regex did not match"
    p.write_text(t)
    print(f"{p.name}: patched")
PY
```

### Verification

```bash
for i in 201 202 203 204 205 206 207 208; do
  printf "fsp%s: tlsSecretName=%s IN=%s OUT=%s\n" \
    "$i" \
    "$(yq .simulators.fsp${i}.config.schemeAdapter.secrets.tlsSecretName ${REPO_ROOT}/infrastructure/dfsp/values-fsp${i}.yaml 2>/dev/null)" \
    "$(yq .simulators.fsp${i}.config.schemeAdapter.env.INBOUND_MUTUAL_TLS_ENABLED  ${REPO_ROOT}/infrastructure/dfsp/values-fsp${i}.yaml 2>/dev/null)" \
    "$(yq .simulators.fsp${i}.config.schemeAdapter.env.OUTBOUND_MUTUAL_TLS_ENABLED ${REPO_ROOT}/infrastructure/dfsp/values-fsp${i}.yaml 2>/dev/null)"
done
# expect 8 lines: tlsSecretName=mtls-shared-creds IN=false OUT=false
```

Round-trip check the cert:

```bash
yq -r '.data."tls.crt"' ${REPO_ROOT}/infrastructure/mtls/04-switch-tls-secret.yaml \
  | base64 -d | openssl x509 -noout -subject -ext subjectAltName
# expect: subject=CN=mojaloop-perf-mtls  +  SAN list of 11 DNS entries
```

## Phase 1 — prep, non-breaking

Switch and DFSP tracks are independent — run in parallel. `smoke-transfer.sh`
must stay green throughout.

### Phase 1A — switch

Free `:443` on nginx so Istio's ingress gateway can take it. Strategic-merge `apply` won't delete array items (merge-key `containerPort` re-adds them) — use a JSON patch `remove`:

```bash
idx=$(kubectl --kubeconfig=${KC_SWITCH} -n ingress get daemonset nginx-ingress-microk8s-controller -o json \
  | jq '[.spec.template.spec.containers[0].ports[] | .name] | index("https")')
if [[ "$idx" != "null" ]]; then
  kubectl --kubeconfig=${KC_SWITCH} -n ingress patch daemonset nginx-ingress-microk8s-controller --type=json \
    -p="[{\"op\":\"remove\",\"path\":\"/spec/template/spec/containers/0/ports/${idx}\"}]"
  kubectl --kubeconfig=${KC_SWITCH} -n ingress rollout status daemonset nginx-ingress-microk8s-controller --timeout=180s
fi
```

Install Gateway API CRDs + Istio ambient + IngressGateway:

```bash
kubectl --kubeconfig=${KC_SWITCH} apply -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

helm repo add istio https://istio-release.storage.googleapis.com/charts && helm repo update istio

ISTIO=1.24.1
K="--kubeconfig=${KC_SWITCH}"

helm ${K} -n istio-system upgrade --install istio-base        istio/base    --create-namespace --version ${ISTIO} --wait

# Default profile (sidecar-injection-capable). The ingress gateway and
# (in Phase 3) the egress gateway are both Deployments running Envoy —
# they don't need ambient mode, ztunnel, or istio-cni. We're keeping the
# install minimal: just istiod + the gateway chart.
helm ${K} -n istio-system upgrade --install istiod            istio/istiod  --version ${ISTIO} --wait

helm ${K} -n istio-system upgrade --install istio-ingressgateway istio/gateway \
  --version ${ISTIO} --wait --skip-schema-validation \
  -f ${REPO_ROOT}/infrastructure/mtls/istio-ingressgateway-values.yaml

# Chart has no values for :443 container/hostPort — post-install patch (idempotent).
if ! kubectl ${K} -n istio-system get daemonset istio-ingressgateway \
     -o jsonpath='{.spec.template.spec.containers[0].ports[*].name}' | grep -qw https; then
  kubectl ${K} -n istio-system patch daemonset istio-ingressgateway --type=json -p='[
    {"op":"add","path":"/spec/template/spec/containers/0/ports/-",
     "value":{"containerPort":443,"hostPort":443,"name":"https","protocol":"TCP"}}
  ]'
fi
kubectl ${K} -n istio-system rollout status daemonset istio-ingressgateway --timeout=180s
```

Apply Phase 1 mTLS resources (Leg A only — Leg B / `07-switch-outbound-mtls.yaml`
is applied in Phase 3 because it references the egress gateway, which is
deployed there):

```bash
kubectl ${K} apply -f ${REPO_ROOT}/infrastructure/mtls/04-switch-tls-secret.yaml
kubectl ${K} apply -f ${REPO_ROOT}/infrastructure/mtls/05-switch-inbound-mtls.yaml
```

### Phase 1B — DFSPs (loop × 8)

```bash
for i in 201 202 203 204 205 206 207 208; do
  KC=${KCDIR}/kubeconfig-fsp${i}.yaml

  # 1. Enable ssl-passthrough on the nginx controller (capability switch, idempotent).
  #    Do NOT pipe args through `jq ... | unique` — it sorts the array alphabetically
  #    and breaks the container start (`/nginx-ingress-controller` must stay at args[0]).
  if ! kubectl --kubeconfig=${KC} -n ingress get daemonset nginx-ingress-microk8s-controller \
       -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q enable-ssl-passthrough; then
    kubectl --kubeconfig=${KC} -n ingress patch daemonset nginx-ingress-microk8s-controller --type=json -p='[
      {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--enable-ssl-passthrough"}
    ]'
  fi
  kubectl --kubeconfig=${KC} -n ingress rollout status daemonset nginx-ingress-microk8s-controller --timeout=180s

  # 2. Defuse :80 -> :443 auto-redirect that would fire once a TLS Ingress appears
  kubectl --kubeconfig=${KC} -n dfsps annotate ingress dfsp-sim-simulators \
    nginx.ingress.kubernetes.io/ssl-redirect=false --overwrite

  # 3. Shared cert Secret
  kubectl --kubeconfig=${KC} apply -f ${REPO_ROOT}/infrastructure/mtls/04-dfsp-tls-secret.yaml

  # 4. Passthrough Ingress :443 -> SDK :4000
  sed "s/fspNNN/fsp${i}/g" ${REPO_ROOT}/infrastructure/mtls/08-dfsp-mtls-passthrough.yaml.template \
    | kubectl --kubeconfig=${KC} apply -f -

  # 5. Swap the SDK's mounted TLS Secret to our shared-creds Secret.
  #    (We patch the Deployment directly rather than running `helm upgrade` because
  #    `infrastructure/dfsp/deploy.bash` uses `kubectl scale` + `kubectl set image`
  #    after the initial install. Under Helm 4's server-side apply, those field
  #    managers own `.spec.replicas` and the container image, so `helm upgrade`
  #    fails with "Apply failed with 2 conflicts". See Known caveats.)
  kubectl --kubeconfig=${KC} -n dfsps patch deployment dfsp-sim-fsp${i}-scheme-adapter --type=strategic -p '
spec:
  template:
    spec:
      volumes:
      - name: tls-secrets
        secret:
          secretName: mtls-shared-creds'
  kubectl --kubeconfig=${KC} -n dfsps rollout status deployment/dfsp-sim-fsp${i}-scheme-adapter --timeout=240s
done
```

> The `OUTBOUND_MUTUAL_TLS_ENABLED` / `INBOUND_MUTUAL_TLS_ENABLED` flips from Phase 0 are still in the values files as documentation of intent (and future-proofing for a world where `deploy.bash` no longer conflicts with helm). Today they take effect only via the kubectl patches in Phase 2 / Phase 3 below.

### Validate Phase 1

```bash
${REPO_ROOT}/performance-tests/src/utils/smoke-transfer.sh   # expect green

# Switch :443 mTLS path end-to-end (uses the same shared cert as client material)
KC=${KCDIR}/kubeconfig-fsp201.yaml
SWITCH_IP=$(kubectl --kubeconfig=${KC_SWITCH} get node -l workload-class.mojaloop.io/CORE-API-ADAPTERS=true \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

kubectl --kubeconfig=${KC} -n dfsps run mtls-probe-ok --rm -i --restart=Never \
  --image=curlimages/curl:8.10.1 --quiet --overrides='{"spec":{
    "containers":[{"name":"c","image":"curlimages/curl:8.10.1",
      "command":["sh","-c","curl -sS --resolve account-lookup-service.local:443:'${SWITCH_IP}' --cacert /tls/ca.crt --cert /tls/cert.crt --key /tls/cert.key -o /dev/null -w %{http_code} https://account-lookup-service.local/health"],
      "volumeMounts":[{"name":"t","mountPath":"/tls"}]}],
    "volumes":[{"name":"t","secret":{"secretName":"mtls-shared-creds","items":[
      {"key":"outbound-cacert.pem","path":"ca.crt"},
      {"key":"outbound-cert.pem","path":"cert.crt"},
      {"key":"outbound-key.pem","path":"cert.key"}]}}]}}'
# expect: 200

# Enforcement check — same probe WITHOUT client cert. TLS server must demand one.
kubectl --kubeconfig=${KC} -n dfsps run mtls-probe-enforce --rm -i --restart=Never \
  --image=curlimages/curl:8.10.1 --quiet --overrides='{"spec":{
    "containers":[{"name":"c","image":"curlimages/curl:8.10.1",
      "command":["sh","-c","curl -v --resolve account-lookup-service.local:443:'${SWITCH_IP}' --cacert /tls/ca.crt https://account-lookup-service.local/health 2>&1 | grep -E \"Request CERT|alert|error\" | head -3"],
      "volumeMounts":[{"name":"t","mountPath":"/tls"}]}],
    "volumes":[{"name":"t","secret":{"secretName":"mtls-shared-creds","items":[
      {"key":"outbound-cacert.pem","path":"ca.crt"}]}}]}}'
# expect: a line containing "Request CERT (13)" — the server requires a client cert
```

## Phase 2 — DFSP → switch mTLS

Endpoint URLs stay as bare hostnames — the SDK derives `https://…:443` from the
flag. We flip the flag via `kubectl set env` (direct patch) rather than
`helm upgrade`, for the reason explained in Phase 1B step 5.

```bash
# Update values-fspNNN.yaml for documentation / future helm reconciliation
cd ${REPO_ROOT}
python3 - <<'PY'
from pathlib import Path
for i in range(201, 209):
    p = Path(f"infrastructure/dfsp/values-fsp{i}.yaml")
    p.write_text(p.read_text().replace(
        "          OUTBOUND_MUTUAL_TLS_ENABLED: false",
        "          OUTBOUND_MUTUAL_TLS_ENABLED: true", 1))
PY

# Apply the flag to the running Deployments
for i in 201 202 203 204 205 206 207 208; do
  KC=${KCDIR}/kubeconfig-fsp${i}.yaml
  kubectl --kubeconfig=${KC} -n dfsps set env deployment/dfsp-sim-fsp${i}-scheme-adapter \
    --containers=scheme-adapter OUTBOUND_MUTUAL_TLS_ENABLED=true
done

for i in 201 202 203 204 205 206 207 208; do
  KC=${KCDIR}/kubeconfig-fsp${i}.yaml
  kubectl --kubeconfig=${KC} -n dfsps rollout status deployment/dfsp-sim-fsp${i}-scheme-adapter --timeout=240s
done

${REPO_ROOT}/performance-tests/src/utils/smoke-transfer.sh   # expect green
```

Switch → DFSP callbacks remain on plain HTTP `:80` during this phase.

### Hard-proof DFSP → switch traffic is actually mTLS

```bash
GPOD=$(kubectl --kubeconfig=${KC_SWITCH} -n istio-system \
  get pod -l app=istio-ingressgateway -o name | head -1 | cut -d/ -f2)

kubectl --kubeconfig=${KC_SWITCH} -n istio-system exec ${GPOD} -- \
  pilot-agent request GET config_dump \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for cfg in data.get('configs', []):
    if 'ListenersConfigDump' in cfg.get('@type',''):
        for l in cfg.get('dynamic_listeners', []):
            if '_443' in l.get('name',''):
                fc = l['active_state']['listener']['filter_chains'][0]
                ts = fc['transport_socket']['typed_config']
                print('require_client_certificate:', ts.get('require_client_certificate'))
                print('server cert:', [c.get('name') for c in ts.get('common_tls_context',{}).get('tls_certificate_sds_secret_configs', [])])"
# expect:
#   require_client_certificate: True
#   server cert: ['kubernetes://switch-mtls-creds']
```

## Phase 3 — switch → DFSP mTLS (egress gateway)

> Earlier ambient/waypoint attempts in this lab were abandoned because of
> dual-stack DNS auto-allocation breaking Node.js (it dials IPv6 first;
> ztunnel didn't intercept v6) and Bitnami kafka NetworkPolicies refusing
> HBONE on `:15008` from ambient-labelled handler pods. **The egress
> gateway pattern keeps app pods out of the mesh entirely** (no ambient
> label, no sidecar) — neither blocker applies.

### Architecture in one picture

```
[ Switch app pod ]                                              [ Egress gateway pod ]                        [ DFSP node ]
  resolves                                                        resolves                                       :443 nginx
  sim-fsp201.local            plain HTTP :80                       sim-fsp201.local       mTLS :443               ssl-passthrough
  via hostAliases     ──────────────────────────────────►           via switch CoreDNS  ────────────────────►       to SDK :4000
  → 10.152.183.200                                                  → 10.112.2.222                                  (mTLS terminator)
```

- App pod has `hostAliases` overriding `sim-fsp*.local` → `10.152.183.200`
  (the egress gateway's pinned ClusterIP).
- Egress gateway pod has no `hostAliases`; it falls through to CoreDNS,
  which has a `hosts{}` block listing real DFSP node IPs.
- Two resolution scopes, kept apart by which pod is asking. Same hostname,
  different answer per pod role. No Istio DNS proxy, no synthetic VIPs,
  no namespace-wide ambient label.

The four switch Deployments that originate DFSP callbacks (and therefore
need the `hostAliases` patch):

- `moja-ml-api-adapter-handler-notification`
- `moja-account-lookup-service`
- `moja-quoting-service`
- `moja-quoting-service-handler`

### Prerequisites — verify before starting

These must already be true after Phase 1 + Phase 2:

```bash
K="--kubeconfig=${KC_SWITCH}"

# istiod + ingress gateway up
kubectl ${K} -n istio-system get pods | grep -E "istiod|istio-ingressgateway"
# expect: all Running

# switch-mtls-creds Secret in istio-system
kubectl ${K} -n istio-system get secret switch-mtls-creds
# expect: switch-mtls-creds  kubernetes.io/tls   3

# Phase 2 (Leg A) is healthy — DFSP→switch mTLS validated
${REPO_ROOT}/performance-tests/src/utils/smoke-transfer.sh
# expect: PASS smoke-transfer COMPLETED
```

If any of these fail, stop here and finish Phase 1 / Phase 2 first.

If a previous ambient Phase 3 attempt was made, clean up its leftovers:

```bash
K="--kubeconfig=${KC_SWITCH}"
kubectl ${K} delete gateway.gateway.networking.k8s.io/waypoint -n mojaloop --ignore-not-found
kubectl ${K} delete peerauthentication mojaloop-permissive -n mojaloop --ignore-not-found
kubectl ${K} delete authorizationpolicy mojaloop-allow-all -n mojaloop --ignore-not-found
for d in moja-ml-api-adapter-handler-notification \
         moja-account-lookup-service \
         moja-quoting-service \
         moja-quoting-service-handler; do
  kubectl ${K} -n mojaloop label deployment "$d" istio.io/dataplane-mode- 2>/dev/null
  kubectl ${K} -n mojaloop patch deployment "$d" --type=json \
    -p='[{"op":"remove","path":"/spec/template/metadata/labels/istio.io~1dataplane-mode"}]' 2>/dev/null
done
```

### Step 1 — Patch switch CoreDNS with DFSP host entries

The egress gateway pod resolves `sim-fsp*.local` via cluster CoreDNS. We
inject a `hosts{}` block listing the real DFSP node IPs. (Switch app pods
don't read this — they're shadowed by `hostAliases` in step 5.)

```bash
K="--kubeconfig=${KC_SWITCH}"

DFSP_HOSTS=$(jq -r '.spec.template.spec.hostAliases[] | "          \(.ip) \(.hostnames | join(" "))"' \
  ${REPO_ROOT}/performance-tests/results/${SCENARIO}/artifacts/hostaliases.json)

SWITCH_IP=$(kubectl ${K} get node -l workload-class.mojaloop.io/CORE-API-ADAPTERS=true \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

kubectl ${K} -n kube-system patch configmap coredns --type merge -p "$(cat <<EOF
data:
  Corefile: |
    .:53 {
        errors
        health {
          lameduck 5s
        }
        ready
        log . {
          class error
        }
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
        }
        hosts {
          ${SWITCH_IP} account-lookup-service.local quoting-service.local ml-api-adapter.local
${DFSP_HOSTS}
          fallthrough
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
EOF
)"
kubectl ${K} -n kube-system rollout restart deployment coredns
kubectl ${K} -n kube-system rollout status deployment coredns --timeout=120s
```

> ⚠ CoreDNS Corefile syntax requires multi-line `{ ... }` blocks. **Do
> not** collapse `health { lameduck 5s }` onto a single line — CoreDNS
> will fail to start with `Wrong argument count or unexpected line ending
> after '}'`.

**Verify:** the new Corefile has a `hosts{}` block with all 8 DFSP IPs:

```bash
kubectl ${K} -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | grep "sim-fsp"
# expect: 8 lines, e.g.
#   10.112.2.222 sim-fsp201.local
#   10.112.2.57 sim-fsp202.local
#   ...

# CoreDNS pods healthy
kubectl ${K} -n kube-system get pods -l k8s-app=kube-dns
# expect: all Running 1/1
```

**If CoreDNS pods CrashLoopBackOff,** look at the new pod's log:

```bash
NEWPOD=$(kubectl ${K} -n kube-system get pod -l k8s-app=kube-dns --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')
kubectl ${K} -n kube-system logs ${NEWPOD}
# Most likely cause: malformed Corefile. Re-run the patch with corrected syntax.
```

### Step 2 — Install the egress gateway (Helm)

The `istio/gateway` chart does NOT expose `service.clusterIP`. Our values
file disables the chart's Service (`service.type: None`) so we can ship
our own with the pinned IP.

```bash
K="--kubeconfig=${KC_SWITCH}"

helm ${K} -n istio-system upgrade --install istio-egressgateway istio/gateway \
  --version 1.24.1 --wait --skip-schema-validation \
  -f ${REPO_ROOT}/infrastructure/mtls/06-istio-egressgateway-values.yaml
```

**Verify:** 2 pods running, no chart-managed Service yet:

```bash
kubectl ${K} -n istio-system get pods -l istio=egressgateway
# expect: 2 pods, all Running 1/1

kubectl ${K} -n istio-system get svc istio-egressgateway 2>&1
# expect: Error from server (NotFound)   ← chart skipped Service creation, by design
```

### Step 3 — Create the standalone Service with pinned ClusterIP

```bash
kubectl ${K} apply -f ${REPO_ROOT}/infrastructure/mtls/06-istio-egressgateway-service.yaml
```

**Verify:** the Service has `ClusterIP: 10.152.183.200`:

```bash
kubectl ${K} -n istio-system get svc istio-egressgateway -o wide
# expect:
#   NAME                  TYPE        CLUSTER-IP       PORT(S)              SELECTOR
#   istio-egressgateway   ClusterIP   10.152.183.200   15021/TCP,80/TCP     app=istio-egressgateway,istio=egressgateway
```

> ⚠ If `10.152.183.200` is already taken on a fresh cluster
> (`Error from server: services "..." already exists` or
> `ip already allocated`), pick another free address in the cluster's
> service CIDR (default `10.152.183.0/24` on MicroK8s) and update **both**
> `06-istio-egressgateway-service.yaml` AND `hostaliases-mtls.json`. The
> two files must agree.

### Step 4 — Apply the Istio resources

`07-switch-outbound-mtls.yaml` declares: 1× `Gateway` (in `istio-system`,
port 80, hosts `sim-fsp*.local`), 8× `ServiceEntry` (`resolution: DNS`,
port 443), 8× `VirtualService` (URI prefix `/sim/fspNNN/inbound/` → `/`,
bound to the gateway), 8× `DestinationRule` (MUTUAL TLS on `:443`,
`credentialName: switch-mtls-creds`, `sni: sim-fspNNN.local`).

```bash
kubectl ${K} apply -f ${REPO_ROOT}/infrastructure/mtls/07-switch-outbound-mtls.yaml
```

**Verify:** Envoy on the egress gateway has TLS configured for each DFSP
upstream cluster:

```bash
GW=$(kubectl ${K} -n istio-system get pod -l istio=egressgateway -o jsonpath='{.items[0].metadata.name}')

kubectl ${K} -n istio-system exec ${GW} -- pilot-agent request GET config_dump 2>/dev/null \
  | jq '.configs[] | select(."@type" | contains("ClustersConfigDump")) | .dynamic_active_clusters[]
        | select(.cluster.name=="outbound|443||sim-fsp201.local") | .cluster.transport_socket_matches[]
        | select(.name=="user")
        | {client_cert: .transport_socket.typed_config.common_tls_context.tls_certificate_sds_secret_configs[0].name,
           ca: .transport_socket.typed_config.common_tls_context.combined_validation_context.validation_context_sds_secret_config.name,
           sni: .transport_socket.typed_config.sni}'
# expect:
# {
#   "client_cert": "kubernetes://switch-mtls-creds",
#   "ca": "kubernetes://switch-mtls-creds-cacert",
#   "sni": "sim-fsp201.local"
# }
```

### Step 5 — Repoint switch app `hostAliases` at the egress gateway

This replaces the per-DFSP `hostaliases.json` patched in Phase 0 /
`deploy.bash`. After this step, every `sim-fsp*.local` DNS lookup from the
four callback Deployments lands at `10.152.183.200`.

```bash
K="--kubeconfig=${KC_SWITCH}"

for d in moja-ml-api-adapter-handler-notification \
         moja-account-lookup-service \
         moja-quoting-service \
         moja-quoting-service-handler; do
  kubectl ${K} -n mojaloop patch deployment "$d" --type=strategic \
    -p "$(cat ${REPO_ROOT}/infrastructure/mtls/hostaliases-mtls.json)"
done

# Wait for all rollouts in parallel.
for d in moja-ml-api-adapter-handler-notification \
         moja-account-lookup-service \
         moja-quoting-service \
         moja-quoting-service-handler; do
  kubectl ${K} -n mojaloop rollout status deployment "$d" --timeout=600s &
done
wait
```

> ⚠ The kafka-consuming handlers
> (`moja-quoting-service-handler`,`moja-ml-api-adapter-handler-notification`)
> rebalance during pod replacement; their rollouts can take 5+ minutes.
> Don't proceed until all 4 Deployments report `successfully rolled out`.

**Verify:** a switch app pod resolves `sim-fsp201.local` to the egress
gateway IP, not the DFSP IP:

```bash
POD=$(kubectl ${K} -n mojaloop get pod -l app.kubernetes.io/name=ml-api-adapter-handler-notification \
  -o jsonpath='{.items[0].metadata.name}')
kubectl ${K} -n mojaloop exec ${POD} -c ml-api-adapter-handler-notification -- \
  getent hosts sim-fsp201.local
# expect:
#   10.152.183.200    sim-fsp201.local  sim-fsp201.local
```

### Step 6 — Flip INBOUND mTLS on all 8 DFSPs

The DFSP SDKs currently serve plain HTTP on `:4000`. Until this flip,
nginx ssl-passthrough hands raw TLS bytes to a non-TLS server and the
egress gateway's TLS handshake fails with
`SSL routines:OPENSSL_internal:WRONG_VERSION_NUMBER`.

```bash
# Update the values files for documentation / future helm reconciliation.
cd ${REPO_ROOT}
python3 - <<'PY'
from pathlib import Path
for i in range(201, 209):
    p = Path(f"infrastructure/dfsp/values-fsp{i}.yaml")
    p.write_text(p.read_text().replace(
        "          INBOUND_MUTUAL_TLS_ENABLED: false",
        "          INBOUND_MUTUAL_TLS_ENABLED: true", 1))
PY

# Apply the flag on each DFSP's running SDK.
for i in 201 202 203 204 205 206 207 208; do
  KC=${KCDIR}/kubeconfig-fsp${i}.yaml
  kubectl --kubeconfig=${KC} -n dfsps set env deployment/dfsp-sim-fsp${i}-scheme-adapter \
    --containers=scheme-adapter INBOUND_MUTUAL_TLS_ENABLED=true
done

# Wait for all 8 to roll out in parallel.
for i in 201 202 203 204 205 206 207 208; do
  KC=${KCDIR}/kubeconfig-fsp${i}.yaml
  kubectl --kubeconfig=${KC} -n dfsps rollout status deployment/dfsp-sim-fsp${i}-scheme-adapter --timeout=600s &
done
wait
```

**Verify:** the SDK is now requiring a client cert (negative probe — TLS
without cert from inside the DFSP cluster):

```bash
KC=${KCDIR}/kubeconfig-fsp202.yaml
kubectl --kubeconfig=${KC} -n dfsps run nocert-probe --rm -i --restart=Never --quiet \
  --image=curlimages/curl:8.10.1 -- sh -c '
    SDK_IP=$(getent hosts dfsp-sim-fsp202-scheme-adapter | head -1 | awk "{print \$1}")
    curl -v --insecure --connect-timeout 5 -o /dev/null https://$SDK_IP:4000/ 2>&1 | grep -E "Request CERT|alert" | head -3
  '
# expect: a line containing "TLSv1.3 (IN), TLS handshake, Request CERT (13):"
#         (the SDK is asking the client for a certificate — i.e. mTLS is enforced)
```

### Step 7 — End-to-end smoke

```bash
${REPO_ROOT}/performance-tests/src/utils/smoke-transfer.sh
# expect:
#   [1/3 POST]        currentState=WAITING_FOR_PARTY_ACCEPTANCE
#   [2/3 acceptParty] currentState=WAITING_FOR_QUOTE_ACCEPTANCE
#   [3/3 acceptQuote] currentState=COMPLETED
#   PASS  smoke-transfer COMPLETED
```

### Final verification — prove the egress gateway is the path

```bash
K="--kubeconfig=${KC_SWITCH}"
GW=$(kubectl ${K} -n istio-system get pod -l istio=egressgateway -o jsonpath='{.items[0].metadata.name}')

# A) Per-DFSP cluster stats on the egress gateway — should show successful
#    upstream connections to real DFSP IPs after a smoke run.
kubectl ${K} -n istio-system exec ${GW} -- pilot-agent request GET clusters 2>/dev/null \
  | grep -F "outbound|443||sim-fsp" \
  | grep -E "::cx_total::|::rq_success::" \
  | sort
# expect: per-DFSP lines like:
#   outbound|443||sim-fsp202.local::10.112.2.57:443::cx_total::N
#   outbound|443||sim-fsp202.local::10.112.2.57:443::rq_success::N
#   (run smoke-transfer.sh again if all counters are 0)

# B) DFSP SDK access log shows the request came from the egress gateway —
#    the x-envoy-peer-metadata-id header is added by Envoy on the source proxy.
KC=${KCDIR}/kubeconfig-fsp202.yaml
SDK=$(kubectl --kubeconfig=${KC} -n dfsps get pods -o name | grep scheme-adapter | head -1 | cut -d/ -f2)
kubectl --kubeconfig=${KC} -n dfsps logs ${SDK} --tail=400 \
  | grep -E "x-envoy-peer-metadata-id.*istio-egressgateway" | head -2
# expect: a request log line whose headers include
#   "x-envoy-peer-metadata-id":"router~<gw-pod-ip>~istio-egressgateway-<hash>.istio-system~..."
#   (irrefutable proof that the request transited the egress gateway)
```

## Rollback

### Phase 3

Reverts the four callback Deployments' `hostAliases` to the per-DFSP
mapping, disables INBOUND mTLS on the DFSPs, deletes the egress gateway
and its Istio resources, and removes the DFSP entries from switch CoreDNS.

```bash
K="--kubeconfig=${KC_SWITCH}"

# 1. Revert INBOUND mTLS on DFSPs
cd ${REPO_ROOT}
python3 -c '
from pathlib import Path
for i in range(201,209):
    p=Path(f"infrastructure/dfsp/values-fsp{i}.yaml")
    p.write_text(p.read_text().replace(
      "          INBOUND_MUTUAL_TLS_ENABLED: true",
      "          INBOUND_MUTUAL_TLS_ENABLED: false",1))'
for i in 201 202 203 204 205 206 207 208; do
  KC=${KCDIR}/kubeconfig-fsp${i}.yaml
  kubectl --kubeconfig=${KC} -n dfsps set env deployment/dfsp-sim-fsp${i}-scheme-adapter \
    --containers=scheme-adapter INBOUND_MUTUAL_TLS_ENABLED=false
done

# 2. Restore the per-DFSP hostAliases on the four callback Deployments.
#    Source of truth: performance-tests/results/${SCENARIO}/artifacts/hostaliases.json
HOSTALIASES=${REPO_ROOT}/performance-tests/results/${SCENARIO}/artifacts/hostaliases.json
for d in moja-ml-api-adapter-handler-notification \
         moja-account-lookup-service \
         moja-quoting-service \
         moja-quoting-service-handler; do
  kubectl ${K} -n mojaloop patch deployment "$d" --type=strategic -p "$(cat ${HOSTALIASES})"
  kubectl ${K} -n mojaloop rollout status deployment "$d" --timeout=240s
done

# 3. Tear down Leg B Istio resources and the egress gateway (chart + standalone Service).
kubectl ${K} delete -f ${REPO_ROOT}/infrastructure/mtls/07-switch-outbound-mtls.yaml --ignore-not-found
kubectl ${K} delete -f ${REPO_ROOT}/infrastructure/mtls/06-istio-egressgateway-service.yaml --ignore-not-found
helm ${K} -n istio-system uninstall istio-egressgateway 2>/dev/null || true

# 4. Restore the original switch CoreDNS Corefile (no DFSP hosts{} entries).
#    The deploy.bash already programs only switch services into hosts{}.
SWITCH_IP=$(kubectl ${K} get node -l workload-class.mojaloop.io/CORE-API-ADAPTERS=true \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
kubectl ${K} -n kube-system patch configmap coredns --type merge -p "$(cat <<EOF
data:
  Corefile: |
    .:53 {
        errors
        health {
          lameduck 5s
        }
        ready
        log . {
          class error
        }
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
        }
        hosts {
          ${SWITCH_IP} account-lookup-service.local quoting-service.local ml-api-adapter.local
          fallthrough
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
EOF
)"
kubectl ${K} -n kube-system rollout restart deployment coredns
```

### Phase 2

```bash
cd ${REPO_ROOT}
python3 -c '
from pathlib import Path
for i in range(201,209):
    p=Path(f"infrastructure/dfsp/values-fsp{i}.yaml")
    p.write_text(p.read_text().replace(
      "          OUTBOUND_MUTUAL_TLS_ENABLED: true",
      "          OUTBOUND_MUTUAL_TLS_ENABLED: false",1))'
for i in 201 202 203 204 205 206 207 208; do
  KC=${KCDIR}/kubeconfig-fsp${i}.yaml
  kubectl --kubeconfig=${KC} -n dfsps set env deployment/dfsp-sim-fsp${i}-scheme-adapter \
    --containers=scheme-adapter OUTBOUND_MUTUAL_TLS_ENABLED=false
done
```

### Phase 1 — DFSPs

```bash
for i in 201 202 203 204 205 206 207 208; do
  KC=${KCDIR}/kubeconfig-fsp${i}.yaml

  # Revert the TLS Secret mount back to the chart-generated one
  kubectl --kubeconfig=${KC} -n dfsps patch deployment dfsp-sim-fsp${i}-scheme-adapter --type=strategic -p "
spec:
  template:
    spec:
      volumes:
      - name: tls-secrets
        secret:
          secretName: dfsp-sim-fsp${i}-tls-creds"

  kubectl --kubeconfig=${KC} -n dfsps delete ingress dfsp-sim-fsp${i}-mtls-passthrough --ignore-not-found
  kubectl --kubeconfig=${KC} -n dfsps annotate ingress dfsp-sim-simulators nginx.ingress.kubernetes.io/ssl-redirect-
  kubectl --kubeconfig=${KC} -n dfsps delete secret mtls-shared-creds --ignore-not-found

  # Remove --enable-ssl-passthrough — find its index, then JSON-patch remove.
  # Do NOT use `jq ... | apply` to rewrite args: it sorts the array alphabetically
  # and moves /nginx-ingress-controller off args[0], crashing the container.
  idx=$(kubectl --kubeconfig=${KC} -n ingress get daemonset nginx-ingress-microk8s-controller -o json \
    | jq '[.spec.template.spec.containers[0].args[]] | index("--enable-ssl-passthrough")')
  if [[ "$idx" != "null" ]]; then
    kubectl --kubeconfig=${KC} -n ingress patch daemonset nginx-ingress-microk8s-controller --type=json \
      -p="[{\"op\":\"remove\",\"path\":\"/spec/template/spec/containers/0/args/${idx}\"}]"
    kubectl --kubeconfig=${KC} -n ingress rollout status daemonset nginx-ingress-microk8s-controller --timeout=180s
  fi
done
```

### Phase 1 — switch

```bash
K="--kubeconfig=${KC_SWITCH}"

kubectl ${K} -n mojaloop delete secret switch-mtls-creds --ignore-not-found
kubectl ${K} delete -f ${REPO_ROOT}/infrastructure/mtls/07-switch-outbound-mtls.yaml --ignore-not-found
kubectl ${K} delete -f ${REPO_ROOT}/infrastructure/mtls/05-switch-inbound-mtls.yaml --ignore-not-found
kubectl ${K} delete -f ${REPO_ROOT}/infrastructure/mtls/04-switch-tls-secret.yaml --ignore-not-found

helm ${K} -n istio-system uninstall istio-egressgateway 2>/dev/null || true
helm ${K} -n istio-system uninstall istio-ingressgateway
helm ${K} -n istio-system uninstall istiod
helm ${K} -n istio-system uninstall istio-base
kubectl ${K} delete ns istio-system --ignore-not-found
kubectl ${K} delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml --ignore-not-found

# Restore :443 on switch nginx
kubectl ${K} -n ingress patch daemonset nginx-ingress-microk8s-controller --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/ports/-",
   "value":{"containerPort":443,"hostPort":443,"name":"https","protocol":"TCP"}}
]'
kubectl ${K} -n ingress rollout status daemonset nginx-ingress-microk8s-controller --timeout=180s
```

## Known caveats

- **Helm 4 schema validation** fails on Istio's gateway chart —
  `--skip-schema-validation` is required.
- **Values file YAML is brittle**: `values-fspNNN.yaml` has duplicate
  `&inbound` anchors that make `defaults.config.schemeAdapter.secrets.tls.{inbound,outbound}`
  resolve to `null`. That's why we use `tlsSecretName` to supply the cert —
  putting PEMs directly in `tls.inbound`/`tls.outbound` would be silently
  ignored.
- **Server-cert SAN list** covers the 3 switch hostnames + 8 sim hostnames,
  nothing else. A new hostname (e.g. `bulk-*.local`, a 9th DFSP) needs a new
  SAN list — rerun `regen-certs.sh` with the file updated.
- **Why egress gateway and not ambient/waypoint.** A 2026-04-30 ambient
  attempt got the synthetic VIP machinery working (DNS capture +
  `PILOT_ENABLE_IP_AUTOALLOCATE=true`; SEs bound to a waypoint and
  resolved to `240.240.x.x`) but broke at the application layer:
  (a) `PILOT_ENABLE_IP_AUTOALLOCATE` allocates **both** v4 and v6 VIPs;
  Node.js dialed v6, ztunnel didn't intercept v6, ALS calls timed out;
  (b) ambient labels on the kafka-consuming handler Deployments wrapped
  their kafka traffic in HBONE `:15008`, which the Bitnami kafka
  NetworkPolicy doesn't allow → consumers connected but never got
  partition assignment, readiness probes failed. Egress gateway pattern
  keeps app pods out of the mesh (no ambient label, no sidecar) and
  routes through a single Envoy at the edge — neither blocker applies.
  See `mtls_phase3_blocker.md` in the project memory for the full
  empirical record.
- **Pinned ClusterIP for the egress gateway.** `10.152.183.200` was
  picked from the MicroK8s default service CIDR `10.152.183.0/24`. It
  was free at the time of writing; if a fresh cluster reports it taken,
  pick another IP in the high range and update both
  `06-istio-egressgateway-service.yaml` and `hostaliases-mtls.json`. The
  Service and the patch must agree.
- **`istio/gateway` chart has no `service.clusterIP` field.** That's
  why we set `service.type: None` in `06-istio-egressgateway-values.yaml`
  and ship our own Service in `06-istio-egressgateway-service.yaml`.
  Don't try `--set service.clusterIP=...` — it's silently dropped by
  the chart and you'll get a random ClusterIP.
- **CoreDNS Corefile multi-line block syntax.** `health { lameduck 5s }`
  on a single line crashes CoreDNS at startup with
  `Wrong argument count or unexpected line ending after '}'`. Each
  `block { ... }` directive must be on its own multi-line block. The
  Phase 3 / rollback patches are already correct — match their layout
  if you edit them.
- **Phase 3 ordering: INBOUND mTLS flip is required.** If the
  `INBOUND_MUTUAL_TLS_ENABLED=true` flip on the DFSP SDKs is skipped or
  mis-applied, nginx ssl-passthrough hands TLS bytes to a non-TLS server
  (the SDK still serves plain HTTP on `:4000`), and the egress gateway's
  TLS handshake fails with `OPENSSL_internal:WRONG_VERSION_NUMBER`. The
  smoke test will fail with HTTP 503 from Envoy before the SDK even
  sees a request.
- **Never mutate MicroK8s nginx `args` via `jq ... | unique | kubectl apply`**.
  `unique` sorts the array alphabetically, which moves `/nginx-ingress-controller`
  off `args[0]` — the container then tries to exec `" "` (a literal space) and
  dies with `No such file or directory`. Use JSON-patch `add`/`remove` at an
  explicit index (as the Phase 1B and rollback snippets do).
- **Strategic-merge cannot delete array items** whose merge key still matches.
  Removing `:443` from the nginx DS via `jq '...map(select(.name != "https"))' | kubectl apply`
  silently re-adds the port. Use JSON-patch `remove` at a computed index.
- **Helm 4 vs `deploy.bash` field ownership**: this repo's `infrastructure/dfsp/deploy.bash`
  uses `kubectl scale --replicas=…` and (historically) `kubectl set image …` after the
  initial `helm install`. Under Helm 4's server-side apply, those manager names own
  `.spec.replicas` and `.spec.template.spec.containers[name="scheme-adapter"].image`,
  so any later `helm upgrade` fails with `Apply failed with 2 conflicts: conflicts with
  "kubectl" with subresource "scale"` / `conflicts with "kubectl-set"`. For mTLS
  rollout we sidestep this by patching the Deployment directly (`kubectl patch` for
  the volume, `kubectl set env` for the flags) instead of running `helm upgrade`.
  The values files still carry the `tlsSecretName` + `*_MUTUAL_TLS_ENABLED` flips so
  the intent is recorded and a future cleanup (moving replicas / image into values,
  then running `helm upgrade --force-conflicts --take-ownership`) makes helm the
  single owner again.
