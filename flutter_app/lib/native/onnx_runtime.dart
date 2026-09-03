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
/// pixels on each side. Every bundled model's export happens to be fully
/// dynamic (any width/height) — a fixed tile size is still required
/// because [OnnxModel] itself is model-agnostic rather than special-casing
/// per model.
/// [scaleFactor]: 1 for same-resolution models (denoise), 2/4 for
/// upscalers — the output tile is `inputTileSize * scaleFactor` per side.
class OnnxModelSpec {
  const OnnxModelSpec({
    required this.fileName,
    required this.inputTileSize,
    required this.scaleFactor,
    this.channels = 3,
    this.customAbsolutePath,
  });

  /// Builds a spec for a user-supplied model file (Settings' "custom
  /// denoise model" picker) — same tile geometry as [denoiseModelSpec],
  /// since this is deliberately a drop-in replacement for it, not a
  /// generically-introspected model (see [customAbsolutePath]'s doc for
  /// why: pixel normalization can't be recovered from the ONNX graph
  /// itself, so trying to support arbitrary conventions would mean
  /// silently-wrong output is possible, not just a load error).
  OnnxModelSpec.customDenoiseModel(String absolutePath)
    : fileName = p.basename(absolutePath),
      inputTileSize = 256,
      scaleFactor = 1,
      channels = 3,
      customAbsolutePath = absolutePath;

  final String fileName;
  final int inputTileSize;
  final int scaleFactor;

  /// Floats/pixel the model's input and output tensors carry. 3 (RGB) for
  /// every sRGB-domain model (the default denoise model, DIS); the raw-domain
  /// PMRID denoiser (`pmridDenoiseModelSpec`) is the one caller that's 4
  /// (packed RGGB Bayer planes) instead.
  final int channels;

  /// When set, [OnnxModel] loads the session from this exact absolute
  /// path instead of resolving [fileName] next to the executable (see
  /// `_OrtLib.modelPath`) — the mechanism behind Settings' "custom
  /// denoise model" file picker. The chosen file is trusted to already
  /// match [denoiseModelSpec]'s conventions (3-channel RGB, dynamic
  /// same-resolution in/out, "input"/"output" tensor names, [0,1]
  /// normalization); there's no way to verify the normalization range
  /// from the ONNX file itself, so a model that uses a different
  /// convention won't error, it'll just produce visibly wrong (washed
  /// out/oversaturated) output — a real load/inference failure (wrong
  /// channel count, wrong tensor names, corrupt file) does surface as a
  /// normal [OrtException] though, same as any other model.
  final String? customAbsolutePath;

  int get outputTileSize => inputTileSize * scaleFactor;

  /// Distinguishes sessions in [OnnxModel]'s cache — the full path when
  /// [customAbsolutePath] is set (so switching between two different
  /// custom files, or between a custom file and the bundled default that
  /// happens to share a basename, never reuses the wrong cached session),
  /// otherwise just [fileName].
  String get cacheKey => customAbsolutePath ?? fileName;
}

/// 1xDeNoise (MIT, RealPLKSR architecture, huggingface.co/huggingworld/
/// onnx-image-models) — reconstructive denoise, same 3-channel/[0,1]/
/// "input"-"output" convention as the NAFNet-SIDD model this replaced
/// (2026-08-31, item 35 follow-up): NAFNet-SIDD's output was too smoothed
/// ("papado") for the user's taste even after the earlier hue/artifact
/// fixes; this model's crop tests showed real grain/noise reduction
/// without washing out detail. The real cost: ~3.3x slower per tile than
/// NAFNet-SIDD (2.4min vs ~40s on a 24MP photo) — accepted deliberately,
/// quality over speed for the always-on default pass. 256 chosen for the
/// same tile-count/overhead balance as the previous model; this
/// architecture has no hard divisibility requirement discovered so far,
/// but hasn't been stress-tested at other tile sizes.
const denoiseModelSpec = OnnxModelSpec(
  fileName: '1xDeNoise_realplksr_otf_fp32.onnx',
  inputTileSize: 256,
  scaleFactor: 1,
);

