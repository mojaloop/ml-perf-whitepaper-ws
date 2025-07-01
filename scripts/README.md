# Automation Scripts

Utility scripts for validation, automation, and analysis.

## Directory Structure

- **validation/**: Pre-flight and validation checks
- **automation/**: Deployment and test automation
- **analysis/**: Result analysis and reporting

## Key Scripts

### Validation Scripts

1. **validate-infrastructure.sh**: Verify AWS resources
2. **validate-kubernetes.sh**: Check K8s cluster health
3. **validate-mojaloop.sh**: Verify Mojaloop deployment
4. **validate-connectivity.sh**: Test network connectivity

### Automation Scripts

1. **deploy-all.sh**: Complete deployment automation
2. **run-test-suite.sh**: Execute full test battery
3. **collect-metrics.sh**: Gather all metrics
4. **cleanup-resources.sh**: Resource cleanup

### Analysis Scripts

1. **analyze-results.py**: Python analysis tool
2. **generate-reports.sh**: Create PDF reports
3. **compare-runs.py**: Compare test runs
4. **extract-metrics.sh**: Extract key metrics

## Usage Examples

### Full Deployment
```bash
./automation/deploy-all.sh --config production
```

### Run Complete Test Suite
```bash
./automation/run-test-suite.sh --tps 1000 --duration 1h
```

### Analyze Results
```bash
./analysis/analyze-results.py --input results/latest --output report.pdf
```

## Script Requirements

- Bash 4.0+
- Python 3.8+ with pandas, matplotlib
- kubectl, terraform, aws-cli
- jq for JSON processing

## Environment Variables

Required environment variables:
```bash
export AWS_REGION=us-west-2
export CLUSTER_NAME=mojaloop-perf
export K6_CLUSTER_NAME=k6-perf
export RESULTS_BUCKET=mojaloop-perf-results
```
