/// Bump this whenever a change to `libraw.dart`'s decode params
/// (`RawImage`/`decodeRawImage`) would meaningfully change a RAW's
/// resulting pixels — anything that isn't purely a speed/quality-tier
/// knob a cache already namespaces on its own (preview resolution is;
/// `no_auto_bright`, `highlight`, `gamm`, `use_camera_matrix` etc. are
/// not). The on-disk preview/native-source caches
/// (`catalog/preview_cache_dir.dart`, `catalog/native_source_cache.dart`)
/// fold this into their directory path, so a bump here starts every
/// cached photo from a clean, freshly-decoded slate instead of silently
/// mixing old and new pixels under the same key — the bug that made
/// `no_auto_bright` + the "darkmoon Color" tone curve double up on
/// stale, pre-change decodes (2026-08-29): the cache only keys on
/// `sha1(path|mtime|size)`, which the RAW file itself never changes just
/// because darkmoon's own decode logic did.
///
/// No Flutter/ffi imports here on purpose — both the cache-dir resolvers
/// (path_provider, main-isolate-only) and libraw.dart (dart:ffi) need to
/// read this without pulling the other's dependencies in.
const int rawDecodeFormatVersion = 3;
