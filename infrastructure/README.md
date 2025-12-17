# Infrastructure and Deployment of Mojaloop for Performance Testing

This document describes the end-to-end infrastructure and deployment process for running high-volume performance tests on a Mojaloop switch. It focuses on building a reproducible Kubernetes-based environment using MicroK8s, provisioning observability and TLS, and deploying all core Mojaloop components required for realistic transaction flows.

Performance tests are executed using a dedicated k6 Operator cluster, which generates all load centrally and sends traffic to eight DFSP simulators. In this setup, four DFSPs act as **payers** and the other four act as **payees**, producing realistic end-to-end Discovery → Quotes → Transfers flows across the Mojaloop switch.

The guide walks through installing the Kubernetes cluster, configuring cert-manager, setting up monitoring, deploying shared backend services, rolling out Mojaloop components, onboarding DFSP simulators, and finally installing and configuring the k6 Operator–based load testing infrastructure.

## Prerequisites

- `kubectl`, `ansible`, `terraform` and `helm` installed locally
- Docker Hub credentials exported:

```bash
export DOCKERHUB_USERNAME=...
export DOCKERHUB_TOKEN=...
export DOCKERHUB_EMAIL=...
```

## Provision AWS Infrastructure
All virtual machines required for the Mojaloop performance-testing environment are provisioned using Terraform.  
The Terraform configuration for this project is located in: `provisioning/terraform`

### Infrastructure Configuration (config.yaml)

All infrastructure provisioning is driven by a single declarative configuration file: `provisioning/config.yaml`.

For different performance test scenarios—such as **1000 TPS**, **2000 TPS**, **5000 TPS**, and others—this repository includes scenario-specific configuration files under the `results/` directory.  
Each scenario directory contains its own tuned version of `config.yaml`, optimized for the expected workload and node sizing required for that TPS target.

When running a specific performance scenario, use the **config.yaml inside that scenario’s directory**, not the default one in `provisioning/`. This ensures the Terraform-provisioned infrastructure matches the resource profile needed for that particular test run.

For full details on how the Terraform provisioning works, see the [`provisioning/terraform/README.md`](provisioning/terraform/README.md).


## Install MicroK8s and create Kubernetes clusters

Once the infrastructure has been provisioned with Terraform, MicroK8s is installed and configured on all nodes using Ansible. This step turns the raw VMs into one multi-node Kubernetes cluster for the Mojaloop switch, plus one single-node cluster per DFSP and one for the k6 load generator.

All Ansible content for this step is located under: `kubernetes/ansible`

For full details on how the ansible is used to install microk8s, see the [`kubernetes/ansible/README.md`](kubernetes/ansible/README.md).


## Setup Cert Manager

To install cert-manager and configure issuers before enabling mTLS in Mojaloop deployments, see the [`certmanager/README.md`](certmanager/README.md).

## Setup Monitoring

To set up monitoring with Prometheus and Grafana, see the [`monitoring/README.md`](monitoring/README.md).


## Deploy Mojaloop backend

The Mojaloop backend consists of the core infrastructure components required by the switch, including Kafka, MySQL, MongoDB, and Redis. These services must be deployed and fully running before installing the Mojaloop switch.

A detailed setup guide, including TPS-specific backend configurations and Helm override files, is available here: [`backend/README.md`](backend/README.md).


## Deploy Mojaloop switch

Once the backend services (Kafka, MySQL, MongoDB, Redis) are running, the Mojaloop switch can be deployed.  
This installs all core Mojaloop components — ALS, Quoting Service, ML-API-Adapter, Central Ledger handlers, Settlement services, and supporting pods—onto the switch Kubernetes cluster.

A detailed deployment guide, including Helm commands, configuration overrides, and service layout, is available in: [`mojaloop/README.md`](mojaloop/README.md).


## Deploy DFSPs

DFSP simulators are deployed as independent MicroK8s clusters and act as payers and payees during performance tests. Each DFSP runs a Mojaloop Simulator with configurable scaling to support different TPS scenarios.

The complete deployment process, including the generic deployment script and scenario-based tuning (switch IP and replica counts), is documented here:
[`dfsp/README.md`](dfsp/README.md).


## Deploy k6 infrastructure

A dedicated Kubernetes cluster is used to run k6 load tests via the **k6 Operator**. This cluster is responsible for generating all test traffic and sending it to the DFSP simulator endpoints.

The setup includes installing the k6 Operator, configuring image pull secrets, and updating CoreDNS so the k6 cluster can resolve DFSP simulator domains.

Full installation details and the automated setup script are available here:
[`k6-infrastructure/README.md`](k6-infrastructure/README.md).


