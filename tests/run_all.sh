#!/usr/bin/env bash
# run_all.sh — Top-level test runner for claude-config
#
# Runs all test suites and reports aggregate pass/fail counts.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOTAL_PASS=0
TOTAL_FAIL=0
SUITES_PASSED=0
SUITES_FAILED=0

echo ""
echo "################################################################"
echo "  claude-config — Full Test Suite"
echo "################################################################"

run_suite() {
  local name="$1"
  local cmd="$2"
  echo ""
  echo "================================================================"
  echo "  Running: $name"
  echo "================================================================"

  set +e
  eval "$cmd"
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    SUITES_PASSED=$((SUITES_PASSED + 1))
    echo "  >>> $name: ALL PASSED"
  else
    SUITES_FAILED=$((SUITES_FAILED + 1))
    TOTAL_FAIL=$((TOTAL_FAIL + rc))
    echo "  >>> $name: $rc FAILURES"
  fi
}

# 1. compose.sh unit tests
run_suite "test_compose.sh" "bash '$SCRIPT_DIR/test_compose.sh'"

# 2. Structural integrity tests
run_suite "test_structure.sh" "bash '$SCRIPT_DIR/test_structure.sh'"

# 3. validate_gate.py unit tests
run_suite "test_validate_gate.py" "python -m pytest '$SCRIPT_DIR/test_validate_gate.py' -v --tb=short 2>&1"

# 4. validate_gate.py consumer-context tests
run_suite "test_gate_consumer.py" "python -m pytest '$SCRIPT_DIR/test_gate_consumer.py' -v --tb=short 2>&1"

# 5. Cross-repo sync simulation
run_suite "test_sync_workflow.sh" "bash '$SCRIPT_DIR/test_sync_workflow.sh'"

echo ""
echo "################################################################"
echo "  SUMMARY"
echo "################################################################"
echo ""
echo "  Suites passed: $SUITES_PASSED"
echo "  Suites failed: $SUITES_FAILED"
echo "  Total failure count: $TOTAL_FAIL"
echo ""
if [[ $SUITES_FAILED -eq 0 ]]; then
  echo "  RESULT: ALL SUITES PASSED"
  echo ""
  echo "################################################################"
  exit 0
else
  echo "  RESULT: $SUITES_FAILED SUITE(S) FAILED"
  echo ""
  echo "################################################################"
  exit 1
fi
