import '../catalog/catalog_store.dart';
import '../catalog/curve_store.dart';
import '../catalog/mask_store.dart';
import '../catalog/photo_preset_store.dart';
import '../catalog/sidecar_xmp.dart';
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

  /// Every path any of the four maps knows.
  Set<String> get paths => {
    ...values.keys,
    ...curves.keys,
    ...masks.keys,
    ...presets.keys,
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
    ).wait;
    values = loaded.$1;
    curves = loaded.$2;
    masks = loaded.$3;
    presets = loaded.$4;
  }

  /// Persists the three edit maps — see `writeJsonFileAtomically` for
  /// the crash and overlap guarantees.
  Future<void> saveEdits() async {
    await saveCatalog(values);
    await savePhotoCurves(curves);
    await savePhotoMasks(masks);
  }

  Future<void> savePresets() => savePhotoPresets(presets);

  /// All four.
  Future<void> save() async {
    await saveEdits();
    await savePresets();
  }

  /// Drops [path] from every map (in memory only — follow with [save]).
  void removeWhere(bool Function(String path) test) {
    values.removeWhere((path, _) => test(path));
    curves.removeWhere((path, _) => test(path));
    masks.removeWhere((path, _) => test(path));
    presets.removeWhere((path, _) => test(path));
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
  PhotoSidecar sidecarFor(String path) => PhotoSidecar(
    values: values[path] ?? const {},
    curves: curves[path] ?? identityPhotoCurves,
    masks: masks[path] ?? const [],
    presetId: presets[path],
  );

  /// Mirrors [path]'s edits to the `.xmp` beside it — see
  /// `sidecar_xmp.dart`, which logs its own failures.
  Future<void> writeSidecar(String path) =>
      writeSidecarFile(path, sidecarFor(path));

  /// Takes [sidecar]'s edits as [path]'s (in memory — follow with
  /// [save]). The preset marker is only set, never cleared: a sidecar
  /// from another editor says nothing about presets.
  void adopt(String path, PhotoSidecar sidecar) {
    values[path] = {...sidecar.values};
    curves[path] = sidecar.curves;
    masks[path] = [...sidecar.masks];
    if (sidecar.presetId case final id?) {
      presets[path] = id;
    }
  }
}
