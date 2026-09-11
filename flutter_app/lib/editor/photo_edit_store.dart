import '../catalog/catalog_store.dart';
import '../catalog/curve_store.dart';
import '../catalog/mask_store.dart';
import '../catalog/photo_meta_store.dart';
import '../catalog/photo_preset_store.dart';
import '../catalog/sidecar_xmp.dart';
import '../library/photo_mover.dart' show rekeyUnderFolder;
import '../render/mask.dart';
import '../render/tone_curve.dart';

/// Every photo's saved edits, keyed by absolute path — the in-memory
/// twin of the four JSON stores in `Documents/darkmoon` (slider values,
/// curves, mask stacks, applied preset ids) and of the `.xmp` sidecar
/// beside each photo.
///
/// Extracted from the editor screen's State (2026-09-10) as the first of
/// its controllers: the editor owns one of these, reads the maps
/// directly, and asks it to load, save and mirror to sidecars. It holds
/// no widget state and knows nothing about which photo is selected, so
/// it can be exercised without a widget tree.
///
/// Loaded once at startup; not guarded against edits made before that
/// finishes, since reading a small JSON file is effectively instant next
/// to how long opening a folder via a native file dialog takes.
class PhotoEditStore {
  /// Slider values per photo.
  Map<String, Map<String, double>> values = {};

  /// Tone Curve + Color Curve control points per photo — its own file,
  /// since a curve is a list of points, not a single double.
  Map<String, PhotoCurves> curves = {};

  /// Mask stacks per photo — structured data, its own file too.
  Map<String, List<MaskLayer>> masks = {};

  /// Which preset id was last applied to each photo, so the Presets
  /// panel still marks it as applied after a restart. Purely a UI hint;
  /// the actual edit lives in [values]/[curves]/[masks].
  Map<String, String> presets = {};

  /// Rating, colour label and keywords per photo — not an edit, but it
  /// rides in the same sidecar, so it lives here too.
  Map<String, PhotoMeta> meta = {};

  /// Every path any of the maps knows.
  Set<String> get paths => {
    ...values.keys,
    ...curves.keys,
    ...masks.keys,
    ...presets.keys,
    ...meta.keys,
  };

  /// Whether [path] has a saved edit of any kind (a preset marker alone
  /// does not count — it is a hint about an edit, not one).
  bool contains(String path) =>
      values.containsKey(path) ||
      curves.containsKey(path) ||
      masks.containsKey(path);

  /// Reads all four stores. Each one that is missing or unreadable comes
  /// back empty (the stores log that themselves).
  Future<void> load() async {
    final loaded = await (
      loadCatalog(),
      loadPhotoCurves(),
      loadPhotoMasks(),
      loadPhotoPresets(),
      loadPhotoMeta(),
    ).wait;
    values = loaded.$1;
    curves = loaded.$2;
    masks = loaded.$3;
    presets = loaded.$4;
    meta = loaded.$5;
  }

  /// Persists the three edit maps — see `writeJsonFileAtomically` for
  /// the crash and overlap guarantees.
  Future<void> saveEdits() async {
    await saveCatalog(values);
    await savePhotoCurves(curves);
    await savePhotoMasks(masks);
  }

  Future<void> savePresets() => savePhotoPresets(presets);

  Future<void> saveMeta() => savePhotoMeta(meta);

  /// All five.
  Future<void> save() async {
    await saveEdits();
    await savePresets();
    await saveMeta();
  }

  /// Sets [path]'s rating/label/tags (in memory — follow with [saveMeta]);
  /// an empty [PhotoMeta] removes the entry.
  void setMeta(String path, PhotoMeta value) {
    if (value.isEmpty) {
      meta.remove(path);
    } else {
      meta[path] = value;
    }
  }

  /// Moves every entry keyed by a path in [renames] (old → new) to the
  /// new path, in every map — a photo moved on disk keeps its edits,
  /// preset marker and rating. In memory only; follow with [save].
  void rekey(Map<String, String> renames) {
    if (renames.isEmpty) {
      return;
    }
    values = _rekeyed(values, renames);
    curves = _rekeyed(curves, renames);
    masks = _rekeyed(masks, renames);
    presets = _rekeyed(presets, renames);
    meta = _rekeyed(meta, renames);
  }

  /// [rekey] for every path that is [oldFolder] or inside it — a folder
  /// moved on disk.
  void rekeyFolder(String oldFolder, String newFolder) {
    final renames = <String, String>{};
    for (final path in paths) {
      final next = rekeyUnderFolder(path, oldFolder, newFolder);
      if (next != path) {
        renames[path] = next;
      }
    }
    rekey(renames);
  }

  static Map<String, T> _rekeyed<T>(
    Map<String, T> map,
    Map<String, String> renames,
  ) => {
    for (final entry in map.entries)
      renames[entry.key] ?? entry.key: entry.value,
  };

  /// Drops [path] from every map (in memory only — follow with [save]).
  void removeWhere(bool Function(String path) test) {
    values.removeWhere((path, _) => test(path));
    curves.removeWhere((path, _) => test(path));
    masks.removeWhere((path, _) => test(path));
    presets.removeWhere((path, _) => test(path));
    meta.removeWhere((path, _) => test(path));
  }

  /// Deletes the three edit stores on disk and empties their maps — the
  /// Settings "clear catalog" action. Preset markers are left alone, as
  /// they always were: a marker for a photo with no edit is harmless and
  /// the next flush of that photo overwrites it.
  Future<void> clear() async {
    await clearCatalog();
    await clearPhotoCurves();
    await clearPhotoMasks();
    values = {};
    curves = {};
    masks = {};
  }

  /// [path]'s edits as one sidecar document.
  PhotoSidecar sidecarFor(String path) {
    final m = meta[path] ?? const PhotoMeta();
    return PhotoSidecar(
      values: values[path] ?? const {},
      curves: curves[path] ?? identityPhotoCurves,
      masks: masks[path] ?? const [],
      presetId: presets[path],
      rating: m.rating,
      label: m.label,
      tags: m.tags,
    );
  }

  /// Mirrors [path]'s edits to the `.xmp` beside it — see
  /// `sidecar_xmp.dart`, which logs its own failures.
  Future<void> writeSidecar(String path) =>
      writeSidecarFile(path, sidecarFor(path));

  /// Takes [sidecar]'s edits as [path]'s (in memory — follow with
  /// [save]). The preset marker is only set, never cleared: a sidecar
  /// from another editor says nothing about presets. Rating, label and
  /// tags come along when the sidecar has any — see [adoptMeta].
  void adopt(String path, PhotoSidecar sidecar) {
    values[path] = {...sidecar.values};
    curves[path] = sidecar.curves;
    masks[path] = [...sidecar.masks];
    if (sidecar.presetId case final id?) {
      presets[path] = id;
    }
    adoptMeta(path, sidecar);
  }

  /// Takes [sidecar]'s rating/label/tags as [path]'s when it has any —
  /// a rating given in another application, seen here for the first
  /// time. Returns whether anything was taken.
  bool adoptMeta(String path, PhotoSidecar sidecar) {
    if (!sidecar.hasMetadata) {
      return false;
    }
    meta[path] = PhotoMeta(
      rating: sidecar.rating,
      label: sidecar.label,
      tags: sidecar.tags,
    );
    return true;
  }
}
