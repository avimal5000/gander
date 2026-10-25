#!/usr/bin/env bash
# Lints all Swift code. swift-format ships with Xcode; SwiftLint runs only if installed.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

xcrun swift-format lint --strict --recursive --parallel Sway SwayCore/Package.swift SwayCore/Sources SwayCore/Tests
echo "swift-format: clean"

if command -v swiftlint >/dev/null 2>&1; then
  swiftlint lint --quiet
  echo "SwiftLint: clean"
else
  echo "SwiftLint not installed; skipped (brew install swiftlint)."
fi
