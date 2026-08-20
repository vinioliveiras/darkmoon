import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'onnxruntime_bindings.dart';

/// Filename the tiled NAFNet-SIDD model is vendored under, next to
/// `onnxruntime.dll`/`DirectML.dll` — see `windows/native/` and
/// `windows/CMakeLists.txt`'s install(FILES ...) block.
const String _modelFileName = 'nafnet_sidd_width32.onnx';

/// Every tile this model was exported for must be exactly this size on
/// each side (divisible by 16, the network's downsample factor) — see
/// `third_party/onnxruntime_headers/README.md` and the model export notes.
const int nafnetTileSize = 256;

/// Thrown when an ONNX Runtime C API call returns a non-null `OrtStatus*`.
/// Carries the human-readable message `OrtApi::GetErrorMessage` returns,
/// since the status pointer itself isn't meaningful to callers.
class OrtException implements Exception {
  const OrtException(this.message);

  final String message;

  @override
  String toString() => 'OrtException: $message';
}

/// Resolves the ONNX Runtime API once per process. Mirrors `libraw.dart`'s
/// `_Lib` singleton, but with an extra layer of indirection: unlike LibRaw
/// (whose bindings are ordinary exported functions ffigen binds directly),
/// only `OrtGetApiBase` and the DirectML EP registration function are real
/// exports from `onnxruntime.dll` — every other operation (session/tensor
/// creation, `Run`, error handling) is reached through the `OrtApi`
/// function-pointer-table struct that `OrtGetApiBase().GetApi(...)`
/// returns, resolved here once and cached.
class _OrtLib {
  static OnnxruntimeBindings? _bindingsInstance;
  static Pointer<OrtApi>? _apiInstance;

  static OnnxruntimeBindings get bindings =>
      _bindingsInstance ??= OnnxruntimeBindings(_load());

  static Pointer<OrtApi> get api {
    final cached = _apiInstance;
    if (cached != null) {
      return cached;
    }
    final base = bindings.OrtGetApiBase();
    if (base == nullptr) {
      throw const OrtException('OrtGetApiBase returned null');
    }
    final apiPtr = base.ref.GetApi
        .asFunction<Pointer<OrtApi> Function(int version)>()(ORT_API_VERSION);
    if (apiPtr == nullptr) {
      throw const OrtException(
        'OrtApi unavailable for ORT_API_VERSION $ORT_API_VERSION — '
        'onnxruntime.dll is older than this app was built against',
      );
    }
    return _apiInstance = apiPtr;
  }

  static DynamicLibrary _load() {
    if (Platform.isWindows) {
      // Installed next to the executable by windows/CMakeLists.txt, same
      // as raw_r.dll.
      return DynamicLibrary.open('onnxruntime.dll');
    }
    throw UnsupportedError('ONNX Runtime is only wired up for Windows so far.');
  }

  /// Resolved once and reused for the process lifetime — unlike raw_r.dll's
  /// per-file open/close session, an ORT model session is expensive to
  /// stand up (graph load + DirectML EP init) and cheap to keep around.
  /// Not a Flutter asset: FFI/isolate code needs a real filesystem path,
  /// and this deliberately mirrors raw_r.dll's own "next to the exe"
  /// resolution rather than pulling in path_provider (kept dependency-free
  /// here the same way thumbnail_cache.dart's cache logic is, so this file
  /// stays safe to use from a `compute()`/spawned isolate).
  static String get modelPath =>
      p.join(p.dirname(Platform.resolvedExecutable), _modelFileName);
}

/// Throws [OrtException] with `status`'s message if it's non-null, and
/// always releases it — the same "check return code, free unconditionally"
/// discipline `libraw.dart` applies to LibRaw's error codes, adapted to
/// ORT's status-pointer convention.
void _check(Pointer<OrtStatus> status) {
  if (status == nullptr) {
    return;
  }
  try {
    final api = _OrtLib.api;
    final msgPtr = api.ref.GetErrorMessage
        .asFunction<Pointer<Char> Function(Pointer<OrtStatus>)>()(status);
    final message = msgPtr == nullptr
        ? 'unknown ONNX Runtime error'
        : msgPtr.cast<Utf8>().toDartString();
    throw OrtException(message);
  } finally {
    _OrtLib.api.ref.ReleaseStatus
        .asFunction<void Function(Pointer<OrtStatus>)>()(status);
  }
}

