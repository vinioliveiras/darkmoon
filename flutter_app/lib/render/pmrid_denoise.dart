import 'dart:typed_data';

import 'ai_denoise_tiling.dart';
import '../native/onnx_runtime.dart' show pmridDenoiseModelSpec;

/// Raw-domain denoise (PMRID, ECCV20 "Practical Deep Raw Image Denoising
/// on Mobile Devices") — unlike the sRGB-domain AI Enhance pipeline
/// (`ai_enhance.dart`'s NAFNet-SIDD pass, which runs *after* demosaic on
/// the final gamma-encoded RGB), this runs on the sensor's own Bayer data
/// *before* demosaic — see `native/pmrid_raw.dart` for how the raw buffer
/// is packed into/unpacked out of the 4-channel layout this function
/// expects, and `libraw.dart`'s `decodeRawImageWithPmridDenoise` for where
/// that packing sits relative to LibRaw's own unpack/demosaic calls.
///
/// [rggb] is packed, row-major, 4 floats/pixel — channel order R, G, G2, B
/// (PMRID's own reference `bayer2rggb`: each 2x2 Bayer block's top-left,
/// top-right, bottom-left, bottom-right pixel respectively), normalized to
/// [0,1] against the sensor's black/white levels. [rggbWidth]/[rggbHeight]
/// are in *packed* pixels (half the sensor's Bayer width/height each).
///
/// [denoise] is `OnnxModel.forSpec(pmridDenoiseModelSpec).runPackedTile`
/// (or a fake, for testing — same dependency-injection shape
/// `ai_enhance.dart`'s `enhanceImage` already uses). No FFI/native
/// dependency here; blocking (potentially many tile inferences), callers
/// must run this on a background isolate.
///
/// PMRID's own reference pipeline (`run_benchmark.py`) applies an
/// ISO-calibrated "K-Sigma" affine transform before/after inference,
/// derived from noise parameters measured on one specific phone sensor
/// (an Oppo Reno 10x) — darkmoon has no equivalent per-camera calibration
/// for arbitrary cameras. At the model's own anchor ISO that transform is
/// exactly the identity, leaving just a fixed input scale
/// ([isoAnchorScale], 256 — the paper's own anchor-ISO value); using that
/// scale unconditionally, regardless of the photo's actual ISO, is the
/// practical middle ground here. Confirmed (see PENDING.md item 13's raw
/// denoise section) to produce real, visible grain reduction with no
/// destructive blur on a real Canon 350D CR2 test shot at an unknown ISO —
/// not calibrated per-sensor, but not a no-op either.
Float32List denoisePmridRggb(
  Float32List rggb,
  int rggbWidth,
  int rggbHeight, {
  required Float32List Function(Float32List packedTile) denoise,
  double isoAnchorScale = 256.0,
  void Function(int tileIndex, int totalTiles)? onProgress,
}) {
  final scaled = Float32List(rggb.length);
  for (var i = 0; i < rggb.length; i++) {
    scaled[i] = rggb[i] * isoAnchorScale;
  }

  final denoisedScaled = denoiseTiled(
    scaled,
    rggbWidth,
    rggbHeight,
    inputTileSize: pmridDenoiseModelSpec.inputTileSize,
    overlap: pmridDenoiseModelSpec.inputTileSize ~/ 8,
    scaleFactor: pmridDenoiseModelSpec.scaleFactor,
    channels: pmridDenoiseModelSpec.channels,
    processTile: denoise,
    onProgress: onProgress,
  );

  final out = Float32List(denoisedScaled.length);
  for (var i = 0; i < denoisedScaled.length; i++) {
    out[i] = (denoisedScaled[i] / isoAnchorScale).clamp(0.0, 1.0);
  }
  return out;
}
