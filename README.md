# Mojaloop Performance Testing Whitepaper

This repository contains a comprehensive, reproducible methodology for performance testing Mojaloop implementations. It provides all necessary components for third parties to validate and replicate our performance testing results.

## Overview

This project demonstrates how to achieve 1000+ TPS on Mojaloop with:
- Full production security stack (mTLS, JWS, ILP)
- 8 DFSP test scenario with realistic transaction distribution
- Isolated K6 load generation infrastructure
- Comprehensive monitoring and analysis tools

## Repository Structure

```
ml-perf-whitepaper-ws/
├── infrastructure/          # AWS infrastructure provisioning
├── kubernetes/             # K8s cluster and platform services
├── mojaloop/              # Mojaloop deployment and configuration
├── k6-infrastructure/     # Isolated K6 testing infrastructure
├── k6-tests/              # Test scenarios and configurations
├── monitoring/            # Prometheus, Grafana, dashboards
├── results/               # Test results and analysis
├── docs/                  # Documentation and guides
└── scripts/               # Automation and utilities
```

## Quick Start

1. **Infrastructure Setup**: See [infrastructure/README.md](infrastructure/README.md)
2. **Kubernetes Deployment**: See [kubernetes/README.md](kubernetes/README.md)
3. **Mojaloop Installation**: See [mojaloop/README.md](mojaloop/README.md)
4. **K6 Test Infrastructure**: See [k6-infrastructure/README.md](k6-infrastructure/README.md)
5. **Running Tests**: See [k6-tests/README.md](k6-tests/README.md)
6. **Analyzing Results**: See [results/README.md](results/README.md)

## Key Features

- **Reproducibility**: Complete infrastructure as code
- **Isolation**: Separate K6 infrastructure to avoid impacting switch performance
- **Security**: Full production security stack enabled
- **Scalability**: Tested up to 1000 TPS with 8 DFSPs
- **Monitoring**: Comprehensive metrics and dashboards
- **Documentation**: Step-by-step guides for every component

## Performance Targets

- **Target TPS**: 1000 transactions per second
- **DFSPs**: 8 (4 payers, 4 payees)
- **Transaction Mix**: Asymmetric distribution mimicking real-world patterns
- **Security**: mTLS, JWS signatures, ILP validation enabled
- **Success Rate**: >99.5%
- **P95 Latency**: <500ms end-to-end

## Contributing

This project is designed to be forked and adapted for specific Mojaloop deployments. See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

## License

[Apache 2.0](LICENSE)
