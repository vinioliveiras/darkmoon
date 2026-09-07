# Cutting a darkmoon release

Everything needed to publish a release, and the traps that have actually
cost a rebuild or broken the website. Read this **before** starting, not
after something goes wrong.

Written in English like the rest of the repository. `PENDING.md` is the
Portuguese working document; this is process, and it ships.

---

## 1. The six artifacts

Every platform ships **both** a portable build and an installer. That is a
standing requirement, not a nice-to-have.

| platform | portable | installer |
|---|---|---|
| Windows | `darkmoon-v<VER>-windows-x64-portable.zip` | `darkmoon-v<VER>-windows-x64-setup.exe` |
| Linux | `darkmoon-v<VER>-linux-x64.tar.gz` | `darkmoon_<VER>_amd64.deb` |
| macOS | `darkmoon-v<VER>-macos-arm64.zip` | `darkmoon-v<VER>-macos-arm64.dmg` |

Note the `.deb` is the one name **without** a `v` before the version and
with underscores — that is Debian's required convention, not an
inconsistency to fix.

Each is roughly 1.2 GB. About 99 MB of that is the application; the rest
is the ONNX model weights, which ship bundled by decision (2026-09-04).
Do not add a runtime downloader without being asked.

## 2. Naming and language

- **Tag**: `vX.Y.Z`
- **Release title**: the bare tag, `v1.10.0`. **Not** `darkmoon v1.10.0` —
  that was the style up to v1.3.0 and was dropped at v1.4.0.
- **Release notes**: English. Always, even though the project is developed
  in Portuguese.
- **No AI attribution anywhere in a release.** No "Generated with Claude
  Code", no robot emoji, nothing of the kind, in a title or a body. Git
  commit trailers are a separate surface and are unaffected.

## 3. Version numbering

Bump both, together:

- `flutter_app/pubspec.yaml` — `version: X.Y.Z+1`
- `flutter_app/lib/widgets/about_dialog.dart` — `darkmoonAppVersion`

Both packaging scripts read the version from `pubspec.yaml`, so nothing
else needs editing. A mismatch between the two shows up in the About
dialog and nowhere else, which is why it survives unnoticed.

Patch for fixes, minor for features. Installers arriving on all three
platforms was 1.10.0, not 1.9.3.

## 4. `releases/latest` is load-bearing

`docs/index.html`'s download buttons link to `releases/latest` rather than
to a pinned version, so **whatever GitHub considers latest is what the
website hands to visitors**.

GitHub recomputes "latest" as the newest non-prerelease whenever releases
change. `--latest=false` at creation does **not** survive that recompute.
This has already broken once: deleting v1.9.2 promoted the `models-v1`
weights release to latest, and darkmoon.pt briefly offered ONNX model
files where the application should be.

- Any non-application release must be marked `--prerelease`. GitHub never
  elects a prerelease as latest.
- After creating **or deleting** any release, check:

```bash
gh api repos/vinioliveiras/darkmoon/releases/latest --jq .tag_name
```

It must name an application release carrying all six assets.

## 5. Prerequisites

- **Flutter 3.35.5** at `D:\flutter\bin\flutter.bat`
- **Model weights** in `flutter_app/native_models/` — `tool/fetch_models.sh`
  pulls them from the `models-v1` release and verifies `tool/models.sha256`
- **Inno Setup 6** for the Windows installer:
  `winget install --id JRSoftware.InnoSetup`
- **WSL (Ubuntu)** for the Linux build — see the glibc note below
- macOS needs nothing locally; it is built on GitHub's Apple runners

## 6. Procedure

### 6.1 Bump and commit

Bump the two files above, commit, and make sure the tree is clean.

### 6.2 Linux, in WSL

**Build Linux in WSL, never on `ubuntu-latest` in CI.** The runner is
Ubuntu 24.04 (glibc 2.39); building there would raise the requirement
above the 2.34 floor this project worked to reach and break Ubuntu 22.04
users.

```bash
cd flutter_app
flutter pub get          # required after any Windows-side pub get
flutter build linux --release
bash tool/package_linux.sh   # writes both the tarball and the .deb
```

Confirm the glibc floor did not move — the highest `GLIBC_x.y` any binary
in the bundle requires must stay at **2.34**:

```bash
objdump -T <binary> | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -uV | tail -1
```

### 6.3 Windows

`flutter pub get` again on the Windows side first: the package config
carries absolute paths and WSL just rewrote them.

```bash
cd flutter_app
flutter pub get
flutter build windows --release
bash tool/package_windows.sh   # writes both the zip and the setup.exe
```

Then the native smoke test, which must report a GPU provider:

