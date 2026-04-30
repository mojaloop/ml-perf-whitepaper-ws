# mTLS Implementation Analysis for ml-perf-whitepaper-ws

## Executive Summary

This document analyzes the current ml-perf-whitepaper-ws environment and provides comprehensive options for implementing mTLS at the Mojaloop switch ingress point for performance testing scenarios.

---

## 1. Current ml-perf-whitepaper-ws Setup

### Infrastructure Overview

**Cloud Provider**: AWS (eu-west-2)
**Kubernetes Distribution**: MicroK8s 1.32/stable
**CNI**: Calico (MicroK8s default)
**Ingress Controller**: NGINX Ingress Controller (MicroK8s addon)

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       AWS VPC (10.112.0.0/16)               │
│                                                             │
│  ┌────────────┐         ┌──────────────────────────────┐  │
│  │  Bastion   │────────▶│   Private Subnet (10.112.2.0/24) │
│  │   Host     │         │                               │  │
│  └────────────┘         │  ┌─────────────────────────┐  │  │
│                         │  │ Switch Cluster (3-node)  │  │  │
│                         │  │ - Mojaloop core services │  │  │
│                         │  │ - Kafka, MySQL, MongoDB  │  │  │
│                         │  │ - Internal NLB           │  │  │
│                         │  │   (80→30080, 443→30443) │  │  │
│                         │  └─────────────────────────┘  │  │
│                         │                               │  │
│                         │  ┌─────────────────────────┐  │  │
│                         │  │ DFSP Clusters (8x)       │  │  │
│                         │  │ - fsp201-fsp208          │  │  │
│                         │  │ - mojaloop-simulator     │  │  │
│                         │  │ - sdk-scheme-adapter     │  │  │
│                         │  └─────────────────────────┘  │  │
│                         │                               │  │
│                         │  ┌─────────────────────────┐  │  │
│                         │  │ k6 Cluster (1-node)      │  │  │
│                         │  │ - k6 Operator            │  │  │
│                         │  │ - Performance tests      │  │  │
│                         │  └─────────────────────────┘  │  │
│                         └───────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Current State Analysis

#### What's Deployed
- **MicroK8s addons enabled**: dns, storage, ingress, metrics-server
- **Ingress**: NGINX Ingress Controller (via MicroK8s addon)
  - NodePort 30080 (HTTP) and 30443 (HTTPS)
  - Internal NLB forwards traffic to these NodePorts
- **TLS/mTLS Status**: Currently disabled
  - `INBOUND_MUTUAL_TLS_ENABLED: false` in DFSP values
  - `OUTBOUND_MUTUAL_TLS_ENABLED: false` in DFSP values
- **Certificate Infrastructure**: Present but not active
  - Shared CA certificate exists: `/infrastructure/dfsp/generate-tls/ca-cert.pem`
  - Shared client cert/key exists for all DFSPs (simplifies testing)
  - cert-manager installed with ClusterIssuers configured

#### CNI Details
- **Calico CNI** (MicroK8s default)
  - BGP routing (port 179/tcp)
  - VXLAN overlay (port 4789/udp)
  - **NOT Cilium** - therefore no CiliumEnvoyConfig option available

#### DNS Strategy
- `.local` domains for private VPC communication
- Cross-cluster DNS via CoreDNS ConfigMap patches and pod hostAliases
- DFSPs resolve: `account-lookup-service.local`, `quoting-service.local`, `ml-api-adapter.local` → switch NLB IP

#### Performance Considerations
- Cluster placement group for lowest latency (all instances in same rack)
- ENA support enabled (Enhanced Networking Adapter)
- EBS optimized instances
- High IOPS storage (gp3/io2 volumes)
- Current test scenarios: 500 TPS, 1000 TPS, 2000 TPS

---

## 2. Istio-Based mTLS Implementation (Detailed)

### Overview
Istio is a full-featured service mesh that provides mTLS, traffic management, observability, and policy enforcement. For the switch ingress use case, we'd primarily use Istio Ingress Gateway.

