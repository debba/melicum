#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# MELICUM_ARCHS="arm64 x86_64" builds a universal binary.
# MELICUM_SIGN_IDENTITY signs with a Developer ID and the hardened runtime instead of ad hoc.
flags=(-c release)
for arch in ${=MELICUM_ARCHS:-}; do flags+=(--arch "$arch"); done
swift build $flags
bin=$(swift build $flags --show-bin-path)
app='build/Melicum.app'
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin/Melicum" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
sparkle='.build/artifacts/sparkle/Sparkle'
framework="$app/Contents/Frameworks/Sparkle.framework"
ditto "$sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$framework"
cp "$sparkle/LICENSE" "$app/Contents/Resources/Sparkle-License.txt"
for resource in "$bin"/*.bundle(N); do ditto "$resource" "$app/Contents/Resources/${resource:t}"; done
# Compile the layered icon so modern macOS does not wrap the legacy tile in a second frame.
xcrun actool --compile "$app/Contents/Resources" --platform macosx --minimum-deployment-target 14.2 --app-icon AppIcon --output-partial-info-plist build/icon-info.plist --output-format human-readable-text --warnings --errors Resources/AppIcon.icon
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$app/Contents/Resources/"; fi
cp Resources/BrandMark.png "$app/Contents/Resources/"
cp Resources/MenuBarIcon.tiff "$app/Contents/Resources/"
if [[ -f build/MelicumSystemVolume.pkg ]]; then cp build/MelicumSystemVolume.pkg "$app/Contents/Resources/"; fi
identity=${MELICUM_SIGN_IDENTITY:--}
# Sign Sparkle's nested helpers before sealing the framework and the app.
signing=(--force --sign "$identity" --preserve-metadata=entitlements)
if [[ $identity != - ]]; then signing+=(--options runtime --timestamp); fi
for code in "$framework/Versions/B/XPCServices/"*.xpc(N) "$framework/Versions/B/Autoupdate" "$framework/Versions/B/Updater.app" "$framework"; do
    codesign $signing "$code"
done
if [[ $identity == - ]]; then
    codesign --force --sign - --identifier local.hdmiaudio.app "$app"
else
    codesign --force --options runtime --timestamp --entitlements Resources/Melicum.entitlements --sign "$identity" "$app"
fi
codesign --verify --deep --strict "$app"
echo "App ready: $app"
