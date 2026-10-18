#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if pgrep -f 'Melicum.app/Contents/MacOS/' >/dev/null; then
    echo 'Close Melicum before updating the installed bundle.' >&2
    exit 1
fi
zsh scripts/build.sh
mkdir -p "$HOME/Applications"
ditto 'build/Melicum.app' "$HOME/Applications/Melicum.app"
codesign --verify --deep --strict "$HOME/Applications/Melicum.app"
echo "Installed: $HOME/Applications/Melicum.app"
