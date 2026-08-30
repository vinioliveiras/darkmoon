import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'onnxruntime_bindings.dart';

/// Describes one ONNX model's execution geometry — everything [OnnxModel]
/// needs to know to marshal tensors for it, without hand-coding a second
/// copy of the tensor-marshaling logic per model.
///
/// [inputTileSize]: every tile fed to the model must be exactly this many
/// pixels on each side. NAFNet-SIDD's own export is fully dynamic
/// (any width/height), but Real-ESRGAN's export is traced at a fixed
/// 64x64 input — using one fixed tile size for both keeps [OnnxModel]
/// itself model-agnostic rather than special-casing one of them.
/// [scaleFactor]: 1 for same-resolution models (denoise), 2/4 for
/// upscalers — the output tile is `inputTileSize * scaleFactor` per side.
class OnnxModelSpec {
  const OnnxModelSpec({
    required this.fileName,
    required this.inputTileSize,
    required this.scaleFactor,
  });

  final String fileName;
  final int inputTileSize;
  final int scaleFactor;

  int get outputTileSize => inputTileSize * scaleFactor;
}

/// NAFNet-SIDD-width64 (MIT, megvii-research/NAFNet, SIDD-trained —
/// real sensor noise, not synthetic gaussian) — reconstructive denoise +
/// film-grain removal. Exported with dynamic spatial dims; 256 is chosen
/// here (divisible by 16, the network's downsample factor) to balance
/// tile count against per-tile GPU overhead, same reasoning as the
/// original plan.
const denoiseModelSpec = OnnxModelSpec(
  fileName: 'NAFNet-SIDD-width64.onnx',
  inputTileSize: 256,
  scaleFactor: 1,
);

/// Real-ESRGAN x2plus (BSD-3-Clause, xinntao/Real-ESRGAN) — 2x super-
/// resolution / detail reconstruction. This particular export is traced
/// at a *fixed* 64x64 input (not dynamic like NAFNet's) — see
/// `third_party/onnxruntime_headers/README.md` for the provenance note
/// and the perf implication (many more, smaller tiles than the denoise
/// pass) this fixed size forces.
const upscaleModelSpec = OnnxModelSpec(
  fileName: 'Real-ESRGAN_x2plus.onnx',
  inputTileSize: 64,
  scaleFactor: 2,
);

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
      final override = _nativeDirOverride;
      if (override != null) {
        return DynamicLibrary.open(p.join(override, 'onnxruntime.dll'));
      }
      // Installed next to the executable by windows/CMakeLists.txt, same
      // as raw_r.dll.
      return DynamicLibrary.open('onnxruntime.dll');
    }
    throw UnsupportedError('ONNX Runtime is only wired up for Windows so far.');
  }

  /// Set only for standalone `dart run tool/*.dart` smoke tests (see
  /// `tool/onnx_denoise_smoke_test.dart`) — a bare `dart run` process's
  /// `Platform.resolvedExecutable` is the Dart SDK's own `dart.exe`, not
  /// this app's build output, so neither the DLL nor the model file would
  /// resolve without this override. Unset (the normal app run/build path),
  /// this is a no-op and behavior is unchanged.
  static String? get _nativeDirOverride =>
      Platform.environment['DARKMOON_NATIVE_DIR'];

  /// Resolved once and reused for the process lifetime — unlike raw_r.dll's
  /// per-file open/close session, an ORT model session is expensive to
  /// stand up (graph load + DirectML EP init) and cheap to keep around.
  /// Not a Flutter asset: FFI/isolate code needs a real filesystem path,
  /// and this deliberately mirrors raw_r.dll's own "next to the exe"
  /// resolution rather than pulling in path_provider (kept dependency-free
  /// here the same way thumbnail_cache.dart's cache logic is, so this file
  /// stays safe to use from a `compute()`/spawned isolate).
  static String modelPath(String fileName) => p.join(
    _nativeDirOverride ?? p.dirname(Platform.resolvedExecutable),
    fileName,
  );
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

/// One loaded inference session for a given [OnnxModelSpec] — either the
/// denoise or the upscale model, both go through this same class.
///
/// Tries the DirectML execution provider first (GPU); if that fails for
/// any reason (no DX12-capable GPU, driver too old, a graph node DML
/// can't run), transparently falls back to ORT's default CPU execution
/// provider instead of failing outright — slower, but always available.
/// [usingGpu] reports which one actually ended up running, so callers can
/// warn the user ("this will be slower on CPU") rather than silently
/// eating the cost.
///
/// Expensive to create (graph load + DirectML device init), so callers
/// should keep one instance around rather than recreating it per tile —
/// [OnnxModel.forSpec] caches one instance per model file for that reason.
class OnnxModel {
  OnnxModel._(
    this._spec,
    this._env,
    this._session,
    this._memoryInfo,
    this.usingGpu,
    this.directMlError,
  );

  // Never read directly, only kept alive: the env must outlive the
  // session for the process lifetime of this singleton (there's no
  // dispose path — same "just leak it, the process is about to exit
  // anyway" reasoning `libraw.dart` doesn't need since it opens/closes a
  // libraw_data_t* per call instead of holding a long-lived session).
  // ignore: unused_field
  final Pointer<OrtEnv> _env;
  final Pointer<OrtSession> _session;
  final Pointer<OrtMemoryInfo> _memoryInfo;
  final OnnxModelSpec _spec;

  /// True if this session is actually running on the DirectML (GPU)
  /// execution provider; false if it fell back to plain CPU.
  final bool usingGpu;

