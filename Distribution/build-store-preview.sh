#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
archive=${1:?Path to the pinned Python runtime tarball}
destination=${2:?Absolute path to a new .app bundle}
[[ -f "$archive" ]] || { echo "Python runtime archive not found." >&2; exit 1; }
[[ ! -e "$destination" ]] || { echo "Choose a new destination for the preview." >&2; exit 1; }
./build.sh "$destination" >/dev/null
/usr/bin/plutil -replace CFBundleIdentifier -string se.richard.bigbrain-studio.preview "$destination/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleDisplayName -string "BigBrain Studio Preview" "$destination/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleName -string "BigBrain Studio Preview" "$destination/Contents/Info.plist"
/usr/bin/plutil -replace LSMinimumSystemVersion -string 26.0 "$destination/Contents/Info.plist"
/usr/bin/plutil -insert BigBrainDistribution -string store "$destination/Contents/Info.plist"
rm -f "$destination/Contents/Resources/bigbrain"
./Distribution/embed-python-runtime.sh "$archive" "$destination/Contents/Frameworks/PythonRuntime.framework"
/usr/bin/codesign --force --sign - --entitlements Distribution/AppSandbox.entitlements "$destination"
/usr/bin/codesign --verify --deep --strict "$destination"
printf '%s\n' "$destination"
