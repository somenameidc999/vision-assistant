#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if ! xcrun --find simctl >/dev/null 2>&1 && [ -d /Applications/Xcode-26.6.0.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
  export DEVELOPER_DIR
fi
task_simulator_id="$(xcrun simctl list devices booted -j | python3 -c '
import json,sys
devices=[d for items in json.load(sys.stdin)["devices"].values() for d in items if d["state"]=="Booted" and "iPhone" in d["name"]]
if not devices: sys.exit("Run scripts/run_simulator.sh first.")
print(devices[0]["udid"])
')"
task_result_id="$(python3 -c 'import uuid; print(uuid.uuid4().hex[:8])')"
xcodebuild -project ios/VisionAssistant.xcodeproj -scheme VisionAssistant \
  -destination "platform=iOS Simulator,id=$task_simulator_id" \
  -derivedDataPath runs/DerivedData -parallel-testing-enabled NO \
  -resultBundlePath "runs/SimulatorUITests-$task_result_id.xcresult" \
  -only-testing:VisionAssistantUITests/ConversationTests CODE_SIGNING_ALLOWED=NO test
