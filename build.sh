#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
destination=${1:-"$PWD/BigBrain Agent.app"}
mkdir -p .build/SwiftCache
if [[ ! -x .build/BigBrain || Sources/BigBrain.swift -nt .build/BigBrain || Sources/Atlas.swift -nt .build/BigBrain || Sources/Distribution.swift -nt .build/BigBrain || Sources/SpeechTranscription.swift -nt .build/BigBrain || Sources/StudioEditor.swift -nt .build/BigBrain || Sources/StudioMarkdown.swift -nt .build/BigBrain || Sources/StudioExport.swift -nt .build/BigBrain ]]; then
  swiftc -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$PWD/.build/SwiftCache" \
    -parse-as-library Sources/BigBrain.swift Sources/Atlas.swift Sources/Distribution.swift Sources/SpeechTranscription.swift Sources/StudioEditor.swift Sources/StudioMarkdown.swift Sources/StudioExport.swift -o .build/BigBrain
fi
/usr/bin/python3 Sources/icon.py .build/AppIcon.icns
mkdir -p "$destination/Contents/MacOS" "$destination/Contents/Resources"
cp .build/BigBrain "$destination/Contents/MacOS/BigBrain"
cp .build/AppIcon.icns Sources/brain.py Sources/network.py Sources/public_source.py Sources/word_import.py Sources/bigbrain "$destination/Contents/Resources/"
/usr/bin/ditto Skills "$destination/Contents/Resources/Skills"
cp Sources/Info.plist "$destination/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$destination"
printf '%s\n' "$destination"
