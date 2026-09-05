#!/bin/bash
set -euo pipefail

policy=$1
expected=$2
log=$3
shift 3

mkdir -p "$(dirname "$log")"
status=0
"$@" >"$log" 2>&1 || status=$?
cat "$log"

case "$policy" in
  positive)
    if (( status != 0 )) \
        || ! grep -Fxq "PASS: $expected" "$log" \
        || grep -Eq 'Dynamic assertion failed|Assertion failed|(^|[[:space:]])Error:|(^|[[:space:]])FATAL([ :]|$)|^FAIL([ :]|$)' "$log"; then
      echo "FAIL: $expected" >&2
      exit 1
    fi
    ;;
  expected)
    if ! grep -Fq 'Dynamic assertion failed' "$log" \
        || ! grep -Fxq "$expected" "$log"; then
      echo "expected runtime diagnostic not observed: $expected" >&2
      exit 1
    fi
    ;;
  *)
    echo "unknown test policy: $policy" >&2
    exit 1
    ;;
esac
