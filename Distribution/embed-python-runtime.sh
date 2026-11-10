#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
archive=${1:?Path to the pinned Python runtime tarball}
destination=${2:?Path to the PythonRuntime.framework build output}
case "$destination" in
    /*/PythonRuntime.framework) ;;
    *) echo "Choose an absolute PythonRuntime.framework output path." >&2; exit 1 ;;
esac
expected=353d5f1b4fd2715e7053f12f068435d5bbad16b91e057006b5d01e0925709a7e
actual=$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{ print $1 }')
[[ "$expected" == "$actual" ]] || { echo "Unexpected Python runtime digest." >&2; exit 1; }
[[ "$(uname -m)" == arm64 ]] || { echo "This preview targets Apple Silicon." >&2; exit 1; }
mkdir -p "$(dirname "$destination")"
tmp=$(/usr/bin/mktemp -d "$(dirname "$destination")/.bigbrain-runtime.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
/usr/bin/tar -xzf "$archive" -C "$tmp"
framework="$tmp/PythonRuntime.framework"
version="$framework/Versions/A"
mkdir -p "$version/bin" "$version/lib" "$version/Resources"
cp "$tmp/python/bin/python3.12" "$version/bin/python3.12"
/usr/bin/ditto "$tmp/python/lib" "$version/lib"
if [[ -f "$tmp/python/LICENSE.txt" ]]; then cp "$tmp/python/LICENSE.txt" "$version/Resources/LICENSE.txt"; fi
if [[ -d "$tmp/python/licenses" ]]; then /usr/bin/ditto "$tmp/python/licenses" "$version/Resources/licenses"; fi
rm -rf "$version/lib/python3.12/site-packages/pip" "$version/lib/python3.12/ensurepip"
cat > "$version/Resources/Info.plist" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>PythonRuntime</string>
    <key>CFBundleIdentifier</key><string>se.richard.bigbrain-studio.python</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleVersion</key><string>3.12.16</string>
</dict></plist>
XML
mv "$version/lib/libpython3.12.dylib" "$version/PythonRuntime"
ln -s ../PythonRuntime "$version/lib/libpython3.12.dylib"
ln -s A "$framework/Versions/Current"
ln -s Versions/Current/PythonRuntime "$framework/PythonRuntime"
ln -s Versions/Current/Resources "$framework/Resources"
while IFS= read -r -d '' library; do
    /usr/bin/codesign --force --sign - "$library"
done < <(/usr/bin/find "$version/lib" -type f \( -name '*.dylib' -o -name '*.so' \) -print0)
/usr/bin/codesign --force --sign - --entitlements Distribution/Helper.entitlements "$version/bin/python3.12"
/usr/bin/codesign --force --sign - "$framework"
/usr/bin/codesign --verify --deep --strict "$framework"
backup="$tmp/PreviousRuntime.framework"
if [[ -e "$destination" ]]; then mv "$destination" "$backup"; fi
if ! mv "$framework" "$destination"; then
    if [[ -e "$backup" ]]; then mv "$backup" "$destination"; fi
    exit 1
fi
