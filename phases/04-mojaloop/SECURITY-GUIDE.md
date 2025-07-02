# Mojaloop Security Stack Configuration

> **Goal**: Enable full production security (mTLS, JWS, ILP) while maintaining 1000 TPS performance.

## 🔐 Security Components Overview

```
┌─────────────────────────────────────────────────────────────┐
│                   Security Stack                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. mTLS (Mutual TLS)                                       │
│     └─> Service-to-service authentication                   │
│     └─> Encrypted communication                             │
│     └─> Managed by Istio service mesh                       │
│                                                              │
│  2. JWS (JSON Web Signatures)                               │
│     └─> Message integrity                                   │
│     └─> Non-repudiation                                     │
│     └─> Implemented in SDK-Scheme-Adapter                   │
│                                                              │
│  3. ILP (Interledger Protocol)                              │
│     └─> Cryptographic proof of payment                      │
│     └─> Condition/fulfillment validation                    │
│     └─> End-to-end transaction security                     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## 🔒 mTLS Configuration

### How It Works
```
Service A → [Client Cert] → mTLS → [Server Cert] → Service B
    ↓                                                    ↓
Validates B's cert                            Validates A's cert
```

### Enable Strict mTLS

```bash
# Apply strict mTLS policy
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: mojaloop
spec:
  mtls:
    mode: STRICT
EOF

# Verify mTLS is active
istioctl authn tls-check account-lookup-service.mojaloop.svc.cluster.local
```

### Certificate Management

```bash
# Check certificate expiry
kubectl get secret -n istio-system istio-ca-secret -o json | \
  jq -r '.data["ca-cert.pem"]' | base64 -d | \
  openssl x509 -text -noout | grep -A2 Validity

# Rotate certificates (if needed)
./scripts/rotate-istio-certs.sh
```

### Performance Impact
- **Latency**: +5-7ms per request
- **CPU**: +10-15% overhead
- **Throughput**: Negligible impact with modern CPUs

### Troubleshooting mTLS

```bash
# Check for TLS errors
kubectl logs -n istio-system deployment/istiod | grep -i tls

# Test service connectivity
kubectl exec -n mojaloop deployment/ml-api-adapter -c ml-api-adapter -- \
  curl -v https://account-lookup-service:443/health

# Temporarily disable for debugging
kubectl apply -f debug/mtls-permissive.yaml
```

---

## ✍️ JWS (JSON Web Signatures)

### How It Works
```
SDK-Scheme-Adapter → Sign(message, private_key) → Mojaloop
                                                      ↓
                                            Verify(signature, public_key)
```

### Generate JWS Keys

```bash
# Generate keys for all DFSPs
for i in {1..8}; do
  ./scripts/generate-jws-keys.sh --dfsp perffsp-$i
done

# Verify keys created
kubectl get secrets -n mojaloop | grep jws-keys
```

### Configure SDK-Scheme-Adapter

```yaml
# helm-values/mojaloop-values.yaml
mojaloop-simulator:
  sdk-scheme-adapter:
    config:
      JWS_SIGN: true
      JWS_VERIFICATION_KEYS_DIRECTORY: /opt/app/secrets/jwsVerificationKeys
      JWS_SIGNING_KEY: /opt/app/secrets/jwsSigningKey.pem
```

### Deploy JWS Configuration

```bash
# Update ConfigMaps
./scripts/update-jws-config.sh

# Mount keys in pods
kubectl patch deployment perffsp-1-sdk -n mojaloop --patch '
spec:
  template:
    spec:
      volumes:
      - name: jws-keys
        secret:
          secretName: perffsp-1-jws-keys
      containers:
      - name: sdk-scheme-adapter
        volumeMounts:
        - name: jws-keys
          mountPath: /opt/app/secrets'

# Restart to apply
kubectl rollout restart deployment -n mojaloop -l component=sdk-scheme-adapter
```

### Verify JWS Working

```bash
# Check logs for signature validation
kubectl logs -n mojaloop deployment/perffsp-1-sdk | grep -i jws

# Test transaction with JWS
./scripts/test-jws-transaction.sh

# Monitor signature failures
kubectl logs -n mojaloop -l app=ml-api-adapter | grep "signature.*fail"
```

### Performance Impact
- **Latency**: +3-5ms for signing/verification
- **CPU**: +5% per SDK adapter
- **Memory**: Minimal (keys cached)

---

## 🔗 ILP (Interledger Protocol)

### How It Works
```
Quote Phase:
  Generate condition = hash(fulfillment + secret)
  
Transfer Phase:
  Validate: hash(received_fulfillment) == original_condition
