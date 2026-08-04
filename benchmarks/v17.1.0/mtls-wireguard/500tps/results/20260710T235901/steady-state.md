# Steady-state report

run window:     2026-07-11T05:58:55Z .. 2026-07-11T06:42:57Z  (2642s)
steady window:  2026-07-11T06:03:55Z .. 2026-07-11T06:40:57Z  (2222s; warm-up 300s + drain 120s excluded)

measured transfers (steady): 999810

| metric | p50 | p95 | p99 | avg | stddev |
|---|---|---|---|---|---|
| e2e_time | 643ms | 834ms | 918ms | 648ms | 109ms |
| transfer_time | 462ms | 630ms | 704ms | 468ms | 93ms |
| quote_time | 157ms | 252ms | 291ms | 159ms | 53ms |
| discovery_time | 18ms | 33ms | 48ms | 20ms | 12ms |

## Validity gate (kafka topic rates, steady window)
topic-notification-event:                 899.9/s
topic-quotes-post:                        450.0/s
topic-transfer-fulfil:                    449.9/s
topic-transfer-position-batch:            899.9/s
topic-transfer-prepare:                   450.0/s
gate: fulfil/prepare=1.000  notif/prepare=2.000  -> PASS

## Switch/backing node CPU (steady window)
sw1-kafka-n1     avg  87.4%   peak  87.9%
sw1-monitoring   avg  23.6%   peak  28.6%
sw1-mysql-n1     avg  64.7%   peak  65.3%
sw1-n1           avg  53.8%   peak  54.8%
sw1-n2           avg  79.1%   peak  80.1%
sw1-n3           avg  78.0%   peak  79.6%
sw1-n4           avg  66.9%   peak  67.7%
sw1-n5           avg  78.8%   peak  79.7%
