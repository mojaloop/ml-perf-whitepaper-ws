#!/usr/bin/env bash

INTERVAL=30
USER=ubuntu

NODES=(
  sw1-n1
  sw1-n2
  sw1-n3
  sw1-n4
  sw1-kafka-n1
  sw1-mysql-n1
  fsp201
  fsp202
  fsp203
  fsp204
  fsp205
  fsp206
  fsp207
  fsp208
)

_ssh_stats() {
  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=8 \
    -o ConnectionAttempts=1 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    "${USER}@${1}" \
    'read l1 l5 l15 _ < /proc/loadavg
     mem_total=$(awk "/MemTotal:/ {print \$2}" /proc/meminfo)
     mem_available=$(awk "/MemAvailable:/ {print \$2}" /proc/meminfo)
     mem_used=$((mem_total - mem_available))
     mem_pct=$(awk -v u="$mem_used" -v t="$mem_total" "BEGIN { printf \"%.1f\", (u/t)*100 }")
     mem_used_gb=$(awk -v u="$mem_used" "BEGIN { printf \"%.1f\", u/1024/1024 }")
     mem_total_gb=$(awk -v t="$mem_total" "BEGIN { printf \"%.1f\", t/1024/1024 }")
     echo "$l1 $l5 $l15 $mem_pct $mem_used_gb/$mem_total_gb"' \
    2>/dev/null
}

get_stats() {
  local node="$1"
  local result

  result=$(_ssh_stats "$node")
  # one retry on failure — handles transient packet loss / slow sshd under load
  if [ -z "$result" ]; then
    sleep 1
    result=$(_ssh_stats "$node")
  fi

  if [ -n "$result" ]; then
    echo "$node $result"
  else
    echo "$node ERROR"
  fi
}

while true; do
  start_time=$(date +%s)
  tmpfile=$(mktemp)

  echo "===== $(date '+%Y-%m-%d %H:%M:%S') ====="
  echo "NODE            LOAD1 LOAD5 LOAD15 MEM% USED/TOTAL(GB)"

  for node in "${NODES[@]}"; do
    (
      get_stats "$node"
    ) >> "$tmpfile" &
  done

  wait

  sort "$tmpfile" | awk '
    $2 == "ERROR" {
      printf "%-15s %-5s\n", $1, $2
      next
    }
    {
      printf "%-15s %-5s %-5s %-6s %-5s %s\n", $1, $2, $3, $4, $5, $6
    }
  '

  rm -f "$tmpfile"
  echo ""

  end_time=$(date +%s)
  elapsed=$((end_time - start_time))
  sleep_time=$((INTERVAL - elapsed))

  if [ "$sleep_time" -gt 0 ]; then
    sleep "$sleep_time"
  fi
done