```

### ILP Configuration

```yaml
# In quoting-service config
ILP_SECRET: "RycKYRgLTBn4g1zx6WkXmJ4sZvqz8PQs" # Change in production!
ILP_EXPIRY_DURATION: 3600 # 1 hour
```

### Generate Test ILP Packet

```bash
# Generate condition/fulfillment pair
./scripts/generate-ilp-test.sh

# Example output:
# Condition: GRzLaTP7DJ9t...
# Fulfillment: GyPjLv5ehFN...
# ILP Packet: AQAAAAAAAADIEHByaXZhdGUucGF5ZWVmc3A...
```

### Verify ILP in Transactions

```bash
# Enable ILP debug logging
kubectl set env deployment/central-ledger -n mojaloop \
  LOG_LEVEL=debug \
  LOG_FILTER="ilp.*"

# Monitor ILP validation
kubectl logs -n mojaloop deployment/central-ledger -f | grep -i ilp

# Check for ILP failures
./scripts/check-ilp-failures.sh --last-hour
```

### Performance Impact
- **Latency**: +2-3ms for crypto operations
- **CPU**: Minimal (SHA-256 is hardware accelerated)
- **Memory**: Negligible

---

## 🎯 Security Best Practices

### 1. Key Management

```bash
# Store keys in Kubernetes secrets
kubectl create secret generic dfsp-keys \
  --from-file=private.pem \
  --from-file=public.pem \
  -n mojaloop

# Use Sealed Secrets for GitOps
kubeseal --format=yaml < secret.yaml > sealed-secret.yaml

# Rotate keys periodically
./scripts/rotate-all-keys.sh --schedule monthly
```

### 2. Network Policies

```yaml
# Restrict DFSP communication
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: dfsp-isolation
  namespace: mojaloop
spec:
  podSelector:
    matchLabels:
      component: sdk-scheme-adapter
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: ml-api-adapter
```

### 3. Audit Logging

```bash
# Enable audit logging
kubectl set env deployment/central-ledger -n mojaloop \
  AUDIT_LOG_ENABLED=true \
  AUDIT_LOG_LEVEL=info

# View security events
kubectl logs -n mojaloop -l app=central-audit | jq '.event_type == "security"'
```

---

## 📊 Security Performance Tuning

### Optimize TLS

```bash
# Use TLS 1.3 for better performance
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: tls-optimization
  namespace: mojaloop
spec:
  host: "*.mojaloop.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
      minProtocolVersion: TLSV1_3
EOF
```

### JWS Caching

```javascript
// In SDK adapter config
JWS_VERIFICATION_CACHE_SIZE: 1000
JWS_VERIFICATION_CACHE_TTL: 3600 // 1 hour
```

### Connection Pooling

```bash
# Reuse TLS connections
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: connection-pool
  namespace: mojaloop
spec:
  host: account-lookup-service
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http2MaxRequests: 100
        maxRequestsPerConnection: 2
EOF
```

---

## 🔍 Security Monitoring

### Dashboard Queries

```promql
# mTLS handshake failures
rate(istio_tcp_connection_errors_total{security_policy="mutual_tls"}[5m])

# JWS signature failures  
sum(rate(mojaloop_jws_verification_failed_total[5m])) by (dfsp)

# ILP validation errors
sum(rate(mojaloop_ilp_validation_failed_total[5m])) by (error_type)
```

### Security Alerts

```yaml
# AlertManager configuration
- name: security_alerts
  rules:
  - alert: HighJWSFailureRate
    expr: rate(mojaloop_jws_verification_failed_total[5m]) > 0.01
    annotations:
      summary: "JWS verification failures exceeding 1%"
```

---

## 🚨 Security Incident Response

### If Security Validation Fails

1. **Isolate affected DFSP**:
   ```bash
   kubectl label pod -n mojaloop -l dfsp=perffsp-1 quarantine=true
   ```

2. **Check for compromise**:
   ```bash
   ./scripts/security-audit.sh --dfsp perffsp-1
   ```

3. **Rotate credentials**:
   ```bash
   ./scripts/emergency-key-rotation.sh --dfsp perffsp-1
   ```

4. **Resume after fix**:
   ```bash
   kubectl label pod -n mojaloop -l dfsp=perffsp-1 quarantine-
   ```

---

## 📚 Additional Resources

- [Mojaloop Security Guide](https://docs.mojaloop.io/documentation/mojaloop-technical-overview/security/)
- [Istio Security Best Practices](https://istio.io/latest/docs/ops/best-practices/security/)
- [JWS RFC 7515](https://tools.ietf.org/html/rfc7515)
- [Interledger Protocol Spec](https://interledger.org/developers/rfcs/)