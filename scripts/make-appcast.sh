#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

# Generate a signed update feed that becomes available only when its release is published.
: "${TAG:?Set TAG to the GitHub release tag.}"
repository=${GITHUB_REPOSITORY:-debba/melicum}
version=${TAG#v}
archive="dist/Melicum-$version.zip"
updates='build/updates'
rm -rf "$updates"
mkdir -p "$updates"
cp "$archive" "$updates/"
arguments=(--download-url-prefix "https://github.com/$repository/releases/download/$TAG/" --link "https://melicum.app/" --maximum-deltas 0 --maximum-versions 1)
if [[ -n ${SPARKLE_PRIVATE_KEY:-} ]]; then
    print -r -- "$SPARKLE_PRIVATE_KEY" | .build/artifacts/sparkle/Sparkle/bin/generate_appcast --ed-key-file - $arguments "$updates"
else
    .build/artifacts/sparkle/Sparkle/bin/generate_appcast --account local.melicum.updates $arguments "$updates"
fi
cp "$updates/appcast.xml" dist/appcast.xml
