# Documentation

Comprehensive documentation for reproducing Mojaloop performance tests.

## Directory Structure

- **setup-guides/**: Step-by-step setup instructions
- **runbooks/**: Operational procedures
- **troubleshooting/**: Common issues and solutions
- **architecture/**: System design and architecture

## Documentation Index

### Setup Guides

1. **[Prerequisites](setup-guides/prerequisites.md)**: Required tools and access
2. **[AWS Setup](setup-guides/aws-setup.md)**: AWS account and IAM configuration
3. **[Infrastructure Provisioning](setup-guides/infrastructure.md)**: Terraform deployment
4. **[Kubernetes Setup](setup-guides/kubernetes.md)**: EKS cluster configuration
5. **[Mojaloop Installation](setup-guides/mojaloop.md)**: Helm deployment
6. **[K6 Infrastructure](setup-guides/k6-infrastructure.md)**: Test infrastructure
7. **[First Test Run](setup-guides/first-test.md)**: Running your first test

### Runbooks

1. **[Daily Operations](runbooks/daily-operations.md)**: Routine tasks
2. **[Test Execution](runbooks/test-execution.md)**: Running performance tests
3. **[Result Collection](runbooks/result-collection.md)**: Gathering test data
4. **[Troubleshooting Tests](runbooks/troubleshooting.md)**: Common test issues

### Architecture

1. **[System Overview](architecture/overview.md)**: High-level architecture
2. **[Network Design](architecture/network.md)**: VPC and connectivity
3. **[Security Architecture](architecture/security.md)**: mTLS, JWS, ILP
4. **[Scaling Design](architecture/scaling.md)**: Horizontal scaling approach

### Troubleshooting

1. **[Infrastructure Issues](troubleshooting/infrastructure.md)**
2. **[Mojaloop Problems](troubleshooting/mojaloop.md)**
3. **[K6 Test Failures](troubleshooting/k6.md)**
4. **[Performance Issues](troubleshooting/performance.md)**

## Best Practices

### Performance Testing

1. **Isolation**: Always use separate K6 infrastructure
2. **Warm-up**: Run 5-minute warm-up before measurements
3. **Monitoring**: Watch metrics during entire test
4. **Validation**: Verify results with multiple runs

### Security

1. **Credentials**: Use AWS Secrets Manager
2. **Network**: Implement least-privilege security groups
3. **Encryption**: Enable encryption at rest and in transit
4. **Auditing**: Enable CloudTrail and K8s audit logs

## FAQ

Common questions and answers about the performance testing setup.