/// One loaded NAFNet-SIDD inference session, with the DirectML execution
/// provider registered — GPU-only by design (see `isDirectMLAvailable`):
/// this app doesn't fall back to ORT's default CPU execution provider.
///
/// Expensive to create (graph load + DirectML device init), so callers
/// should keep one instance around rather than recreating it per tile —
/// [DenoiseModel.instance] is a lazy singleton for that reason.
class DenoiseModel {
  DenoiseModel._(this._env, this._session, this._memoryInfo);

  // Never read directly, only kept alive: the env must outlive the
  // session for the process lifetime of this singleton (there's no
  // dispose path — same "just leak it, the process is about to exit
  // anyway" reasoning `libraw.dart` doesn't need since it opens/closes a
  // libraw_data_t* per call instead of holding a long-lived session).
  // ignore: unused_field
  final Pointer<OrtEnv> _env;
  final Pointer<OrtSession> _session;
  final Pointer<OrtMemoryInfo> _memoryInfo;

  static DenoiseModel? _instance;

  /// Lazily creates (once) and returns the shared model session. Throws
  /// [OrtException] if the model file is missing, the DirectML EP can't be
  /// registered (no DX12-capable GPU / driver too old), or session
  /// creation otherwise fails — callers that only want to know "is this
  /// available" should use [isDirectMLAvailable] instead, which catches
  /// this.
  static DenoiseModel get instance => _instance ??= _create();

  static DenoiseModel _create() {
    final api = _OrtLib.api;

    final envOut = calloc<Pointer<OrtEnv>>();
    final logId = 'darkmoon-onnx'.toNativeUtf8();
    final Pointer<OrtEnv> env;
    try {
      _check(
        api.ref.CreateEnv
            .asFunction<
              Pointer<OrtStatus> Function(
                int logSeverityLevel,
                Pointer<Char> logId,
                Pointer<Pointer<OrtEnv>> out,
              )
            >()(
          OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING.value,
          logId.cast(),
          envOut,
        ),
      );
      env = envOut.value;
    } finally {
      calloc.free(envOut);
      calloc.free(logId);
    }

    final optionsOut = calloc<Pointer<OrtSessionOptions>>();
    final Pointer<OrtSessionOptions> options;
    try {
      _check(
        api.ref.CreateSessionOptions
            .asFunction<
              Pointer<OrtStatus> Function(
                Pointer<Pointer<OrtSessionOptions>> out,
              )
            >()(optionsOut),
      );
      options = optionsOut.value;
    } finally {
      calloc.free(optionsOut);
    }

    try {
      // GPU-only requirement: registering the DirectML EP does not, by
      // itself, guarantee zero CPU execution — ORT's default behavior lets
      // individual graph nodes the DML EP doesn't support silently fall
      // back to the CPU EP. This session-config entry is the documented
      // mechanism to make that a hard failure instead (session creation
      // below then fails if any node can't run on DML), matching this
      // app's "GPU-only, no silent CPU fallback" requirement. Best-effort:
      // some ORT builds/versions have had this config entry not fully
      // enforced for every op type, so isDirectMLAvailable's real
      // session-creation probe (not just "did this call succeed") remains
      // the source of truth for whether the feature works end-to-end.
      final key = 'session.disable_cpu_ep_fallback'.toNativeUtf8();
      final value = '1'.toNativeUtf8();
      try {
        _check(
          api.ref.AddSessionConfigEntry
              .asFunction<
                Pointer<OrtStatus> Function(
                  Pointer<OrtSessionOptions>,
                  Pointer<Char>,
                  Pointer<Char>,
                )
              >()(options, key.cast(), value.cast()),
        );
      } finally {
        calloc.free(key);
        calloc.free(value);
      }

      _check(
        _OrtLib.bindings.OrtSessionOptionsAppendExecutionProvider_DML(
          options,
          0,
        ),
      );

      final modelPathPtr = _OrtLib.modelPath.toNativeUtf16();
      final sessionOut = calloc<Pointer<OrtSession>>();
      final Pointer<OrtSession> session;
      try {
        _check(
          api.ref.CreateSession
              .asFunction<
                Pointer<OrtStatus> Function(
                  Pointer<OrtEnv>,
                  Pointer<WChar>,
                  Pointer<OrtSessionOptions>,
                  Pointer<Pointer<OrtSession>> out,
                )
              >()(env, modelPathPtr.cast(), options, sessionOut),
        );
        session = sessionOut.value;
      } finally {
        calloc.free(modelPathPtr);
        calloc.free(sessionOut);
      }

      final memInfoOut = calloc<Pointer<OrtMemoryInfo>>();
      final Pointer<OrtMemoryInfo> memoryInfo;
      try {
        _check(
          api.ref.CreateCpuMemoryInfo
              .asFunction<
                Pointer<OrtStatus> Function(
                  int type,
                  int memType,
                  Pointer<Pointer<OrtMemoryInfo>> out,
                )
              >()(
            OrtAllocatorType.OrtDeviceAllocator.value,
            OrtMemType.OrtMemTypeDefault.value,
            memInfoOut,
          ),
        );
        memoryInfo = memInfoOut.value;
      } finally {
        calloc.free(memInfoOut);
      }

      return DenoiseModel._(env, session, memoryInfo);
    } finally {
      api.ref.ReleaseSessionOptions
          .asFunction<void Function(Pointer<OrtSessionOptions>)>()(options);
    }
  }

