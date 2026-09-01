# darkmoon Color profiles

Fitted per-hue corrections (see `lib/render/color_profile.dart`) that nudge
darkmoon's neutral rendering toward how Meridian's "Adobe Color" profile
renders the same RAW — the HueSatMap half of what an Adobe camera profile
bakes in (the tone half is `calBaseContrast`).

Build one with:

    dart run tool/build_color_profile.dart <pairs-dir> assets/color_profiles/<name>.json "<Name>"

`<pairs-dir>` holds `<stem>.RAF` next to `<stem>.tif` / `.png` / `.jpg` —
the RAW and its Meridian export (Profile = Adobe Color, every slider 0,
WB As Shot, linear tone curve; prefer 16-bit TIFF or PNG over JPEG).

The app loads `darkmoon_fuji.json` if present (via `loadColorProfile`);
missing = no correction, same as before profiles existed.
