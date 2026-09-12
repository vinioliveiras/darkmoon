// Presets from other editors (2026-09-12): each reader turns one foreign
// file into a [Preset] carrying our own slider keys, and the store then
// writes it back out as a darkmoon `.xmp` — the library only ever holds
// one format, whatever came in.
//
// - `.lrtemplate` — Meridian's older preset format, a Lua table whose
//   `settings` block uses exactly the `crs:` names the `.xmp` reader
//   maps, so it shares that mapping outright. Still what most preset
//   packs sold online ship as.
// - `.pp3` — RawTherapee's processing profile, an INI file. Open format
//   with documented ranges; the sections we read are listed at
//   [presetFromPp3]. A `[Film Simulation]` naming one of the bundled
//   film stocks becomes our Film section.
// - `.costyle` — Capture One's style: XML of `<E K="…" V="…"/>` entries.
//   Read tolerantly (any element with K and V), mapped where the meaning
//   is the same as one of our sliders.
//
// Not read: darktable `.dtstyle` (each module's settings are a hex dump
// of a versioned C struct, so nothing short of darktable itself decodes
// them reliably), ON1 and Luminar (closed, undocumented containers).
//
// Every reader returns null for a file that is not what its extension
// claims, like `presetFromXmp` does.

import 'package:xml/xml.dart';

import '../render/tone_curve.dart';
import 'preset.dart';
import 'preset_xmp.dart';

/// Which reader handles [path], by extension; null for a file this
/// module does not read (an `.xmp` is the XMP reader's).
Preset? presetFromForeignFile(
  String path,
  String contents, {
  required String fallbackName,
}) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.lrtemplate')) {
    return presetFromLrTemplate(contents, fallbackName: fallbackName);
  }
  if (lower.endsWith('.pp3')) {
    return presetFromPp3(contents, fallbackName: fallbackName);
  }
  if (lower.endsWith('.costyle')) {
    return presetFromCoStyle(contents, fallbackName: fallbackName);
  }
  return null;
}

/// Extensions [presetFromForeignFile] reads, without the dot.
const foreignPresetExtensions = ['lrtemplate', 'pp3', 'costyle'];

// ---------------------------------------------------------------------
// .lrtemplate
// ---------------------------------------------------------------------

/// Reads a Meridian `.lrtemplate`. The values live in `settings = { … }`
/// as `Name = value,` lines with the `crs:` attribute names; curves are
/// flat `{ x0, y0, x1, y1, … }` lists on 0..255, like the XMP `rdf:Seq`.
Preset? presetFromLrTemplate(String source, {required String fallbackName}) {
  final settings = _luaBlock(source, 'settings');
  if (settings == null) {
    return null;
  }
  final scalars = <String, String>{};
  final lists = <String, List<double>>{};
  for (final m in RegExp(
    r'(\w+)\s*=\s*\{([^{}]*)\}',
    multiLine: true,
  ).allMatches(settings)) {
    lists[m.group(1)!] = [
      for (final part in m.group(2)!.split(','))
        if (double.tryParse(part.trim()) case final v?) v,
    ];
  }
  for (final m in RegExp(
    r'(\w+)\s*=\s*([^,{}\n]+)',
    multiLine: true,
  ).allMatches(settings)) {
    scalars[m.group(1)!] = m.group(2)!.trim();
  }
  if (scalars.isEmpty && lists.isEmpty) {
    return null;
  }
  double? attr(String name) {
    final raw = scalars[name];
    return raw == null ? null : double.tryParse(raw);
  }

  final title = RegExp(
    r'\btitle\s*=\s*"([^"]*)"',
  ).firstMatch(source)?.group(1)?.trim();
  final name = (title == null || title.isEmpty) ? fallbackName : title;
  return Preset(
    id: presetIdFromName(name),
    name: name,
    values: valuesFromCrsLookup(attr),
    curves: PhotoCurves(
      tone: _curveFromFlat(lists['ToneCurvePV2012']),
      red: _curveFromFlat(lists['ToneCurvePV2012Red']),
      green: _curveFromFlat(lists['ToneCurvePV2012Green']),
      blue: _curveFromFlat(lists['ToneCurvePV2012Blue']),
    ),
  );
}

/// The text between the braces of `name = {` … `}` in a Lua table,
/// brace-balanced; null when [name] is not there.
String? _luaBlock(String source, String name) {
  final start = RegExp('\\b$name\\s*=\\s*\\{').firstMatch(source);
  if (start == null) return null;
  var depth = 1;
  for (var i = start.end; i < source.length; i++) {
    final c = source[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return source.substring(start.end, i);
    }
  }
  return null;
}

