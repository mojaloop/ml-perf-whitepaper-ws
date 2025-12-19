# Mojaloop Performance Tests for 1000 TPS with Kafka and Mysql replication

### Summary:
1000 (F)TPS for a total of 1 Million transfers achieved with 99.9792% success rate with below configuration and details.
```
1. discovery_time.................: avg=24.96ms  min=1ms      med=19ms     max=3.47s   p(90)=38ms     p(95)=47ms

2. quote_time.....................: avg=120.34ms min=36ms     med=117ms    max=1.2s    p(90)=191ms    p(95)=212ms

3. transfer_time..................: avg=466.29ms min=162ms    med=459ms    max=3.52s   p(90)=592ms    p(95)=636ms

4. e2e_time.......................: avg=611.96ms min=225ms    med=601ms    max=3.95s   p(90)=759ms    p(95)=812ms

5. vus............................: 1       min=0         max=1036

6. vus_max........................: 5000    min=4829      max=5000

```

We are able to run 500k transfers with 1100 ftps
```
1. discovery_time.................: avg=44.55ms  min=1ms      med=21ms     max=3.94s    p(90)=57ms     p(95)=90ms
2. quote_time.....................: avg=124.8ms  min=36ms     med=119ms    max=1.19s    p(90)=199ms    p(95)=222ms
3. transfer_time..................: avg=504.83ms min=170ms    med=489ms    max=5.41s    p(90)=654ms    p(95)=715ms
4. e2e_time.......................: avg=674.68ms min=240ms    med=642ms    max=5.55s    p(90)=853ms    p(95)=952ms
5. vus............................: 40      min=0         max=1437
6. vus_max........................: 5000    min=5000      max=5000

```

## Infrastructure Used

### Mojaloop Switch — `m7i.8xlarge` (3 nodes)

| Spec | Details |
|------|----------|
| **vCPUs** | 32 |
| **Memory** | 128 GiB |
| **Storage** | EBS-Only |
| **Network Performance** | 12.5 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | 10 Gbps |

---

### Kafka Nodes — `m7i.4xlarge` (2 nodes)

| Spec | Details |
|------|----------|
| **vCPUs** | 16 |
| **Memory** | 64 GiB |
| **Storage** | EBS-Only |
| **Network Performance** | 12.5 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | Up to 10 Gbps |

---

### MySQL Node — `m7i.4xlarge` (2 node)

| Spec | Details |
|------|----------|
| **vCPUs** | 16 |
| **Memory** | 64 GiB |
| **Storage** | EBS only |
| **Network Performance** | 12.5 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | Up to 10 Gbps |

---

### FSP Nodes — `c7i.4xlarge` (8 nodes)

| Spec | Details |
|------|----------|
| **vCPUs** | 16 |
| **Memory** | 32 GiB |
| **Storage** | EBS only |
| **Network Performance** | up to 12.5 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | Up to 10 Gbps |

---

### k6 node — `m7i.xlarge` (1 node)

| Spec | Details |
|------|----------|
| **vCPUs** | 4 |
| **Memory** | 16 GiB |
| **Storage** | EBS-Only |
| **Network Performance** | Up to 12.5 |
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
| moja-account-lookup-service | 16 |
| moja-als-msisdn-oracle | 8 |
| moja-centralledger-handler-transfer-fulfil | 12 |
| moja-centralledger-handler-transfer-prepare | 12 |
| moja-centralledger-service | 8 |
| moja-handler-pos-batch | 8 |       
| moja-ml-api-adapter-handler-notification | 18 |
| moja-ml-api-adapter-service | 12 |
| moja-quoting-service | 12 |
| moja-quoting-service-handler | 12 |

### SDK replicas

| Service | Replica count |
|------|----------|
| sdk-scheme-adapter | 12 |

### Replication config
We use bitnami charts to deploy kafka and mysql in replication mode. The configs are in the respective directories and scripts.

### Other config changes

Change log levels on core services

```
    config:
      # Log config
      log_level: error
      event_log_filter: 'log:info, log:warn, log:error'    
```      

