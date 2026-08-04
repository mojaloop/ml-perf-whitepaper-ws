# Steady-state report

run window:     2026-07-07T21:37:53Z .. 2026-07-07T22:21:53Z  (2640s)
steady window:  2026-07-07T21:42:53Z .. 2026-07-07T22:19:53Z  (2220s; warm-up 300s + drain 120s excluded)

measured transfers (steady): 1109349

| metric | p50 | p95 | p99 | avg | stddev |
|---|---|---|---|---|---|
| e2e_time | 624ms | 823ms | 910ms | 630ms | 109ms |
| transfer_time | 446ms | 616ms | 698ms | 453ms | 92ms |
| quote_time | 153ms | 248ms | 288ms | 155ms | 53ms |
| discovery_time | 19ms | 37ms | 53ms | 21ms | 8ms |

## Validity gate (kafka topic rates, steady window)
topic-notification-event:                 999.6/s
topic-quotes-post:                        500.0/s
topic-transfer-position-batch:            999.9/s
topic-transfer-prepare:                   500.0/s
topic-transfer-fulfil:                    499.9/s
gate: fulfil/prepare=1.000  notif/prepare=1.999  -> PASS

## Switch/backing node CPU (steady window)
sw1-kafka-n1     avg  68.8%   peak  69.6%
sw1-monitoring   avg  21.7%   peak  23.2%
sw1-mysql-n1     avg  55.3%   peak  56.8%
sw1-n1           avg  72.4%   peak  74.0%
sw1-n2           avg  73.2%   peak  75.1%
sw1-n3           avg  83.4%   peak  85.4%
sw1-n4           avg  85.4%   peak  87.7%
sw1-n5           avg  50.9%   peak  53.5%
