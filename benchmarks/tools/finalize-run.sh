#!/usr/bin/env bash
# Parse a test run's k6 log and write summary.json + MANIFEST.md into its
# results/<UTC>/ dir, so recording a run is one command.
#
# Usage:
#   tools/finalize-run.sh <version>/<mtls>/<tps>            # newest results/<UTC>
#   tools/finalize-run.sh <version>/<mtls>/<tps> <run-id>   # a specific results dir
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
CELL_ARG="${1:?usage: finalize-run.sh <version>/<mtls>/<tps> [run-id]}"
CELL_REL="${CELL_ARG#benchmarks/}"; CELL_REL="${CELL_REL%/}"
IFS='/' read -r VERSION MTLS TPS <<<"$CELL_REL"

RESBASE="$ROOT/$CELL_REL/results"
RUNID="${2:-$(ls -1 "$RESBASE" 2>/dev/null | sort | tail -1 || true)}"
[[ -n "$RUNID" && -d "$RESBASE/$RUNID" ]] || { echo "ERROR: no results dir under $RESBASE" >&2; exit 1; }
R="$RESBASE/$RUNID"

LOG="$(grep -lF 'completed_transactions' "$R"/*.log 2>/dev/null | head -1 || true)"
[[ -n "$LOG" ]] || { echo "ERROR: no k6 summary found in $R/*.log" >&2; exit 1; }

num_key() { grep -hoE "\"$1\": *[0-9.]+" "$R"/*.log | tail -1 | grep -oE '[0-9.]+$'; }
to_ms() {   # "53ms" | "1.2s" -> integer ms ; empty -> null
  local v="$1"; [[ -z "$v" ]] && { echo null; return; }
  case "$v" in
    *ms) awk -v x="${v%ms}" 'BEGIN{printf "%d", x+0.5}';;
    *s)  awk -v x="${v%s}"  'BEGIN{printf "%d", x*1000+0.5}';;
    *)   echo "$v";;
  esac
}
p99() { grep -hE "${1}\.{2,}" "$R"/*.log | grep -oE 'p\(99\)=[0-9.]+(ms|s)' | tail -1 | sed -E 's/p\(99\)=//'; }

ATPS_RAW="$(num_key actual_tps)"; SUCC_RAW="$(num_key success_rate)"; COMP="$(num_key completed_transactions)"
STATUS_RAW="$(grep -hoE '"status": *"[A-Z]+"' "$R"/*.log | tail -1 | grep -oE '[A-Z]+' || true)"
case "$STATUS_RAW" in PASSED) STATUS=PASS;; FAILED) STATUS=FAIL;; "") STATUS=UNKNOWN;; *) STATUS="$STATUS_RAW";; esac

ATPS="$(awk -v x="${ATPS_RAW:-0}" 'BEGIN{printf "%.1f", x}')"
SUCC="$(awk -v x="${SUCC_RAW:-0}" 'BEGIN{printf "%.2f", x}')"
D_P99="$(to_ms "$(p99 discovery_time)")"; Q_P99="$(to_ms "$(p99 quote_time)")"
T_P99="$(to_ms "$(p99 transfer_time)")"; E_P99="$(to_ms "$(p99 e2e_time)")"
GIT_SHA="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"

cat > "$R/summary.json" <<JSON
{
  "version": "$VERSION",
  "mtls": "${MTLS#mtls-}",
  "tps": ${TPS%tps},
  "run_id": "$RUNID",
  "git_sha": "$GIT_SHA",
  "chart_version": "",
  "status": "$STATUS",
  "actual_tps": $ATPS,
  "success_pct": $SUCC,
  "transactions": ${COMP:-null},
  "p99_ms": { "discovery": $D_P99, "quote": $Q_P99, "transfer": $T_P99, "e2e": $E_P99 },
  "notes": "Auto-generated from $(basename "$LOG") by finalize-run.sh"
}
JSON

pass_mark() { [[ "$1" == PASS ]] && echo "✅" || echo "❌"; }
cat > "$R/MANIFEST.md" <<MD
# Run MANIFEST

| Field | Value |
|-------|-------|
| Version | $VERSION |
| mTLS | ${MTLS#mtls-} |
| Target TPS | ${TPS%tps} |
| Run ID (UTC) | $RUNID |
| Git SHA | \`$GIT_SHA\` |

## Result

| Metric | Value |
|--------|-------|
| Status | **$STATUS** $(pass_mark "$STATUS") |
| Actual TPS | $ATPS |
| Completed transactions | ${COMP:-—} |
| Success % | $SUCC% |
| e2e p99 | ${E_P99} ms |
| discovery p99 | ${D_P99} ms |
| quote p99 | ${Q_P99} ms |
| transfer p99 | ${T_P99} ms |

Metrics auto-extracted from \`$(basename "$LOG")\`. Add chart version, grafana/, metrics/ as needed.
MD

echo "$R"
echo "  status=$STATUS  tps=$ATPS  success=$SUCC%  e2e_p99=${E_P99}ms  (disc=$D_P99 quote=$Q_P99 transfer=$T_P99)"
echo "wrote summary.json + MANIFEST.md — update the Results table in benchmarks/README.md"
