# Vendored ONNX Runtime headers

Used only to generate `lib/native/onnxruntime_bindings.dart` via `ffigen` —
not compiled or shipped. The actual native code is
`windows/native/onnxruntime.dll` + `windows/native/DirectML.dll`, extracted
from the official prebuilt NuGet packages (see below) — same version pin as
these headers.

- `onnxruntime_c_api.h` — fetched as-is from
  https://github.com/microsoft/onnxruntime/blob/v1.19.2/include/onnxruntime/core/session/onnxruntime_c_api.h
  (2026-08-18). Genuinely plain C (unlike LibRaw's `libraw.h`, this doesn't
  mix in a C++ class) — used directly as ffigen input, no hand-written shim
  needed for it.
- `dml_provider_factory.h` — fetched as-is from
  https://github.com/microsoft/onnxruntime/blob/v1.19.2/include/onnxruntime/core/providers/dml/dml_provider_factory.h
  (2026-08-18). Kept only as a reference for verifying `onnx_dml_c_api.h`'s
  signature against upstream — **not** used as ffigen input, since it
  unconditionally `#include`s `<d3d12.h>` (a large COM header irrelevant to
  the one function this app calls).
- `onnx_dml_c_api.h` — hand-written entry point for ffigen, same reasoning
  as `third_party/libraw_headers/libraw_c_api.h`: rather than feed
  `dml_provider_factory.h` itself (and its `<d3d12.h>` dependency) to
  ffigen, this shim declares just the one function this app calls
  (`OrtSessionOptionsAppendExecutionProvider_DML`), signature copied
  verbatim from the real header.
- `onnxruntime.dll` was extracted from the `Microsoft.ML.OnnxRuntime.DirectML`
  NuGet package v1.19.2 (`runtimes/win-x64/native/onnxruntime.dll`).
- `DirectML.dll` was extracted from the `Microsoft.AI.DirectML` NuGet
  package v1.15.4 (`bin/x64-win/DirectML.dll`) — the DirectML redistributable
  that `Microsoft.ML.OnnxRuntime.DirectML` 1.19.2 depends on.
- Both NuGet packages (and this repo's use of ONNX Runtime) are MIT
  licensed.

## Binding a C API that's mostly a function-pointer table

Unlike LibRaw (whose bindings are ordinary exported functions ffigen binds
directly), only two real symbols are exported from `onnxruntime.dll`:
`OrtGetApiBase()` and `OrtSessionOptionsAppendExecutionProvider_DML`.
Everything else — session/tensor creation, `Run`, error handling — is
reached at runtime via `OrtGetApiBase().GetApi(ORT_API_VERSION)`, which
returns an `OrtApi` struct whose fields are function pointers. The
hand-written wrapper (`lib/native/onnx_runtime.dart`) resolves and calls
those itself; ffigen's `functions.include` in `ffigen_onnx.yaml` only lists
the two real exports, while `OrtApi`/`OrtApiBase` are bound as ordinary
(non-opaque) structs so their function-pointer fields are usable.

## Regenerating bindings

```sh
dart run ffigen --config ffigen_onnx.yaml
```

Requires libclang (see `third_party/libraw_headers/README.md` for how it's
installed in this environment) — plus the Windows SDK's `shared/` include
directory (for `specstrings.h` and its own transitive SAL headers), added
via `compiler-opts` in `ffigen_onnx.yaml` as an 8.3 short path (the long
path, with its parenthesis and spaces, gets mis-tokenized by ffigen's
`-I` handling).

If ONNX Runtime ships a new major version with a bumped `ORT_API_VERSION`
or C API changes, refresh `onnxruntime_c_api.h` from upstream, re-check
`onnx_dml_c_api.h`'s signature against the new `dml_provider_factory.h`,
and re-extract matching `onnxruntime.dll`/`DirectML.dll` builds.
