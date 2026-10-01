#!/bin/bash
# Assemble Codenotch.app and a DMG from `swift build` output, with only the
# Command Line Tools installed (no Xcode, actool or xcodebuild). BDB-only path;
# upstream releases still go through the Makefile.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/bdb
NAME="BDB AO Codenotch"
BUNDLE_ID=dev.bdb.ao-codenotch
APP="$OUT/$NAME.app"
DMG="$OUT/BDB-AO-Codenotch.dmg"
VERSION=$(awk -F'"' '/MARKETING_VERSION:/ {print $2}' project.yml)
BUILD=$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ {print $2}' project.yml)

swift build -c release --product Codenotch
BIN=$(swift build -c release --show-bin-path)

rm -rf "$APP" "$DMG" "$OUT/stage"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Codenotch" "$APP/Contents/MacOS/Codenotch"

# Sparkle ships as a binary framework in the SwiftPM artifacts.
SPARKLE=$(find .build/artifacts -type d -name Sparkle.framework -path '*macos*' | head -1)
[ -n "$SPARKLE" ] || { echo "Sparkle.framework not found under .build/artifacts"; exit 1; }
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Codenotch" 2>/dev/null || true

# Info.plist: the checked-in one is an Xcode template; fill its variables.
sed -e "s/\$(EXECUTABLE_NAME)/Codenotch/" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/" \
    -e "s/\$(MARKETING_VERSION)/$VERSION/" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD/" \
    Sources/Info.plist > "$APP/Contents/Info.plist"
PB() { /usr/libexec/PlistBuddy -c "$1" "$APP/Contents/Info.plist"; }
PB "Add :CFBundleIconFile string AppIcon"
PB "Set :CFBundleDisplayName $NAME"
PB "Set :CFBundleName $NAME"
PB "Add :NSHumanReadableCopyright string Based on Codenotch by vinzdg (MIT). BDB changes (c) hybridlabor-api."
# No Sparkle feed, no key: every update path in the app is off (BDBBrand).
PB "Delete :SUFeedURL"
PB "Delete :SUPublicEDKey"
PB "Delete :SUScheduledCheckInterval"
PB "Set :SUEnableAutomaticChecks false"

# App icon: the BDB variant in Brand/ (regenerate with Scripts/bdb-icon.py).
iconutil -c icns Brand/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# Credits for the About panel; the MIT notice travels with the app.
cp LICENSE "$APP/Contents/Resources/LICENSE-Codenotch-MIT.txt"
cat > "$APP/Contents/Resources/Credits.rtf" <<'RTF'
{\rtf1\ansi\deff0{\fonttbl{\f0 Helvetica;}}\f0\fs20
BDB AO Codenotch is a fork of Codenotch by vinzdg (https://github.com/vinzdg/codenotch), MIT licence. The licence text is in LICENSE-Codenotch-MIT.txt inside this app.\par
BDB additions (c) hybridlabor-api.\par}
RTF

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
hdiutil create -volname "$NAME" -srcfolder "$OUT/stage" -ov -format UDZO "$DMG"
rm -rf "$OUT/stage"
echo "App: $APP"; echo "DMG: $DMG"
