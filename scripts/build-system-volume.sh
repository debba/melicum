#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# MELICUM_SIGN_IDENTITY signs the driver with a Developer ID instead of ad hoc.
# MELICUM_INSTALLER_IDENTITY signs the package with a Developer ID Installer certificate.
root='build/system-volume-root'
driver="$root/Library/Audio/Plug-Ins/HAL/MelicumSystemVolume.driver"
rm -rf "$root"
mkdir -p "$driver/Contents/MacOS" "$driver/Contents/Resources"
xcrun clang -std=c11 -O2 -fblocks -arch arm64 -arch x86_64 -mmacosx-version-min=14.2 -bundle Driver/SystemVolume.c -framework CoreAudio -framework CoreFoundation -framework Accelerate -o "$driver/Contents/MacOS/MelicumSystemVolume"
cp Driver/Info.plist "$driver/Contents/Info.plist"
cp Resources/AppIcon.icns "$driver/Contents/Resources/AppIcon.icns"
cp ThirdParty/BlackHole/LICENSE "$driver/Contents/Resources/BlackHole-Source-License.txt"
cp LICENSE "$driver/Contents/Resources/Application-License.txt"
xattr -cr "$root"
identity=${MELICUM_SIGN_IDENTITY:--}
if [[ $identity == - ]]; then
    codesign --force --sign - --identifier local.melicum.systemvolume "$driver"
else
    codesign --force --options runtime --timestamp --sign "$identity" "$driver"
fi
codesign --verify --strict "$driver"
chmod +x scripts/driver-package/postinstall
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
signing=()
if [[ -n ${MELICUM_INSTALLER_IDENTITY:-} ]]; then signing=(--sign "$MELICUM_INSTALLER_IDENTITY" --timestamp); fi
pkgbuild --root "$root" --identifier local.melicum.systemvolume --version "$version" --install-location / --scripts scripts/driver-package $signing build/MelicumSystemVolume.pkg
echo 'Installer ready: build/MelicumSystemVolume.pkg'