  /// The `OrtException.message` from the DirectML attempt, if [usingGpu]
  /// is false because that attempt failed (null if it never ran, or if it
  /// succeeded). Surfaced through dev-mode logging so a "why did this fall
  /// back to CPU" bug report carries the real reason (an unsupported op,
  /// a driver issue, etc.) instead of just the fact that it happened.
  final String? directMlError;

  static final Map<String, OnnxModel> _instances = {};

  /// Lazily creates (once per [spec]) and returns a shared model session.
  /// Throws [OrtException] only if *both* the GPU and CPU session-creation
  /// attempts fail (e.g. the model file itself is missing/corrupt) —
  /// a GPU-only failure is caught internally and silently retried on CPU.
  static OnnxModel forSpec(OnnxModelSpec spec) =>
      _instances[spec.fileName] ??= _create(spec);

  static OnnxModel _create(OnnxModelSpec spec) {
    try {
      return _createSession(spec, useDirectMl: true);
    } on OrtException catch (e) {
      // GPU path failed (no DX12-capable GPU, driver too old, or a node
      // DML can't run) — fall back to CPU rather than making the whole
      // feature unavailable. If this *also* throws, the real problem is
      // something more fundamental (missing/corrupt model file) and
      // should propagate. Keep e.message: it's the only place the actual
      // DirectML rejection reason is ever available.
      return _createSession(spec, useDirectMl: false, directMlError: e.message);
    }
  }

  static OnnxModel _createSession(
    OnnxModelSpec spec, {
    required bool useDirectMl,
    String? directMlError,
  }) {
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
      if (useDirectMl) {
        // Ask ORT to fail session creation outright if any graph node
        // can't run on DML, rather than silently mixing in the CPU EP
        // node-by-node — that "did it actually fully succeed on GPU"
        // signal is exactly what decides whether _create falls back to
        // a full CPU session below. Best-effort: some ORT builds/versions
        // haven't fully enforced this for every op type, so a session
        // that "succeeds" here is still only a strong signal, not an
        // absolute guarantee, that zero CPU execution happened.
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
      }
      // useDirectMl == false: append nothing — ORT always registers its
      // own CPU execution provider by default, no explicit call needed.

      final modelPathPtr = _OrtLib.modelPath(spec.fileName).toNativeUtf16();
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

      return OnnxModel._(
        spec,
        env,
        session,
        memoryInfo,
        useDirectMl,
        directMlError,
      );
    } finally {
      api.ref.ReleaseSessionOptions
          .asFunction<void Function(Pointer<OrtSessionOptions>)>()(options);
    }
  }

  /// Runs one [OnnxModelSpec.inputTileSize] x `inputTileSize` RGB tile
  /// through the model, returning an [OnnxModelSpec.outputTileSize] x
  /// `outputTileSize` RGB tile. [rgbTile] is packed, row-major, 3
  /// floats/pixel (channel order R,G,B), already normalized to whatever
  /// range the model expects (see `third_party/onnxruntime_headers/
  /// README.md`'s export notes) — normalization/denormalization is the
  /// caller's responsibility, this function only marshals tensors and
  /// runs inference.
  ///
  /// Blocking native call — run on a background isolate, same convention
  /// as `libraw.dart`'s decode functions.
  Float32List runTile(Float32List rgbTile) {
    final inSize = _spec.inputTileSize;
    final outSize = _spec.outputTileSize;
    final expectedInLength = inSize * inSize * 3;
    final expectedOutLength = outSize * outSize * 3;
    if (rgbTile.length != expectedInLength) {
      throw ArgumentError(
        'rgbTile must have $expectedInLength floats '
        '($inSize x $inSize x 3), got ${rgbTile.length}',
      );
    }
    final api = _OrtLib.api;

    // NCHW layout, matching the export's expected input shape.
    final shape = calloc<Int64>(4);
    shape[0] = 1;
    shape[1] = 3;
    shape[2] = inSize;
    shape[3] = inSize;

    final inputData = calloc<Float>(expectedInLength);
    _packChwFromRgb(rgbTile, inputData.asTypedList(expectedInLength), inSize);

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
          expectedInLength * sizeOf<Float>(),
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

      final chwOut = outData.cast<Float>().asTypedList(expectedOutLength);
      final rgbOut = Float32List(expectedOutLength);
      _unpackRgbFromChw(chwOut, rgbOut, outSize);
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
void _packChwFromRgb(Float32List rgb, Float32List chwOut, int tileSize) {
  final pixelCount = tileSize * tileSize;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    chwOut[p] = rgb[i];
    chwOut[pixelCount + p] = rgb[i + 1];
    chwOut[pixelCount * 2 + p] = rgb[i + 2];
  }
}

/// Inverse of [_packChwFromRgb].
void _unpackRgbFromChw(Float32List chw, Float32List rgbOut, int tileSize) {
  final pixelCount = tileSize * tileSize;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    rgbOut[i] = chw[p];
    rgbOut[i + 1] = chw[pixelCount + p];
    rgbOut[i + 2] = chw[pixelCount * 2 + p];
  }
}

/// Probes whether the given model can load at all (GPU or CPU — see
/// [OnnxModel]'s fallback behavior) on this machine. Reuses [OnnxModel]'s
/// real session-creation path as the capability check, rather than writing
/// separate device-enumeration code: if a session can be created, inference
/// will work.
///
/// Blocking native call — run on a background isolate. Expensive (session
/// creation, not a lightweight query), so callers should cache the result
/// rather than probing repeatedly.
bool probeOnnxAvailable(OnnxModelSpec spec) {
  try {
    OnnxModel.forSpec(spec);
    return true;
  } catch (_) {
    return false;
  }
}
