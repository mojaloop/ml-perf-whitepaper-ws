#!/usr/bin/env bash
# Steady-state measurement report for a k6 run, from Prometheus.
#
# Methodology: the measurement interval excludes a fixed warm-up after run
# start and a fixed drain before run end (TPC/SPEC-style steady-state
# characterization). The k6 end-of-run summary remains the full-run aggregate;
# this report is the steady-state complement. Always publish both.
#
# Usage:
#   steady-state.sh                          # auto-detect the most recent run
#   steady-state.sh <start-iso> <end-iso>    # explicit run window (UTC, e.g. 2026-07-07T00:54:00Z)
#
# Options (env):
#   PROM=http://localhost:9090   Prometheus base URL (port-forward)
#   WARMUP=300                   seconds trimmed after run start
#   DRAIN=120                    seconds trimmed before run end
#
# Requires: curl, jq. Percentiles come from k6 native histograms
# (k6_*_seconds), so the k6 TestRun must have rwTrendAsNativeHistogram: true.
set -euo pipefail

PROM="${PROM:-http://localhost:9090}"
WARMUP="${WARMUP:-300}"
DRAIN="${DRAIN:-120}"

q()  { curl -sf "$PROM/api/v1/query" --data-urlencode "query=$1" | jq -r "${2:-.data.result[0].value[1]}"; }
qr() { curl -sf "$PROM/api/v1/query_range" --data-urlencode "query=$1" --data-urlencode "start=$2" --data-urlencode "end=$3" --data-urlencode "step=$4"; }

iso_to_epoch() {
  date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null || date -u -d "$1" +%s
}
epoch_to_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

# ---- run window ------------------------------------------------------------
if [ $# -ge 2 ]; then
  RUN_START=$(iso_to_epoch "$1"); RUN_END=$(iso_to_epoch "$2")
else
  # Auto-detect: last contiguous stretch of k6 iteration activity in 12h.
  NOW=$(date +%s)
  MAP=$(qr 'histogram_count(sum(rate(k6_e2e_time_seconds[1m])))' $((NOW-43200)) "$NOW" 60 \
    | jq -r '.data.result[0].values[]? | "\(.[0]) \(.[1])"')
  [ -n "$MAP" ] || { echo "ERROR: no k6 activity found in the last 12h (is the port-forward up?)" >&2; exit 1; }
  # Note: Prometheus omits samples for idle periods (no zero rows), so a gap
  # in timestamps IS the run boundary; keep the LAST contiguous stretch.
  read -r RUN_START RUN_END < <(awk '
    $2 > 1 { if (last == "" || $1 > last + 120) start = $1; last = $1 }
    END { print start, last }' <<<"$MAP")
  [ -n "$RUN_START" ] && [ "$RUN_START" != "0" ] || { echo "ERROR: could not detect a run window" >&2; exit 1; }
fi

SS_START=$((RUN_START + WARMUP))
SS_END=$((RUN_END - DRAIN))
W=$((SS_END - SS_START))
[ "$W" -gt 0 ] || { echo "ERROR: steady window is empty (run shorter than WARMUP+DRAIN?)" >&2; exit 1; }

pct() { q "histogram_quantile($1, sum(rate(k6_${2}_seconds[${W}s] @ $SS_END)))" | awk '{printf "%d", $1*1000}'; }
sdev() { q "histogram_stddev(sum(rate(k6_${1}_seconds[${W}s] @ $SS_END)))" | awk '{printf "%d", $1*1000}'; }
havg() { q "histogram_avg(sum(rate(k6_${1}_seconds[${W}s] @ $SS_END)))" | awk '{printf "%d", $1*1000}'; }
cnt() { q "histogram_count(sum(increase(k6_${1}_seconds[${W}s] @ $SS_END)))" | awk '{printf "%d", $1}'; }

echo "# Steady-state report"
echo
echo "run window:     $(epoch_to_iso "$RUN_START") .. $(epoch_to_iso "$RUN_END")  ($((RUN_END-RUN_START))s)"
echo "steady window:  $(epoch_to_iso "$SS_START") .. $(epoch_to_iso "$SS_END")  (${W}s; warm-up ${WARMUP}s + drain ${DRAIN}s excluded)"
echo

N=$(cnt e2e_time)
echo "measured transfers (steady): $N"
echo
echo "| metric | p50 | p95 | p99 | avg | stddev |"
echo "|---|---|---|---|---|---|"
for m in e2e_time transfer_time quote_time discovery_time; do
  echo "| $m | $(pct 0.50 $m)ms | $(pct 0.95 $m)ms | $(pct 0.99 $m)ms | $(havg $m)ms | $(sdev $m)ms |"
done
echo

# ---- validity gate (same steady window) ------------------------------------
echo "## Validity gate (kafka topic rates, steady window)"
TOPICS=$(q "sum by (topic) (increase(kafka_server_brokertopicmetrics_messagesinpersec_count{topic=~\"topic-transfer-prepare|topic-transfer-fulfil|topic-notification-event|topic-transfer-position-batch|topic-quotes-post\"}[${W}s] @ $SS_END))" \
  '.data.result[] | "\(.metric.topic) \(.value[1])"')
echo "$TOPICS" | awk -v w="$W" '{printf "%-38s %8.1f/s\n", $1":", $2/w}'
PREP=$(echo "$TOPICS" | awk '$1=="topic-transfer-prepare"{print $2}')
FUL=$(echo "$TOPICS" | awk '$1=="topic-transfer-fulfil"{print $2}')
NOTIF=$(echo "$TOPICS" | awk '$1=="topic-notification-event"{print $2}')
awk -v p="$PREP" -v f="$FUL" -v n="$NOTIF" 'BEGIN {
  ok = (f > p*0.98 && f < p*1.02 && n > p*1.96 && n < p*2.04)
  printf "gate: fulfil/prepare=%.3f  notif/prepare=%.3f  -> %s\n", f/p, n/p, (ok ? "PASS" : "FAIL — run under-processed, do NOT publish")
}'
echo

# ---- node CPU (steady window) ----------------------------------------------
echo "## Switch/backing node CPU (steady window)"
NAMES=$(q "node_uname_info @ $SS_END" '.data.result[] | "\(.metric.instance) \(.metric.nodename)"')
AVG=$(q "100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[${W}s] @ $SS_END)))" '.data.result[] | "\(.metric.instance) \(.value[1])"')
PEAK=$(q "100 * max_over_time((1 - avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[2m])))[${W}s:2m] @ $SS_END)" '.data.result[] | "\(.metric.instance) \(.value[1])"')
join <(echo "$NAMES" | sort) <(echo "$AVG" | sort) | join - <(echo "$PEAK" | sort) \
  | awk '$2 ~ /^sw1-/ {printf "%-16s avg %5.1f%%   peak %5.1f%%\n", $2, $3, $4}' | sort
