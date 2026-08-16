# darkmoon (Flutter port)

Work-in-progress Flutter/Dart rewrite of the Python/PySide6 Darkmoon editor, built
incrementally in `../main.py`'s sibling directory. See the repo root README for the
original app; this one only covers the Flutter side.

## Running

```sh
flutter run -d windows   # or -d chrome, once mobile/desktop targets are set up
```

## Known environment quirk: Visual Studio 18 (2026) + this Flutter SDK

This machine has **Visual Studio Build Tools 2026 (major version 18)** installed.
The Flutter SDK pinned here (3.35.5 stable) predates that release and doesn't know
about it yet, which breaks the native Windows build in two ways:

1. `flutter doctor` / `flutter build windows` report the VS install as "incomplete"
   until *all* selected components are on the exact same catalog version — if VS
   auto-updates mid-session, re-run (as admin):

   ```powershell
   & "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" repair --installPath "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools" --quiet --norestart
   ```

2. `flutter_tools` hardcodes the CMake generator name per VS major version and
   doesn't have an entry for `18`, so it falls back to the wrong `"Visual Studio 16
   2019"` generator and CMake fails. **This SDK copy at `D:\flutter` has been
   patched** in
   `packages/flutter_tools/lib/src/windows/visual_studio.dart` (`cmakeGenerator`
   getter) to map major version `18` → `'Visual Studio 18 2026'` (confirmed via
   `cmake --help` that this is the exact generator name CMake exposes for this VS
   version). After any edit to `flutter_tools` source, delete
   `bin/cache/flutter_tools.snapshot` and `bin/cache/flutter_tools.stamp` to force
   a rebuild — editing the `.dart` file alone has no effect since Flutter runs from
   a cached compiled snapshot.

If this Flutter SDK is ever reinstalled/updated, re-apply the `cmakeGenerator`
patch (or check whether the newer Flutter release has added native support for VS
18 upstream, making the patch unnecessary).
