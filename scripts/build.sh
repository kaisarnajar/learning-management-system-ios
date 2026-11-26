#!/bin/zsh
# Generates the project and builds for the iOS Simulator, printing only diagnostics and the result.
# Usage: scripts/build.sh [build|test] [extra xcodebuild args...]
set -o pipefail
cd "$(dirname "$0")/.."
action=${1:-build}; shift 2>/dev/null
xcodegen generate --quiet || exit 1
dest=${DEST:-'generic/platform=iOS Simulator'}
xcodebuild -project DarseQuran.xcodeproj -scheme DarseQuran -destination "$dest" -derivedDataPath build/dd "$action" "$@" 2>&1 \
  | grep -E "^/.*(error|warning):|error:|\*\* (BUILD|TEST)|Test Case .* failed|Executed [0-9]+ test" | grep -v "/build/dd/SourcePackages/" | sort -u | head -80
