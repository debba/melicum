# Changelog

## 0.3.1 — 2026-10-18

- Fix the virtual output's maximum volume being limited by the physical device's previous volume on outputs with native volume controls.
- Synchronize writable physical master or channel volume controls with the virtual slider, applying master attenuation once. Fixed-volume HDMI and DisplayPort outputs retain software volume control.
- Synchronize supported physical mute controls and keep the requested volume and mute state when restoring the physical output.
- Set virtual volume and mute after selecting the default output, preserving the chosen startup level when macOS restores cached device controls.
- Stop processing safely if a physical volume or mute control fails, and add regression tests for native, per-channel and fixed-volume outputs.

Existing audio settings and presets are retained. This fix does not require reinstalling the optional system volume component.

## 0.3.0 — 2026-10-18

- Redesign the main window as an audio console with persistent master controls, compact navigation and inset editing panels.
- Coordinate buttons, checkbox and switch states, segmented selectors, fields and keyboard focus with the original graphite, cream and red logo palette. The logo artwork is unchanged.
- Refine the EQ graph with hollow control nodes and a subtle response fill.
- Redesign the menu bar panel around volume, mute and quick access to the main window.
- Preserve native accessibility roles, selected values and disabled states for the redesigned controls.
- Add a scoped uninstall script with dry-run, personal-data purge and local build cleanup options.
- Refresh documentation screenshots and add a reproducible capture script with isolated example data.
- Document startup preferences, every settings panel, preset recall and signed automatic update checks, including the confirmation required before installation.

The audio engine, virtual device identity and installed bundle identifier remain compatible with 0.2.2. Existing audio settings and presets are retained by an app update.
