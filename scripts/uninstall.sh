#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
purge=false
clean_build=false
dry_run=false
for argument in "$@"; do
    case "$argument" in
        --purge) purge=true ;;
        --clean-build) clean_build=true ;;
        --dry-run) dry_run=true ;;
        *) echo "Usage: $0 [--purge] [--clean-build] [--dry-run]" >&2; exit 2 ;;
    esac
done

apps=(/Applications/Melicum.app "$HOME/Applications/Melicum.app" '/Applications/HDMI Audio.app' "$HOME/Applications/HDMI Audio.app")
drivers=(/Library/Audio/Plug-Ins/HAL/MelicumSystemVolume.driver /Library/Audio/Plug-Ins/HAL/HDMIAudioSystemVolume.driver)
receipts=(local.melicum.systemvolume local.hdmiaudio.systemvolume)
user_data=(
    "$HOME/Library/Application Support/Melicum"
    "$HOME/Library/Application Support/HDMI Audio"
    "$HOME/Library/Caches/local.hdmiaudio.app"
    "$HOME/Library/Caches/local.hdmiaudio.app.sparkle"
    "$HOME/Library/Preferences/local.hdmiaudio.app.plist"
    "$HOME/Library/Preferences/local.melicum.update-verification.plist"
    "$HOME/Library/Preferences/ByHost/"local.hdmiaudio.app.*.plist(N)
    "$HOME/Library/Saved Application State/local.hdmiaudio.app.savedState"
    "$HOME/Library/HTTPStorages/local.hdmiaudio.app"
    "$HOME/Library/HTTPStorages/local.hdmiaudio.app.binarycookies"
    "$HOME/Library/WebKit/local.hdmiaudio.app"
    "$HOME/Library/Logs/"Melicum*(N)
    "$HOME/Library/Logs/DiagnosticReports/"Melicum*(N)
)
build_paths=("$project_root/build" "$project_root/.build" "$project_root/dist"
    "$HOME/Library/Developer/Xcode/DerivedData/"Melicum-*(N/)
    "$HOME/Library/Developer/Xcode/DerivedData/"melicum-*(N/))

if $dry_run; then
    echo 'Existing paths to remove:'
    paths=("${apps[@]}" "${drivers[@]}")
    if $purge; then paths+=("${user_data[@]}"); fi
    if $clean_build; then paths+=("${build_paths[@]}"); fi
    for cleanup_path in "${paths[@]}"; do
        if [[ -e "$cleanup_path" || -L "$cleanup_path" ]]; then print -r -- "$cleanup_path"; fi
    done
    echo 'Installer receipts to forget, when present:'
    for receipt in "${receipts[@]}"; do
        if pkgutil --pkg-info "$receipt" >/dev/null 2>&1; then print -r -- "$receipt"; fi
    done
    echo 'Removing the audio component requires administrator authentication and restarts coreaudiod.'
    exit 0
fi

if pgrep -x Melicum >/dev/null || pgrep -f '(Melicum|HDMI Audio)\.app/Contents/MacOS/' >/dev/null; then
    echo 'Disable audio and quit Melicum before uninstalling it.' >&2
    exit 1
fi
needs_admin=false
restart_audio=false
for app in "${apps[@]}"; do
    if [[ -d "$app" && ! -w "$app" ]]; then needs_admin=true; fi
done
for driver in "${drivers[@]}"; do
    if [[ -d "$driver" ]]; then needs_admin=true; restart_audio=true; fi
done
for receipt in "${receipts[@]}"; do
    if pkgutil --pkg-info "$receipt" >/dev/null 2>&1; then needs_admin=true; fi
done
# Authenticate before removing anything. Password entry stays in the user's terminal.
if $needs_admin; then
    echo 'Administrator authentication is needed to remove the optional audio component.'
    echo 'The audio service will restart, briefly interrupting audio from all apps.'
    sudo -v
fi
if $purge; then
    tccutil reset All local.hdmiaudio.app || echo 'macOS could not reset the app permission records; review Privacy & Security if needed.' >&2
    defaults delete local.hdmiaudio.app >/dev/null 2>&1 || true
    defaults delete local.melicum.update-verification >/dev/null 2>&1 || true
fi
lsregister='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
registered_apps=("${apps[@]}" "$project_root"/build/**/Melicum*.app(N/))
for app in "${registered_apps[@]}"; do
    if [[ -d "$app" ]]; then "$lsregister" -u "$app" >/dev/null 2>&1 || true; fi
done
if $needs_admin; then sudo /bin/rm -rf -- "${apps[@]}"; else rm -rf -- "${apps[@]}"; fi
if $needs_admin; then
    sudo /bin/rm -rf -- "${drivers[@]}" /Library/Audio/Plug-Ins/HAL/._MelicumSystemVolume.driver /Library/Audio/Plug-Ins/HAL/._HDMIAudioSystemVolume.driver
    for receipt in "${receipts[@]}"; do
        if pkgutil --pkg-info "$receipt" >/dev/null 2>&1; then sudo /usr/sbin/pkgutil --forget "$receipt"; fi
    done
fi
if $restart_audio; then sudo /usr/bin/killall coreaudiod || echo 'The audio service was not running; macOS will start it when needed.' >&2; fi
if $purge; then rm -rf -- "${user_data[@]}"; fi
if $clean_build; then rm -rf -- "${build_paths[@]}"; fi
echo 'Melicum and its optional audio component have been removed.'
if $purge; then echo 'Personal settings, caches and saved state have been removed.'; fi
if $clean_build; then echo 'Local build artifacts have been removed; repository sources and documentation are preserved.'; fi
