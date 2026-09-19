#!/bin/bash
# Run financial AQuery q scripts after loading data, or measure load-only time.
#
# Usage from any directory:
#   bash aquery-master/src/test/financial/l_query/L_comparison/q_query/base_aquery.sh
#   bash aquery-master/src/test/financial/l_query/L_comparison/q_query/base_aquery.sh Q0.q:Q0 Q1.q:Q1
#
# Environment:
#   Q_BIN=/path/to/q              Override q executable.
#   SCRIPT_BIN=/usr/bin/script    Override script executable.
#   ITERATIONS=11                 Override repetitions.
#   USE_SCRIPT=1                  Run q through script(1); set 0 to run q directly.
#   PURGE_CACHE=1                 Run PURGE_CMD before each iteration.
#   PURGE_CMD=/usr/sbin/purge     Override cache purge command.
#   LOAD_SCRIPT=load_10_5.q       Override data load script.
#   RESULTS_DIR=./results         Override output directory, relative to current directory.
#   OUT_CSV=financial_aquery.csv  Override output CSV filename.
#   POST_PURGE_SLEEP=0            Seconds to wait after purge, not included in timing.

set -euo pipefail
TIMEFORMAT='%R %U %S'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITERATIONS="${ITERATIONS:-11}"
Q_BIN="${Q_BIN:-q}"
SCRIPT_BIN="${SCRIPT_BIN:-script}"
USE_SCRIPT="${USE_SCRIPT:-1}"
PURGE_CACHE="${PURGE_CACHE:-0}"
PURGE_CMD="${PURGE_CMD:-/usr/sbin/purge}"
POST_PURGE_SLEEP="${POST_PURGE_SLEEP:-0}"
RESULTS_DIR="${RESULTS_DIR:-./results}"
LOAD_SCRIPT="${LOAD_SCRIPT:-load_10_5.q}"
OUT_CSV="${OUT_CSV:-financial_aquery.csv}"

cd "$SCRIPT_DIR"

pad0() {
  local val="$1"
  if [[ "$val" =~ ^\.[0-9] ]]; then
    echo "0$val"
  else
    echo "$val"
  fi
}

