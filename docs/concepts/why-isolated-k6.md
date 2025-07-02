# Why Isolated K6 Infrastructure?

> **tl;dr**: Running load generation on the same infrastructure as your system under test gives you false results.

## The Problem

When K6 runs on the same cluster as Mojaloop:

```
Shared Cluster Resources
├── CPU (100 cores total)
│   ├── Mojaloop: Fighting for CPU
│   └── K6: Also fighting for same CPU
├── Memory (400GB total)
│   ├── Mojaloop: Competing for memory
│   └── K6: Creating memory pressure
└── Network (10 Gbps)
    ├── Mojaloop: Internal traffic
    └── K6: Load generation traffic
```

## What Happens

1. **CPU Starvation**: K6 generating 1000 TPS uses significant CPU, starving Mojaloop
2. **Memory Pressure**: Both compete for memory, triggering GC and swapping
3. **Network Congestion**: Shared network interface becomes bottleneck
4. **Noisy Neighbor**: Can't distinguish between load generation and processing overhead

## The Solution

Isolated K6 infrastructure:

```
Mojaloop Cluster          K6 Cluster
├── 100% CPU for          ├── 100% CPU for
│   processing             │   load generation
├── All memory for        ├── Dedicated memory
│   services               │   for K6 workers
└── Network for           └── Network for
    actual traffic            generating load
         ↓                          ↓
         └──────── VPC Peering ─────┘
                (Clean measurement)
```

## Real Impact

In our tests:
- **Shared infrastructure**: Achieved only 400 TPS (bottlenecked by K6)
- **Isolated infrastructure**: Achieved 1000+ TPS (true capacity)

That's a 150% difference in measured capacity!

## Cost vs Accuracy

Yes, isolated K6 costs more (~$60/day), but:
- Accurate measurements prevent over-provisioning (saves money)
- Find real bottlenecks, not false ones
- Make decisions based on true capacity

## When You Can Share Infrastructure

Only when:
- Running small tests (<50 TPS)
- Doing functional testing, not performance testing
- Cost is absolutely critical and accuracy isn't

For any serious performance testing, isolation is mandatory.
