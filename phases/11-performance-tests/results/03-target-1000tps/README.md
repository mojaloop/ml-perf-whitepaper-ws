# Mojaloop Performance Tests for 1000 TPS

### Summary:
1000 (F)TPS for a total of 1 Million transfers achieved with 99.9899% success rate with below configuration and details.
```
1. discovery_time.................: avg=60.66ms  min=2ms      med=45ms     max=2.4s   p(90)=109ms    p(95)=152ms

2. quote_time.....................: avg=147.2ms  min=40ms     med=135ms    max=2.48s  p(90)=218ms    p(95)=247ms

3. transfer_time..................: avg=351.67ms min=82ms     med=331ms    max=3.01s  p(90)=480ms    p(95)=540ms

4. e2e_time.......................: avg=560.11ms min=173ms    med=523ms    max=4.32s  p(90)=734ms    p(95)=829ms

5. vus............................: 1       min=0         max=2313

6. vus_max........................: 5000    min=3003      max=5000

```

## Infrastructure Used

### Mojaloop Switch — `m7i.4xlarge` (3 nodes)

| Spec | Details |
|------|----------|
| **vCPUs** | 16 |
| **Memory** | 64 GiB |
| **Storage** | EBS-Only |
| **Network Performance** | 12.5 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | Up to 10 Gbps |

---

### Kafka Nodes — `m7i.4xlarge` (1 node)

| Spec | Details |
|------|----------|
| **vCPUs** | 16 |
| **Memory** | 64 GiB |
| **Storage** | EBS-Only |
| **Network Performance** | 12.5 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | Up to 10 Gbps |

---

### MySQL Node — `m7i.4xlarge` (1 node)

| Spec | Details |
|------|----------|
| **vCPUs** | 16 |
| **Memory** | 64 GiB |
| **Storage** | EBS only |
| **Network Performance** | 12.5 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | Up to 10 Gbps |

---

### FSP Nodes — `m7i.2xlarge` (8 nodes)

| Spec | Details |
|------|----------|
| **vCPUs** | 8 |
| **Memory** | 32 GiB |
| **Storage** | EBS only |
| **Network Performance** | High (up to 12.5 Gbps) |
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
| moja-account-lookup-service | 20 |
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
| sdk-scheme-adapter | 16 |

### Other config changes

Change log levels on core services

```
    config:
      # Log config
      log_level: error
      event_log_filter: 'log:info, log:warn, log:error'    
```      

### Distribution of load

Moved topic-transfer-prepare pods from sw1-n1 node which was under high CPU demand to sw1-n2 node which had some capacity. But this depends on how kubernetes schedules your pods. Probably in next iteration we should add pod affinity to have a consistent distribution of load on nodes.


## K6 Log:

There are some ALS failures because we re-use same 1000 MSISDNs registered per fsp so there is likely conflict in redis cache with duplicate key.

