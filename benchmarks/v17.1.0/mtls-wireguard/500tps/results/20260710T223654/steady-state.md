# Steady-state report

run window:     2026-07-11T04:38:17Z .. 2026-07-11T05:21:17Z  (2580s)
steady window:  2026-07-11T04:43:17Z .. 2026-07-11T05:19:17Z  (2160s; warm-up 300s + drain 120s excluded)

measured transfers (steady): 1079992

| metric | p50 | p95 | p99 | avg | stddev |
|---|---|---|---|---|---|
| e2e_time | 724ms | 963ms | 1077ms | 732ms | 128ms |
| transfer_time | 533ms | 747ms | 851ms | 543ms | 113ms |
| quote_time | 159ms | 259ms | 296ms | 163ms | 54ms |
| discovery_time | 22ms | 47ms | 71ms | 26ms | 12ms |

## Validity gate (kafka topic rates, steady window)
topic-notification-event:                1000.0/s
topic-quotes-post:                        500.0/s
topic-transfer-fulfil:                    500.0/s
topic-transfer-position-batch:           1000.1/s
topic-transfer-prepare:                   500.0/s
gate: fulfil/prepare=1.000  notif/prepare=2.000  -> PASS

## Switch/backing node CPU (steady window)
sw1-kafka-n1     avg  88.8%   peak  89.6%
sw1-monitoring   avg  25.6%   peak  57.8%
sw1-mysql-n1     avg  69.2%   peak  69.9%
sw1-n1           avg  59.6%   peak  61.7%
sw1-n2           avg  86.9%   peak  89.5%
sw1-n3           avg  85.5%   peak  88.3%
sw1-n4           avg  75.8%   peak  78.9%
sw1-n5           avg  87.2%   peak  89.9%
