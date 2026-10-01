#!/bin/bash
# Assemble Codenotch.app and a DMG from `swift build` output, with only the
# Command Line Tools installed (no Xcode, actool or xcodebuild). BDB-only path;
# upstream releases still go through the Makefile.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/bdb
APP=$OUT/Codenotch.app
VERSION=$(awk -F'"' '/MARKETING_VERSION:/ {print $2}' project.yml)
BUILD=$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ {print $2}' project.yml)

swift build -c release --product Codenotch
BIN=$(swift build -c release --show-bin-path)

rm -rf "$APP" "$OUT/Codenotch.dmg" "$OUT/stage"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Codenotch" "$APP/Contents/MacOS/Codenotch"

# Sparkle ships as a binary framework in the SwiftPM artifacts.
SPARKLE=$(find .build/artifacts -type d -name Sparkle.framework -path '*macos*' | head -1)
[ -n "$SPARKLE" ] || { echo "Sparkle.framework not found under .build/artifacts"; exit 1; }
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Codenotch" 2>/dev/null || true

# Info.plist: the checked-in one is an Xcode template; fill its variables.
sed -e "s/\$(EXECUTABLE_NAME)/Codenotch/" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.vinz.codenotch/" \
    -e "s/\$(MARKETING_VERSION)/$VERSION/" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD/" \
    Sources/Info.plist > "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"

# App icon: appiconset -> .icns (iconutil wants icon_*.png in a *.iconset).
ICONSET=$OUT/AppIcon.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
cp Sources/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET/"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Named images: NSImage(named:) also resolves plain files in Resources.
for d in Sources/Assets.xcassets/*.imageset; do
  for f in "$d"/*.svg "$d"/*.png "$d"/*.pdf; do
    [ -e "$f" ] && cp "$f" "$APP/Contents/Resources/$(basename "$d" .imageset).${f##*.}"
  done
done

cp Sources/Resources/*.json "$APP/Contents/Resources/"
python3 Scripts/bdb-xcstrings.py Sources/Localizable.xcstrings "$APP/Contents/Resources"

# Inside-out ad-hoc signing; hardened runtime would need the
# disable-library-validation entitlement for an ad-hoc Sparkle (see Makefile
# build-ci), so it is left off here.
codesign --force --deep -s - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p "$OUT/stage"; cp -R "$APP" "$OUT/stage/"; ln -s /Applications "$OUT/stage/Applications"
hdiutil create -volname Codenotch -srcfolder "$OUT/stage" -ov -format UDZO "$OUT/Codenotch.dmg"
rm -rf "$OUT/stage"
echo "App: $APP"; echo "DMG: $OUT/Codenotch.dmg"
