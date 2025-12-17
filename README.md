# Mojaloop Performance Testing Workspace

This repository contains the complete infrastructure, tooling, and test definitions used to perform **end-to-end performance testing of Mojaloop** at scale (hundreds to thousands of TPS).

The workspace is structured to clearly separate **infrastructure provisioning**, **test execution**, and **test results**, making it easy to reproduce, tune, and analyze performance runs.

---

## Repository Structure

```text
ML-PERF-WHITEPAPER-WS
├── infrastructure/
│   └── README.md
│       - Provisioning of cloud infrastructure
│       - Kubernetes clusters (MicroK8s)
│       - Mojaloop backend, switch, DFSPs
│       - k6 operator setup
│
├── performance-tests/
│   ├── src/
│   │   └── README.md
│   │       - k6 test implementation
│   │       - Helm chart for k6 Operator
│   │       - Test configuration and execution scripts
│   │
│   └── results/
│       - Test results (summaries, metrics, logs)
│       - Scenario-specific configuration overrides
│       - TPS-specific tuning references (e.g. 500 / 1000 / 2000 TPS)
│
├── docs/
│   - Supporting documentation and notes
│
├── README.md
└── LICENSE.md
```

---

## High-level Workflow

1. **Provision Infrastructure**  
   Use Terraform and Ansible to provision compute, networking, and Kubernetes clusters.  
   See: [`infrastructure/README.md`](infrastructure/README.md)

2. **Deploy Mojaloop Stack**  
   Deploy Mojaloop backend services, switch, DFSP simulators, monitoring, and security components.

3. **Prepare Test Data**  
   Pre-register MSISDNs and verify Kafka, MySQL, and DFSP readiness.

4. **Run Performance Tests**  
   Execute k6 tests via the k6 Operator from a dedicated k6 cluster.  
   See: [`performance-tests/src/README.md`](performance-tests/src/README.md)

5. **Analyze Results**  
   Review metrics, summaries, and scenario configurations under `performance-tests/results`.

---

## Design Principles

- **Reproducibility** – Fully declarative infra and test configuration  
- **Scalability** – Tested with multiple DFSPs and high TPS targets  
- **Isolation** – Dedicated clusters for switch, DFSPs, and load generation  
- **Observability** – Prometheus, Grafana, and Kafka UI support

---

## License

This project is licensed under the terms of the [`LICENSE.md`](LICENSE.md).
