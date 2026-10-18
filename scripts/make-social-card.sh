#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
profile=$(mktemp -d)
trap 'rm -rf "$profile"' EXIT
"$chrome" --headless --disable-gpu --hide-scrollbars --user-data-dir="$profile" \
    --force-device-scale-factor=1 --window-size=1280,640 --virtual-time-budget=10000 \
    --screenshot="$PWD/docs/images/social-card.png" "file://$PWD/Resources/brand/social-card.html" 2>/dev/null
sips -g pixelWidth -g pixelHeight docs/images/social-card.png | tail -2