List<CurvePoint> _curveFromFlat(List<double>? flat) {
  if (flat == null || flat.length < 4 || flat.length.isOdd) {
    return identityToneCurve;
  }
  return [
    for (var i = 0; i + 1 < flat.length; i += 2)
      CurvePoint(
        (flat[i] / 255).clamp(0.0, 1.0),
        (flat[i + 1] / 255).clamp(0.0, 1.0),
      ),
  ];
}

// ---------------------------------------------------------------------
// .pp3
// ---------------------------------------------------------------------

/// Reads a RawTherapee `.pp3`. Sections and keys read, with the range
/// each is converted from:
///
/// - `[Exposure]` Compensation (stops), Contrast, Saturation (-100..100),
///   Brightness (-100..100).
/// - `[Shadows & Highlights]` Highlights/Shadows 0..100 (recovery
///   strengths), only when Enabled.
/// - `[Vibrance]` Pastels/Saturated -100..100, averaged.
/// - `[White Balance]` Temperature (K) and Green (a multiplier around 1),
///   only for a Custom setting — a Camera setting is our as-shot.
/// - `[Sharpening]` Amount 1..1000 and Radius, only when Enabled.
/// - `[Local Contrast]` Amount as Clarity, `[Dehaze]` Strength.
/// - `[Vignetting Correction]` Amount -100..100, Radius as Midpoint.
/// - `[Film Simulation]` ClutFilename: when it names one of the bundled
///   film stocks, that film with Strength as its amount.
Preset? presetFromPp3(String source, {required String fallbackName}) {
  final sections = _parseIni(source);
  if (sections.isEmpty || !sections.containsKey('Version')) {
    return null;
  }
  final values = <String, double>{};
  double? num(String section, String key) {
    final raw = sections[section]?[key];
    return raw == null ? null : double.tryParse(raw);
  }

  bool enabled(String section) =>
      (sections[section]?['Enabled'] ?? 'true').toLowerCase() == 'true';

  if (num('Exposure', 'Compensation') case final v?) {
    values['Exposure'] = exposureFromStops(v);
  }
  if (num('Exposure', 'Contrast') case final v?) values['Contrast'] = v;
  if (num('Exposure', 'Saturation') case final v?) values['Saturation'] = v;
  if (num('Exposure', 'Brightness') case final v?) values['Brightness'] = v;
  if (enabled('Shadows & Highlights')) {
    if (num('Shadows & Highlights', 'Highlights') case final v?) {
      values['Highlights'] = -v;
    }
    if (num('Shadows & Highlights', 'Shadows') case final v?) {
      values['Shadows'] = v;
    }
  }
  if (enabled('Vibrance')) {
    final pastels = num('Vibrance', 'Pastels');
    final saturated = num('Vibrance', 'Saturated');
    if (pastels != null || saturated != null) {
      values['Vibrance'] = ((pastels ?? 0) + (saturated ?? 0)) / 2;
    }
  }
  if ((sections['White Balance']?['Setting'] ?? '').toLowerCase() == 'custom') {
    if (num('White Balance', 'Temperature') case final v?) {
      values['Temperature'] = v;
    }
    if (num('White Balance', 'Green') case final v?) {
      // RawTherapee's green multiplier is 1 at neutral, >1 toward green;
      // our Tint is 0 at neutral, positive toward magenta.
      values['Tint'] = ((1 - v) * 100).clamp(-150.0, 150.0);
    }
  }
  if (enabled('Sharpening')) {
    if (num('Sharpening', 'Amount') case final v?) {
      values['SharpenAmount'] = (v / 1000 * 150).clamp(0.0, 150.0);
    }
    if (num('Sharpening', 'Radius') case final v?) {
      values['SharpenRadius'] = v.clamp(0.5, 3.0);
    }
  }
  if (enabled('Local Contrast')) {
    if (num('Local Contrast', 'Amount') case final v?) {
      values['Clarity'] = v.clamp(-100.0, 100.0);
    }
  }
  if (enabled('Dehaze')) {
    if (num('Dehaze', 'Strength') case final v?) values['Dehaze'] = v;
  }
  if (enabled('Vignetting Correction')) {
    if (num('Vignetting Correction', 'Amount') case final v?) {
      values['VignetteAmount'] = v;
    }
    if (num('Vignetting Correction', 'Radius') case final v?) {
      values['VignetteMidpoint'] = v;
    }
  }
  if (enabled('Film Simulation')) {
    final clut = sections['Film Simulation']?['ClutFilename'];
    final film = clut == null ? null : bundledFilmIdForClutName(clut);
    if (film != null) {
      values['Film'] = film.toDouble();
      if (num('Film Simulation', 'Strength') case final v?) {
        values['FilmAmount'] = v.clamp(0.0, 100.0);
      }
    }
  }
  return Preset(
    id: presetIdFromName(fallbackName),
    name: fallbackName,
    values: values,
  );
}

