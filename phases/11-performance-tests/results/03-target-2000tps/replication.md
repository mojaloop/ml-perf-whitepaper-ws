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

-----
500000 at 1100tps

    ✗ ALS_FSPIOP_GET_PARTIES_RESPONSE_IS_200
      ↳  99% — ✓ 500483 / ✗ 18
     ✗ QUOTES_FSPIOP_POST_QUOTES_RESPONSE_IS_200
      ↳  99% — ✓ 500482 / ✗ 1
     ✗ TRANSFERS_FSPIOP_POST_TRANSFERS_RESPONSE_IS_200
      ↳  99% — ✓ 500286 / ✗ 196

   ✓ checks.........................: 99.98%  ✓ 1501251     ✗ 215
   ✓ completed_transactions.........: 500286  1034.9332/s
     data_received..................: 3.3 GB  6.8 MB/s
     data_sent......................: 1.4 GB  2.9 MB/s
   ✓ discovery_time.................: avg=44.55ms  min=1ms      med=21ms     max=3.94s    p(90)=57ms     p(95)=90ms
   ✓ e2e_time.......................: avg=674.68ms min=240ms    med=642ms    max=5.55s    p(90)=853ms    p(95)=952ms
     failed_transactions............: 215     0.444767/s
     http_req_blocked...............: avg=788.46µs min=119.96µs med=215.46µs max=1.01s    p(90)=834.93µs p(95)=1.65ms
     http_req_connecting............: avg=622.16µs min=106.33µs med=187.26µs max=1.01s    p(90)=672.42µs p(95)=1.49ms
   ✓ http_req_duration..............: avg=227.95ms min=290.02µs med=122.45ms max=30.05s   p(90)=552.83ms p(95)=623.55ms
       { expected_response:true }...: avg=223.74ms min=1.23ms   med=122.43ms max=5.41s    p(90)=552.7ms  p(95)=623.24ms
     http_req_failed................: 0.01%   ✓ 215         ✗ 1501251
     http_req_receiving.............: avg=418.89µs min=10.96µs  med=33.84µs  max=440.48ms p(90)=89.88µs  p(95)=870.87µs
     http_req_sending...............: avg=170.87µs min=6.25µs   med=23.15µs  max=466.95ms p(90)=47.92µs  p(95)=166.72µs
     http_req_tls_handshaking.......: avg=0s       min=0s       med=0s       max=0s       p(90)=0s       p(95)=0s
     http_req_waiting...............: avg=227.36ms min=203.21µs med=121.89ms max=30.05s   p(90)=552.28ms p(95)=622.86ms
     http_reqs......................: 1501466 3106.057359/s
     iteration_duration.............: avg=687.44ms min=15.62ms  med=642.73ms max=31.28s   p(90)=853.65ms p(95)=954.26ms
     iterations.....................: 500501  1035.377967/s
   ✓ quote_time.....................: avg=124.8ms  min=36ms     med=119ms    max=1.19s    p(90)=199ms    p(95)=222ms
   ✓ success_rate...................: 99.95%  ✓ 500286      ✗ 215
   ✓ transfer_time..................: avg=504.83ms min=170ms    med=489ms    max=5.41s    p(90)=654ms    p(95)=715ms
     vus............................: 40      min=0         max=1437
     vus_max........................: 5000    min=5000      max=5000


=== K6 TEST SUMMARY ===
{
  "test_config": {
    "target_transactions": 500000,
    "target_tps": 1100,
    "duration": 455,
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
    "completed_transactions": 500286,
    "success_rate": 99.95704304287104,
    "actual_tps": 1099.5296703296704,
    "e2e_time_p95": 952,
    "http_req_duration_p95": 623.55858325
  },
  "status": "PASSED"
}
