#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--dev-prerecorded-scene" ]; }; then
  echo 'Usage: scripts/run_simulator.sh [--dev-prerecorded-scene]' >&2
  exit 1
fi
if ! xcrun --find simctl >/dev/null 2>&1 && [ -d /Applications/Xcode-26.6.0.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
  export DEVELOPER_DIR
fi
if ! xcodebuild -checkFirstLaunchStatus; then
  echo 'Complete Xcode license and first-launch setup locally. See docs/setup.md.' >&2
  exit 1
fi
if ! xcrun --find simctl >/dev/null 2>&1; then
  echo 'Full Xcode is required. See docs/setup.md.' >&2
  exit 1
fi
python3 scripts/bootstrap.py --client-only
xcodegen generate --spec ios/project.yml
task_simulator_id="$(xcrun simctl list devices available -j | python3 -c '
import json,sys
data=json.load(sys.stdin)
devices=[d for runtime,items in data["devices"].items() if "iOS-26" in runtime for d in items if "iPhone" in d["name"]]
if not devices: sys.exit("No iOS 26 iPhone simulator is available. Create one in Xcode > Window > Devices and Simulators.")
print(next((d for d in devices if d["state"]=="Booted"),devices[0])["udid"])
')"
if ! xcrun simctl list devices booted | rg -q "$task_simulator_id"; then
  xcrun simctl boot "$task_simulator_id"
fi
task_developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
open -a "$task_developer_dir/Applications/Simulator.app"
xcrun simctl bootstatus "$task_simulator_id" -b
xcodebuild -project ios/VisionAssistant.xcodeproj -scheme VisionAssistant \
  -destination "platform=iOS Simulator,id=$task_simulator_id" \
  -derivedDataPath runs/DerivedData CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$task_simulator_id" runs/DerivedData/Build/Products/Debug-iphonesimulator/VisionAssistant.app
xcrun simctl terminate "$task_simulator_id" local.personal.VisionAssistant >/dev/null 2>&1 || true
xcrun simctl launch "$task_simulator_id" local.personal.VisionAssistant "$@"
