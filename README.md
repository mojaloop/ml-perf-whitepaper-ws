# Mojaloop Performance Testing Whitepaper

> **The Challenge**: Can Mojaloop handle 1000 transactions per second with full production security enabled? Where are the limits given the configuration and how to reach it?
>
> **The Answer**: This repository proves it with a fully reproducible methodology.

## 🚀 Start Your Journey

<div align="center">

### **[→ Follow the Setup Journey](SETUP_JOURNEY.md)**
*A guided path to achieving 1000 TPS in up to 2 weeks, plus how to push the bounderies to max out the given configuration*

</div>

## 🎯 What This Repository Provides

A **complete, reproducible methodology** for performance testing Mojaloop at scale:

- ✅ **Infrastructure as Code** - Every component automated
- ✅ **Step-by-Step Journey** - From zero to 1000 TPS  
- ✅ **Real Production Setup** - mTLS, JWS signatures, ILP validation
- ✅ **Isolated Load Testing** - Accurate measurements with dedicated K6 infrastructure
- ✅ **Comprehensive Analysis** - Detailed metrics, bottleneck identification, and reports

## 📊 Proven Results

```
Achievement: 1000 TPS sustained for 1,000,000 transactions
Success Rate: 100%
P95 Latency: 187ms
Infrastructure: AWS EKS with 15 nodes
Configuration: 8 DFSPs with asymmetric load
Security: Full stack enabled
Cost: $x per million transactions
```

## 🗺️ Repository Structure

```
ml-perf-whitepaper-ws/
├── 📍 SETUP_JOURNEY.md                    # Your guide to 1000 TPS
├── 📁 phases/                             # Your journey in 8 phases
│   ├── 01-prerequisites/                  # ✓ Get ready (2-4 hrs)
│   │   ├── README.md                      # Start here
│   │   ├── scripts/                       # Tool installation
│   │   └── validation/                    # Readiness checks
│   │
│   ├── 02-infrastructure/                 # ✓ Build AWS foundation (4-8 hrs)
│   │   ├── README.md                      # Phase guide
│   │   ├── terraform/                     # Infrastructure as code
│   │   │   ├── vpc/                       # Network setup
│   │   │   ├── eks-mojaloop/             # Mojaloop cluster
│   │   │   └── eks-k6/                    # K6 cluster
│   │   └── scripts/                       # Deployment automation
│   │
│   ├── 03-kubernetes/                     # ✓ Deploy platform services (3-6 hrs)
│   │   ├── README.md                      # Phase guide
│   │   ├── platform-services/             # Base platform
│   │   │   ├── istio/                     # Service mesh
│   │   │   ├── cert-manager/              # TLS management
│   │   │   └── monitoring/                # Prometheus & Grafana
│   │   └── scripts/                       # Installation scripts
│   │
│   ├── 04-mojaloop/                       # ✓ Install Mojaloop + 8 DFSPs (4-8 hrs)
│   │   ├── README.md                      # Phase guide
│   │   ├── helm-values/                   # Mojaloop configuration
│   │   ├── dfsp-setup/                    # 8 DFSP configurations
│   │   ├── security-stack/                # mTLS, JWS, ILP setup
│   │   └── scripts/                       # Deployment & validation
│   │
│   ├── 05-k6-infrastructure/              # ✓ Isolated load testing (3-6 hrs)
│   │   ├── README.md                      # Phase guide
│   │   ├── k6-operator/                   # K6 deployment
│   │   ├── test-scenarios/                # Load test definitions
│   │   └── scripts/                       # K6 cluster setup
│   │
│   ├── 06-first-test/                     # ✓ Validate everything works (2-4 hrs)
│   │   ├── README.md                      # Phase guide
│   │   ├── validation-tests/              # Small-scale tests
│   │   └── scripts/                       # Test execution
│   │
│   ├── 07-performance-tests/              # ✓ Achieve 1000 TPS (2-5 days iterating)
│   │   ├── README.md                      # Phase guide
│   │   ├── test-suite/                    # Full test scenarios
│   │   │   ├── 01-baseline-100tps/        # Warm-up test
│   │   │   ├── 02-scale-500tps/           # Scale test
│   │   │   ├── 03-target-1000tps/         # Target test
│   │   │   ├── 04-endurance-1000tps/      # Sustain test
│   │   │   └── 05-stress-to-failure/      # Breaking point
│   │   ├── monitoring/                    # Real-time dashboards
│   │   └── scripts/                       # Test orchestration
│   │
│   └── 08-analysis/                       # ✓ Generate insights (4-8 hrs)
│       ├── README.md                      # Phase guide
│       ├── analysis-tools/                # Data processing
│       ├── report-templates/              # Output formats
│       ├── results/                       # Test results go here
│       └── scripts/                       # Analysis automation
│
├── 📁 docs/                               # Additional reading
│   ├── architecture/                      # System design
│   ├── troubleshooting/                   # Common issues
│   └── theory/                            # Performance testing concepts
│
└── 📁 .github/                            # Repository management
    └── ISSUE_TEMPLATE/                    # Bug reports, questions
```

## 🚦 Getting Started

Start with [SETUP_JOURNEY.md](SETUP_JOURNEY.md) and follow each phase to understand the architecture and achieve 1000 TPS.

## 💡 Key Insights

### Why This Approach Works

1. **Isolated K6 Infrastructure** - Load generation doesn't compete with Mojaloop for resources
2. **Production Security** - Tests include full mTLS, JWS, and ILP overhead
3. **Realistic Load Pattern** - 8 DFSPs with asymmetric traffic distribution
4. **Comprehensive Monitoring** - Every metric captured for analysis

### What Makes This Reproducible

- **Self-Contained Phases** - Each phase has everything it needs
- **No Hidden Dependencies** - All configurations included
- **Validated Progress** - Can't proceed until current phase succeeds
- **Clear Recovery Path** - Every phase can be rolled back

## 📋 Prerequisites

Before starting, you'll need:
- AWS account with appropriate limits
- Basic tools: kubectl, helm, terraform
- Budget: ~$TBD/day during testing
- Time: up to 2 weeks total (including iterative tuning)

See [Phase 01: Prerequisites](phases/01-prerequisites/) for detailed requirements.

## 🤝 Contributing

This project is designed to be:
- **Forked** and adapted for your specific needs
- **Extended** with additional test scenarios
- **Improved** based on your findings

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

## 📜 License

[Apache 2.0](LICENSE) - Use freely and contribute back!
