#!/usr/bin/env bash
# Native Mac acceptance for Joey after PR #19 merge.
# Linux/cloud agents must not treat this as runnable proof — execute on macOS only.
# Does not touch production media, Google Drive, or installed production bundles
# unless Frank separately authorizes those paths.
set -u
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "REFUSE: verify-macos-acceptance.sh requires macOS. Prepare/handoff only on Linux." >&2
  exit 2
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${JOEY_ACCEPTANCE_OUT_DIR:-$ROOT/verification-reports}"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/macos-acceptance-$STAMP.txt"
DISPOSABLE_DIR="$OUT_DIR/disposable-$STAMP"
mkdir -p "$DISPOSABLE_DIR"
LAUNCHER=(python3 "$ROOT/Tools/run-local.py")

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
DIRTY="$(git status --porcelain 2>/dev/null || true)"

{
  echo "Joey native Mac acceptance report"
  echo "milestone_target=MAC ACCEPTANCE PASSED — AWAITING DEPLOYMENT APPROVAL"
  echo "timestamp_utc=$STAMP"
  echo "cwd=$ROOT"
  echo "branch=$BRANCH"
  echo "commit=$COMMIT"
  echo "pr19_note=PR #19 is merged; do not re-merge"
  echo "swift=$("${LAUNCHER[@]}" swift --version 2>&1 | tr '\n' ' ')"
  echo "xcode=$(xcodebuild -version 2>&1 | tr '\n' ' ' || true)"
  echo "ffmpeg=$(command -v ffmpeg >/dev/null && ffmpeg -version 2>&1 | head -n 1 || echo missing)"
  echo
} | tee "$REPORT"

fail_dirty() {
  if [[ -n "$DIRTY" && "${JOEY_ACCEPTANCE_ALLOW_DIRTY:-}" != "1" ]]; then
    echo "REFUSE: working tree is dirty. Use a clean main checkout or set JOEY_ACCEPTANCE_ALLOW_DIRTY=1." | tee -a "$REPORT"
    echo "$DIRTY" | tee -a "$REPORT"
    exit 3
  fi
}

if [[ "$BRANCH" != "main" && "${JOEY_ACCEPTANCE_ALLOW_NON_MAIN:-}" != "1" ]]; then
  echo "REFUSE: checkout is '$BRANCH', expected main (or set JOEY_ACCEPTANCE_ALLOW_NON_MAIN=1)." | tee -a "$REPORT"
  exit 3
fi
fail_dirty

CODES=()
record() {
  local name="$1" code="$2"
  CODES+=("$name=$code")
  echo "RESULT $name exit=$code" | tee -a "$REPORT"
}

run_check() {
  local name="$1"
  shift
  local log="$OUT_DIR/${name}-$STAMP.log"
  echo "=== BEGIN $name ===" | tee -a "$REPORT"
  echo "command: ${LAUNCHER[*]} $*" | tee -a "$REPORT"
  set +e
  "${LAUNCHER[@]}" "$@" >"$log" 2>&1
  local code=$?
  set -e
  echo "exit_code=$code" | tee -a "$REPORT"
  echo "log=$log" | tee -a "$REPORT"
  if [[ "$code" -ne 0 ]]; then
    echo "--- tail $name ---" | tee -a "$REPORT"
    tail -n 100 "$log" | tee -a "$REPORT"
  fi
  echo "=== END $name ===" | tee -a "$REPORT"
  echo | tee -a "$REPORT"
  record "$name" "$code"
  return "$code"
}

# 1) Toolchain / helpers presence
HELPER_CODE=0
command -v ffmpeg >/dev/null || HELPER_CODE=1
command -v ffprobe >/dev/null || HELPER_CODE=1
record "helpers-ffmpeg-ffprobe" "$HELPER_CODE"

# 2) Complete Swift suite
FULL_CODE=0
run_check full-swift-test test || FULL_CODE=$?

# 3) Lock + low-storage oriented filters
LOCK_CODE=0
run_check integrity-security-repair-tests test --filter IntegritySecurityRepairTests || LOCK_CODE=$?
STORAGE_CODE=0
run_check storage-tests test --filter StorageTests || STORAGE_CODE=$?

# 4) Native Release build
RELEASE_CODE=0
DERIVED="$OUT_DIR/DerivedData-acceptance-$STAMP"
SCHEME=""
if xcodebuild -list -project Joey.xcodeproj 2>/dev/null | grep -q "Joey Native"; then
  SCHEME="Joey Native"