  /// Runs one [nafnetTileSize] x [nafnetTileSize] RGB tile through the
  /// model. [rgbTile] is packed, row-major, 3 floats/pixel (channel order
  /// R,G,B), already normalized to whatever range the model expects (see
  /// `third_party/onnxruntime_headers/README.md`'s export notes) —
  /// normalization/denormalization is the caller's responsibility, this
  /// function only marshals tensors and runs inference.
  ///
  /// Blocking native call — run on a background isolate, same convention
  /// as `libraw.dart`'s decode functions.
  Float32List runTile(Float32List rgbTile) {
    final expectedLength = nafnetTileSize * nafnetTileSize * 3;
    if (rgbTile.length != expectedLength) {
      throw ArgumentError(
        'rgbTile must have $expectedLength floats '
        '($nafnetTileSize x $nafnetTileSize x 3), got ${rgbTile.length}',
      );
    }
    final api = _OrtLib.api;

    // NCHW layout, matching the export's expected input shape.
    final shape = calloc<Int64>(4);
    shape[0] = 1;
    shape[1] = 3;
    shape[2] = nafnetTileSize;
    shape[3] = nafnetTileSize;

    final inputData = calloc<Float>(expectedLength);
    _packChwFromRgb(rgbTile, inputData.asTypedList(expectedLength));

    final inputValueOut = calloc<Pointer<OrtValue>>();
    final outputValue = calloc<Pointer<OrtValue>>();
    final inputNamePtr = 'input'.toNativeUtf8();
    final outputNamePtr = 'output'.toNativeUtf8();
    final inputNames = calloc<Pointer<Char>>();
    final outputNames = calloc<Pointer<Char>>();
    inputNames[0] = inputNamePtr.cast();
    outputNames[0] = outputNamePtr.cast();
    Pointer<OrtValue> inputValue = nullptr;

    try {
      _check(
        api.ref.CreateTensorWithDataAsOrtValue
            .asFunction<
              Pointer<OrtStatus> Function(
                Pointer<OrtMemoryInfo>,
                Pointer<Void>,
                int,
                Pointer<Int64>,
                int,
                int,
                Pointer<Pointer<OrtValue>> out,
              )
            >()(
          _memoryInfo,
          inputData.cast(),
          expectedLength * sizeOf<Float>(),
          shape,
          4,
          ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT.value,
          inputValueOut,
        ),
      );
      inputValue = inputValueOut.value;

      _check(
        api.ref.Run
            .asFunction<
              Pointer<OrtStatus> Function(
                Pointer<OrtSession>,
                Pointer<OrtRunOptions>,
                Pointer<Pointer<Char>>,
                Pointer<Pointer<OrtValue>>,
                int,
                Pointer<Pointer<Char>>,
                int,
                Pointer<Pointer<OrtValue>>,
              )
            >()(
          _session,
          nullptr,
          inputNames,
          inputValueOut,
          1,
          outputNames,
          1,
          outputValue,
        ),
      );

      final outDataOut = calloc<Pointer<Void>>();
      final Pointer<Void> outData;
      try {
        _check(
          api.ref.GetTensorMutableData
              .asFunction<
                Pointer<OrtStatus> Function(
                  Pointer<OrtValue>,
                  Pointer<Pointer<Void>> out,
                )
              >()(outputValue.value, outDataOut),
        );
        outData = outDataOut.value;
      } finally {
        calloc.free(outDataOut);
      }

      final chwOut = outData.cast<Float>().asTypedList(expectedLength);
      final rgbOut = Float32List(expectedLength);
      _unpackRgbFromChw(chwOut, rgbOut);
      return rgbOut;
    } finally {
      if (outputValue.value != nullptr) {
        api.ref.ReleaseValue.asFunction<void Function(Pointer<OrtValue>)>()(
          outputValue.value,
        );
      }
      if (inputValue != nullptr) {
        api.ref.ReleaseValue.asFunction<void Function(Pointer<OrtValue>)>()(
          inputValue,
        );
      }
      calloc.free(shape);
      calloc.free(inputData);
      calloc.free(inputValueOut);
      calloc.free(outputValue);
      calloc.free(inputNamePtr);
      calloc.free(outputNamePtr);
      calloc.free(inputNames);
      calloc.free(outputNames);
    }
  }
}