### Architecture

```
┌───────────────────────────────────────────────────────────┐
│                    Switch Cluster                         │
│                                                           │
│  ┌──────────────────────────────────────────────────┐   │
│  │         AWS Network Load Balancer                │   │
│  │         (Internal, 80:30080, 443:30443)          │   │
│  └─────────────────┬────────────────────────────────┘   │
│                    │                                     │
│  ┌─────────────────▼────────────────────────────────┐   │
│  │     Istio Ingress Gateway (NodePort 30443)       │   │
│  │     - Terminates mTLS from DFSPs                 │   │
│  │     - Validates client certificates              │   │
│  │     - Routes to Mojaloop services                │   │
│  └─────────────────┬────────────────────────────────┘   │
│                    │ Plain HTTP                          │
│  ┌─────────────────▼────────────────────────────────┐   │
│  │    Mojaloop Core Services                        │   │
│  │    - ml-api-adapter                              │   │
│  │    - account-lookup-service                      │   │
│  │    - quoting-service                             │   │
│  └──────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────┘
```

### Installation Steps

#### 1. Install Istio (Minimal Profile for Ingress Only)

```bash
# Download Istio
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.23.0 sh -
cd istio-1.23.0
export PATH=$PWD/bin:$PATH

# Install Istio with minimal profile (ingress gateway only, no sidecar injection)
istioctl install --set profile=minimal -y

# Verify installation
kubectl get pods -n istio-system
```

**Expected output**:
```
NAME                                    READY   STATUS    RESTARTS   AGE
istio-ingressgateway-xxx                1/1     Running   0          1m
istiod-xxx                              1/1     Running   0          1m
```

#### 2. Create mTLS Certificate Secret

```bash
# Use existing shared certificates from infrastructure/dfsp/generate-tls/
kubectl create namespace istio-system  # if not exists

kubectl create secret generic mojaloop-mtls-certs \
  -n istio-system \
  --from-file=tls.crt=infrastructure/dfsp/generate-tls/shared-cert.pem \
  --from-file=tls.key=infrastructure/dfsp/generate-tls/shared-key.pem \
  --from-file=ca.crt=infrastructure/dfsp/generate-tls/ca-cert.pem
```

#### 3. Configure Istio Gateway for mTLS

Create `/infrastructure/mojaloop/istio-gateway-mtls.yaml`:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: mojaloop-mtls-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway  # Use Istio's ingress gateway
  servers:
  # HTTPS with mTLS for FSPIOP API
  - port:
      number: 443
      name: https-mtls
      protocol: HTTPS
    tls:
      mode: MUTUAL  # Enforce client certificate validation
      credentialName: mojaloop-mtls-certs  # Secret with CA cert
      minProtocolVersion: TLSV1_2
    hosts:
    - "ml-api-adapter.local"
    - "account-lookup-service.local"
    - "quoting-service.local"
  # Optional: HTTP port for non-mTLS traffic (admin, monitoring)
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "testing-toolkit.local"
    - "grafana.local"
```

#### 4. Configure VirtualServices for Routing

Create `/infrastructure/mojaloop/istio-virtualservices.yaml`:

```yaml
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: ml-api-adapter
  namespace: default
spec:
  hosts:
  - "ml-api-adapter.local"
  gateways:
  - istio-system/mojaloop-mtls-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: ml-api-adapter-service.default.svc.cluster.local
        port:
          number: 80
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: account-lookup-service
  namespace: default
spec:
  hosts:
  - "account-lookup-service.local"
  gateways:
  - istio-system/mojaloop-mtls-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: account-lookup-service.default.svc.cluster.local
        port:
          number: 80
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: quoting-service
  namespace: default
spec:
  hosts:
  - "quoting-service.local"
  gateways:
  - istio-system/mojaloop-mtls-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: quoting-service.default.svc.cluster.local
        port:
          number: 80
