import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../diagnostics/dev_log.dart';
import '../presets/preset_xmp.dart';
import '../render/mask.dart';
import '../render/tone_curve.dart';
import 'atomic_json_file.dart';
import 'curve_store.dart';
import 'mask_store.dart';

/// Per-photo `.xmp` sidecar files — one photo's edits written next to the
/// photo itself (`DSCF0345.RAF` → `DSCF0345.xmp`), the way Meridian's
/// "automatically write changes into XMP" does.
///
/// The catalog in `Documents/darkmoon` stays the source of truth while
/// the app runs; the sidecar is the copy that travels with the file. It
/// carries two layers:
///
/// * **`crs:` attributes** — the sliders and curves that have a Camera
///   Raw equivalent, through the same mapping the preset exporter uses
///   (`preset_xmp.dart`), so another editor opening the folder sees the
///   same numbers, and a sidecar another editor wrote gives this app its
///   sliders.
/// * **`darkmoon:` elements** — the complete edit state as JSON (every
///   slider including the ones with no `crs:` name, curves at full
///   precision, the mask stack, the applied preset id), so a round trip
///   through the sidecar is lossless for this app. When both layers are
///   present the `darkmoon:` one wins.
///
/// Plus the standard metadata a library needs and other tools already
/// write: `xmp:Rating` (0-5), `xmp:Label` (a colour name) and
/// `dc:subject` (keywords). Nothing in the editor sets them yet; a
/// rewrite preserves whatever the file already had, so a rating given in
/// another application survives an edit here.
const darkmoonNamespace = 'http://darkmoon.app/ns/1.0/';
const xmpNamespace = 'http://ns.adobe.com/xap/1.0/';
const dcNamespace = 'http://purl.org/dc/elements/1.1/';

/// Bumped when the `darkmoon:` layer changes shape in a way an older
/// build could misread. Readers accept anything ≤ their own version.
const sidecarFormatVersion = 1;

/// One photo's sidecar contents.
class PhotoSidecar {
  const PhotoSidecar({
    this.values = const {},
    this.curves = identityPhotoCurves,
    this.masks = const [],
    this.presetId,
    this.rating = 0,
    this.label = '',
    this.tags = const [],
  });

  /// Slider values, same keys as the catalog (`_edits`).
  final Map<String, double> values;
  final PhotoCurves curves;
  final List<MaskLayer> masks;

  /// Id of the preset shown as applied, if any.
  final String? presetId;

  /// `xmp:Rating`, 0 (none) to 5.
  final int rating;

  /// `xmp:Label` — a colour name such as `Red`, empty for none.
  final String label;

  /// `dc:subject` keywords.
  final List<String> tags;

  bool get hasEdits =>
      values.isNotEmpty || !curves.isIdentity || masks.isNotEmpty;

  bool get hasMetadata => rating != 0 || label.isNotEmpty || tags.isNotEmpty;

  PhotoSidecar copyWith({
    Map<String, double>? values,
    PhotoCurves? curves,
    List<MaskLayer>? masks,
    String? presetId,
    int? rating,
    String? label,
    List<String>? tags,
  }) => PhotoSidecar(
    values: values ?? this.values,
    curves: curves ?? this.curves,
    masks: masks ?? this.masks,
    presetId: presetId ?? this.presetId,
    rating: rating ?? this.rating,
    label: label ?? this.label,
    tags: tags ?? this.tags,
  );
}

/// The sidecar file for [photoPath]: same folder, same base name, `.xmp`.
File sidecarFileFor(String photoPath) =>
    File(p.setExtension(photoPath, '.xmp'));

/// Builds the sidecar document for [sidecar].
String xmpFromSidecar(PhotoSidecar sidecar) {
  final builder = XmlBuilder();
  builder.element(
    'x:xmpmeta',
    namespaces: {'adobe:ns:meta/': 'x'},
    attributes: {'x:xmptk': 'darkmoon'},
    nest: () {
      builder.element(
        'rdf:RDF',
        namespaces: {rdfNamespace: 'rdf'},
        nest: () {
          builder.element(
            'rdf:Description',
            namespaces: {
              xmpNamespace: 'xmp',
              dcNamespace: 'dc',
              crsNamespace: 'crs',
              darkmoonNamespace: 'darkmoon',
            },
            attributes: {
              'rdf:about': '',
              if (sidecar.rating != 0) 'xmp:Rating': sidecar.rating.toString(),
              if (sidecar.label.isNotEmpty) 'xmp:Label': sidecar.label,
              if (sidecar.hasEdits) ...{
                'crs:Version': crsVersion,
                'crs:ProcessVersion': crsProcessVersion,
                'crs:HasSettings': 'True',
                if (hasCustomCurves(sidecar.curves))
                  'crs:ToneCurveName2012': 'Custom',
                ...crsAttributesForValues(sidecar.values),
              },
              'darkmoon:Version': sidecarFormatVersion.toString(),
              if (sidecar.presetId case final id?) 'darkmoon:PresetId': id,
            },
            nest: () {
              if (sidecar.tags.isNotEmpty) {
                builder.element(
                  'dc:subject',
                  nest: () {
                    builder.element(
                      'rdf:Bag',
                      nest: () {
                        for (final tag in sidecar.tags) {
                          builder.element('rdf:li', nest: tag);
                        }
                      },
                    );
                  },
                );
              }
              if (sidecar.hasEdits) {
                writeCrsCurves(builder, sidecar.curves);
                builder.element(
                  'darkmoon:Values',
                  nest: jsonEncode(sidecar.values),
                );
                if (!sidecar.curves.isIdentity) {
                  builder.element(
                    'darkmoon:Curves',
                    nest: jsonEncode(encodePhotoCurves(sidecar.curves)),
                  );
                }
                if (sidecar.masks.isNotEmpty) {
                  builder.element(
                    'darkmoon:Masks',
                    nest: jsonEncode([
                      for (final mask in sidecar.masks) encodeMaskLayer(mask),
                    ]),
                  );
                }
              }
            },
          );
        },
      );
    },
  );
  final body = builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  return '<?xpacket begin="\u{feff}" id="W5M0MpCehiHzreSzNTczkc9d"?>\n'
      '$body\n'
      '<?xpacket end="w"?>';
}