/// The bundled film (see `assets/film_luts/manifest.json`) a RawTherapee
/// Film Simulation Collection file name refers to, by the stock named in
/// the file — push/pull suffixes (`1 -`, `2`, `3 +`) and folders are
/// ignored. Null for a stock that is not bundled.
int? bundledFilmIdForClutName(String clutFilename) {
  var stem = clutFilename.replaceAll('\\', '/').split('/').last;
  final dot = stem.lastIndexOf('.');
  if (dot > 0) stem = stem.substring(0, dot);
  final lower = stem.toLowerCase().trim();
  for (final (prefix, id) in _collectionStems) {
    if (lower.startsWith(prefix)) return id;
  }
  return null;
}

/// (lower-case file-name stem in the collection, bundled id) — the ids
/// are `tool/build_film_luts.dart`'s, in its order.
const _collectionStems = [
  ('kodak portra 160', 1),
  ('kodak portra 400', 2),
  ('kodak portra 800', 3),
  ('kodak ektar 100', 4),
  ('kodak kodachrome 64', 5),
  ('kodak ektachrome 100 vs', 6),
  ('fuji velvia 50', 7),
  ('fuji provia 100f', 8),
  ('fuji astia 100f', 9),
  ('fuji superia 200', 10),
  ('fuji superia 400', 11),
  ('agfa vista 200', 12),
  ('polaroid 690', 13),
  ('kodak tri-x 400', 14),
  ('ilford hp5 plus 400', 15),
];

Map<String, Map<String, String>> _parseIni(String source) {
  final sections = <String, Map<String, String>>{};
  Map<String, String>? current;
  for (final raw in source.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
      continue;
    }
    if (line.startsWith('[') && line.endsWith(']')) {
      current = sections.putIfAbsent(
        line.substring(1, line.length - 1).trim(),
        () => {},
      );
      continue;
    }
    final eq = line.indexOf('=');
    if (eq <= 0 || current == null) continue;
    current[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
  }
  return sections;
}

// ---------------------------------------------------------------------
// .costyle
// ---------------------------------------------------------------------

/// (Capture One key, our slider, scale) — the value is multiplied by
/// [scale], so a key whose range already matches ours has 1.
const _coStyleMappings = [
  ('Exposure', 'Exposure', 1.0), // stops, which is our slider's unit too
  ('Contrast', 'Contrast', 1.0),
  ('Brightness', 'Brightness', 1.0),
  ('Saturation', 'Saturation', 1.0),
  ('HighlightRecovery', 'Highlights', -1.0),
  ('Highlight', 'Highlights', -1.0),
  ('ShadowRecovery', 'Shadows', 1.0),
  ('Shadow', 'Shadows', 1.0),
  ('White', 'Whites', 1.0),
  ('Black', 'Blacks', 1.0),
  ('ClarityAmount', 'Clarity', 1.0),
  ('ClarityStructure', 'Texture', 1.0),
  ('Kelvin', 'Temperature', 1.0),
  ('Tint', 'Tint', 1.0),
  ('Dehaze', 'Dehaze', 1.0),
  ('DehazeAmount', 'Dehaze', 1.0),
  ('SharpeningAmount', 'SharpenAmount', 150.0 / 1000.0),
  ('SharpeningRadius', 'SharpenRadius', 1.0),
  ('VignettingAmount', 'VignetteAmount', 25.0), // EV (-4..4) -> -100..100
  ('FilmGrainAmount', 'GrainAmount', 1.0),
];

/// Reads a Capture One `.costyle`: every `<E K="key" V="value"/>` entry
/// is one setting. Only keys whose meaning matches one of our sliders
/// are taken (see [_coStyleMappings]); the rest are reported as
/// unsupported so the user knows the style did not carry over whole.
Preset? presetFromCoStyle(String source, {required String fallbackName}) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(source);
  } catch (_) {
    return null;
  }
  final entries = <String, String>{};
  for (final element in document.descendants.whereType<XmlElement>()) {
    final key = element.getAttribute('K');
    final value = element.getAttribute('V');
    if (key != null && value != null) {
      entries[key] = value;
    }
  }
  if (entries.isEmpty) {
    return null;
  }
  final values = <String, double>{};
  final supported = <String>{};
  for (final (theirs, ours, scale) in _coStyleMappings) {
    supported.add(theirs);
    final raw = entries[theirs];
    final v = raw == null ? null : double.tryParse(raw);
    if (v == null || values.containsKey(ours)) continue;
    values[ours] = v * scale;
  }
  final name =
      document.rootElement.getAttribute('Name')?.trim() ??
      document.rootElement.getAttribute('name')?.trim() ??
      fallbackName;
  return Preset(
    id: presetIdFromName(name.isEmpty ? fallbackName : name),
    name: name.isEmpty ? fallbackName : name,
    values: values,
    unsupportedAttributes: [
      for (final key in entries.keys)
        if (!supported.contains(key)) key,
    ],
  );
}
