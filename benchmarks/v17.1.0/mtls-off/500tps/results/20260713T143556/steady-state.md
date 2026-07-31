# Steady-state report

run window:     2026-07-13T20:35:47Z .. 2026-07-13T21:08:45Z  (1978s)
steady window:  2026-07-13T20:40:47Z .. 2026-07-13T21:06:45Z  (1558s; warm-up 300s + drain 120s excluded)

measured transfers (steady): 1012461

| metric | p50 | p95 | p99 | avg | stddev |
|---|---|---|---|---|---|
| e2e_time | 630ms | 846ms | 946ms | 636ms | 122ms |
| transfer_time | 481ms | 672ms | 755ms | 486ms | 105ms |
| quote_time | 122ms | 216ms | 249ms | 125ms | 51ms |
| discovery_time | 19ms | 51ms | 79ms | 24ms | 14ms |

## Validity gate (kafka topic rates, steady window)
topic-notification-event:                1299.9/s
topic-quotes-post:                        650.0/s
topic-transfer-fulfil:                    649.9/s
topic-transfer-position-batch:           1300.0/s
topic-transfer-prepare:                   650.0/s
gate: fulfil/prepare=1.000  notif/prepare=2.000  -> PASS

## Switch/backing node CPU (steady window)
sw1-kafka-n1     avg  66.0%   peak  66.6%
sw1-monitoring   avg  24.5%   peak  45.5%
sw1-mysql-n1     avg  69.8%   peak  70.3%
sw1-n1           avg  74.8%   peak  75.8%
sw1-n2           avg  67.7%   peak  68.7%
sw1-n3           avg  69.9%   peak  71.5%
sw1-n4           avg  75.4%   peak  76.6%
sw1-n5           avg  81.8%   peak  83.5%

## DFSP node CPU (steady window, avg)
fsp201  76.4%   (source of 70% of load)
fsp202  72.1%   (destination of 49%)
fsp206  54.3%
fsp208  46.9%
fsp204  46.2%
fsp203  31.1%
fsp207  29.7%
fsp205  29.4%
