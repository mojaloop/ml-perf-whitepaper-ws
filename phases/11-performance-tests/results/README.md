# Performance Test Results

This directory contains all performance test results organized by test type and timestamp.

## Directory Structure

```
results/
├── 01-baseline-100tps/
│   └── YYYY-MM-DD-HH-MM-SS/    # Timestamped runs
├── 02-scale-500tps/
│   └── YYYY-MM-DD-HH-MM-SS/
├── 03-target-1000tps/
│   ├── 2024-01-15-14-30-22/    # Example: First attempt
│   ├── 2024-01-16-10-15-45/    # Example: After tuning
│   └── YYYY-MM-DD-HH-MM-SS/    # Multiple runs supported
├── 04-endurance-1000tps/
│   └── YYYY-MM-DD-HH-MM-SS/
├── 05-stress-to-failure/
│   └── YYYY-MM-DD-HH-MM-SS/
└── aggregated/                   # Cross-test analysis
```

## Run Directory Contents

Each timestamped run directory contains:
- **k6-raw-data/**: Complete test output and metrics
- **k6-summaries/**: Processed summaries for quick review
- **metrics/**: Time-series data from Prometheus
- **resource-utilization/**: CPU, memory, network, disk metrics
- **grafana-dashboards/**: Screenshots organized by dashboard type
- **logs/**: Service and infrastructure logs
- **analysis/**: Post-test analysis outputs
- **config-snapshots/**: Test-time configurations

## Why This Structure?

- **Multiple Runs**: Each test type can have multiple timestamped runs
- **Easy Comparison**: Compare different runs of the same test
- **Iterative Tuning**: Track progress across tuning iterations
- **Clear History**: See exactly when each test was performed
- **No Overwrites**: Each run is preserved with its unique timestamp