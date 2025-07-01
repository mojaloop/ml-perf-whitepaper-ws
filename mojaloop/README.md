# Mojaloop Configuration

Production-grade Mojaloop deployment with full security stack and 8 DFSP configuration.

## Directory Structure

- **releases/**: Mojaloop helm chart versions and customizations
- **configurations/**: Environment-specific values files
- **dfsp-setup/**: DFSP provisioning and configuration
- **security-stack/**: mTLS, JWS, and security configurations

## Deployment Configuration

### Core Services

Document the Mojaloop services configuration optimized for 1000 TPS:

1. **Account Lookup Service (ALS)**
   - Replicas: 10
   - Resources: 4 CPU, 8Gi memory
   - Cache: Redis with 10GB allocation

2. **Quoting Service**
   - Replicas: 8
   - Resources: 4 CPU, 8Gi memory
   - Database: PostgreSQL with connection pooling

3. **ML API Adapter**
   - Replicas: 12
   - Resources: 4 CPU, 8Gi memory
   - Kafka: 5 brokers, 3 replicas

4. **Central Ledger**
   - Replicas: 6
   - Resources: 8 CPU, 16Gi memory
   - Database: MySQL with ProxySQL

### Security Stack

1. **mTLS Configuration**
   - Certificate generation and distribution
   - Istio service mesh configuration
   - Mutual authentication between services

2. **JWS Signatures**
   - SDK-scheme-adapter configuration
   - Key management and rotation
   - Signature validation settings

3. **ILP (Interledger Protocol)**
   - Condition/fulfillment validation
   - Cryptographic proof configuration

### DFSP Configuration

Document the setup for 8 performance testing DFSPs:

```yaml
# Example DFSP configuration
perffsp-1:
  participantId: perffsp1
  currency: USD
  position: 1000000
  netDebitCap: 500000
  endpoints:
    - type: FSPIOP_CALLBACK_URL_PARTIES_PUT
      value: http://perffsp-1:3002
```

## Deployment Steps

1. **Install Mojaloop**:
   ```bash
   helm install mojaloop mojaloop/mojaloop -f configurations/values-performance.yaml
   ```

2. **Configure DFSPs**:
   ```bash
   kubectl apply -f dfsp-setup/
   ```

3. **Enable Security Stack**:
   ```bash
   ./security-stack/enable-security.sh
   ```

## Performance Optimizations

Document all performance tuning applied:
- Connection pool settings
- Kafka configurations
- Database optimizations
- Resource allocations
