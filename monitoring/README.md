# Monitoring Stack

Comprehensive monitoring for Mojaloop performance testing with Prometheus, Grafana, and custom dashboards.

## Directory Structure

- **prometheus/**: Prometheus configuration and rules
- **grafana/**: Dashboard definitions and datasources
- **alerts/**: Alert rules and notification channels
- **dashboards/**: Custom performance dashboards

## Components

### Prometheus

1. **Metrics Collection**
   - Mojaloop service metrics
   - K6 test metrics
   - Infrastructure metrics
   - Custom application metrics

2. **Recording Rules**
   - Pre-aggregated metrics for performance
   - TPS calculations
   - Success rate computations

3. **Retention**
   - 30 days for detailed metrics
   - 1 year for aggregated metrics

### Grafana Dashboards

1. **Mojaloop Performance Overview**
   - Real-time TPS
   - Success rates
   - Latency percentiles
   - Error rates

2. **Service-Level Dashboards**
   - ALS performance
   - Quoting service metrics
   - Transfer processing
   - Central ledger status

3. **Infrastructure Dashboards**
   - CPU/Memory utilization
   - Network throughput
   - Disk I/O
   - Kubernetes metrics

4. **K6 Test Progress**
   - Active VUs
   - Request rates
   - Response times
   - Test completion status

### Alerts

Critical alerts for performance testing:

1. **Performance Degradation**
   - TPS below target
   - Latency spike detection
   - Error rate thresholds

2. **Infrastructure Issues**
   - Node pressure
   - Pod evictions
   - Resource exhaustion

3. **Service Health**
   - Service unavailable
   - Database connection issues
   - Kafka lag

## Setup

1. **Deploy Prometheus**:
   ```bash
   kubectl apply -f prometheus/
   ```

2. **Deploy Grafana**:
   ```bash
   kubectl apply -f grafana/
   ```

3. **Import Dashboards**:
   ```bash
   ./scripts/import-dashboards.sh
   ```

## Key Metrics

Document the most important metrics to track:

- **mojaloop_transfer_success_rate**
- **mojaloop_transfer_processing_time**
- **k6_http_req_duration**
- **k6_iterations_per_second**