```bash
BUNDLE=".../flutter_app/build/windows/x64/runner/Release"
DARKMOON_NATIVE_DIR="$BUNDLE" PATH="$PATH:$BUNDLE" \
  dart run tool/native_smoke_test.dart
# expect: provider: DirectML (gpu=true)
```

### 6.4 Tag, release, upload

```bash
git tag -a vX.Y.Z -m "darkmoon vX.Y.Z" && git push origin vX.Y.Z
gh release create vX.Y.Z --title "vX.Y.Z" --notes-file notes.md --latest
gh release upload vX.Y.Z <the four local artifacts>
```

### 6.5 macOS

Built on GitHub's Apple runners, because the project has no Mac.

```bash
gh workflow run release-macos.yml --ref master -f tag=vX.Y.Z
```

It fetches the weights, builds, bundles the native dylibs, ad-hoc signs,
checks the bundle carries all seven models, then attaches the `.dmg` and
`.zip` to that release. It accepts a branch name instead of a tag for a
dry run, in which case it keeps the artifacts and attaches nothing.

## 7. macOS specifics — put these in the notes every time

- **Apple Silicon only.** Microsoft publishes no `onnxruntime` for Intel
  macOS, so this is not a gap that can be closed here. The `arm64` in the
  filename is deliberate.
- **Ad-hoc signed, not notarized.** Gatekeeper blocks the first launch;
  the user must go to **System Settings → Privacy & Security → Open
  Anyway**. Spell that out in the notes. An Apple Developer account
  (99 USD/yr) would remove it entirely and has been declined for now.
- **Label it beta** until someone has actually opened the GUI on a Mac.
  Everything verified so far is FFI smoke tests on CI runners, which is
  not the same thing.

## 8. Verification before announcing

Do this. Each item on the list has caught something real.

- [ ] `releases/latest` resolves to this release (section 4)
- [ ] All six assets uploaded, each roughly 1.1–1.2 GB
- [ ] Linux glibc floor still 2.34
- [ ] Windows smoke test reports a GPU provider
- [ ] macOS workflow logged `models in bundle: 7 (expected 7)`
- [ ] Windows installer installs and uninstalls cleanly, leaving no files
      and no registry entry
- [ ] `.deb` installs (`dpkg -i`), shows status `ii`, and removes cleanly
- [ ] Release notes are English and carry no AI attribution
- [ ] Title is the bare tag

## 9. Release notes template

Lead with who should care and who should not. If a platform's binary is
unchanged apart from the version string, say so — asking someone to
download 1.2 GB for nothing is a real cost.

```markdown
One-paragraph summary: what arrived, and who this release is for.

---

## Pick a download

| | portable | installer |
|---|---|---|
| **Windows** | `-windows-x64-portable.zip` | `-windows-x64-setup.exe` |
| **Linux** | `-linux-x64.tar.gz` | `darkmoon_<ver>_amd64.deb` |
| **macOS** | `-macos-arm64.zip` | `-macos-arm64.dmg` |

Portable means extract and run. The installers add a menu entry and an
uninstaller.

## <Each change, as its own section>

What changed, and why it was worth changing. Where a fix is interesting,
say what was actually wrong rather than only that it is fixed.

## macOS

<The three points from section 7, in full, every release.>

## Known limitations

State what does not work, plainly. A limitation the user discovers alone
is worse than one they were told about.
```

## 10. Traps

Every one of these has cost a failed build or a broken artifact.

- **Git Bash rewrites arguments starting with `/`** into Windows paths, so
  `/DAppVersion=1.2.3` reaches ISCC as `C:/Program Files/Git/D...`. Fixed
  with `MSYS_NO_PATHCONV=1` in `package_windows.sh`.
- **ISCC exits 0 on that usage error**, so a run that built nothing looks
  like success. `package_windows.sh` now checks the file exists — do not
  remove that check.
- **Inno's `AppId` GUID must never change.** Windows recognises an
  existing installation by it; a new GUID turns every upgrade into a
  second parallel copy of a 1.3 GB application.
- **macOS archives use `ditto -c -k`, never `zip`**, and `ditto` rather
  than `cp -R` when staging. Plain `zip`/`cp` drop the extended attributes
  carrying the code signature, and Apple Silicon will not launch an app
  whose signature does not verify.
- **Signing comes last**, after the models are copied in. Sign first and
  the seal covers a bundle that no longer exists.
- **Cross-OS `pub get`.** Building on one side then the other without
  re-running `flutter pub get` corrupts `.dart_tool`.
- **Close the app before building on Windows** or the linker fails with
  LNK1104 on a locked `darkmoon.exe`.
