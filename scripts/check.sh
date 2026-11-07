#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
npm --prefix backend run check
npm --prefix backend test
python3 scripts/test_probe_budget.py
python3 scripts/test_iphone_install.py
mkdir -p runs
swiftc ios/VisionCore/Sources/VisionCore/SceneHistory.swift \
  ios/VisionCore/Sources/VisionCore/VoiceDetector.swift scripts/check_core.swift -o runs/check-core
runs/check-core
swiftc -frontend -parse ios/VisionAssistant/*.swift
python3 scripts/check_docs.py
git diff --check