/// Parses a sidecar — ours, or one written by another editor (only the
/// `crs:` sliders and the standard metadata come through then). Null when
/// [xmlSource] is not an XMP document at all.
PhotoSidecar? sidecarFromXmp(String xmlSource) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(xmlSource);
  } catch (_) {
    return null;
  }
  final description = document
      .findAllElements('Description', namespace: rdfNamespace)
      .firstOrNull;
  if (description == null) {
    return null;
  }

  // XMP allows every simple property either as an attribute or as a
  // child element; Meridian writes attributes, other tools elements.
  String? property(String namespace, String name) {
    final attribute = description.attributes
        .where((a) => a.name.local == name && a.name.namespaceUri == namespace)
        .firstOrNull;
    if (attribute != null) {
      return attribute.value;
    }
    return description
        .findElements(name, namespace: namespace)
        .firstOrNull
        ?.innerText;
  }

  Map<String, double> values;
  final ownValues = property(darkmoonNamespace, 'Values');
  if (ownValues != null) {
    try {
      values = {
        for (final entry
            in (jsonDecode(ownValues) as Map<String, dynamic>).entries)
          if (entry.value is num) entry.key: (entry.value as num).toDouble(),
      };
    } catch (e, st) {
      DevLog.logError('sidecar darkmoon:Values unreadable, using crs:', e, st);
      values = valuesFromCrsDescription(description);
    }
  } else {
    values = valuesFromCrsDescription(description);
  }

  var curves = curvesFromCrsDescription(description);
  final ownCurves = property(darkmoonNamespace, 'Curves');
  if (ownCurves != null) {
    try {
      curves = decodePhotoCurves(jsonDecode(ownCurves) as Map<String, dynamic>);
    } catch (e, st) {
      DevLog.logError('sidecar darkmoon:Curves unreadable, using crs:', e, st);
    }
  }

  var masks = const <MaskLayer>[];
  final ownMasks = property(darkmoonNamespace, 'Masks');
  if (ownMasks != null) {
    try {
      masks = [
        for (final raw in jsonDecode(ownMasks) as List)
          decodeMaskLayer(raw as Map<String, dynamic>),
      ];
    } catch (e, st) {
      DevLog.logError('sidecar darkmoon:Masks unreadable, dropped', e, st);
    }
  }

  final tags = [
    for (final subject in description.findElements(
      'subject',
      namespace: dcNamespace,
    ))
      for (final li in subject.findAllElements('li', namespace: rdfNamespace))
        if (li.innerText.trim() case final tag when tag.isNotEmpty) tag,
  ];

  return PhotoSidecar(
    values: values,
    curves: curves,
    masks: masks,
    presetId: property(darkmoonNamespace, 'PresetId'),
    rating: (int.tryParse(property(xmpNamespace, 'Rating')?.trim() ?? '') ?? 0)
        .clamp(0, 5),
    label: property(xmpNamespace, 'Label')?.trim() ?? '',
    tags: tags,
  );
}

/// [photoPath]'s sidecar, or null when there is none (or it is not XMP).
Future<PhotoSidecar?> readSidecar(String photoPath) async {
  final file = sidecarFileFor(photoPath);
  try {
    if (!await file.exists()) {
      return null;
    }
    return sidecarFromXmp(await file.readAsString());
  } catch (e, st) {
    DevLog.logError('sidecar read failed for $photoPath', e, st);
    return null;
  }
}

/// Writes [sidecar] next to [photoPath]. Rating, label and tags the file
/// already carries are kept when [sidecar] has none of its own, so
/// metadata written by another application survives an edit here. A
/// sidecar with nothing left to say (edits reset, no metadata) is
/// removed rather than left as an empty document. Errors are logged, not
/// thrown — every caller fires this from a save that must not fail
/// because the photo sits on a read-only volume.
Future<void> writeSidecarFile(String photoPath, PhotoSidecar sidecar) async {
  final file = sidecarFileFor(photoPath);
  try {
    var merged = sidecar;
    if (!sidecar.hasMetadata) {
      final existing = await readSidecar(photoPath);
      if (existing != null && existing.hasMetadata) {
        merged = sidecar.copyWith(
          rating: existing.rating,
          label: existing.label,
          tags: existing.tags,
        );
      }
    }
    if (!merged.hasEdits && !merged.hasMetadata && merged.presetId == null) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }
    await writeJsonFileAtomically(file, xmpFromSidecar(merged));
  } catch (e, st) {
    DevLog.logError('sidecar write failed for $photoPath', e, st);
  }
}
