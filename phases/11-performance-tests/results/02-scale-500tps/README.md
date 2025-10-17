# Mojaloop Performance Tests for 500 TPS

### Summary:
500 TPS for a total of 1 Million transfers achieved with 99.999% success rate with below configuration and details.

discovery_time.................: avg=22.54ms  min=2ms      med=21ms     max=1.06s   p(90)=29ms     p(95)=34ms
quote_time.....................: avg=124.35ms min=38ms     med=124ms    max=375ms   p(90)=191ms    p(95)=211ms
transfer_time..................: avg=543.58ms min=202ms    med=530ms    max=1.8s    p(90)=707ms    p(95)=768ms
e2e_time.......................: avg=690.72ms min=276ms    med=679ms    max=1.97s   p(90)=867ms    p(95)=929ms
vus............................: 148     min=0         max=496
vus_max........................: 3000    min=3000      max=3000

## Infrastructure Used

### Mojaloop Switch — `m7i.4xlarge` (3 nodes)

| Spec | Details |
|------|----------|
| **vCPUs** | 16 |
| **Memory** | 64 GiB |
| **Storage** | EBS only (no instance store) |
| **Network Performance** | High (up to 10 Gbps) |
| **Processor** | Intel Xeon E5-2686 v4 (Broadwell) |
| **EBS Bandwidth** | Up to 2,000 Mbps |

---

### Kafka Nodes — `m7i.4xlarge` (4 nodes)

| Spec | Details |
|------|----------|
| **vCPUs** | 16 |
| **Memory** | 64 GiB |
| **Storage** | EBS only (NVMe SSD-backed) |
| **Network Performance** | Up to 10 Gbps |
| **Processor** | 3.1 GHz Intel Xeon Platinum 8175 M (Skylake/Cascade Lake) |
| **EBS Bandwidth** | Up to 4,750 Mbps |

---

### MySQL Node — `m7i.4xlarge` (1 node)

| Spec | Details |
|------|----------|
| **vCPUs** | 16 |
| **Memory** | 64 GiB |
| **Storage** | EBS only |
| **Network Performance** | Up to 10 Gbps |
| **Processor** | Intel Xeon Platinum 8175 M |
| **EBS Bandwidth** | Up to 4,750 Mbps |

---

### FSP Nodes — `m7i.2xlarge` (8 nodes)

| Spec | Details |
|------|----------|
| **vCPUs** | 8 |
| **Memory** | 32 GiB |
| **Storage** | EBS only |
| **Network Performance** | High (up to 1–10 Gbps, depending on region) |
| **Processor** | Intel Xeon E5-2686 v4 (Broadwell) |
| **EBS Bandwidth** | Up to 1,000 Mbps |

---

### k6 node — `m7i.4xlarge` (1 node)

| Spec | Details |
|------|----------|
| **vCPUs** | 16 |
| **Memory** | 64 GiB |
| **Storage** | EBS only (NVMe SSD-backed) |
| **Network Performance** | Up to 10 Gbps |
| **Processor** | 3.1 GHz Intel Xeon Platinum 8175 M (Skylake/Cascade Lake) |
| **EBS Bandwidth** | Up to 4,750 Mbps |


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
kafka-topics.sh --alter --topic topic-notification-event --partitions 12 --bootstrap-server kafka:9092
```

### Core services - handlers replicas

| Service | Replica count |
|------|----------|
| moja-account-lookup-service | 16 |
| moja-als-msisdn-oracle | 8 |
| moja-centralledger-handler-transfer-fulfil | 12 |
| moja-centralledger-handler-transfer-prepare | 12 |
| moja-centralledger-service | 12 |
| moja-handler-pos-batch | 8 |       
| moja-ml-api-adapter-handler-notification | 12 |
| moja-ml-api-adapter-service | 12 |
| moja-quoting-service | 12 |
| moja-quoting-service-handler | 12 |




## K6 Log:

```
     ✗ ALS_FSPIOP_GET_PARTIES_RESPONSE_IS_200
      ↳  99% — ✓ 999998 / ✗ 3
     ✓ QUOTES_FSPIOP_POST_QUOTES_RESPONSE_IS_200
     ✗ TRANSFERS_FSPIOP_POST_TRANSFERS_RESPONSE_IS_200
      ↳  99% — ✓ 999994 / ✗ 4

   ✓ checks.........................: 99.99%  ✓ 2999990     ✗ 7
   ✓ completed_transactions.........: 999994  499.811072/s
     data_received..................: 6.6 GB  3.3 MB/s
     data_sent......................: 2.8 GB  1.4 MB/s
   ✓ discovery_time.................: avg=22.54ms  min=2ms      med=21ms     max=1.06s   p(90)=29ms     p(95)=34ms
   ✓ e2e_time.......................: avg=690.72ms min=276ms    med=679ms    max=1.97s   p(90)=867ms    p(95)=929ms
     failed_transactions............: 7       0.003499/s
     http_req_blocked...............: avg=281.32µs min=125.52µs med=213.7µs  max=1.03s   p(90)=376.39µs p(95)=426.83µs
     http_req_connecting............: avg=246.86µs min=104.69µs med=184.25µs max=1.03s   p(90)=346.98µs p(95)=396.65µs
   ✓ http_req_duration..............: avg=229.76ms min=405.73µs med=123.26ms max=30s     p(90)=595.89ms p(95)=668.74ms
       { expected_response:true }...: avg=229.73ms min=1.5ms    med=123.26ms max=1.8s    p(90)=595.89ms p(95)=668.74ms
     http_req_failed................: 0.00%   ✓ 7           ✗ 2999990
     http_req_receiving.............: avg=87.52µs  min=11.68µs  med=34.13µs  max=65.52ms p(90)=57.28µs  p(95)=73.53µs
     http_req_sending...............: avg=33.22µs  min=6.29µs   med=23.05µs  max=64.51ms p(90)=34.53µs  p(95)=39.62µs
     http_req_tls_handshaking.......: avg=0s       min=0s       med=0s       max=0s      p(90)=0s       p(95)=0s
     http_req_waiting...............: avg=229.64ms min=342.49µs med=123.16ms max=30s     p(90)=595.75ms p(95)=668.62ms
     http_reqs......................: 2999997 1499.440714/s
     iteration_duration.............: avg=691.04ms min=94.03ms  med=678.83ms max=30s     p(90)=867.11ms p(95)=929.42ms
     iterations.....................: 1000001 499.814571/s
   ✓ quote_time.....................: avg=124.35ms min=38ms     med=124ms    max=375ms   p(90)=191ms    p(95)=211ms
   ✓ success_rate...................: 99.99%  ✓ 999994      ✗ 7
   ✓ transfer_time..................: avg=543.58ms min=202ms    med=530ms    max=1.8s    p(90)=707ms    p(95)=768ms
     vus............................: 148     min=0         max=496
     vus_max........................: 3000    min=3000      max=3000
```
