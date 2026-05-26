# Mojaloop Performance Tests for 1000 TPS

### Summary:
1000 (F)TPS for a total of 1 Million transfers achieved with 99.998% success rate with below configuration and details.


```
1. discovery_time.................: avg=19.84ms  min=1ms      med=18ms     max=1.12s   p(90)=28ms     p(95)=34ms     p(99)=48ms

1. quote_time.....................: avg=112.2ms  min=32ms     med=108ms    max=504ms   p(90)=181ms    p(95)=204ms    p(99)=239ms

1. transfer_time..................: avg=320.11ms min=60ms     med=327ms    max=2.29s   p(90)=462ms    p(95)=505ms    p(99)=587ms

1. e2e_time.......................: avg=452.5ms  min=113ms    med=453ms    max=2.45s   p(90)=618ms    p(95)=663ms    p(99)=754ms

1. vus............................: 298     min=0         max=639

1. vus_max........................: 1000    min=1000     max=1000

```

## Infrastructure Used

### Mojaloop Switch — `m7i.4xlarge` (4 nodes)

| Spec | Details |
|------|----------|
| **vCPUs** | 16 |
| **Memory** | 64 GiB |
| **Storage** | EBS-Only |
| **Network Performance** | Up to 12.5 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | Up to 10 Gbps |

---

### Kafka Nodes — `m7i.2xlarge` (1 node)

| Spec | Details |
|------|----------|
| **vCPUs** | 8 |
| **Memory** | 32 GiB |
| **Storage** | EBS-Only |
| **Network Performance** | Up to 12.5 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | Up to 10 Gbps |

---

### MySQL Node — `m7i.4xlarge` (1 node)

| Spec | Details |
|------|----------|
| **vCPUs** | 16 |
| **Memory** | 64 GiB |
| **Storage** | EBS-Only |
| **Network Performance** | Up to 12.5 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | Up to 10 Gbps |

---

### Large FSP Nodes — `c7i.8xlarge` (2 nodes)

| Spec | Details |
|------|----------|
| **vCPUs** | 32 |
| **Memory** | 64 GiB |
| **Storage** | EBS-Only |
| **Network Performance** | Up to 15 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | Up to 10 Gbps |

### Small FSP Nodes — `c7i.2xlarge` (6 nodes)

| Spec | Details |
|------|----------|
| **vCPUs** | 8 |
| **Memory** | 16 GiB |
| **Storage** | EBS-Only |
| **Network Performance** | Up to 12.5 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | Up to 10 Gbps |

---

### k6 node — `m7i.2xlarge` (1 node)

| Spec | Details |
|------|----------|
| **vCPUs** | 8 |
| **Memory** | 32 GiB |
| **Storage** | EBS-Only |
| **Network Performance** | Up to 12.5 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | Up to 10 Gbps |


Affinities if any


## Deployment Architecture 
Diagram

### Kafka Partitions

```
kafka-topics.sh --alter --topic topic-transfer-prepare --partitions 16 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-fulfil --partitions 16 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-position-batch --partitions 8 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-notification-event --partitions 24 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-quotes-post --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-quotes-put --partitions 12 --bootstrap-server kafka:9092
```

### Core services - handlers replicas

| Service | Replica count |
|------|----------|
| moja-account-lookup-service | 12 |
| moja-als-msisdn-oracle | 12 |
| moja-centralledger-handler-transfer-fulfil | 16 |
| moja-centralledger-handler-transfer-prepare | 16 |
| moja-centralledger-service | 8 |
| moja-handler-pos-batch | 8 |
| moja-ml-api-adapter-handler-notification | 24 |
| moja-ml-api-adapter-service | 12 |
| moja-quoting-service | 12 |
| moja-quoting-service-handler | 12 |



## K6 Log:

