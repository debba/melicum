#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift scripts/make-icon.swift Resources
mkdir -p build/BrandIcon.iconset
for entry in '16 icon_16x16' '32 icon_16x16@2x' '32 icon_32x32' '64 icon_32x32@2x' '128 icon_128x128' '256 icon_128x128@2x' '256 icon_256x256' '512 icon_256x256@2x' '512 icon_512x512' '1024 icon_512x512@2x'; do
    size=${entry%% *}
    name=${entry#* }
    sips -z "$size" "$size" Resources/BrandIcon.png --out "build/BrandIcon.iconset/$name.png" >/dev/null
done
iconutil -c icns build/BrandIcon.iconset -o Resources/AppIcon.icns
mkdir -p docs/images
sips -z 512 512 Resources/BrandIcon.png --out docs/images/melicum-icon.png >/dev/null
cp Resources/brand/melicum-mark-dark.svg docs/images/melicum-mark.svg
sed 's/viewBox="0 0 1024 1024"/viewBox="100 100 824 824"/' Resources/brand/melicum-icon.svg > docs/favicon.svg
sips -c 824 824 Resources/BrandIcon.png --out build/favicon-tile.png >/dev/null
sips -z 180 180 build/favicon-tile.png --out docs/apple-touch-icon.png >/dev/null
sips -s format ico -z 32 32 build/favicon-tile.png --out docs/favicon.ico >/dev/null
