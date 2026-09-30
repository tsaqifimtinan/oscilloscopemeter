#!/bin/sh
# Usage: ./scripts/build.sh [xcodebuild actions...]   (default: build; e.g. `./scripts/build.sh test`)
set -eu
cd "$(dirname "$0")/.."
# xcode-select may point at CommandLineTools; xcodebuild needs full Xcode.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
[ $# -eq 0 ] && set -- build
xcodegen generate --quiet
xcodebuild -quiet -scheme Scope -configuration Debug -derivedDataPath build -destination 'platform=macOS,arch=arm64' "$@"