```

#### 5. Adjust Istio Gateway Service to Use Existing NodePort

```bash
# Patch the istio-ingressgateway service to use NodePort 30443
kubectl patch service istio-ingressgateway -n istio-system -p '
{
  "spec": {
    "type": "NodePort",
    "ports": [
      {
        "name": "http2",
        "port": 80,
        "targetPort": 8080,
        "nodePort": 30080
      },
      {
        "name": "https",
        "port": 443,
        "targetPort": 8443,
        "nodePort": 30443
      }
    ]
  }
}'
```

#### 6. Apply Configuration

```bash
kubectl apply -f infrastructure/mojaloop/istio-gateway-mtls.yaml
kubectl apply -f infrastructure/mojaloop/istio-virtualservices.yaml
```

#### 7. Enable mTLS on DFSP Side

Update DFSP Helm values (e.g., `infrastructure/dfsp/values-fsp201.yaml`):

```yaml
schemeAdapter:
  env:
    OUTBOUND_MUTUAL_TLS_ENABLED: true
  secrets:
    tls:
      outbound:
        cert: |
          -----BEGIN CERTIFICATE-----
          <content of shared-cert.pem>
          -----END CERTIFICATE-----
        key: |
          -----BEGIN PRIVATE KEY-----
          <content of shared-key.pem>
          -----END PRIVATE KEY-----
        cacert: |
          -----BEGIN CERTIFICATE-----
          <content of ca-cert.pem>
          -----END CERTIFICATE-----
```

### Pros

1. **Battle-tested**: Industry standard service mesh, extensive production use
2. **Rich features**: Traffic management, retries, circuit breaking, rate limiting
3. **Observability**: Built-in metrics, tracing, and access logging
4. **Fine-grained control**: Per-route policies, header manipulation
5. **mTLS everywhere**: Can optionally enable mTLS between all services (not just ingress)
6. **Community support**: Large community, extensive documentation
7. **Mutual TLS support**: Native `tls.mode: MUTUAL` in Gateway spec

### Cons

1. **Resource overhead**: 
   - Control plane (istiod): ~500MB memory, 0.5 CPU
   - Ingress gateway: ~256MB memory, 0.2 CPU
   - **Impact on 2000 TPS**: Moderate (adds ~1-2ms latency for TLS termination)
2. **Complexity**: 
   - New CRDs to learn (Gateway, VirtualService, DestinationRule)
   - Requires understanding of Istio concepts
   - More moving parts to debug
3. **Operational burden**: 
   - Need to monitor Istio components
   - Certificate rotation procedures
   - Upgrade path considerations
4. **Overkill for simple use case**: Most features unused in perf testing scenario
5. **Learning curve**: Team needs Istio expertise

### Performance Impact

- **TLS handshake overhead**: ~5-10ms per connection (mitigated by connection reuse)
- **Data plane latency**: ~1-2ms added per request
- **Throughput**: Minimal impact (<5%) at 2000 TPS with proper tuning
- **CPU usage**: Ingress gateway uses ~10-15% more CPU for TLS termination

### Resource Requirements

```yaml
# Recommended resource limits for 2000 TPS
istio-ingressgateway:
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 2Gi
  hpaSpec:
    minReplicas: 2
    maxReplicas: 5
```

---

## 3. Alternative mTLS Solutions

### 3.1 NGINX Ingress Controller with mTLS (Recommended for ml-perf)

**Why this is the best fit for ml-perf-whitepaper-ws**:
- Already installed (MicroK8s addon)
- Zero new infrastructure
- Minimal complexity
- Lowest performance overhead

#### Architecture

```
┌────────────────────────────────────────────────────────┐
│               AWS Network Load Balancer                │
│               (80:30080, 443:30443)                    │
└───────────────────┬────────────────────────────────────┘
                    │
┌───────────────────▼────────────────────────────────────┐
│          NGINX Ingress Controller                      │
│          (Already running as MicroK8s addon)           │
│          - nginx.ingress.kubernetes.io/auth-tls-verify-client: "on" │
│          - Validates client cert against CA            │
└───────────────────┬────────────────────────────────────┘
                    │ HTTP