/// DIS Fast 2x (Apache-2.0, Kim2091/DIS — "Direct Image Supersampling") —
/// 2x super-resolution. Replaces the earlier Real-ESRGAN x2plus spec: a
/// tiny (~195K-parameter), all-stride-1-conv architecture (no pooling/
/// downsampling anywhere, so — unlike [denoiseModelSpec]/PMRID above —
/// there's no tile size divisibility requirement at all), exported with fully dynamic
/// spatial dims. 256 chosen for the same tile-count/overhead balance as
/// [denoiseModelSpec].
const upscaleModelSpec = OnnxModelSpec(
  fileName: 'DIS-Fast-2x.onnx',
  inputTileSize: 256,
  scaleFactor: 2,
);

/// Real-ESRGAN x2plus (BSD-3-Clause, xinntao/Real-ESRGAN) — the model
/// [upscaleModelSpec] above replaced for speed, still bundled and now
/// re-offered as a deliberate slower/higher-quality alternative (item 35's
/// "papado" denoise investigation, 2026-08-31 — see PENDING.md and
/// project_darkmoon_color_profile.md's sibling item for the full trail).
///
/// The two models differ in *kind*, not just speed: [upscaleModelSpec]
/// (DIS) is trained with a pixel-fidelity loss, so it never invents detail
/// it isn't confident about — safe, but can look "papado"/over-smoothed on
/// real sensor noise. This model is trained with an adversarial (GAN)
/// loss, which rewards synthesizing plausible high-frequency texture even
/// where the input is ambiguous — measurably closer to the crisp,
/// reconstructed look of tools like Topaz's video/photo remasters, at a
/// real cost: on a full 24MP photo this takes ~3.5 minutes end-to-end
/// (denoise + upscale) versus a few seconds for DIS, and it can *alter*
/// (not just sharpen) very small text/detail near the edge of resolution
/// — confirmed on a real photo where small signage text came out
/// perceptibly different, not just crisper. Offer this as an explicit,
/// slower choice; never make it the default.
///
/// Fixed 64x64 input tile (unlike [upscaleModelSpec]'s dynamic sizing) —
/// this specific export's own constraint, not a general property of
/// Real-ESRGAN models.
const realEsrganUpscaleModelSpec = OnnxModelSpec(
  fileName: 'Real-ESRGAN_x2plus.onnx',
  inputTileSize: 64,
  scaleFactor: 2,
);

/// PMRID (Apache-2.0, MegEngine/PMRID, ECCV20 "Practical Deep Raw Image
/// Denoising on Mobile Devices") — raw-domain denoise, run on the packed
/// RGGB Bayer buffer *before* demosaic (`pmrid_denoise.dart`), unlike
/// [denoiseModelSpec]/DIS above which both run after. 4 input/output
/// channels (R, G, G2, B planes), residual output added back to the input
/// by the network itself. Exported with dynamic spatial dims; 256 chosen
/// for the same tile-count/overhead balance as [denoiseModelSpec], and
/// must stay a multiple of 32 (the network's total downsample factor).
const pmridDenoiseModelSpec = OnnxModelSpec(
  fileName: 'PMRID.onnx',
  inputTileSize: 256,
  scaleFactor: 1,
  channels: 4,
);

/// GaterV3 restore (CC-BY-4.0, github.com/Phhofm/models, "gaterv3_r"
/// architecture) — same-resolution general restoration (noise/resize/
/// JPEG/mild blur), meant to run *before* [gaterV3SharpenModelSpec] in
/// the pair the author trained them as (2026-08-31, PENDING.md item 35
/// combo follow-up — restoration-research report's Tier 1). Confirmed
/// via `onnx.load(...)` (not guessed): fully dynamic input, "input"/
/// "output" tensor names — this app's own default convention, no
/// [OnnxModelSpec.inputName] override needed. Crop-tested on a real
/// noisy 24MP photo: visibly sharper edges/detail than
/// [denoiseModelSpec] alone, and much faster per tile (~1.3s vs ~4.4s
/// on the same 700x700 crop) — worth the extra pass.
const gaterV3RestoreModelSpec = OnnxModelSpec(
  fileName: '1xgaterv3_r_restore_fp32_op17.onnx',
  inputTileSize: 256,
  scaleFactor: 1,
);

