# K6 Test Scenarios

Performance test scenarios for Mojaloop with various load patterns and DFSP configurations.

## Directory Structure

- **scenarios/**: Test scenario definitions
- **configs/**: Environment-specific configurations
- **scripts/**: Test execution and utility scripts
- **data-generation/**: Tools for generating test data

## Test Scenarios

### 1. Baseline Tests
- Single DFSP pair (payer → payee)
- 100 TPS steady state
- 5-minute duration

### 2. Multi-DFSP Tests
- 8 DFSPs (4 payers, 4 payees)
- Asymmetric load distribution
- 1000 TPS target

### 3. Stress Tests
- Ramp to failure
- Identify breaking points
- Recovery behavior

### 4. Endurance Tests
- 24-hour sustained load
- Memory leak detection
- Performance degradation analysis

## Configuration

### Environment Variables
```bash
# Mojaloop endpoints
export ALS_ENDPOINT=http://account-lookup-service.mojaloop
export QUOTES_ENDPOINT=http://quoting-service.mojaloop
export TRANSFERS_ENDPOINT=http://ml-api-adapter.mojaloop

# Test parameters
export TARGET_TPS=1000
export TRANSACTION_COUNT=1000000
export TEST_DURATION=1h
```

### DFSP Configuration

Document the 8 DFSP setup:
- **Payers**: perffsp-1, perffsp-2, perffsp-3, perffsp-4
- **Payees**: perffsp-5, perffsp-6, perffsp-7, perffsp-8

### Load Distribution

Asymmetric pattern mimicking real-world usage:
- 40% traffic: perffsp-1 → perffsp-5
- 25% traffic: perffsp-2 → perffsp-6
- 20% traffic: perffsp-3 → perffsp-7
- 15% traffic: perffsp-4 → perffsp-8

## Running Tests

1. **Quick validation**:
   ```bash
   ./scripts/run-validation.sh
   ```

2. **Full performance test**:
   ```bash
   ./scripts/run-performance-test.sh 1000 1h
   ```

3. **Stress test**:
   ```bash
   ./scripts/run-stress-test.sh
   ```

## Test Data

Document test data generation including:
- MSISDN ranges per DFSP
- Account provisioning
- Initial position setup
