import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../render/mask.dart';

/// Bump when anything changes what a model would produce for the same
/// photo and prompt — a different model file, different preprocessing, a
/// different working resolution. (2 = the input is tonally levelled before
/// inference, `autoLevelForAiMask`; 3 = the SAM-backed Subject type is
/// gone, and with it the prompt that used to be part of every key.) Folded into every key, same role
/// `colorize_cache.dart`'s `colorizeCacheVersion` plays there.
const int aiMaskCacheVersion = 3;

/// Identifies one cached model output.
///
/// [frameSignature] is a hash of the exact pixels the model was shown —
/// see [aiMaskFrameSignature] — and [kind] separates the models ('sky',
/// 'depth', ...). Nothing else: none of these types takes a prompt.
///
/// `path_provider`-free, like the rest of this file — safe to call from a
/// background isolate.
String aiMaskCacheKey({
  required String frameSignature,
  required String kind,
}) => sha1
    .convert(utf8.encode('$frameSignature|$kind|v$aiMaskCacheVersion'))
    .toString();

/// Hashes the frame a map was computed from.
///
/// The pixels themselves, rather than the photo's path and mtime plus
/// some enumeration of the crop and lens settings that produced them.
/// These maps live in the *cropped* frame the render runs on, so every
/// input to that frame has to be part of the key — and hashing the result
/// gets lens correction, crop, straighten, upright and the working
/// resolution all at once, with no field that can be forgotten here when
/// a new geometry stage is added over there. A few milliseconds against
/// the seconds of inference it guards.
String aiMaskFrameSignature(Uint8List rgb) =>
    sha1.convert(rgb).toString();

File _entryFile(String cacheDir, String key, String extension) =>
    File(p.join(cacheDir, '$key.$extension'));

/// Reads back a map stored by [storeAiMaskMap]. Null on a miss or on any
/// read failure — a cache that cannot be read is a cache miss, not an
/// error, same discipline as every other cache here.
Future<AiMaskMap?> lookupAiMaskMap(String cacheDir, String key) async {
  try {
    final file = _entryFile(cacheDir, key, 'aimask');
    if (!await file.exists()) {
      return null;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length < 8) {
      return null;
    }
    final header = bytes.buffer.asUint32List(bytes.offsetInBytes, 2);
    final width = header[0];
    final height = header[1];
    if (width <= 0 || height <= 0 || bytes.length != 8 + width * height) {
      return null;
    }
    return AiMaskMap(
      width: width,
      height: height,
      data: Uint8List.sublistView(bytes, 8),
    );
  } catch (_) {
    return null;
  }
}

/// Writes [map] as its two dimensions followed by its raw bytes — no
/// image container, because nothing but this file ever reads it and a PNG
/// encode/decode round trip would cost more than the disk it saves.
/// tmp-then-rename, same crash-safety as `catalog_store.dart`.
Future<void> storeAiMaskMap(
  String cacheDir,
  String key,
  AiMaskMap map,
) async {
  try {
    final out = Uint8List(8 + map.data.length);
    out.buffer.asUint32List(0, 2)
      ..[0] = map.width
      ..[1] = map.height;
    out.setAll(8, map.data);
    final dest = _entryFile(cacheDir, key, 'aimask');
    final tmp = File('${dest.path}.tmp');
    await tmp.writeAsBytes(out, flush: true);
    await tmp.rename(dest.path);
  } catch (_) {
    // Best-effort: the caller already holds the map it just computed.
  }
}