```
     ✗ ALS_FSPIOP_GET_PARTIES_RESPONSE_IS_200
      ↳  99% — ✓ 999991 / ✗ 10
     ✗ QUOTES_FSPIOP_POST_QUOTES_RESPONSE_IS_200
      ↳  99% — ✓ 999989 / ✗ 2
     ✗ TRANSFERS_FSPIOP_POST_TRANSFERS_RESPONSE_IS_200
      ↳  99% — ✓ 999986 / ✗ 2

   ✓ checks.........................: 99.99%  ✓ 2999966     ✗ 14
   ✓ completed_transactions.........: 999986  999.374661/s
     data_received..................: 6.7 GB  6.7 MB/s
     data_sent......................: 2.8 GB  2.8 MB/s
   ✓ discovery_time.................: avg=19.84ms  min=1ms      med=18ms     max=1.12s   p(90)=28ms     p(95)=34ms     p(99)=48ms
   ✓ e2e_time.......................: avg=452.5ms  min=113ms    med=453ms    max=2.45s   p(90)=618ms    p(95)=663ms    p(99)=754ms
     failed_transactions............: 15      0.014991/s
     http_req_blocked...............: avg=3.15µs   min=612ns    med=2.15µs   max=19.66ms p(90)=3.95µs   p(95)=5.08µs   p(99)=10.73µs
     http_req_connecting............: avg=461ns    min=0s       med=0s       max=19.58ms p(90)=0s       p(95)=0s       p(99)=0s
   ✓ http_req_duration..............: avg=150.67ms min=630.87µs med=105.05ms max=30.01s  p(90)=390.01ms p(95)=436.74ms p(99)=533.87ms
       { expected_response:true }...: avg=150.56ms min=1.17ms   med=105.05ms max=2.29s   p(90)=390.01ms p(95)=436.74ms p(99)=533.85ms
     http_req_failed................: 0.00%   ✓ 14          ✗ 2999966
     http_req_receiving.............: avg=25.12µs  min=7.45µs   med=21.97µs  max=17.57ms p(90)=36.01µs  p(95)=41.6µs   p(99)=60.08µs
     http_req_sending...............: avg=20.96µs  min=3.55µs   med=9.81µs   max=44.04ms p(90)=18.86µs  p(95)=22.63µs  p(99)=164.69µs
     http_req_tls_handshaking.......: avg=0s       min=0s       med=0s       max=0s      p(90)=0s       p(95)=0s       p(99)=0s
     http_req_waiting...............: avg=150.62ms min=596.22µs med=105.01ms max=30.01s  p(90)=389.98ms p(95)=436.71ms p(99)=533.83ms
     http_reqs......................: 2999980 2998.145969/s
     iteration_duration.............: avg=452.96ms min=13.55ms  med=453.26ms max=30.13s  p(90)=617.71ms p(95)=662.83ms p(99)=754.24ms
     iterations.....................: 1000001 999.389652/s
   ✓ quote_time.....................: avg=112.2ms  min=32ms     med=108ms    max=504ms   p(90)=181ms    p(95)=204ms    p(99)=239ms
   ✓ success_rate...................: 99.99%  ✓ 999986      ✗ 15
   ✓ transfer_time..................: avg=320.11ms min=60ms     med=327ms    max=2.29s   p(90)=462ms    p(95)=505ms    p(99)=587ms
     vus............................: 298     min=0         max=639
     vus_max........................: 1000    min=1000      max=1000

=== K6 TEST SUMMARY ===
{
  "test_config": {
    "target_transactions": 1000000,
    "target_tps": 1000,
    "duration": 1000,
    "fsp_pairs": [
      {
        "dest": "fsp202",
        "source": "fsp201",
        "weight": 0.28
      },
      {
        "dest": "fsp204",
        "source": "fsp201",
        "weight": 0.04
      },
      {
        "dest": "fsp206",
        "source": "fsp201",
        "weight": 0.04
      },
      {
        "dest": "fsp208",
        "source": "fsp201",
        "weight": 0.04
      },
      {
        "dest": "fsp204",
        "source": "fsp203",
        "weight": 0.0667
      },
      {
        "dest": "fsp206",
        "source": "fsp203",
        "weight": 0.0667
      },
      {
        "dest": "fsp208",
        "source": "fsp203",
        "weight": 0.0667
      },
      {
        "dest": "fsp204",
        "source": "fsp205",
        "weight": 0.0667
      },
      {
        "dest": "fsp206",
        "source": "fsp205",
        "weight": 0.0667
      },
      {
        "dest": "fsp208",
        "source": "fsp205",
        "weight": 0.0667
      },
      {
        "dest": "fsp204",
        "source": "fsp207",
        "weight": 0.0667
      },
      {
        "dest": "fsp206",
        "source": "fsp207",
        "weight": 0.0667
      },
      {
        "dest": "fsp208",
        "source": "fsp207",
        "weight": 0.0667
      }
    ]
  },
  "results": {
    "completed_transactions": 999986,
    "success_rate": 99.9985000015,
    "actual_tps": 999.986,
    "e2e_time_p95": 663,
    "e2e_time_p99": 754,
    "http_req_duration_p95": 436.74863419999997,
    "http_req_duration_p99": 533.87284756
  },
  "status": "PASSED"
}
```
