import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../raw_files.dart' show isRawFile;
import 'common_image.dart';
import 'image_utils.dart';
import 'libraw.dart';

/// The live-drag preview's target long-edge size — matches the Python
/// app's LIVE_PREVIEW_MAX_DIM. Used only while a slider is actively being
/// dragged, so re-rendering stays fast enough to feel live; the settled
/// view always renders against [EditSourcePair.full] instead (the sensor's
/// native resolution, no downscale — there's no separate lower-resolution
/// "preview" tier to fall back to for the non-dragging state).
const int livePreviewMaxDimension = 800;

/// One decoded working-resolution RGB buffer (packed, 3 bytes/pixel) that
/// the render pipeline reads from.
class EditSource {
  const EditSource({
    required this.width,
    required this.height,
    required this.rgbBytes,
  });

  final int width;
  final int height;
  final Uint8List rgbBytes;
}

/// The two resolutions [decodeEditSources] produces for one photo: [full]
/// (sensor-native resolution, what the settled/non-dragging view renders
/// against) and [live] (downscaled to [livePreviewMaxDimension], for
/// responsiveness while a slider is being actively dragged).
class EditSourcePair {
  const EditSourcePair({required this.full, required this.live});

  final EditSource full;
  final EditSource live;
}

Uint8List _rgbBytes(img.Image image) =>
    image.getBytes(order: img.ChannelOrder.rgb);

/// Fully decodes the RAW file at [path] once, at full sensor resolution
/// with LibRaw's best available demosaic — this is what every photo
/// renders against, not an opt-in mode — and derives the smaller live-drag
/// buffer from it, so later adjustments only need to re-run the (much
/// cheaper) pixel-math pipeline, not the RAW decode.
///
/// [onStage], if given, is called as each [RawDecodeStage] of the
/// underlying LibRaw decode starts — see [decodeRawImage].
///
/// Designed to run via `compute()` (when [onStage] is null — a `compute()`
/// call only returns once, at the end, so it can't carry intermediate
/// stage signals) or via [decodeEditSourcesWithProgress] otherwise.
EditSourcePair? decodeEditSources(
  String path, {
  void Function(RawDecodeStage stage)? onStage,
}) {
  final decoded = isRawFile(path)
      ? decodeRawImage(path, onStage: onStage)
      : decodeCommonImage(path);
  if (decoded == null) {
    return null;
  }
  final full = img.Image.fromBytes(
    width: decoded.width,
    height: decoded.height,
    bytes: decoded.rgbBytes.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  final liveImage = fitToMaxDimension(full, livePreviewMaxDimension);
  return EditSourcePair(
    full: EditSource(
      width: decoded.width,
      height: decoded.height,
      rgbBytes: decoded.rgbBytes,
    ),
    live: EditSource(
      width: liveImage.width,
      height: liveImage.height,
      rgbBytes: _rgbBytes(liveImage),
    ),
  );
}

class _EditSourcesIsolateArgs {
  const _EditSourcesIsolateArgs(this.path, this.sendPort);

  final String path;
  final SendPort sendPort;
}

void _decodeEditSourcesIsolateEntry(_EditSourcesIsolateArgs args) {
  final result = decodeEditSources(
    args.path,
    onStage: (stage) => args.sendPort.send(stage),
  );
  args.sendPort.send(result);
}

/// Same work as [decodeEditSources], but run in a dedicated [Isolate]
/// (rather than `compute()`, which only returns once at the very end) so
/// [onProgress] can be called as each [RawDecodeStage] starts — the same
/// pattern `export_job.dart`'s `exportPhotoWithProgress` uses.
Future<EditSourcePair?> decodeEditSourcesWithProgress(
  String path,
  void Function(RawDecodeStage stage) onProgress,
) async {
  final receivePort = ReceivePort();
  final isolate = await Isolate.spawn(
    _decodeEditSourcesIsolateEntry,
    _EditSourcesIsolateArgs(path, receivePort.sendPort),
  );
  try {
    await for (final message in receivePort) {
      if (message is RawDecodeStage) {
        onProgress(message);
      } else {
        return message as EditSourcePair?;
      }
    }
    return null;
  } finally {
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}
