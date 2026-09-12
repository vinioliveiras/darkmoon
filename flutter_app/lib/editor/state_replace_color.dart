// Replace color (2026-09-13): the eyedropper that picks the colour to
// replace. The stage itself is render/replace_color.dart; this is the
// click on the canvas that sets `ReplaceColorR/G/B` from the rendered
// preview — the pixels the user is looking at, which is what the stage
// (last in the pipeline) compares against.
//
// A `part` of editor_screen.dart: same library, same private scope, no
// public API of its own.

part of '../editor_screen.dart';

extension _EditorReplaceColor on _EditorScreenState {
  void _toggleReplaceColorPick() {
    _rebuild(() {
      _replaceColorPicking = !_replaceColorPicking;
      if (_replaceColorPicking) {
        _wbEyedropperActive = false;
        _removeSourcePicking = false;
      }
    });
  }

  /// The canvas click while picking: averages a 5x5 patch of the rendered
  /// preview around ([nx], [ny]) (normalised over the shown image) and
  /// stores it as the colour to replace.
  Future<void> _onReplaceColorPick(double nx, double ny) async {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    final image = selected == null ? null : _renderedPreviews[selected.path];
    if (image == null) {
      _rebuild(() => _replaceColorPicking = false);
      return;
    }
    final width = image.width, height = image.height;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (!mounted || data == null) {
      return;
    }
    final bytes = data.buffer.asUint8List();
    final cx = (nx * (width - 1)).round().clamp(0, width - 1);
    final cy = (ny * (height - 1)).round().clamp(0, height - 1);
    var sumR = 0.0, sumG = 0.0, sumB = 0.0, n = 0;
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        final x = cx + dx, y = cy + dy;
        if (x < 0 || y < 0 || x >= width || y >= height) {
          continue;
        }
        final i = (y * width + x) * 4;
        sumR += bytes[i];
        sumG += bytes[i + 1];
        sumB += bytes[i + 2];
        n++;
      }
    }
    if (n == 0) {
      return;
    }
    _rebuild(() {
      _replaceColorPicking = false;
      _paramValues = {
        ..._paramValues,
        replaceColorPickedKey: 1.0,
        replaceColorRKey: (sumR / n).roundToDouble(),
        replaceColorGKey: (sumG / n).roundToDouble(),
        replaceColorBKey: (sumB / n).roundToDouble(),
      };
      _appliedPresetId = null;
    });
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }
}
