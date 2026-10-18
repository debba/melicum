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

- `melicum-icon.svg`: macOS icon master. The tile follows the macOS grid: 824 px, inset 100 px, corner radius 185 px.
- `melicum-mark.svg`: transparent mark for light backgrounds.
- `melicum-mark-dark.svg`: transparent mark for dark backgrounds.
- `../BrandIcon.png`: 1024 px icon with alpha outside the tile.
- `../BrandMark.png`: transparent cream and red header mark for the dark app window.
- `../../docs/images/melicum-icon.png`: 512 px icon shown in the repository README.

The artwork is drawn from shared vector geometry in `scripts/make-icon.swift`.
Rebuild the SVG, PNG and ICNS assets from the project root:

```sh
zsh scripts/make-brand-icon.sh
```

This version is code-drawn vector artwork. It supersedes the earlier M-curve mark,
the previous imagegen concept, and its prompt; none of them are used by the app.
