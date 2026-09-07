#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

xcodebuild \
  -quiet \
  -project GitCalendar.xcodeproj \
  -scheme GitCalendar \
  -destination 'platform=macOS' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