elif xcodebuild -list -project Joey.xcodeproj 2>/dev/null | grep -qE '^[[:space:]]+Joey$'; then
  SCHEME="Joey"
fi

if [[ -n "$SCHEME" ]]; then
  echo "Using Xcode scheme: $SCHEME" | tee -a "$REPORT"
  run_check release-xcodebuild xcodebuild -project Joey.xcodeproj -scheme "$SCHEME" -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build || RELEASE_CODE=$?
else
  echo "No Joey/Joey Native scheme listed; SwiftPM Release fallback." | tee -a "$REPORT"
  run_check release-swiftpm build -c release || RELEASE_CODE=$?
fi

# 5) Launch probe (built app only — does not replace installed production app)
LAUNCH_CODE=0
if [[ "${JOEY_ACCEPTANCE_SKIP_LAUNCH:-}" == "1" ]]; then
  echo "Launch probe skipped (JOEY_ACCEPTANCE_SKIP_LAUNCH=1)." | tee -a "$REPORT"
  record "launch-probe" 0
else
  APP=""
  if [[ -n "$SCHEME" ]]; then
    APP="$(find "$DERIVED/Build/Products/Release" -maxdepth 2 -name '*.app' -print 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$APP" || ! -d "$APP" ]]; then
    echo "No Release .app product found for launch probe." | tee -a "$REPORT"
    LAUNCH_CODE=1
    record "launch-probe" "$LAUNCH_CODE"
  else
    echo "Launching: $APP" | tee -a "$REPORT"
    set +e
    open "$APP"
    sleep 5
    BASENAME="$(basename "$APP" .app)"
    if pgrep -f "$BASENAME.app/Contents/MacOS" >/dev/null 2>&1; then
      echo "Process observed running." | tee -a "$REPORT"
      pkill -f "$BASENAME.app/Contents/MacOS" >/dev/null 2>&1 || true
      sleep 1
      LAUNCH_CODE=0
    else
      echo "Process not observed after open." | tee -a "$REPORT"
      LAUNCH_CODE=1
    fi
    set -e
    record "launch-probe" "$LAUNCH_CODE"
  fi
fi

# 6) Disposable media — synthetic file + MediaTests (fixtures are disposable)
DISPOSABLE_CODE=0
if [[ "${JOEY_ACCEPTANCE_SKIP_DISPOSABLE:-}" == "1" ]]; then
  echo "Disposable media step skipped." | tee -a "$REPORT"
  record "disposable-media" 0
else
  CLIP="$DISPOSABLE_DIR/acceptance-clip.mp4"
  set +e
  "${LAUNCHER[@]}" ffmpeg -nostdin -y -f lavfi -i "testsrc2=s=320x180:r=30:d=2" \
    -f lavfi -i "sine=frequency=440:duration=2" \
    -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$CLIP" >"$OUT_DIR/ffmpeg-disposable-$STAMP.log" 2>&1
  FF_CODE=$?
  set -e
  echo "disposable_ffmpeg_exit=$FF_CODE path=$CLIP" | tee -a "$REPORT"
  if [[ "$FF_CODE" -ne 0 ]]; then
    DISPOSABLE_CODE=$FF_CODE
  else
    run_check disposable-media-tests test --filter MediaTests || DISPOSABLE_CODE=$?
  fi
  record "disposable-media" "$DISPOSABLE_CODE"
fi

# Summary + blockers template
PASS=1
for item in "${CODES[@]}"; do
  code="${item##*=}"
  if [[ "$code" -ne 0 ]]; then PASS=0; fi
done

{
  echo "SUMMARY"
  for item in "${CODES[@]}"; do echo "$item"; done
  if [[ "$PASS" -eq 1 ]]; then
    echo "result=PASS"
    echo "milestone=MAC ACCEPTANCE PASSED — AWAITING DEPLOYMENT APPROVAL"
  else
    echo "result=FAIL"
    echo "milestone=MAC ACCEPTANCE NOT PASSED"
  fi
  echo "report=$REPORT"
  echo
  echo "BLOCKERS_TEMPLATE"
  echo "- credential_incident_OPENAI_API_KEY: (owner confirmation pending — see docs/CREDENTIAL_INCIDENT.md)"
  echo "- production_install_authority: not granted by this acceptance script"
  echo "- live_drive_oauth_smoke: not run (out of scope)"
  echo "- other:"
} | tee -a "$REPORT"

if [[ "$PASS" -eq 1 ]]; then
  exit 0
fi
exit 1
