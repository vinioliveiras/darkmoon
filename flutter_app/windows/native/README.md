# Vendored native libraries (Windows)

`raw_r.dll` / `vcomp140.dll` — LibRaw and the OpenMP runtime it links
against. See `linux/native/README.md` for how the Linux equivalent is
built; the Windows DLL predates that note.

`onnxruntime.dll` — the official ONNX Runtime 1.24.4 release build with
the DirectML execution provider, paired with `DirectML.dll`.

`onnxruntime_providers_webgpu.dll` + `dxcompiler.dll` + `dxil.dll` — the
WebGPU plugin execution provider and the DirectX shader compiler Dawn
needs to translate its shaders to D3D12. Distributed as a Python wheel
rather than a GitHub release asset, so they are extracted from there:

```sh
python - <<'PY'
import json, urllib.request, zipfile, io
d = json.load(urllib.request.urlopen(
    "https://pypi.org/pypi/onnxruntime-ep-webgpu/0.3.0/json"))
f = next(f for f in d['urls'] if 'win_amd64' in f['filename'])
z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(f['url']).read()))
for n in ['onnxruntime_providers_webgpu.dll', 'dxcompiler.dll', 'dxil.dll']:
    open(n, 'wb').write(z.read('onnxruntime_ep_webgpu/' + n))
PY
```

Requires `onnxruntime.dll` to be **1.24.4 or newer** — the plugin EP API
it uses landed in ORT 1.23.

**WebGPU is not the GPU path on Windows.** DirectML is tried first and is
what this app has shipped and tuned against; it is already vendor-agnostic
across any DX12 GPU. WebGPU sits behind it as a second chance for a model
DirectML rejects outright, and as the way to A/B the two. Measured on the
development machine, denoising one 256x256 tile with
`1xDeNoise_realplksr_otf_fp32.onnx`:

| EP       | session | one tile |
|----------|---------|----------|
| DirectML | 761ms   | 727ms    |
| WebGPU   | 992ms   | 1280ms   |
| CPU      | 642ms   | 3709ms   |

Outputs agreed to ~7 decimal places across all three.

Force one with `DARKMOON_ONNX_EP=webgpu|directml|cpu` (no UI —
see `onnx_runtime.dart`'s `_providerChain`). Linux has no DirectML, so
WebGPU is the only GPU option there; that is why these are bundled on both
platforms rather than Linux alone.
