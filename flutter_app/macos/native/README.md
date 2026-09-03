# Vendored native libraries (macOS)

Unlike `windows/native/` and `linux/native/`, **nothing here is committed**
— the directory is populated by `tool/fetch_macos_natives.sh`, which runs
on a Mac or a macOS CI runner.

The reason is simply that this project has no Mac. The Windows and Linux
binaries were produced on the machines that build those targets and
checked in; these cannot be, so they are fetched and built at build time
instead. CI caches them between runs.

| library | where it comes from |
|---|---|
| `libonnxruntime.dylib` | official `onnxruntime-osx-arm64-<ver>.tgz` release |
| `libonnxruntime_providers_webgpu.dylib` | PyPI wheel `onnxruntime-ep-webgpu` (no GitHub release asset exists) |
| `libraw_r.dylib` + its dependencies | built from source / Homebrew, then bundled |

## Why LibRaw needs more than a copy

It links against libjpeg, lcms2 and zlib. Linux assumes those are present
system-wide, which is fair on a distro; macOS ships none of them, and
Homebrew's copies live under `/opt/homebrew`, which a distributed `.app`
cannot depend on. `fetch_macos_natives.sh` therefore copies the
dependencies in alongside it and rewrites every `install_name` to
`@rpath`, so they resolve from `Contents/Frameworks/`.

## GPU

The WebGPU plugin EP is backed by **Metal** here (Dawn dispatches to
Metal on macOS, Vulkan on Linux, D3D12 on Windows), so macOS gets GPU
acceleration for the AI features with no extra system dependency — unlike
Linux, which needs a Vulkan loader.

## Signing

`tool/bundle_macos_natives.sh` signs ad-hoc (`codesign -s -`), which is
enough to launch. Distribution outside the App Store needs a Developer ID
and notarization — a paid Apple account this project does not have — so
until then a downloaded build needs right-click → Open on first launch.