```
     ✗ ALS_FSPIOP_GET_PARTIES_RESPONSE_IS_200
      ↳  99% — ✓ 999915 / ✗ 92
     ✗ QUOTES_FSPIOP_POST_QUOTES_RESPONSE_IS_200
      ↳  99% — ✓ 999907 / ✗ 8
     ✗ TRANSFERS_FSPIOP_POST_TRANSFERS_RESPONSE_IS_200
      ↳  99% — ✓ 999899 / ✗ 8

   ✓ checks.........................: 99.99%  ✓ 2999721     ✗ 108
   ✓ completed_transactions.........: 999899  990.684372/s
     data_received..................: 6.5 GB  6.5 MB/s
     data_sent......................: 2.8 GB  2.8 MB/s
   ✓ discovery_time.................: avg=60.66ms  min=2ms      med=45ms     max=2.4s   p(90)=109ms    p(95)=152ms
   ✓ e2e_time.......................: avg=560.11ms min=173ms    med=523ms    max=4.32s  p(90)=734ms    p(95)=829ms
     failed_transactions............: 108     0.107005/s
     http_req_blocked...............: avg=4.2ms    min=139.55µs med=255.57µs max=2.3s   p(90)=5.23ms   p(95)=17.79ms
     http_req_connecting............: avg=1.74ms   min=115.08µs med=216.97µs max=2.3s   p(90)=3.4ms    p(95)=9.58ms
   ✓ http_req_duration..............: avg=182.99ms min=1.48ms   med=136.74ms max=30.08s p(90)=387.33ms p(95)=450.16ms
       { expected_response:true }...: avg=182.07ms min=1.76ms   med=136.73ms max=2.97s  p(90)=387.3ms  p(95)=450.12ms
     http_req_failed................: 0.00%   ✓ 108         ✗ 2999721
     http_req_receiving.............: avg=557.65µs min=13.49µs  med=52.98µs  max=1.55s  p(90)=1.43ms   p(95)=2.92ms
     http_req_sending...............: avg=471.91µs min=7.15µs   med=33.4µs   max=1.45s  p(90)=1.22ms   p(95)=2.51ms
     http_req_tls_handshaking.......: avg=0s       min=0s       med=0s       max=0s     p(90)=0s       p(95)=0s
     http_req_waiting...............: avg=181.96ms min=977.42µs med=135.62ms max=30.08s p(90)=386.29ms p(95)=449.01ms
     http_reqs......................: 2999829 2972.183901/s
     iteration_duration.............: avg=563.13ms min=29.83ms  med=523.24ms max=30.4s  p(90)=734.02ms p(95)=829.92ms
     iterations.....................: 1000007 990.791377/s
   ✓ quote_time.....................: avg=147.2ms  min=40ms     med=135ms    max=2.48s  p(90)=218ms    p(95)=247ms
   ✓ success_rate...................: 99.98%  ✓ 999899      ✗ 108
   ✓ transfer_time..................: avg=351.67ms min=82ms     med=331ms    max=3.01s  p(90)=480ms    p(95)=540ms
     vus............................: 1       min=0         max=2313
     vus_max........................: 5000    min=3003      max=5000

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
    "completed_transactions": 999899,
    "success_rate": 99.98920007559947,
    "actual_tps": 999.899,
    "e2e_time_p95": 829,
    "http_req_duration_p95": 450.16792860000004
  },
  "status": "PASSED"
}
```

# Patch configmaps

## Account lookup service
```
kubectl patch configmap moja-account-lookup-service-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat ./configmaps/account-lookup-service-config.json)" '{data: {"default.json": $cfg}}')"
```

## Quoting service
```
kubectl patch configmap moja-quoting-service-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat ./configmaps/quoting-service-config.json)" '{data: {"default.json": $cfg}}')"
```

## Quoting service handler
```
kubectl patch configmap moja-quoting-service-handler-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat ./configmaps/quoting-service-handler-config.json)" '{data: {"default.json": $cfg}}')"
```

## ml-api-adapter
```
kubectl patch configmap moja-ml-api-adapter-service-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat ./configmaps/ml-api-adapter-service-config.json)" '{data: {"default.json": $cfg}}')"
```

## ml-api-adapter-notification handler
```
kubectl patch configmap moja-ml-api-adapter-handler-notification-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat ./configmaps/ml-api-adapter-handler-notification-config.json)" '{data: {"default.json": $cfg}}')"
```

## Prepare handler 
```
kubectl patch configmap moja-centralledger-handler-transfer-prepare-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat ./configmaps/centralledger-handler-transfer-prepare-config.json)" '{data: {"default.json": $cfg}}')"
```

## Position batch handler
```
kubectl patch configmap moja-handler-pos-batch-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat ./configmaps/handler-pos-batch-config.json)" '{data: {"default.json": $cfg}}')"
```

## Fulfil handler
```
kubectl patch configmap moja-centralledger-handler-transfer-fulfil-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat ./configmaps/centralledger-handler-transfer-fulfil-config.json)" '{data: {"default.json": $cfg}}')"
```

## Restart services after config change
```
    for d in \
      moja-account-lookup-service \
      moja-centralledger-handler-transfer-fulfil \
      moja-centralledger-handler-transfer-prepare \
      moja-handler-pos-batch \
      moja-ml-api-adapter-handler-notification \
      moja-ml-api-adapter-service \
      moja-quoting-service \
      moja-quoting-service-handler; do

      replicas=$(kubectl get deploy $d -n mojaloop -o jsonpath='{.spec.replicas}')
      echo "Scaling $d to 0..."
      kubectl scale deploy/$d -n mojaloop --replicas=0
      echo "Scaling $d back to $replicas..."
      kubectl scale deploy/$d -n mojaloop --replicas=$replicas
    done
```
