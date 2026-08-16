# Vendored LibRaw headers

Used only to generate `lib/native/libraw_bindings.dart` via `ffigen` — not
compiled or shipped. The actual native code is `windows/native/raw_r.dll`
(same build the Python app's `rawpy` uses).

- `libraw/*.h` — fetched as-is from
  https://github.com/LibRaw/LibRaw/tree/master/libraw (2026-08-16). Only the
  pure-C headers are needed: `libraw_types.h`, `libraw_const.h`,
  `libraw_version.h`. (`libraw.h` itself, `libraw_datastream.h`, and
  `libraw_alloc.h` all mix in a C++ convenience API and are intentionally
  **not** used as ffigen input — see below.)
- `libraw_c_api.h` — hand-written entry point for ffigen. `libraw.h` mixes a
  C++ class with LibRaw's plain C API in one file, and the installed ffigen
  version (20.1.1) only parses C, not C++. Rather than fight that, this
  small header includes `libraw_types.h` directly and declares just the
  `extern "C"` functions this app actually calls, with signatures copied
  verbatim from the real `libraw.h`.

## Regenerating bindings

```sh
dart run ffigen --config ffigen.yaml
```

Requires `libclang` (installed here via the LLVM Windows installer —
`winget install LLVM.LLVM` registers the package but doesn't reliably place
the files; downloading and running the installer `.exe` directly with `/S`
does).

If LibRaw ships a new major version with API changes, refresh the headers
in `libraw/` from upstream and re-check `libraw_c_api.h`'s function
signatures against the new `libraw.h`.
