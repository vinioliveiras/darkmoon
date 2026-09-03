import 'dart:typed_data';
import 'dart:ui' as ui;

/// Pulls [image]'s pixels back as the packed-RGB `Float32List` (3 values
/// per pixel, 0-255) that `mask.dart`'s `computeMaskAlpha` and the
/// eyedropper samplers work in.
///
/// The canvas paints a render's own pixels directly now (see
/// `render_job.dart`'s `RenderResult.previewRgba`), so anything that needs
/// to *sample* what the user is looking at reads it back off that same
/// image instead of decoding a preview JPEG that no longer exists. It is
/// also exact: there is no lossy generation between the displayed frame
/// and the values a Color Range / Luminance mask measures against.
///
/// Returns null if the readback fails (`toByteData` is documented as
/// nullable). Must be called from the main isolate — same `dart:ui`
/// constraint as everything else that touches a `ui.Image`.
Future<Float32List?> rgbFloatsFromImage(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) {
    return null;
  }
  final rgba = byteData.buffer.asUint8List();
  final pixelCount = rgba.length ~/ 4;
  final rgb = Float32List(pixelCount * 3);
  var src = 0;
  for (var dst = 0; dst < rgb.length; dst += 3, src += 4) {
    rgb[dst] = rgba[src].toDouble();
    rgb[dst + 1] = rgba[src + 1].toDouble();
    rgb[dst + 2] = rgba[src + 2].toDouble();
  }
  return rgb;
}
