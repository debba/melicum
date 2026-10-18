#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
fixture='Tests/MelicumTests/DocumentationScreenshots.swift'
if [[ -e "$fixture" ]]; then
    echo "Screenshot fixture already exists: $fixture" >&2
    exit 1
fi
trap 'rm -f "$fixture"' EXIT
cp scripts/capture-screenshots.swift "$fixture"
MELICUM_SCREENSHOT_ROOT="$PWD" swift test --filter DocumentationScreenshots
