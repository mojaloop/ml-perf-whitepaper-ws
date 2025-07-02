# Mojaloop Troubleshooting

> **Quick Fix**: 80% of Mojaloop issues are pods not starting. Run `kubectl get pods -n mojaloop | grep -v Running` first!

## 🔴 Common Deployment Issues

### Pods Stuck in Init/Pending State

**Symptoms:**
```bash
NAME                                    READY   STATUS     RESTARTS   AGE
central-ledger-service-7b9c5d4-x9k2l   0/1     Init:0/3   0          15m
ml-api-adapter-service-5f7d8c9-m3n4p   0/1     Pending    0          15m
```

**Quick Diagnosis:**
```bash
# Check init container logs
kubectl logs -n mojaloop <pod-name> -c wait-for-mysql

# Check events
kubectl describe pod -n mojaloop <pod-name> | tail -20
```

**Common Fixes:**

1. **Database not ready**:
   ```bash
   # Check MySQL pod
   kubectl get pod -n mojaloop -l app=mysql
   
   # If not running, check PVC
   kubectl get pvc -n mojaloop
   
   # Force restart MySQL
   kubectl delete pod -n mojaloop -l app=mysql
   ```

2. **Insufficient resources**:
   ```bash
   # Check node capacity
   kubectl top nodes
   
   # Check resource requests
   kubectl describe pod -n mojaloop <pod-name> | grep -A5 Requests
   
   # Scale down replicas temporarily
   kubectl scale deployment -n mojaloop central-ledger --replicas=1
   ```

3. **Image pull errors**:
   ```bash
   # Check for rate limits
   kubectl describe pod -n mojaloop <pod-name> | grep -i pull
   
   # Use local registry mirror
   ./scripts/setup-registry-mirror.sh
   ```

---

### Service Communication Failures

**Symptoms:**
- Transfers fail with 404/503 errors
- "No participant found" errors
- Timeouts between services

**Service Mesh Check:**
```bash
# Verify Istio injection
kubectl get pods -n mojaloop -o json | jq '.items[].spec.containers[].name' | grep istio-proxy

# Check Istio configuration
istioctl analyze -n mojaloop

# Test service connectivity
kubectl exec -n mojaloop deployment/ml-api-adapter -- curl -s account-lookup-service:80/health
```

**Fix mTLS Issues:**
```bash
# Disable mTLS temporarily for debugging
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: mojaloop
spec:
  mtls:
    mode: PERMISSIVE
EOF

# Re-enable after fixing
./scripts/enable-strict-mtls.sh
```

---

### DFSP Registration Failures

**Symptoms:**
- Participants not found
- "FSP not found" errors
- Test accounts missing

**Check Registration:**
```bash
# List all participants
kubectl exec -n mojaloop deployment/central-ledger -- \
  mysql -h mysql -u central_ledger -p$MYSQL_PASSWORD \
  -e "SELECT name, isActive FROM central_ledger.participant;"

# Check specific DFSP
./scripts/check-dfsp.sh --fsp perffsp-1
```

**Re-run Provisioning:**
```bash
# Single DFSP
./scripts/provision-dfsp.sh --fsp perffsp-1 --reset

# All DFSPs
./scripts/provision-all-dfsps.sh --force

# Verify provisioning
./scripts/verify-participants.sh
```

---

### Security Stack Issues

#### JWS Signature Failures

**Symptoms:**
- "Invalid signature" errors
- 401 Unauthorized responses

**Debug:**
```bash
# Check JWS configuration
kubectl get configmap -n mojaloop sdk-scheme-adapter-config -o yaml | grep JWS

# Verify keys are loaded
kubectl exec -n mojaloop deployment/perffsp-1-sdk -- ls -la /opt/app/secrets/

# Test signature validation
./scripts/test-jws-signature.sh --from perffsp-1 --to perffsp-5
```

**Fix:**
```bash
# Regenerate keys
./scripts/regenerate-jws-keys.sh

# Restart SDK adapters
kubectl rollout restart deployment -n mojaloop -l component=sdk-scheme-adapter
```

#### ILP Packet Failures

**Symptoms:**
- "Invalid fulfillment" errors
- Transfer timeout after quote

