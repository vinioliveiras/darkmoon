# Third-party software and models in darkmoon

darkmoon itself is AGPL-3.0 (see `LICENSE`). Everything below is someone
else's work that ships inside the application bundles, with its licence
and where it came from. The model entries restate what
`flutter_app/lib/native/onnx_runtime.dart` records beside each model's
spec, which is the place to update first when a model changes.

## Native libraries

| Component | Licence | Source |
|---|---|---|
| LibRaw (`raw_r.dll`, `libraw_r.so`, `libraw_r.dylib`) | LGPL-2.1 or CDDL-1.0, at the user's choice | <https://www.libraw.org> — built from the 0.21/0.22 sources; see `flutter_app/*/native/README.md` |
| ONNX Runtime (`onnxruntime.dll`, `libonnxruntime.so`, `libonnxruntime.dylib`, `*_providers_shared`) | MIT | <https://github.com/microsoft/onnxruntime> — official release builds |
| ONNX Runtime WebGPU execution provider (`onnxruntime_providers_webgpu.*`) | MIT; bundles Dawn (BSD-3-Clause) | <https://github.com/microsoft/onnxruntime>, `onnxruntime-ep-webgpu` package |
| DirectML (`DirectML.dll`, Windows only) | Microsoft Software License Terms for DirectML (redistributable with applications that use it, not open source) | <https://www.nuget.org/packages/Microsoft.AI.DirectML> |
| DirectX Shader Compiler (`dxcompiler.dll`, `dxil.dll`, Windows only) | Apache-2.0 with LLVM exception (`dxcompiler`); `dxil.dll` under the DXC binary licence | <https://github.com/microsoft/DirectXShaderCompiler> |
| Microsoft Visual C++ OpenMP runtime (`vcomp140.dll`, Windows only) | Microsoft Visual C++ Redistributable licence | Visual Studio redistributables |
| Flutter engine and framework | BSD-3-Clause | <https://flutter.dev> |
| Dart packages (`image`, `path_provider`, `file_picker`, `win32`, `http`, `crypto`, `xml`, `archive`, `url_launcher`, `ffi`, `path`, `intl`, `cupertino_icons`) | MIT or BSD-3-Clause, per package | <https://pub.dev> — each package's LICENSE file, bundled by `flutter build` |

## Data

| Component | Licence | Source |
|---|---|---|
| Lens correction profile database (`assets/lens_profiles/`) | CC BY-SA 3.0 | Lensfun, <https://lensfun.github.io> — see `flutter_app/assets/lens_profiles/LICENSE.txt` |

## ONNX models (`models/` in every bundle)

Attribution is a condition of the CC-BY models below; it is given here
and travels with every release.

| File | Model | Licence | Source |
|---|---|---|---|
| `1xDeNoise_realplksr_otf_fp32.onnx` | 1xDeNoise (RealPLKSR architecture) | MIT | <https://huggingface.co/huggingworld/onnx-image-models> |
| `1xgaterv3_r_restore_fp32_op17.onnx` | GaterV3 restore, by Philip Hofmann | CC BY 4.0 | <https://github.com/Phhofm/models> |
| `1xgaterv3_r_sharpen_fp32_op17.onnx` | GaterV3 sharpen, by Philip Hofmann | CC BY 4.0 | <https://github.com/Phhofm/models> |
| `DIS-Fast-2x.onnx` | DIS Fast 2x ("Direct Image Supersampling"), by Kim2091 | Apache-2.0 | <https://github.com/Kim2091/DIS> |
| `Real-ESRGAN_x2plus.onnx` | Real-ESRGAN x2plus | BSD-3-Clause | <https://github.com/xinntao/Real-ESRGAN> |
| `PMRID.onnx` | PMRID ("Practical Deep Raw Image Denoising on Mobile Devices", ECCV 2020) | Apache-2.0 | <https://github.com/MegEngine/PMRID> |
| `ddcolor_modelscope.onnx` | DDColor, ModelScope checkpoint (ICCV 2023) | Apache-2.0 | <https://github.com/piddnad/DDColor> |
| `inpainting_lama_2025jan.onnx` | LaMa inpainting (WACV 2022), OpenCV Zoo ONNX export | Apache-2.0 | <https://github.com/advimman/lama>, <https://huggingface.co/opencv/inpainting_lama> |
| `sam_vit_b_01ec64_encoder.onnx`, `sam_vit_b_01ec64_decoder.onnx` | Segment Anything, ViT-B | Apache-2.0 | <https://github.com/facebookresearch/segment-anything> |
| `u2net.onnx` | U-2-Net salient object detection | Apache-2.0 | <https://github.com/xuebinqin/U-2-Net> |
| `skyseg-u2net.onnx` | Sky segmentation, U-2-Net architecture | Not recorded by this project — the source repository should be checked before relying on these weights beyond this app | <https://github.com/xiongzhu666/Sky-Segmentation-and-Post-processing> |
| `depth_anything_v2_vits.onnx` | Depth Anything V2, Small | Apache-2.0 | <https://github.com/DepthAnything/Depth-Anything-V2> |

The model files are not in this repository; `flutter_app/tool/fetch_models.sh`
downloads them from the `models-v1` release and `tool/models.sha256` is the
list of exactly which bytes ship.
