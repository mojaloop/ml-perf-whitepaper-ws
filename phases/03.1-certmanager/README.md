# Cert-Manager + Let's Encrypt Setup

## Installation Steps

### 1. Add cert-manager Helm repository
```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

### 2. Install cert-manager
```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --values ml-perf-whitepaper-ws/phases/03.1-certmanager/cert-manager-values.yaml
```

### 3. Verify cert-manager is running
```bash
kubectl get pods -n cert-manager
```

### 4. Configure Let's Encrypt issuers

**Important:** Before applying, update `letsencrypt-issuers.yaml`:
- Change `admin@example.com` to your actual email address
- Change `.local` domains to your actual public domains (Let's Encrypt requires publicly accessible domains)

```bash
kubectl apply -f ml-perf-whitepaper-ws/phases/03.1-certmanager/letsencrypt-issuers.yaml
```

### 5. Verify issuers are ready
```bash
kubectl get clusterissuer
```

## Important Notes for mTLS

1. **Let's Encrypt requires public domains**: The `.local` domains won't work with Let's Encrypt. You need:
   - Actual public domain names
   - DNS records pointing to your ingress controller's public IP

2. **For mTLS, you need both server and client certificates**:
   - Let's Encrypt provides server certificates
   - For client certificates, you may need a separate internal CA

3. **Testing first**: Always test with `letsencrypt-staging` first to avoid hitting rate limits

4. **Switch to production**: Once tested, change issuerRef to `letsencrypt-prod` in the Certificate resource

## Alternative for .local domains

If you're using `.local` domains (not publicly accessible), consider:
- Using a self-signed CA with cert-manager's CA issuer
- Using DNS-01 challenge instead of HTTP-01 (requires DNS provider integration)
