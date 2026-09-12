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

Each is roughly 1.7 GB (1.2 GB up to v1.10.0, before the five AI-mask
models). About 99 MB of that is the application; the rest is the thirteen
ONNX model weights listed in `flutter_app/tool/models.sha256`, which ship
bundled by decision (2026-09-04). Do not add a runtime downloader without
being asked. **Every model in the manifest must also be an asset of the
`models-v1` release** — the workflows fetch from there and refuse a bundle
that is short; v1.11.0 stalled until the five newer ones were uploaded.

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

- **`gh`** logged in, and **Flutter 3.47.2** — `C:\flutter`, first on
  PATH, the same version `.github/workflows/ci.yml` pins. Do not run `pub
  get` or `dart format` from the old 3.35.5 copy at `D:\flutter`; it
  rewrites `pubspec.lock` and reformats files, and CI rejects both.
- Nothing else, since 2026-09-09: all six artifacts are built by GitHub
  Actions. The weights, Inno Setup and WSL are only needed for the
  by-hand fallback in section 6.6.

## 6. Procedure

Since 2026-09-09 the four Windows/Linux artifacts come from
`release.yml`, the same way the macOS pair has always come from
`release-macos.yml`. Each workflow takes a tag, builds from exactly that
ref, verifies the bundle (every model present; on Linux, the glibc floor;
on both, the native smoke test against the real DLLs and weights) and
attaches its two files to the release named by the tag. Pointing either
at a branch instead of a tag is a dry run: it builds everything and
attaches nothing.

### 6.1 Bump, commit, push, and wait for CI

Bump the two files in section 3, commit, push, and wait for `CI` to go
green on that commit — a release built from a red commit is a release
built from something the tests reject.

### 6.2 Tag, and create the release as a prerelease

```bash
git tag -a vX.Y.Z -m "darkmoon vX.Y.Z" && git push origin vX.Y.Z
gh release create vX.Y.Z --title "vX.Y.Z" --notes-file notes.md --prerelease
```

**Prerelease on purpose.** Section 4: `releases/latest` is what the
website hands out, and for the next half hour this release has no
assets. A prerelease is never elected latest, so visitors keep getting
the previous version until the six files are there.

### 6.3 Run the two workflows

```bash
gh workflow run release.yml --ref master -f tag=vX.Y.Z
gh workflow run release-macos.yml --ref master -f tag=vX.Y.Z
gh run watch   # or: gh run list --workflow release.yml
```

About 25–40 minutes, mostly downloading and packaging 1.7 GB per
platform. A failed job leaves the release as it was; fix, push, re-run
with the same tag (`--clobber` on upload makes a re-run harmless).

### 6.4 Promote to latest

Once all six assets are on the release:

```bash
gh release edit vX.Y.Z --prerelease=false --latest
gh api repos/vinioliveiras/darkmoon/releases/latest --jq .tag_name
```

### 6.5 What the runners cannot check

Hosted runners have no real GPU. The workflows' smoke tests prove the
shipped libraries load and run inference; the Windows one reported
`provider: WebGPU (gpu=true)` for v1.11.0, which is Dawn on D3D12's
software adapter, not DirectML on a graphics card. The "reports DirectML"
check in section 8 is therefore still a local one: download the Windows
zip, and run

```bash
BUNDLE=".../darkmoon"   # the extracted zip
DARKMOON_NATIVE_DIR="$BUNDLE" PATH="$PATH:$BUNDLE" \
  dart run tool/native_smoke_test.dart
# expect: provider: DirectML (gpu=true)
```

or simply open the app and apply AI Denoise — the dialog says which
provider it got.

### 6.6 By hand, if Actions is not an option

The workflows are the scripts below wrapped in a runner; the scripts
still work locally.

**Linux, in WSL — never on `ubuntu-latest`.** The runner's own Ubuntu is
24.04 (glibc 2.39); the workflow builds inside an `ubuntu:22.04`
container for the same reason WSL is Ubuntu 22.04 here: the bundle's
highest required `GLIBC_x.y` must stay at **2.34**, or Ubuntu 22.04 users
lose the app.

```bash
cd flutter_app
flutter pub get          # required after any Windows-side pub get
flutter build linux --release
bash tool/package_linux.sh   # writes both the tarball and the .deb
objdump -T <binary> | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -uV | tail -1
```

**Windows.** `flutter pub get` again first: the package config carries
absolute paths and WSL just rewrote them.

```bash
cd flutter_app
flutter pub get
flutter build windows --release
bash tool/package_windows.sh   # writes both the zip and the setup.exe
```

Then `gh release upload vX.Y.Z <the four files>`. Needs the weights
(`tool/fetch_models.sh`), Inno Setup 6
(`winget install --id JRSoftware.InnoSetup`) and WSL Ubuntu 22.04.

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

- [ ] Both workflows green, and the release promoted from prerelease
      (section 6.4)
- [ ] `releases/latest` resolves to this release (section 4)
- [ ] All six assets uploaded, each roughly 1.7 GB
- [ ] Linux glibc floor still 2.34
- [ ] Windows smoke test reports a GPU provider
- [ ] All three workflows logged `models in bundle: 13 (expected 13)` (the
      manifest's line count) and Linux logged `highest GLIBC ... 2.34`
- [ ] Windows installer installs and uninstalls cleanly, leaving no files
      and no registry entry
- [ ] `.deb` installs (`dpkg -i`), shows status `ii`, and removes cleanly
- [ ] Release notes are English and carry no AI attribution
- [ ] Title is the bare tag

## 9. Release notes template

Lead with who should care and who should not. If a platform's binary is
unchanged apart from the version string, say so — asking someone to
download 1.7 GB for nothing is a real cost.

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