### Distribution of load

default distribution of pods across nodes


## K6 Log:

There are some ALS failures because we re-use same 1000 MSISDNs registered per fsp so there is likely conflict in redis cache with duplicate key. The transfer failure are because SDK times out any request running longer than 30 seconds

```
✗ ALS_FSPIOP_GET_PARTIES_RESPONSE_IS_200
      ↳  99% — ✓ 999980 / ✗ 21
     ✓ QUOTES_FSPIOP_POST_QUOTES_RESPONSE_IS_200
     ✗ TRANSFERS_FSPIOP_POST_TRANSFERS_RESPONSE_IS_200
      ↳  99% — ✓ 999793 / ✗ 186

   ✓ checks.........................: 99.99%  ✓ 2999753     ✗ 207
   ✓ completed_transactions.........: 999793  975.917656/s
     data_received..................: 6.6 GB  6.4 MB/s
     data_sent......................: 2.8 GB  2.8 MB/s
   ✓ discovery_time.................: avg=24.96ms  min=1ms      med=19ms     max=3.47s   p(90)=38ms     p(95)=47ms
   ✓ e2e_time.......................: avg=611.96ms min=225ms    med=601ms    max=3.95s   p(90)=759ms    p(95)=812ms
     failed_transactions............: 208     0.203033/s
     http_req_blocked...............: avg=341.97µs min=121.92µs med=206.75µs max=71.72ms p(90)=346.13µs p(95)=438.45µs
     http_req_connecting............: avg=279.46µs min=102.91µs med=179.28µs max=69.27ms p(90)=310.51µs p(95)=392.34µs
   ✓ http_req_duration..............: avg=205.35ms min=528.34µs med=117.12ms max=30.05s  p(90)=509.89ms p(95)=563.88ms
       { expected_response:true }...: avg=203.31ms min=1.24ms   med=117.1ms  max=3.52s   p(90)=509.83ms p(95)=563.78ms
     http_req_failed................: 0.00%   ✓ 207         ✗ 2999753
     http_req_receiving.............: avg=185.53µs min=10.31µs  med=33.15µs  max=70.62ms p(90)=64.53µs  p(95)=360.11µs
     http_req_sending...............: avg=70.02µs  min=6.29µs   med=22.72µs  max=68.08ms p(90)=39.28µs  p(95)=69.51µs
     http_req_tls_handshaking.......: avg=0s       min=0s       med=0s       max=0s      p(90)=0s       p(95)=0s
     http_req_waiting...............: avg=205.09ms min=477.38µs med=116.91ms max=30.01s  p(90)=509.64ms p(95)=563.59ms
     http_reqs......................: 2999960 2928.320093/s
     iteration_duration.............: avg=618.11ms min=76.54ms  med=601.31ms max=30.46s  p(90)=759.35ms p(95)=812.37ms
     iterations.....................: 1000001 976.120689/s
   ✓ quote_time.....................: avg=120.34ms min=36ms     med=117ms    max=1.2s    p(90)=191ms    p(95)=212ms
   ✓ success_rate...................: 99.97%  ✓ 999793      ✗ 208
   ✓ transfer_time..................: avg=466.29ms min=162ms    med=459ms    max=3.52s   p(90)=592ms    p(95)=636ms
     vus............................: 1       min=0         max=1036
     vus_max........................: 5000    min=4829      max=5000


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
        "weight": 0.25
      },
      {
        "dest": "fsp204",
        "source": "fsp203",
        "weight": 0.25
      },
      {
        "dest": "fsp206",
        "source": "fsp205",
        "weight": 0.25
      },
      {
        "dest": "fsp208",
        "source": "fsp207",
        "weight": 0.25
      }
    ]
  },
  "results": {
    "completed_transactions": 999793,
    "success_rate": 99.97920002079998,
    "actual_tps": 999.793,
    "e2e_time_p95": 812,
    "http_req_duration_p95": 563.8833505999999
  },
  "status": "PASSED"
}
```