/// GaterV3 sharpen (CC-BY-4.0, same repo/author/architecture as
/// [gaterV3RestoreModelSpec]) — the second half of the author's intended
/// restore-then-sharpen pair. Same tile geometry and tensor-name
/// convention.
const gaterV3SharpenModelSpec = OnnxModelSpec(
  fileName: '1xgaterv3_r_sharpen_fp32_op17.onnx',
  inputTileSize: 256,
  scaleFactor: 1,
);

// `1xDeJPG_OmniSR.onnx` (JPEG-artifact removal, same research round) was
// tried and rejected, not just skipped: it crashes on DirectML (a
// FusedMatMul/attention op the EP can't run — OmniSR is a transformer-
// style architecture, unlike the pure-conv models above), and true CPU
// execution is ~50x slower than GaterV3's GPU pass (62.7s for a 700x700
// crop alone) — not viable at any tile count for a full photo. No spec
// constant kept for it; re-fetch `huggingface.co/huggingworld/
// onnx-image-models` if revisiting.

/// DDColor "modelscope" checkpoint (Apache-2.0, piddnad/DDColor, ICCV 2023
/// — encoder_name='convnext-l', decoder='MultiScaleColorDecoder', the
/// repo's own recommended default "if you want to test images outside
/// ImageNet") — colorization for item 37 (restore/recolor old B&W
/// photos), 2026-09-01. Not a tiled model like everything else in this
/// file: [inputTileSize] 512 is the model's one fixed working
/// resolution — `colorize.dart`'s pipeline runs it exactly once per
/// photo (no `denoiseTiled`/overlap-blend), on a downscaled version of
/// the image, then upsamples just the 2 predicted a/b channels back onto
/// the photo's own full-resolution L channel (`lab_color.dart`) — the
/// model's own fixed size never limits final output resolution, the same
/// trick this app's own `baseline_chroma.dart` already uses for its own
/// chroma smoothing. [channels] 3 describes the *input* (RGB); the
/// output is 2-channel (Lab a/b), reached via [OnnxModel.runToChannels],
/// not [OnnxModel.runTile].
///
/// Exported from the official `pytorch_model.bin` checkpoint via the
/// repo's own `scripts/export_onnx.py` (opset 12, `dynamo=False` — same
/// legacy-TorchScript-exporter trick as this project's other from-scratch
/// exports), verified numerically against PyTorch (max abs diff 0.009 on
/// random input) and visually on a real daytime photo (sky came back
/// genuinely blue, skin tones plausible) — real caveat found the same
/// day: noticeably worse on night/artificial-lighting scenes (defaults
/// to a warm/sepia cast, misses saturated colored light entirely), and a
/// mild tendency to oversaturate, both consistent with the
/// restoration-research report's own warning about this model. 934MB —
/// far larger than every other bundled model combined; kept anyway since
/// this is a strictly opt-in, on-demand tool, not part of the always-
/// available Enhance pipeline (2026-09-01, confirmed with user).
const ddcolorModelSpec = OnnxModelSpec(
  fileName: 'ddcolor_modelscope.onnx',
  inputTileSize: 512,
  scaleFactor: 1,
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
    if (Platform.isLinux) {
      final override = _nativeDirOverride;
      if (override != null) {
        return DynamicLibrary.open(p.join(override, 'libonnxruntime.so'));
      }
      // Installed into the bundle's lib/ dir (on the executable's rpath)
      // by linux/CMakeLists.txt, same as libraw_r.so.
      return DynamicLibrary.open('libonnxruntime.so');
    }
    throw UnsupportedError(
      'ONNX Runtime is only wired up for Windows/Linux so far.',
    );
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
  ///
  /// Models live in their own `models/` subfolder next to the executable
  /// (2026-09-01, user request) — unlike `onnxruntime.dll`/`raw_r.dll`,
  /// which the OS itself resolves by searching the exe's own directory
  /// (so those *can't* move into a subfolder without breaking
  /// `DynamicLibrary.open`), model files are only ever reached through
  /// this explicit path, so nothing stops them from being organized
  /// separately. See `windows/CMakeLists.txt`/`linux/CMakeLists.txt`'s
  /// matching `DESTINATION ".../models"` install rules.
  static String modelPath(String fileName) => p.join(
    _nativeDirOverride ?? p.dirname(Platform.resolvedExecutable),
    'models',
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

  // Only read by [releaseAll], which must release the env *after* the
  // session that depends on it.
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

  /// Releases every session this isolate created, and empties the cache.
  ///
  /// [_instances] is a static field, so it is scoped to whichever isolate
  /// is running — but the memory behind it is not. An ONNX Runtime session
  /// is native (malloc'd, plus a DirectML device and its GPU allocations),
  /// so it survives the isolate that created it: when a one-shot job's
  /// isolate exits, the Dart map goes away and the session becomes
  /// unreachable *and* unfreed, for the rest of the process's life.
  ///
  /// Real leak fixed 2026-09-03: every AI Enhance and every Colorize run
  /// spawns its own isolate (`edit_source_colorize.dart`,
  /// `ai_enhance_job.dart`) and loaded its models there, so each run leaked
  /// a full set of sessions — including DDColor's, whose graph alone is
  /// 934 MB. Nothing in this file ever called ReleaseSession/ReleaseEnv/
  /// ReleaseMemoryInfo; the comment where the env is declared assumed a
  /// process-lifetime singleton, which is only true on the main isolate.
  ///
  /// Every isolate entry point that touches [forSpec] must call this in a
  /// `finally`. Safe to call more than once, and safe to call when no
  /// model was ever loaded.
  static void releaseAll() {
    if (_instances.isEmpty) {
      return;
    }
    final api = _OrtLib.api;
    for (final model in _instances.values) {
      // Order matters: the session and the memory info both belong to the
      // env, so the env goes last.
      api.ref.ReleaseSession.asFunction<void Function(Pointer<OrtSession>)>()(
        model._session,
      );
      api.ref.ReleaseMemoryInfo
          .asFunction<void Function(Pointer<OrtMemoryInfo>)>()(
        model._memoryInfo,
      );
      api.ref.ReleaseEnv.asFunction<void Function(Pointer<OrtEnv>)>()(
        model._env,
      );
    }
    _instances.clear();
  }

  /// Lazily creates (once per [spec]) and returns a shared model session.
  /// Throws [OrtException] only if *both* the GPU and CPU session-creation
  /// attempts fail (e.g. the model file itself is missing/corrupt) —
  /// a GPU-only failure is caught internally and silently retried on CPU.
  static OnnxModel forSpec(OnnxModelSpec spec) =>
      _instances[spec.cacheKey] ??= _create(spec);

  static OnnxModel _create(OnnxModelSpec spec) {
    // DirectML has no Linux equivalent, and the symbol isn't even exported
    // by libonnxruntime.so there — looking it up would throw an ArgumentError
    // (from the FFI symbol lookup itself, not an OrtException), which the
    // catch below wouldn't handle. Skip straight to CPU instead of
    // attempting-and-catching.
    if (!Platform.isWindows) {
      return _createSession(spec, useDirectMl: false);
    }
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
        // Deliberately NOT setting session.disable_cpu_ep_fallback here —
        // tried that first (to get a hard "did GPU actually work" signal)
        // and found via VERBOSE logging that it backfires: ORT's own
        // GetCpuPreferredNodes optimization *routinely* force-places a
        // handful of tiny, cheap ops (Gather/Unsqueeze/Sub/elementwise
        // Mul, ~100 out of ~1865 nodes on NAFNet-SIDD) on CPU because
        // dispatch overhead to any other EP would be slower for those
        // specific ops — completely normal hybrid execution, not a real
        // DirectML incompatibility. With disable_cpu_ep_fallback set,
        // that benign heuristic placement made CreateSession fail
        // outright, turning a session that would've run ~95% on the GPU
        // into a full CPU fallback instead. Letting CPU fallback happen
        // normally means a session that "succeeds" here is genuinely
        // running on DirectML for the vast majority of its work; only a
        // real failure (missing DirectML.dll, no DX12-capable GPU, a
        // model this build truly can't place on DML at all) throws now.
        _check(
          _OrtLib.bindings.OrtSessionOptionsAppendExecutionProvider_DML(
            options,
            0,
          ),
        );
      }
      // useDirectMl == false: append nothing — ORT always registers its
      // own CPU execution provider by default, no explicit call needed.

      // ORT's CreateSession takes an ORTCHAR_T* — wchar_t on Windows, but
      // plain (UTF-8) char on every other platform, matching ORT's own
      // upstream header. The Dart-side Pointer<WChar> annotation below is
      // only the Windows shape; on Linux this cast reinterprets a narrow
      // UTF-8 buffer instead — the real libonnxruntime.so reads raw bytes,
      // it doesn't care about dart:ffi's static typing. (Passing UTF-16
      // bytes there silently truncated the path at its first embedded NUL
      // byte, right after the first character.)
      final resolvedModelPath =
          spec.customAbsolutePath ?? _OrtLib.modelPath(spec.fileName);
      final modelPathPtr = Platform.isWindows
          ? resolvedModelPath.toNativeUtf16()
          : resolvedModelPath.toNativeUtf8().cast<WChar>();
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
  Float32List runTile(Float32List rgbTile) => _runTile(rgbTile, 3, 3);

  /// Generalization of [runTile] for a model whose [OnnxModelSpec.channels]
  /// isn't 3 — currently just [pmridDenoiseModelSpec] (4: packed RGGB Bayer
  /// planes). [packedTile] is packed, row-major, [OnnxModelSpec.channels]
  /// floats/pixel, same normalization convention as [runTile].
  Float32List runPackedTile(Float32List packedTile) =>
      _runTile(packedTile, _spec.channels, _spec.channels);

  /// Generalization for a model whose output has a *different* channel
  /// count than its input — currently just [ddcolorModelSpec] (3-channel
  /// RGB in, 2-channel Lab a/b out; [outChannels] 2). Same spatial size
  /// in/out either way ([OnnxModelSpec.scaleFactor] 1), same [Float32List]
  /// packing/normalization convention as [runTile].
  Float32List runToChannels(Float32List tile, int outChannels) =>
      _runTile(tile, _spec.channels, outChannels);

  Float32List _runTile(Float32List tile, int inChannels, int outChannels) {
    final inSize = _spec.inputTileSize;
    final outSize = _spec.outputTileSize;
    final expectedInLength = inSize * inSize * inChannels;
    final expectedOutLength = outSize * outSize * outChannels;
    if (tile.length != expectedInLength) {
      throw ArgumentError(
        'tile must have $expectedInLength floats '
        '($inSize x $inSize x $inChannels), got ${tile.length}',
      );
    }
    final api = _OrtLib.api;

    // NCHW layout, matching the export's expected input shape.
    final shape = calloc<Int64>(4);
    shape[0] = 1;
    shape[1] = inChannels;
    shape[2] = inSize;
    shape[3] = inSize;

    final inputData = calloc<Float>(expectedInLength);
    _packChw(tile, inputData.asTypedList(expectedInLength), inSize, inChannels);

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
      final packedOut = Float32List(expectedOutLength);
      _unpackChw(chwOut, packedOut, outSize, outChannels);
      return packedOut;
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

/// Rearranges packed-per-pixel data (`[c0,c1,c2,...,c0,c1,c2,...]`) into
/// planar NCHW (`[c0,c0,...,c1,c1,...,c2,c2,...]`), the layout ONNX image
/// models conventionally expect. `channels` is 3 (RGB) for every
/// sRGB-domain model, 4 (packed RGGB Bayer planes) for [pmridDenoiseModelSpec].
void _packChw(
  Float32List packed,
  Float32List chwOut,
  int tileSize,
  int channels,
) {
  final pixelCount = tileSize * tileSize;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * channels;
    for (var c = 0; c < channels; c++) {
      chwOut[pixelCount * c + p] = packed[i + c];
    }
  }
}

/// Inverse of [_packChw].
void _unpackChw(
  Float32List chw,
  Float32List packedOut,
  int tileSize,
  int channels,
) {
  final pixelCount = tileSize * tileSize;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * channels;
    for (var c = 0; c < channels; c++) {
      packedOut[i + c] = chw[pixelCount * c + p];
    }
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
  } finally {
    // The probe wants the answer, not the session — and it is documented
    // to run on a throwaway background isolate, where a retained session
    // would leak (see [OnnxModel.releaseAll]).
    OnnxModel.releaseAll();
  }
}
