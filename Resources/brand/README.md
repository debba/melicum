# Melicum identity

A lyre drawn as an equalizer. The name comes from the Latin *melicus*, "lyrical",
the poetry sung to the lyre.

- The yoke is an EQ curve with three hollow control nodes; the outer nodes double as tuning pegs.
- Each string ends exactly on the curve, so its length reads as the gain of that band.
- The sound box has the profile of an HDMI receptacle, with an engraved contact slot.
- The horns flare outward above the yoke, like a Greek lyre.

Flat two-tone fills carved by clear space around every stroke and node follow the
construction of the user's `../gitdeck-ios/ios/Assets/brand` reference.

## Palette: Vinyl and VU

| Role | Color |
| --- | --- |
| Tile, light center | `#3D3D46` |
| Tile | `#26262D` |
| Tile, dark edge | `#111114` |
| Strokes and left arm | `#F3EDE2` |
| Right arm (VU-needle red) | `#FF5A47` |
| Ink on light backgrounds | `#1E1E24` |
| Red on light backgrounds | `#DE3B29` |

## Files

- `../AppIcon.icon`: native Icon Composer document. Its full-canvas graphite background and transparent lyre layer let modern macOS apply the outer shape without adding a second frame. Glass, shadows, and translucency on the lyre are disabled to preserve the flat cream and red artwork.
- `../AppIcon.icon/Assets/Lyre.png`: generated foreground layer, using the same geometry and proportions as the legacy icon.
- `melicum-icon.svg`: legacy macOS icon master. The tile follows the older macOS grid: 824 px, inset 100 px, corner radius 185 px.
- `melicum-mark.svg`: transparent mark for light backgrounds.
- `melicum-mark-dark.svg`: transparent mark for dark backgrounds.
- `../BrandIcon.png`: 1024 px icon with alpha outside the tile.
- `../BrandMark.png`: transparent cream and red header mark for the dark app window.
- `../../docs/images/melicum-icon.png`: 512 px icon shown in the repository README.

The artwork is drawn from shared vector geometry in `scripts/make-icon.swift`.
Rebuild the SVG, PNG, native foreground, and legacy ICNS assets from the project root:

```sh
./scripts/make-brand-icon.sh
```

`scripts/build.sh` compiles the native document into `Assets.car` with Xcode's `actool` and bundles the legacy ICNS for earlier macOS releases. Packaging requires Xcode 26 or later. The editable `icon.json` is maintained in Icon Composer and is preserved when regenerating the artwork.

This version is code-drawn vector artwork. It supersedes the earlier M-curve mark,
the previous imagegen concept, and its prompt; none of them are used by the app.
