# darkmoon Color profiles

Fitted per-hue corrections (see `lib/render/color_profile.dart`) that nudge
darkmoon's neutral rendering toward how Meridian's "Adobe Color" profile
renders the same RAW.

2026-09-01: **per-hue only, tone curve forced to identity** — see
`tool/build_color_profile.dart`'s header comment for why (every real bug
this profile ever caused traced back to the old fitted tone curve's
brightness lift amplifying something downstream). Also fit against
whatever `libraw.dart`'s current `no_auto_bright` decodes with (today: on
== auto-bright enabled, darkmoon's normal baseline) rather than a special
decode-time flag, so this profile only ever changes render-time per-hue
color. Applied only under `ColorProfileMode.vivid` (`editor_screen.dart`)
— `ColorProfileMode.darkmoonDefault` never loads or applies it, by
design, regardless of whether this file is present.

Build one with:

    dart run tool/build_color_profile.dart <pairs-dir> assets/color_profiles/<name>.json "<Name>"

`<pairs-dir>` holds `<stem>.RAF` next to `<stem>.tif` / `.png` / `.jpg` —
the RAW and its Meridian export (Profile = Adobe Color, every slider 0,
WB As Shot, linear tone curve; prefer 16-bit TIFF or PNG over JPEG).

The app loads `darkmoon_vivid.json` if present (via `_loadColorProfile`
in `editor_screen.dart`); missing = no correction, same as before
profiles existed.
