#!/bin/bash
# Build, install and run the hang repro on a connected iPhone.
# usage: scripts/run.sh [-n RUNS] [-t] [--no-build] [--no-replay] [--no-control]
#   -n RUNS      repro runs (default 3)
#   -t           also record Time Profiler traces (repro + -nosentry) into traces/
# env: DEVICE (UDID, default: first connected), TEAM (dev team), BUNDLE_ID
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
RUNS=3 TRACE=0 BUILD=1 REPLAY=1 CONTROL=1
while [ $# -gt 0 ]; do case $1 in
  -n) RUNS=$2; shift;; -t) TRACE=1;; --no-build) BUILD=0;; --no-replay) REPLAY=0;; --no-control) CONTROL=0;;
  *) echo "unknown arg $1"; exit 1;; esac; shift; done
TEAM=${TEAM:?set TEAM to your Apple dev team ID}
BUNDLE_ID=${BUNDLE_ID:-com.example.hangrepro}
DEVICE=${DEVICE:-$(xcrun xctrace list devices 2>/dev/null | awk '/^== Devices ==/{f=1;next} /^==/{f=0} f && /\([0-9A-F-]{20,}\)$/ && !/Mac/ {print}' | head -1 | grep -oE '[0-9A-F-]{20,}' | tail -1)}
APP=build/Build/Products/Release-iphoneos/HangRepro.app
mkdir -p logs traces
log() { echo "[$(date '+%H:%M:%S %Z')] $*"; }

if [ $BUILD = 1 ]; then
  [ -d HangRepro.xcodeproj ] || xcodegen -q
  log "building Release for $DEVICE"
  xcodebuild -project HangRepro.xcodeproj -scheme HangRepro -configuration Release \
    -destination "id=$DEVICE" -derivedDataPath build -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" CODE_SIGN_STYLE=Automatic -quiet build
  dwarfdump --uuid "$APP.dSYM"
fi
xcrun devicectl device install app --device "$DEVICE" "$APP" > logs/install.log

# launch NAME SECONDS [args...]: run with console attached, then kill
launch() {
  local name=$1 secs=$2; shift 2
  log "launch $name ($*)"
  xcrun devicectl device process launch --device "$DEVICE" --console --terminate-existing "$BUNDLE_ID" -- "$@" \
    > "logs/$name.log" 2>&1 & local pid=$!
  sleep "$secs"; kill $pid 2>/dev/null || true; wait $pid 2>/dev/null || true
  grep -h "\[REPRO\]" "logs/$name.log" || echo "  (no [REPRO] line)"
}

for ((i = 1; i <= RUNS; i++)); do launch "repro$i" 20; done
launch upload 15   # relaunch so the last run's hang event is sent

if [ $REPLAY = 1 ]; then
  log "replay run: app stays in foreground 60 s after the hang"
  launch replay 65
  log "backgrounding (opening Settings) for 30 s"
  xcrun devicectl device process launch --device "$DEVICE" com.apple.Preferences > /dev/null
  sleep 30
  launch replay-upload 20
fi

[ $CONTROL = 1 ] && launch nosentry 15 -nosentry

if [ $TRACE = 1 ]; then
  for t in repro nosentry; do
    args=(); [ $t = nosentry ] && args=(-nosentry)
    log "Time Profiler trace: $t"
    rm -rf "traces/$t.trace"
    xcrun xctrace record --template 'Time Profiler' --device "$DEVICE" --time-limit 15s \
      --output "traces/$t.trace" --launch -- "$APP" "${args[@]}" > "logs/trace-$t.log" 2>&1 || true
    xcrun xctrace export --input "traces/$t.trace" \
      --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > "traces/$t.xml"
    python3 scripts/trace_breakdown.py "traces/$t.xml" | head -40
  done
fi
log "done"
