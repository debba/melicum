# Project instructions

@/Users/debba/.codex/RTK.md

## Language

- Write all project-owned code, identifiers, comments, documentation, commit messages, scripts, diagnostics, design notes, and analysis summaries in English.
- English is the application's default and source language.
- Other languages belong in the localization catalog and localized resources. Preserve Italian, French, German, and Spanish translations.
- Keep upstream source and license notices intact.

## Product

- The app is named Melicum. Its primary purpose is controlling HDMI and DisplayPort audio from macOS, including native system volume and mute controls.
- Preserve the stable bundle identifier `local.hdmiaudio.app` and virtual device UID `HDMIAudioSystem_UID` when updating installed builds.
- Every other name uses Melicum: the Swift package and executable, `MelicumSystemVolume.driver`, and `local.melicum.*` identifiers. The driver keeps `kDriver_Name "HDMIAudioSystem"` only because BlackHole derives the device UID from it.
- Use original artwork and implementation.
- The logo is a lyre drawn as an equalizer: an EQ-curve yoke with three hollow nodes, strings ending on the curve, and an HDMI-receptacle sound box. Its construction follows `../gitdeck-ios` (flat two-tone fills carved by clear space around strokes and nodes); its "Vinyl and VU" palette is graphite, cream, and VU-needle red.
- The interface uses the logo palette only. Do not add user-selectable themes or accent colors.

## Implementation

- Use SwiftUI for the interface, Core Audio for routing, and C for realtime DSP.
- Keep allocation, file access, blocking synchronization, and UI work outside the audio callback.
- Preserve self-process exclusion, tap muting, and the shared physical output clock to prevent feedback.
- Restore the previous physical output before stopping the virtual device heartbeat.
- Keep system volume and mute synchronized without applying gain twice.
- Keep device disconnect, sample-rate changes, and unexpected process termination safe.
- Do not modify unrelated files in the sibling Gitdeck project.

## Build and validation

- Prefix every shell command with `rtk`; use `rtk proxy` when no dedicated wrapper applies.
- Reach first for `rg` and `rg --files` when searching.
- Run `rtk proxy swift test` after behavior changes.
- Build the app with `rtk proxy ./scripts/build.sh`.
- Regenerate artwork with `rtk proxy ./scripts/make-brand-icon.sh`.
- Build the optional HAL component package with `rtk proxy ./scripts/build-system-volume.sh` before packaging an app that needs an updated component.
- Close the running app before replacing its installed bundle. Preserve user settings.
- Verify UI and audio routing on macOS when changing native controls; a successful build alone does not prove audio behavior.
- Keep generated build artifacts out of source control, as specified in `.gitignore`.

`CLAUDE.md` must remain a relative symlink to this file, not a separate copy.