/// Rearranges packed-RGB (`[r,g,b,r,g,b,...]`) into planar NCHW
/// (`[r,r,r,...,g,g,g,...,b,b,b,...]`), the layout ONNX image models
/// conventionally expect.
void _packChwFromRgb(Float32List rgb, Float32List chwOut) {
  final pixelCount = nafnetTileSize * nafnetTileSize;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    chwOut[p] = rgb[i];
    chwOut[pixelCount + p] = rgb[i + 1];
    chwOut[pixelCount * 2 + p] = rgb[i + 2];
  }
}

/// Inverse of [_packChwFromRgb].
void _unpackRgbFromChw(Float32List chw, Float32List rgbOut) {
  final pixelCount = nafnetTileSize * nafnetTileSize;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    rgbOut[i] = chw[p];
    rgbOut[i + 1] = chw[pixelCount + p];
    rgbOut[i + 2] = chw[pixelCount * 2 + p];
  }
}

/// Probes whether AI Denoise can actually run on this machine — reuses
/// [DenoiseModel]'s real session-creation path (env → session options →
/// DML EP registration → session creation against the real vendored
/// model) as the capability check, rather than writing separate D3D12
/// device-enumeration code: if a session can be created, inference will
/// work; if the GPU/driver doesn't support DirectML (or is too old), the
/// same failure that would happen on first use happens here instead,
/// caught and reported as `false`.
///
/// Blocking native call — run on a background isolate. Expensive (session
/// creation, not a lightweight query), so callers should cache the result
/// rather than probing repeatedly.
bool probeDirectMlAvailable() {
  try {
    DenoiseModel.instance;
    return true;
  } catch (_) {
    return false;
  }
}
