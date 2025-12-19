# Mojaloop Performance Tests for 1000 TPS

### Summary:
2000 (F)TPS for a total of 1 Million transfers achieved with 99.9861% success rate with below configuration and details.
```
1. discovery_time.................: avg=54.4ms   min=1ms      med=25ms     max=6.73s    p(90)=68ms     p(95)=99ms

2. quote_time.....................: avg=227.54ms min=52ms     med=209ms    max=7.4s     p(90)=311ms    p(95)=359ms

3. transfer_time..................: avg=735.02ms min=129ms    med=616ms    max=19.21s   p(90)=1.14s    p(95)=1.47s

4. e2e_time.......................: avg=1.01s    min=268ms    med=884ms    max=20.34s   p(90)=1.49s    p(95)=1.88s

5. vus............................: 1       min=0         max=2745

6. vus_max........................: 2879    min=1000      max=2879

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

### MySQL Node — `m7i.8xlarge` (1 node)

| Spec | Details |
|------|----------|
| **vCPUs** | 32 |
| **Memory** | 128 GiB |
| **Storage** | EBS only |
| **Network Performance** | 12.5 Gbps |
| **Processor** | Intel Xeon Scalable (Sapphire Rapids) |
| **EBS Bandwidth** | 10 Gbps |

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
kafka-topics.sh --alter --topic topic-quotes-post --partitions 16 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-quotes-put --partitions 16 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-prepare --partitions 16 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-fulfil --partitions 16 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-position-batch --partitions 8 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-notification-event --partitions 32 --bootstrap-server kafka:9092
```

### Core services - handlers replicas

| Service | Replica count |
|------|----------|
| moja-account-lookup-service | 24 |
| moja-als-msisdn-oracle | 8 |
| moja-centralledger-handler-transfer-fulfil | 16 |
| moja-centralledger-handler-transfer-prepare | 16 |
| moja-centralledger-service | 8 |
| moja-handler-pos-batch | 8 |       
| moja-ml-api-adapter-handler-notification | 32 |
| moja-ml-api-adapter-service | 16 |
| moja-quoting-service | 16 |
| moja-quoting-service-handler | 16 |

### SDK replicas

| Service | Replica count |
|------|----------|
| sdk-scheme-adapter | 12 |

### Other config changes

Change log levels on core services

```
    config:
      # Log config
      log_level: error
      event_log_filter: 'log:info, log:warn, log:error'    
```      

### Changes on k6 and dfsp nodes

ubuntu@k6:~$ ulimit -n
1024
ubuntu@k6:~$ sysctl net.ipv4.ip_local_port_range
net.ipv4.ip_local_port_range = 32768	60999
ubuntu@k6:~$ sysctl net.core.somaxconn
net.core.somaxconn = 4096
ubuntu@k6:~$ sysctl net.ipv4.tcp_max_syn_backlog
net.ipv4.tcp_max_syn_backlog = 4096
ubuntu@k6:~$ sysctl net.ipv4.ip_local_port_range
net.ipv4.ip_local_port_range = 32768	60999

----SET BELOW
```
ubuntu@k6:~$ ulimit -n 65535
ubuntu@k6:~$ ulimit -n
65535
```

sudo vi /etc/security/limits.conf and add below towards the end 

```
* soft nofile 65535
* hard nofile 65535
```
OR below for "ubuntu" user
ubuntu soft nofile 65535
ubuntu hard nofile 65535

the create below file
```
  sudo vi /etc/sysctl.d/99-k6-tuning.conf
```
add below 
```
net.core.somaxconn = 16384
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65535
```
then 
```
sudo sysctl --system
```

## K6 Log:

There are some ALS failures because we re-use same 1000 MSISDNs registered per fsp so there is likely conflict in redis cache with duplicate key.

```
     ✗ ALS_FSPIOP_GET_PARTIES_RESPONSE_IS_200
      ↳  99% — ✓ 995609 / ✗ 127
     ✗ QUOTES_FSPIOP_POST_QUOTES_RESPONSE_IS_200
      ↳  99% — ✓ 995606 / ✗ 3
     ✗ TRANSFERS_FSPIOP_POST_TRANSFERS_RESPONSE_IS_200
      ↳  99% — ✓ 995598 / ✗ 8

   ✓ checks.........................: 99.99%  ✓ 2986813     ✗ 138
   ✓ completed_transactions.........: 995598  1903.933268/s
     data_received..................: 6.5 GB  12 MB/s
     data_sent......................: 2.8 GB  5.3 MB/s
   ✓ discovery_time.................: avg=54.4ms   min=1ms      med=25ms     max=6.73s    p(90)=68ms     p(95)=99ms
     dropped_iterations.............: 4265    8.156179/s
   ✓ e2e_time.......................: avg=1.01s    min=268ms    med=884ms    max=20.34s   p(90)=1.49s    p(95)=1.88s
     failed_transactions............: 138     0.263904/s
     http_req_blocked...............: avg=6.85µs   min=547ns    med=2.35µs   max=100.87ms p(90)=4.93µs   p(95)=5.66µs
     http_req_connecting............: avg=1.93µs   min=0s       med=0s       max=56.27ms  p(90)=0s       p(95)=0s
   ✓ http_req_duration..............: avg=339.99ms min=724.72µs med=215.14ms max=30.05s   p(90)=798.06ms p(95)=1.03s
       { expected_response:true }...: avg=338.7ms  min=1.18ms   med=215.13ms max=19.21s   p(90)=797.91ms p(95)=1.03s
     http_req_failed................: 0.00%   ✓ 138         ✗ 2986813
     http_req_receiving.............: avg=38.85µs  min=6.24µs   med=18.3µs   max=57.73ms  p(90)=34.5µs   p(95)=43.39µs
     http_req_sending...............: avg=126.78µs min=3.23µs   med=9.41µs   max=142.1ms  p(90)=20.92µs  p(95)=37.55µs
     http_req_tls_handshaking.......: avg=0s       min=0s       med=0s       max=0s       p(90)=0s       p(95)=0s
     http_req_waiting...............: avg=339.83ms min=687.36µs med=215.08ms max=30.05s   p(90)=797.98ms p(95)=1.03s
     http_reqs......................: 2986951 5712.100042/s
     iteration_duration.............: avg=1.02s    min=23.97ms  med=884.34ms max=30.36s   p(90)=1.49s    p(95)=1.89s
     iterations.....................: 995736  1904.197172/s
   ✓ quote_time.....................: avg=227.54ms min=52ms     med=209ms    max=7.4s     p(90)=311ms    p(95)=359ms
   ✓ success_rate...................: 99.98%  ✓ 995598      ✗ 138
   ✓ transfer_time..................: avg=735.02ms min=129ms    med=616ms    max=19.21s   p(90)=1.14s    p(95)=1.47s
     vus............................: 1       min=0         max=2745
     vus_max........................: 2879    min=1000      max=2879
     === K6 TEST SUMMARY ===
{
  "test_config": {
    "target_transactions": 1000000,
    "target_tps": 2000,
    "duration": 500,
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
    "completed_transactions": 995598,
    "success_rate": 99.98614090481814,
    "actual_tps": 1991.196,
    "e2e_time_p95": 1889,
    "http_req_duration_p95": 1037.748395
  },
  "status": "PASSED"
}
```