┌───────────────────▼────────────────────────────────────┐
│          Mojaloop Services                             │
└────────────────────────────────────────────────────────┘
```

#### Implementation Steps

**1. Create TLS Secret**

```bash
kubectl create secret generic mojaloop-mtls-ca \
  --from-file=ca.crt=infrastructure/dfsp/generate-tls/ca-cert.pem \
  --namespace=default

kubectl create secret tls mojaloop-server-tls \
  --cert=infrastructure/dfsp/generate-tls/shared-cert.pem \
  --key=infrastructure/dfsp/generate-tls/shared-key.pem \
  --namespace=default
```

**2. Create Ingress with mTLS**

Create `/infrastructure/mojaloop/nginx-ingress-mtls.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mojaloop-mtls-ingress
  namespace: default
  annotations:
    # Enable mTLS
    nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"
    nginx.ingress.kubernetes.io/auth-tls-secret: "default/mojaloop-mtls-ca"
    nginx.ingress.kubernetes.io/auth-tls-verify-depth: "1"
    nginx.ingress.kubernetes.io/auth-tls-pass-certificate-to-upstream: "false"
    
    # SSL settings
    nginx.ingress.kubernetes.io/ssl-protocols: "TLSv1.2 TLSv1.3"
    nginx.ingress.kubernetes.io/ssl-ciphers: "HIGH:!aNULL:!MD5"
    
    # Backend protocol
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - ml-api-adapter.local
    - account-lookup-service.local
    - quoting-service.local
    secretName: mojaloop-server-tls
  rules:
  - host: ml-api-adapter.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ml-api-adapter-service
            port:
              number: 80
  - host: account-lookup-service.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: account-lookup-service
            port:
              number: 80
  - host: quoting-service.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: quoting-service
            port:
              number: 80
```

**3. Apply**

```bash
kubectl apply -f infrastructure/mojaloop/nginx-ingress-mtls.yaml
```

**4. Update DFSP Configuration**

Same as Istio approach - set `OUTBOUND_MUTUAL_TLS_ENABLED: true` and provide certificates.

#### Pros

1. **Already installed**: Zero new infrastructure
2. **Minimal overhead**: NGINX is highly optimized
3. **Simple configuration**: Standard Ingress annotations
4. **Low learning curve**: Team likely familiar with NGINX
5. **Performance**: Best performance of all options (~0.5-1ms overhead)
6. **Resource efficient**: No additional pods/services needed
7. **Battle-tested**: NGINX Ingress is extremely mature
8. **Perfect for testing**: Simple cert validation without mesh complexity

#### Cons

1. **Limited features**: No advanced traffic management (retries, circuit breakers)
2. **Basic observability**: Standard NGINX logs, no distributed tracing
3. **Single ingress point**: No mesh-wide mTLS between services
4. **Manual cert management**: No automatic cert rotation (fine for testing)

#### Performance Impact

- **TLS overhead**: ~0.5-1ms per request
- **CPU overhead**: ~5% at 2000 TPS
- **Memory overhead**: None (already running)
- **Throughput impact**: <2%

### 3.2 Linkerd Service Mesh

Lightweight alternative to Istio, focused on simplicity and performance.

#### Pros
- **Ultra-lightweight**: Rust-based proxies, minimal resource usage
- **Automatic mTLS**: Zero-config mTLS between all services
- **Simpler than Istio**: Easier to understand and operate
- **Great observability**: Built-in dashboards and metrics

#### Cons
- **Another mesh**: Still requires installing a service mesh
- **Less mature than Istio**: Smaller community, fewer features
- **Ingress still needed**: Linkerd doesn't provide ingress controller (need nginx + linkerd)
- **Overkill for testing**: More complex than needed for perf tests

#### Installation Snippet

```bash
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd viz install | kubectl apply -f -  # Dashboard

