#!/usr/bin/env bash
set -euo pipefail

ROWS=${BENCH_ROWS:-1000}
ITERS=${BENCH_ITERS:-200}
WARMUP=${BENCH_WARMUP:-20}

run_case() {
  local name=$1
  shift
  echo ""
  echo "=== ${name} ==="
  local envs=("SQLITEJSONB_DIRECT_BUILDER=${SQLITEJSONB_DIRECT_BUILDER:-1}" \
    "SQLITEJSONB_UNSAFE_UTF8=${SQLITEJSONB_UNSAFE_UTF8:-1}")

  env "${envs[@]}" "$@" swift run -c release SQLiteJSONBBenchmark --iterations "$ITERS" --rows "$ROWS" --warmup "$WARMUP"
}

run_case "baseline (swift fast)" \
  SQLITEJSONB_DIRECT_BUILDER=1 \
  SQLITEJSONB_UNSAFE_UTF8=1

run_case "direct builder off" \
  SQLITEJSONB_DIRECT_BUILDER=0

run_case "unsafe UTF8 off" \
  SQLITEJSONB_UNSAFE_UTF8=0