**Debug:**
```bash
# Check ILP configuration
kubectl logs -n mojaloop deployment/central-ledger | grep -i ilp

# Verify condition/fulfillment generation
./scripts/test-ilp-packet.sh
```

---

## 🔧 Performance Issues

### High Latency (>200ms)

**Quick Checks:**
```bash
# Service response times
./scripts/check-service-latency.sh

# Database query performance
kubectl exec -n mojaloop deployment/central-ledger -- \
  mysql -h mysql -u central_ledger -p$MYSQL_PASSWORD \
  -e "SHOW PROCESSLIST;"

# Kafka lag
kubectl exec -n mojaloop kafka-0 -- \
  kafka-consumer-groups --bootstrap-server localhost:9092 --list
```

**Common Fixes:**

1. **Database connection pool exhausted**:
   ```bash
   # Increase connections
   kubectl set env deployment/central-ledger -n mojaloop \
     DATABASE_POOL_MIN=50 \
     DATABASE_POOL_MAX=200
   ```

2. **Kafka consumer lag**:
   ```bash
   # Add more partitions
   ./scripts/scale-kafka-topics.sh --partitions 10
   
   # Increase consumers
   kubectl scale deployment -n mojaloop ml-handler-notification --replicas=5
   ```

### Memory Leaks / OOM Kills

**Identify:**
```bash
# Check for OOM kills
kubectl get events -n mojaloop | grep OOM

# Monitor memory usage
watch kubectl top pods -n mojaloop
```

**Fix:**
```bash
# Increase memory limits
kubectl patch deployment central-ledger -n mojaloop --patch '
spec:
  template:
    spec:
      containers:
      - name: central-ledger
        resources:
          limits:
            memory: "16Gi"'

# Enable heap dumps
kubectl set env deployment/central-ledger -n mojaloop \
  NODE_OPTIONS="--max-old-space-size=8192 --heapdump-on-oom"
```

---

## 📊 Monitoring & Debugging

### Essential Debug Commands

```bash
# Full health check
./scripts/mojaloop-health-check.sh

# Service dependency map
./scripts/show-service-dependencies.sh

# Transaction flow trace
./scripts/trace-transaction.sh --id <transaction-id>

# Generate debug bundle
./scripts/create-mojaloop-debug-bundle.sh
```

### Useful Log Queries

```bash
# All errors in last hour
kubectl logs -n mojaloop -l app=central-ledger --since=1h | grep ERROR

# Transaction flow for specific ID
kubectl logs -n mojaloop --all-containers=true --since=1h | grep <transaction-id>

# Performance warnings
kubectl logs -n mojaloop --all-containers=true | grep -E "slow|timeout|latency"
```

---

## 🚨 Emergency Procedures

### Service Cascade Failure

```bash
# 1. Stop incoming traffic
kubectl scale deployment -n mojaloop ml-api-adapter --replicas=0

# 2. Clear queues
./scripts/clear-kafka-queues.sh

# 3. Reset database connections
./scripts/reset-db-connections.sh

# 4. Restart in order
./scripts/restart-mojaloop-ordered.sh
```

### Complete Reset

```bash
# Backup current state
./scripts/backup-mojaloop-state.sh

# Reset to clean state
helm uninstall mojaloop -n mojaloop
kubectl delete pvc --all -n mojaloop
./deploy.sh --clean
```

---

## 💡 Prevention Tips

1. **Monitor during deployment**:
   ```bash
   watch -n 2 'kubectl get pods -n mojaloop | grep -v Running'
   ```

2. **Verify each component**:
   ```bash
   ./scripts/verify-component.sh --component central-ledger
   ./scripts/verify-component.sh --component account-lookup
   ```

3. **Test incrementally**:
   ```bash
   # Test with 2 DFSPs first
   ./deploy.sh --dfsps 2 --test
   ```

## 🆘 Still Stuck?

1. **Enable debug logging**:
   ```bash
   ./scripts/enable-debug-logs.sh
   ```

2. **Check Mojaloop Slack**:
   - [#performance](https://mojaloop.slack.com/channels/performance)
   - [#troubleshooting](https://mojaloop.slack.com/channels/troubleshooting)

3. **Common fixes collection**:
   ```bash
   curl -sL https://mojaloop.io/perf-fixes | bash -s -- --mojaloop
   ```