# Inject linkerd proxy into Mojaloop namespace
kubectl annotate namespace default linkerd.io/inject=enabled
```

### 3.3 Traefik with mTLS

Modern ingress controller with native mTLS support.

#### Pros
- **Modern**: Native Kubernetes integration, good API
- **Flexible routing**: Powerful routing rules
- **mTLS support**: Built-in client cert validation
- **Good documentation**: Well-documented mTLS setup

#### Cons
- **Replacement needed**: Would replace existing NGINX ingress
- **Learning curve**: New tool to learn
- **Not as battle-tested for mTLS** as NGINX in high-throughput scenarios

#### Configuration Example

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: mojaloop-mtls
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`ml-api-adapter.local`)
      kind: Rule
      services:
        - name: ml-api-adapter-service
          port: 80
  tls:
    secretName: mojaloop-server-tls
    options:
      name: mtls-options
---
apiVersion: traefik.io/v1alpha1
kind: TLSOption
metadata:
  name: mtls-options
spec:
  minVersion: VersionTLS12
  clientAuth:
    secretNames:
      - mojaloop-mtls-ca
    clientAuthType: RequireAndVerifyClientCert
```

### 3.4 Envoy Standalone (Without Cilium)

Deploy Envoy proxy as a standalone ingress.

#### Pros
- **Powerful**: Same proxy used by Istio, very capable
- **Flexible configuration**: Fine-grained control
- **Performance**: Excellent performance characteristics

#### Cons
- **Complex configuration**: Envoy config is notoriously complex
- **No controller**: Need to write raw Envoy YAML or use xDS server
- **Operational burden**: Managing Envoy lifecycle manually
- **Not recommended**: Use Istio if you want Envoy (provides management layer)

### 3.5 Ambassador/Emissary

Kubernetes-native API Gateway built on Envoy.

#### Pros
- **Developer-friendly**: Good DX with annotations
- **Envoy-powered**: Leverages Envoy's capabilities
- **mTLS support**: Native client cert validation

#### Cons
- **Commercial focus**: Open-source version has limitations
- **Another replacement**: Would replace NGINX
- **Less common**: Smaller community than NGINX/Traefik

### 3.6 Kong Gateway

Enterprise API Gateway with open-source version.

#### Pros
- **Feature-rich**: Rate limiting, auth, plugins
- **mTLS support**: Client cert validation available
- **Battle-tested**: Widely used in production

#### Cons
- **Heavy**: More resource-intensive than NGINX
- **Complexity**: Many features not needed for perf testing
- **Another replacement**: Would replace NGINX
- **Learning curve**: Kong-specific concepts

### 3.7 Native Kubernetes Ingress with cert verification

Use basic Kubernetes Ingress API with cert validation.

#### Pros
- **Standard API**: No vendor lock-in
- **Simple**: Minimal configuration

#### Cons
- **Limited functionality**: Basic features only
- **Implementation-dependent**: mTLS support varies by ingress controller
- **Not standalone**: Still need an ingress controller (NGINX, Traefik, etc.)

---

## 4. Comparison Matrix

| Solution | Setup Complexity | Performance Overhead | Resource Usage | Features | Best For |
|----------|-----------------|---------------------|----------------|----------|----------|
| **NGINX Ingress (existing)** | ⭐ Very Low | ⭐⭐⭐⭐⭐ Minimal | ⭐⭐⭐⭐⭐ None | Basic mTLS | **Performance testing** |
| **Istio** | ⭐⭐⭐⭐ High | ⭐⭐⭐ Moderate | ⭐⭐ High | Full mesh | Production, complex routing |
| **Linkerd** | ⭐⭐⭐ Moderate | ⭐⭐⭐⭐ Low | ⭐⭐⭐⭐ Low | Auto mTLS | Simplicity + observability |
| **Traefik** | ⭐⭐ Low-Moderate | ⭐⭐⭐⭐ Low | ⭐⭐⭐ Moderate | Modern routing | Greenfield projects |
| **Envoy Standalone** | ⭐⭐⭐⭐⭐ Very High | ⭐⭐⭐⭐ Low | ⭐⭐⭐ Moderate | Very flexible | Expert users only |
| **Ambassador** | ⭐⭐⭐ Moderate | ⭐⭐⭐ Moderate | ⭐⭐⭐ Moderate | API Gateway | API management focus |
| **Kong** | ⭐⭐⭐ Moderate | ⭐⭐ High | ⭐⭐ High | Enterprise features | API gateway + plugins |

