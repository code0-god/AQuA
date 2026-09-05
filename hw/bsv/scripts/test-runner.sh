#!/bin/bash
set -euo pipefail

runner="$(dirname "$0")/run-test.sh"
log="$1/runner-self-test.log"
run() { bash "$runner" "$1" "$2" "$log" bash -c "$3"; }
reject() {
  if run "$@"; then
    echo "runner accepted invalid output" >&2
    exit 1
  fi
}

run positive mkTbRunner 'printf "PASS: mkTbRunner\n"'
reject positive mkTbRunner ':'
reject positive mkTbRunner 'printf "PASS: mkTbOther\n"'
reject positive mkTbRunner 'printf "PASS: mkTbRunner\n"; exit 1'
for diagnostic in 'Dynamic assertion failed' 'Assertion failed' 'Error:' 'FATAL' 'FAIL:'; do
  reject positive mkTbRunner "printf 'PASS: mkTbRunner\n$diagnostic\n'"
done
run positive mkTbRunner 'printf "expected error count is zero\nPASS: mkTbRunner\n"'
run expected 'accumulator addition overflow' \
  'printf "Dynamic assertion failed\naccumulator addition overflow\n"'
reject expected 'accumulator addition overflow' \
  'printf "Dynamic assertion failed\nother assertion\n"'
echo "PASS: test-runner"
