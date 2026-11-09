#!/usr/bin/env bash
# Single Mac verification entry for Joey PR #19 repairs.
# Runs full Swift tests, IntegritySecurityRepairTests, and a Release build.
# Does not touch production media or Google Drive.
set -u
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${JOEY_VERIFY_OUT_DIR:-$ROOT/verification-reports}"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/macos-verify-$STAMP.txt"
LAUNCHER=(python3 "$ROOT/Tools/run-local.py")

{
  echo "Joey macOS verification report"
  echo "timestamp_utc=$STAMP"
  echo "cwd=$ROOT"
  echo "branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  echo "commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "swift=$("${LAUNCHER[@]}" swift --version 2>&1 | tr '\n' ' ')"
  echo "xcode=$(xcodebuild -version 2>&1 | tr '\n' ' ' || true)"
  echo
} | tee "$REPORT"

run_check() {
  local name="$1"
  shift
  local log="$OUT_DIR/${name}-$STAMP.log"
  echo "=== BEGIN $name ===" | tee -a "$REPORT"
  echo "command: $*" | tee -a "$REPORT"
  set +e
  "${LAUNCHER[@]}" "$@" >"$log" 2>&1
  local code=$?
  set -e
  echo "exit_code=$code" | tee -a "$REPORT"
  echo "log=$log" | tee -a "$REPORT"
  if [[ "$code" -ne 0 ]]; then
    echo "--- tail $name ---" | tee -a "$REPORT"
    tail -n 80 "$log" | tee -a "$REPORT"
  fi
  echo "=== END $name ===" | tee -a "$REPORT"
  echo | tee -a "$REPORT"
  return "$code"
}

FULL_CODE=0
FILTER_CODE=0
RELEASE_CODE=0

run_check full-swift-test test || FULL_CODE=$?
run_check integrity-security-repair-tests test --filter IntegritySecurityRepairTests || FILTER_CODE=$?

if xcodebuild -list -project Joey.xcodeproj 2>/dev/null | grep -q "Joey Native"; then
  run_check release-build xcodebuild -project Joey.xcodeproj -scheme "Joey Native" -configuration Release -destination 'platform=macOS' build || RELEASE_CODE=$?
else
  echo "Shared scheme 'Joey Native' absent; using swift build -c release." | tee -a "$REPORT"
  run_check release-build build -c release || RELEASE_CODE=$?
fi

{
  echo "SUMMARY"
  echo "full_swift_test_exit=$FULL_CODE"
  echo "integrity_security_repair_tests_exit=$FILTER_CODE"
  echo "release_build_exit=$RELEASE_CODE"
  if [[ "$FULL_CODE" -eq 0 && "$FILTER_CODE" -eq 0 && "$RELEASE_CODE" -eq 0 ]]; then
    echo "result=PASS"
  else
    echo "result=FAIL"
  fi
  echo "report=$REPORT"
} | tee -a "$REPORT"

if [[ "$FULL_CODE" -eq 0 && "$FILTER_CODE" -eq 0 && "$RELEASE_CODE" -eq 0 ]]; then
  exit 0
fi
exit 1