**Legend**: ⭐⭐⭐⭐⭐ = Excellent, ⭐ = Poor

---

## 5. Recommendations

### For ml-perf-whitepaper-ws Testing Environment

**Primary Recommendation: NGINX Ingress Controller (already installed)**

**Rationale**:
1. **Zero new infrastructure**: Already running as MicroK8s addon
2. **Lowest complexity**: Simple annotations on existing Ingress resources
3. **Best performance**: Minimal overhead (~0.5-1ms, <2% throughput impact)
4. **Perfect for shared cert testing**: Simplified setup with single CA + shared client cert
5. **No learning curve**: Team familiar with NGINX
6. **Fast implementation**: Can be deployed in <1 hour

**Implementation Plan**:

```
Phase 1: Certificate Preparation (10 min)
  - Create K8s secrets from existing shared certs

Phase 2: Ingress Configuration (20 min)
  - Add mTLS annotations to Mojaloop Ingress
  - Apply configuration

Phase 3: DFSP Configuration (20 min)
  - Enable OUTBOUND_MUTUAL_TLS_ENABLED
  - Mount shared certificates
  - Redeploy DFSPs

Phase 4: Testing (10 min)
  - Verify mTLS handshake
  - Run smoke test transfers
  - Confirm cert validation working
```

### If You Need Advanced Features Later

**Secondary Recommendation: Istio (minimal profile)**

Use Istio only if you need:
- Advanced traffic management (retries, circuit breakers, canary deployments)
- Distributed tracing across all services
- Fine-grained authorization policies
- Observability dashboard for service mesh

**Not Recommended**: Linkerd, Traefik, Kong, Ambassador, Envoy standalone
- All introduce unnecessary complexity for a perf testing scenario
- Require replacing or augmenting existing infrastructure
- Higher learning curve with minimal benefit for this use case

---

## 6. Sample Configuration Files

### NGINX Ingress mTLS (Minimal Implementation)

File: `/infrastructure/mojaloop/nginx-ingress-mtls.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mojaloop-mtls-ca
  namespace: default
type: Opaque
data:
  ca.crt: <base64-encoded-ca-cert.pem>
---
apiVersion: v1
kind: Secret
metadata:
  name: mojaloop-server-tls
  namespace: default
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-shared-cert.pem>
  tls.key: <base64-encoded-shared-key.pem>
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mojaloop-fspiop-mtls
  namespace: default
  annotations:
    # mTLS configuration
    nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"
    nginx.ingress.kubernetes.io/auth-tls-secret: "default/mojaloop-mtls-ca"
    nginx.ingress.kubernetes.io/auth-tls-verify-depth: "1"
    
    # SSL configuration
    nginx.ingress.kubernetes.io/ssl-protocols: "TLSv1.2 TLSv1.3"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - ml-api-adapter.local
    - account-lookup-service.local
    - quoting-service.local
    secretName: mojaloop-server-tls
  rules:
  - host: ml-api-adapter.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ml-api-adapter-service
            port:
              number: 80
  - host: account-lookup-service.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: account-lookup-service
            port:
              number: 80
  - host: quoting-service.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: quoting-service
            port:
              number: 80
```

### DFSP Configuration Update

File: `/infrastructure/dfsp/values-fsp201.yaml` (apply to all fsp201-208)

