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

CPU-only build (matches Windows' `1.24.x` DLL). Only depends on standard
system libs (`libdl`/`librt`/`libpthread`/`libstdc++`/`libm`/`libgcc_s`/
`libc`) — no extra apt packages needed.

`libonnxruntime_providers_webgpu.so` — the WebGPU plugin execution
provider, which is what gives the Linux build GPU acceleration for the AI
features at all (DirectML is Windows-only). Distributed as a Python wheel
rather than a GitHub release asset, so it is extracted from there:

```sh
python - <<'PY'
import json, urllib.request, zipfile, io
d = json.load(urllib.request.urlopen(
    "https://pypi.org/pypi/onnxruntime-ep-webgpu/0.3.0/json"))
f = next(f for f in d['urls'] if 'manylinux' in f['filename'])
z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(f['url']).read()))
open('libonnxruntime_providers_webgpu.so', 'wb').write(
    z.read('onnxruntime_ep_webgpu/libonnxruntime_providers_webgpu.so'))
PY
```

Requires the core runtime above to be **1.24.4 or newer** (the plugin
checks, and reports an error at registration if not) — the plugin EP API
it uses landed in ORT 1.23.

Built on Dawn, targeting **Vulkan** on Linux, so it is vendor-agnostic:
NVIDIA, AMD and Intel from the one library, with no CUDA toolkit, ROCm
stack or OpenVINO runtime to install. The one runtime requirement beyond
the standard libs above is a **system Vulkan loader (`libvulkan.so.1`)**,
which comes with any GPU driver package (`mesa-vulkan-drivers` for
AMD/Intel, the NVIDIA driver's own). Without it the plugin still loads but
reports no device, and `onnx_runtime.dart` falls back to CPU with that
reason in the dev log.

The corresponding Windows DLLs live in `windows/native/` — see that
folder's own notes.
