#!/bin/bash
# Run financial native q/l scripts with the lv1 "l" engine.
#
# Usage from any directory:
#   bash aquery-master/src/test/financial/l_query/L_comparison/q_query/base_l_query.sh
#   bash aquery-master/src/test/financial/l_query/L_comparison/q_query/base_l_query.sh Q0.q:Q0 Q1.q:Q1
#
# Environment:
#   L_BIN=/usr/local/bin/l        Override l executable.
#   ITERATIONS=11                 Override repetitions.
#   LOAD_SCRIPT=load.q            Override data load script.
#   RESULTS_DIR=./results         Override output directory, relative to this script.
#   OUT_CSV=financial_l_query.csv Override output CSV filename.
#   PURGE_CACHE=1                 Run PURGE_CMD before each iteration.
#   PURGE_CMD=/usr/sbin/purge     Override cache purge command.
#   POST_PURGE_SLEEP=0            Seconds to wait after purge, not included in timing.

set -euo pipefail
TIMEFORMAT='%R %U %S'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITERATIONS="${ITERATIONS:-11}"
L_BIN="${L_BIN:-l}"
LOAD_SCRIPT="${LOAD_SCRIPT:-load_10_5.q}"
RESULTS_DIR="${RESULTS_DIR:-./results}"
OUT_CSV="${OUT_CSV:-financial_l_query.csv}"
PURGE_CACHE="${PURGE_CACHE:-0}"
PURGE_CMD="${PURGE_CMD:-/usr/sbin/purge}"
POST_PURGE_SLEEP="${POST_PURGE_SLEEP:-0}"

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
  echo "Error: load script not found: $SCRIPT_DIR/$LOAD_SCRIPT" >&2
  exit 1
fi

if ! command -v "$L_BIN" >/dev/null 2>&1; then
  echo "Error: l executable not found: $L_BIN" >&2
  exit 1
fi

mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/$OUT_CSV"

if [[ ! -f "$RESULTS_FILE" ]]; then
  echo "dbms,label,iteration,execution_time,response_time" > "$RESULTS_FILE"
fi

SUMMARY_FILE="$RESULTS_DIR/${OUT_CSV%.csv}_summary.csv"
if [[ ! -f "$SUMMARY_FILE" ]]; then
  echo "dbms,label,iterations,median_response_time" > "$SUMMARY_FILE"
fi

run_once() {
  local label="$1"
  local query_script="$2"
  local iteration="$3"

  local runner_base runner_file stdout_log stderr_log l_pid
  runner_base="$(mktemp "/tmp/financial_l_${label}_${iteration}_XXXXXX")"
  runner_file="${runner_base}.q"
  mv "$runner_base" "$runner_file"
  stdout_log="${runner_file}.stdout.log"
  stderr_log="${runner_file}.stderr.log"
  l_pid=""

  cleanup() {
    kill_process_tree "$l_pid"
    rm -f "$runner_file" "$stdout_log" "$stderr_log"
  }
  trap cleanup EXIT

  {
    printf '\\d .kdb\n'
    printf '\\d .\n'
    printf '\\l %s\n' "$LOAD_SCRIPT"
    printf '\\l %s\n' "$query_script"
    printf '\\\\\n'
  } > "$runner_file"

  purge_cache_if_requested

  set +e
  { time "$L_BIN" < "$runner_file" > "$stdout_log"; } 2> "$stderr_log" &
  l_pid=$!
  wait "$l_pid"
  local l_status=$?
  kill_process_tree "$l_pid"
  l_pid=""
  set -e

  if [[ $l_status -ne 0 ]]; then
    echo "Error: l execution failed for ${label} iteration ${iteration}." >&2
    echo "--- l stdout ---" >&2
    cat "$stdout_log" >&2 || true
    echo "--- l stderr ---" >&2
    cat "$stderr_log" >&2 || true
    exit 1
  fi

  local time_line real_time user_time sys_time execution_time
  time_line="$(grep -E '^[0-9.]+ +[0-9.]+ +[0-9.]+' "$stderr_log" | tail -n 1 || true)"
  if [[ -z "$time_line" ]]; then
    echo "Error: no timing information found for ${label} iteration ${iteration}." >&2
    echo "--- l stdout ---" >&2
    cat "$stdout_log" >&2 || true
    echo "--- l stderr ---" >&2
    cat "$stderr_log" >&2 || true
    exit 1
  fi

  read -r real_time user_time sys_time <<< "$time_line"
  real_time="$(printf "%.6f" "$real_time")"
  user_time="$(printf "%.6f" "$user_time")"
  sys_time="$(printf "%.6f" "$sys_time")"
  execution_time="$(awk -v u="$user_time" -v s="$sys_time" 'BEGIN { printf "%.6f", u + s }')"

  real_time="$(pad0 "$real_time")"
  execution_time="$(pad0 "$execution_time")"

  echo "ran l ${label} ${iteration}"
  echo "${execution_time}            ${real_time}"
  echo "l,${label},${iteration},${execution_time},${real_time}" >> "$RESULTS_FILE"
  RUN_RESPONSE_TIME="$real_time"

  cleanup
  trap - EXIT
}

median_response_time() {
  sort -n | awk '
    NF {
      vals[++n] = $1
    }
    END {
      if (n == 0) {
        exit 1
      }
      if (n % 2) {
        median = vals[(n + 1) / 2]
      } else {
        median = (vals[n / 2] + vals[n / 2 + 1]) / 2
      }
      printf "%.6f", median
    }
  '
}

run_label() {
  local query_script="$1"
  local label="$2"

  echo "L FINANCIAL RUN STARTED"
  echo "Load Script: $LOAD_SCRIPT"
  echo "Query Script: $query_script"
  echo "Label: $label"
  echo "Execution Time      Response Time"

  local i median
  local response_times=()
  for i in $(seq 1 "$ITERATIONS"); do
    run_once "$label" "$query_script" "$i"
    response_times+=("$RUN_RESPONSE_TIME")
  done

  median="$(printf '%s\n' "${response_times[@]}" | median_response_time)"
  median="$(pad0 "$median")"
  echo "Median Response Time: $median"
  echo "l,${label},${ITERATIONS},${median}" >> "$SUMMARY_FILE"

  echo "L FINANCIAL RUN DONE"
}

QUERY_SPECS=()
while IFS= read -r spec; do
  QUERY_SPECS+=("$spec")
done < <(make_query_specs "$@")

if [[ ${#QUERY_SPECS[@]} -eq 0 ]]; then
  echo "Error: no query scripts matched Q[0-9]*_[0-9]*.q in $SCRIPT_DIR" >&2
  exit 1
fi

for spec in "${QUERY_SPECS[@]}"; do
  if [[ "$spec" == *:* ]]; then
    query_path="${spec%%:*}"
    query_label="${spec#*:}"
  else
    query_path="$spec"
    query_label="$(basename "$spec" .q)"
  fi

  if [[ ! -f "$query_path" ]]; then
    echo "Error: query script not found: $query_path" >&2
    exit 1
  fi

  run_label "$query_path" "$query_label"
done

echo "Results saved to: $RESULTS_FILE"
echo "Summary saved to: $SUMMARY_FILE"