```yaml
schemeAdapter:
  env:
    OUTBOUND_MUTUAL_TLS_ENABLED: true
  
  secrets:
    tls:
      outbound:
        cert: |
          -----BEGIN CERTIFICATE-----
          MIIFXzCCA0egAwIBAgIUXxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
          ... (content of shared-cert.pem)
          -----END CERTIFICATE-----
        key: |
          -----BEGIN PRIVATE KEY-----
          MIIJQgIBADANBgkqhkiG9w0BAQEFAASCCSwwggkoAgEAAoICAQC...
          ... (content of shared-key.pem)
          -----END PRIVATE KEY-----
        cacert: |
          -----BEGIN CERTIFICATE-----
          MIIFazCCA1OgAwIBAgIUXxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
          ... (content of ca-cert.pem)
          -----END CERTIFICATE-----
```

---

## 7. Testing and Validation

### Test mTLS is Working

```bash
# From a pod inside the cluster (e.g., curl pod in k6 namespace)

# Test 1: Request WITHOUT client cert should FAIL (403)
curl -k https://ml-api-adapter.local/health
# Expected: 403 Forbidden (No client certificate supplied)

# Test 2: Request WITH client cert should SUCCEED (200)
curl -k \
  --cert /path/to/shared-cert.pem \
  --key /path/to/shared-key.pem \
  --cacert /path/to/ca-cert.pem \
  https://ml-api-adapter.local/health
# Expected: 200 OK

# Test 3: Request with WRONG/INVALID cert should FAIL (400)
curl -k \
  --cert /path/to/wrong-cert.pem \
  --key /path/to/wrong-key.pem \
  --cacert /path/to/ca-cert.pem \
  https://ml-api-adapter.local/health
# Expected: 400 Bad Request (certificate verify failed)
```

### Verify NGINX Logs

```bash
kubectl logs -n ingress daemonset/nginx-ingress-microk8s-controller | grep "ssl"
# Look for TLS handshake logs and client cert validation
```

### Performance Baseline

```bash
# Before mTLS
k6 run --vus 100 --duration 60s performance-tests/src/mojaloop-k6-operator/scripts/tests.js

# After mTLS
k6 run --vus 100 --duration 60s performance-tests/src/mojaloop-k6-operator/scripts/tests.js

# Compare:
# - Average response time (should be <2ms increase)
# - Throughput (should be >98% of baseline)
# - Error rate (should be 0%)
```

---

## 8. Migration Path (If Needed)

If you later need to migrate from NGINX to Istio:

1. **Install Istio** (minimal profile, ingress only)
2. **Create parallel ingress** (Istio Gateway + VirtualServices)
3. **Test with subset of traffic** (route 10% to Istio, 90% to NGINX)
4. **Gradually shift traffic** (20%, 50%, 80%, 100%)
5. **Monitor performance** at each step
6. **Remove NGINX ingress** once validated

This blue/green approach ensures zero downtime and validates performance before full cutover.

---

## 9. Appendix: Certificate Management

### Current Certificate Setup

```
infrastructure/dfsp/generate-tls/
├── ca-cert.pem         # CA certificate (shared across all)
├── ca-key.pem          # CA private key (keep secure!)
├── shared-cert.pem     # Client/server cert (shared for testing)
├── shared-key.pem      # Private key (shared for testing)
└── generate.sh         # Script to regenerate
```

### Regenerating Certificates (if needed)

```bash
cd infrastructure/dfsp/generate-tls/
./generate.sh

# Then re-create Kubernetes secrets and restart pods
```

### Certificate Validity

```bash
# Check expiration
openssl x509 -in infrastructure/dfsp/generate-tls/shared-cert.pem -noout -enddate

# If expired, regenerate using generate.sh
```

---

## 10. Summary

**For ml-perf-whitepaper-ws**: Use **NGINX Ingress Controller mTLS annotations**

- Simplest solution
- Already installed
- Best performance
- Perfect for shared certificate testing scenario
- Implementation time: <1 hour

**Alternative (if advanced features needed)**: Istio minimal profile

**Not recommended**: Any other solution (unnecessary complexity for perf testing)

---

**Document Version**: 1.0
**Last Updated**: 2026-03-05
**Environment**: ml-perf-whitepaper-ws (MicroK8s 1.32, Calico CNI, NGINX Ingress)
