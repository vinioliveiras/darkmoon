# Vendored native library (Linux)

`libraw_r.so` — built from LibRaw 0.22.0 (the same version
`third_party/libraw_headers/` was generated from) via the upstream
autotools build, on Ubuntu 26.04 (WSL):

```sh
git clone https://github.com/LibRaw/LibRaw.git
cd LibRaw
autoreconf -fiv
CC=gcc CXX=g++ ./configure --disable-examples
make -j"$(nproc)"
# lib/.libs/libraw_r.so.<version> -> copy here as libraw_r.so
```

Requires `autoconf automake libtool libjpeg-dev zlib1g-dev liblcms2-dev`
(`g++`, not `clang++` — clang needs a separate `libomp-dev` for `omp.h`
that gcc bundles on its own). Dynamically links against
libjpeg/zlib/lcms2/libgomp/libstdc++ — assumed already present on the
system rather than bundled; revisit if a truly self-contained portable
build is needed later.

`libonnxruntime.so` / `libonnxruntime_providers_shared.so` — the official
prebuilt release, no build step:

```sh
curl -LO https://github.com/microsoft/onnxruntime/releases/download/v1.24.4/onnxruntime-linux-x64-1.24.4.tgz
tar xzf onnxruntime-linux-x64-1.24.4.tgz
# lib/libonnxruntime.so.1.24.4 -> copy here as libonnxruntime.so
# lib/libonnxruntime_providers_shared.so -> copy here as-is
```

CPU-only build (matches Windows' `1.24.x` DLL) — there's no DirectML
equivalent on Linux, `onnx_runtime.dart`'s `_create()` skips the GPU
attempt entirely there rather than trying and catching a failure. Only
depends on standard system libs (`libdl`/`librt`/`libpthread`/`libstdc++`/
`libm`/`libgcc_s`/`libc`) — no extra apt packages needed.