make_query_specs() {
  if [[ $# -gt 0 ]]; then
    printf '%s\n' "$@"
    return
  fi

  shopt -s nullglob
  local f
  for f in Q[0-9].q; do
    printf '%s:%s\n' "$f" "${f%.q}"
  done
}

median() {
  local -a values=("$@")
  local count="${#values[@]}"

  if [[ "$count" -eq 0 ]]; then
    echo ""
    return
  fi

  printf '%s\n' "${values[@]}" |
    sort -n |
    awk -v n="$count" '
      {
        a[NR]=$1
      }
      END {
        if (n % 2) {
          printf "%.6f", a[(n + 1) / 2]
        } else {
          printf "%.6f", (a[n / 2] + a[n / 2 + 1]) / 2
        }
      }'
}

descendant_pids() {
  local pid="$1"
  local child

  pgrep -P "$pid" 2>/dev/null | while read -r child; do
    descendant_pids "$child"
    echo "$child"
  done
}

kill_process_tree() {
  local pid="${1:-}"
  [[ -z "$pid" ]] && return 0

  local pids=()
  while IFS= read -r child; do
    [[ -n "$child" ]] && pids+=("$child")
  done < <(descendant_pids "$pid")

  if kill -0 "$pid" 2>/dev/null; then
    pids+=("$pid")
  fi

  [[ ${#pids[@]} -eq 0 ]] && return 0

  kill "${pids[@]}" 2>/dev/null || true
  sleep 0.1
  kill -9 "${pids[@]}" 2>/dev/null || true
}

purge_cache_if_requested() {
  [[ "$PURGE_CACHE" == "1" ]] || return 0

  local purge_bin="${PURGE_CMD%% *}"
  if ! command -v "$purge_bin" >/dev/null 2>&1; then
    echo "Error: purge command not found: $purge_bin" >&2
    exit 1
  fi

  echo "purging filesystem cache with: $PURGE_CMD"
  if ! bash -c "$PURGE_CMD"; then
    echo "Error: cache purge failed. Try running with a command that has permission, e.g. PURGE_CMD='sudo /usr/sbin/purge'." >&2
    exit 1
  fi

  if [[ "$POST_PURGE_SLEEP" != "0" ]]; then
    echo "waiting ${POST_PURGE_SLEEP}s after cache purge"
    sleep "$POST_PURGE_SLEEP"
  fi
}

if [[ ! -f "$LOAD_SCRIPT" ]]; then
  echo "Error: load script not found: $LOAD_SCRIPT"
  exit 1
fi

if ! command -v "$Q_BIN" >/dev/null 2>&1; then
  echo "Error: q executable not found: $Q_BIN"
  exit 1
fi

if [[ "$USE_SCRIPT" == "1" ]] && ! command -v "$SCRIPT_BIN" >/dev/null 2>&1; then
  echo "Error: script executable not found: $SCRIPT_BIN"
  exit 1
fi

mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/$OUT_CSV"

if [[ ! -f "$RESULTS_FILE" ]]; then
  echo "dbms,label,iteration,execution_time,response_time" > "$RESULTS_FILE"
fi

run_once() {
  local label="$1"
  local query_script="${2:-}"
  local iteration="$3"

  local runner_base runner_file stdout_log stderr_log q_pid
  runner_base="$(mktemp "/tmp/financial_aquery_${iteration}_XXXXXX")"
  runner_file="${runner_base}.q"
  mv "$runner_base" "$runner_file"
  stdout_log="${runner_file}.stdout.log"
  stderr_log="${runner_file}.stderr.log"
  q_pid=""

  cleanup() {
    kill_process_tree "$q_pid"
    rm -f "$runner_file" "$stdout_log" "$stderr_log"
  }
  trap cleanup EXIT

  if [[ -n "$query_script" ]]; then
    printf '\\l %s\n\\l %s\nexit 0\n' "$LOAD_SCRIPT" "$query_script" > "$runner_file"
  else
    printf '\\l %s\nexit 0\n' "$LOAD_SCRIPT" > "$runner_file"
  fi

  purge_cache_if_requested

  set +e
  if [[ "$USE_SCRIPT" == "1" ]]; then
    { time "$SCRIPT_BIN" -q /dev/null "$Q_BIN" < "$runner_file" > "$stdout_log"; } 2> "$stderr_log" &
  else
    { time "$Q_BIN" < "$runner_file" > "$stdout_log"; } 2> "$stderr_log" &
  fi
  q_pid=$!
  wait "$q_pid"
  local q_status=$?
  kill_process_tree "$q_pid"
  q_pid=""
  set -e

  if [[ $q_status -ne 0 ]]; then
    echo "Error: q execution failed."
    echo "--- q stdout ---"
    cat "$stdout_log" || true
    echo "--- q stderr ---"
    cat "$stderr_log" || true
    exit 1
  fi

  local time_line real_time user_time sys_time execution_time
  time_line=$(grep -E '^[0-9.]+ +[0-9.]+ +[0-9.]+' "$stderr_log" | tail -n 1 || true)
  if [[ -z "$time_line" ]]; then
    echo "Error: no timing information found in stderr log"
    echo "--- q stdout ---"
    cat "$stdout_log" || true
    echo "--- q stderr ---"
    cat "$stderr_log" || true
    exit 1
  fi

  read real_time user_time sys_time <<< "$time_line"

  real_time=$(printf "%.6f" "$real_time")
  user_time=$(printf "%.6f" "$user_time")
  sys_time=$(printf "%.6f" "$sys_time")
  execution_time=$(echo "scale=6; $user_time + $sys_time" | bc)

  real_time=$(pad0 "$real_time")
  execution_time=$(pad0 "$execution_time")

  echo "ran aquery ${label} ${iteration}"
  echo "${execution_time}            ${real_time}"
  echo "aquery,${label},${iteration},${execution_time},${real_time}" >> "$RESULTS_FILE"
  RUN_ONCE_RESPONSE_TIME="$real_time"

  cleanup
  trap - EXIT
}

run_label() {
  local label="$1"
  local query_script="${2:-}"

  echo "AQUERY FINANCIAL RUN STARTED"
  echo "Load Script: $LOAD_SCRIPT"
  if [[ -n "$query_script" ]]; then
    echo "Query Script: $query_script"
  else
    echo "Query Script: <load only>"
  fi
  echo "Label: $label"
  echo "Execution Time      Response Time"

  local response_times=()
  for i in $(seq 1 "$ITERATIONS"); do
    run_once "$label" "$query_script" "$i"
    response_times+=("$RUN_ONCE_RESPONSE_TIME")
  done

  local median_response_time
  median_response_time="$(pad0 "$(median "${response_times[@]}")")"
  echo "Median Response Time: ${median_response_time}"
  echo "AQUERY FINANCIAL RUN DONE"
}

QUERY_SPECS=()
while IFS= read -r spec; do
  QUERY_SPECS+=("$spec")
done < <(make_query_specs "$@")

if [[ ${#QUERY_SPECS[@]} -eq 0 ]]; then
  run_label "load_only"
else
  for spec in "${QUERY_SPECS[@]}"; do
    if [[ "$spec" == *:* ]]; then
      query_path="${spec%%:*}"
      query_label="${spec#*:}"
    else
      query_path="$spec"
      query_label="$(basename "$spec")"
    fi

    if [[ ! -f "$query_path" ]]; then
      echo "Error: query script not found: $query_path"
      exit 1
    fi

    run_label "$query_label" "$query_path"
  done
fi

echo "Results saved to: $RESULTS_FILE"
