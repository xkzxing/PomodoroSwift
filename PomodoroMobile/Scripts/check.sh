#!/bin/bash
set -euo pipefail

mobile_root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "$mobile_root/build"
if [[ -f "$mobile_root/../PomodoroSwift/Services/MobileMirror/TaskMirrorSnapshot.swift" ]]; then
  desktop="$mobile_root/../PomodoroSwift"
  cmp "$mobile_root/Sources/PomodoroCore/TaskMirrorSnapshot.swift" "$desktop/Services/MobileMirror/TaskMirrorSnapshot.swift"
  for file in BackgroundTheme ScenePanelColors TodaySkyAstronomy; do
    cmp "$mobile_root/Sources/PomodoroCore/$file.swift" "$desktop/Models/$file.swift"
  done
  cmp "$mobile_root/App/Views/DynamicBackgroundView.swift" "$desktop/Views/DynamicBackgroundView.swift"
  cmp "$mobile_root/App/Views/TodaySkyAppearance.swift" "$desktop/Views/ToDo/TodaySkyAppearance.swift"
fi

swift test --package-path "$mobile_root" --scratch-path "$mobile_root/build/CoreTests"
xcodebuild \
  -project "$mobile_root/PomodoroMobile.xcodeproj" \
  -scheme PomodoroMobile \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$mobile_root/build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build
