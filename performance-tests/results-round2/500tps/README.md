# Mojaloop Performance Tests for 500 TPS

### Summary:
500 (F)TPS for a total of 1 Million transfers achieved with 99.996% success rate with below configuration and details.


```
1. discovery_time.................: avg=18.65ms  min=1ms     med=17ms     max=2.1s    p(90)=25ms     p(95)=29ms     p(99)=41ms

1. quote_time.....................: avg=118.77ms min=33ms    med=118ms    max=363ms   p(90)=186ms    p(95)=206ms    p(99)=233ms

1. transfer_time..................: avg=263.22ms min=61ms    med=240ms    max=2.31s   p(90)=405ms    p(95)=458ms    p(99)=538ms

1. e2e_time.......................: avg=400.84ms min=122ms   med=386ms    max=2.71s   p(90)=554ms    p(95)=606ms    p(99)=703ms

1. vus............................: 89      min=0         max=348

1. vus_max........................: 1000    min=1000      max=1000

```

## Infrastructure Used

### Mojaloop Switch — `m7i.2xlarge` (4 nodes)

| Spec | Details |
|------|----------|
| **vCPUs** | 8 |
| **Memory** | 32 GiB |
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

### MySQL Node — `m7i.2xlarge` (1 node)

| Spec | Details |
|------|----------|
| **vCPUs** | 8 |
| **Memory** | 32 GiB |
| **Storage** | EBS-Only |
| **Network Performance** | Up to 12.5 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | Up to 10 Gbps |

---

### Large FSP Nodes — `c7i.4xlarge` (2 nodes)

| Spec | Details |
|------|----------|
| **vCPUs** | 16 |
| **Memory** | 32 GiB |
| **Storage** | EBS-Only |
| **Network Performance** | Up to 12.5 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | Up to 10 Gbps |

### Small FSP Nodes — `c7i.xlarge` (6 nodes)

| Spec | Details |
|------|----------|
| **vCPUs** | 4 |
| **Memory** | 8 GiB |
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
kafka-topics.sh --alter --topic topic-quotes-post --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-quotes-put --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-prepare --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-fulfil --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-position-batch --partitions 8 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-notification-event --partitions 18 --bootstrap-server kafka:9092
```

### Core services - handlers replicas

| Service | Replica count |
|------|----------|
| moja-account-lookup-service | 8 |
| moja-als-msisdn-oracle | 8 |
| moja-centralledger-handler-transfer-fulfil | 12 |
| moja-centralledger-handler-transfer-prepare | 12 |
| moja-centralledger-service | 12 |
| moja-handler-pos-batch | 8 |       
| moja-ml-api-adapter-handler-notification | 18 |
| moja-ml-api-adapter-service | 12 |
| moja-quoting-service | 12 |
| moja-quoting-service-handler | 12 |



## K6 Log:

```
✗ ALS_FSPIOP_GET_PARTIES_RESPONSE_IS_200
      ↳  99% — ✓ 999963 / ✗ 37
     ✗ QUOTES_FSPIOP_POST_QUOTES_RESPONSE_IS_200
      ↳  99% — ✓ 999962 / ✗ 1
     ✗ TRANSFERS_FSPIOP_POST_TRANSFERS_RESPONSE_IS_200
      ↳  99% — ✓ 999961 / ✗ 1

   ✓ checks.........................: 99.99%  ✓ 2999886     ✗ 39
   ✓ completed_transactions.........: 999961  499.757965/s
     data_received..................: 6.7 GB  3.3 MB/s
     data_sent......................: 2.8 GB  1.4 MB/s
   ✓ discovery_time.................: avg=18.65ms  min=1ms     med=17ms     max=2.1s    p(90)=25ms     p(95)=29ms     p(99)=41ms
   ✓ e2e_time.......................: avg=400.84ms min=122ms   med=386ms    max=2.71s   p(90)=554ms    p(95)=606ms    p(99)=703ms
     failed_transactions............: 39      0.019491/s
     http_req_blocked...............: avg=4.73µs   min=573ns   med=2.75µs   max=10.49ms p(90)=5.46µs   p(95)=6.65µs   p(99)=13.9µs
     http_req_connecting............: avg=1.14µs   min=0s      med=0s       max=10.46ms p(90)=0s       p(95)=0s       p(99)=0s
   ✓ http_req_duration..............: avg=133.77ms min=1.35ms  med=113.99ms max=30s     p(90)=301.94ms p(95)=373.35ms p(99)=489.05ms
       { expected_response:true }...: avg=133.41ms min=1.35ms  med=113.99ms max=2.31s   p(90)=301.93ms p(95)=373.34ms p(99)=488.98ms
     http_req_failed................: 0.00%   ✓ 39          ✗ 2999886
     http_req_receiving.............: avg=35.32µs  min=5.68µs  med=30.78µs  max=3.95ms  p(90)=52.36µs  p(95)=63.45µs  p(99)=167.36µs
     http_req_sending...............: avg=16.19µs  min=2.81µs  med=11.56µs  max=18.39ms p(90)=18.2µs   p(95)=22.61µs  p(99)=48.28µs
     http_req_tls_handshaking.......: avg=0s       min=0s      med=0s       max=0s      p(90)=0s       p(95)=0s       p(99)=0s
     http_req_waiting...............: avg=133.72ms min=1.3ms   med=113.95ms max=30s     p(90)=301.9ms  p(95)=373.31ms p(99)=489ms
     http_reqs......................: 2999925 1499.294886/s
     iteration_duration.............: avg=402.26ms min=21.41ms med=386.2ms  max=30s     p(90)=554.23ms p(95)=606.78ms p(99)=703.83ms
     iterations.....................: 1000000 499.777456/s
   ✓ quote_time.....................: avg=118.77ms min=33ms    med=118ms    max=363ms   p(90)=186ms    p(95)=206ms    p(99)=233ms
   ✓ success_rate...................: 99.99%  ✓ 999961      ✗ 39
   ✓ transfer_time..................: avg=263.22ms min=61ms    med=240ms    max=2.31s   p(90)=405ms    p(95)=458ms    p(99)=538ms
     vus............................: 89      min=0         max=348
     vus_max........................: 1000    min=1000      max=1000
```
