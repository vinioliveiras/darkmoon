import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

import 'cloud_denoise_provider.dart';

/// CryptProtectData's `dwFlags` — "do not display a UI for user
/// input.": if the encrypted blob is missing/foreign (a different
/// Windows account, a copied-over profile), fail immediately instead of
/// ever popping a Windows credential prompt. Not exposed as a named
/// constant by `package:win32` (checked: `crypt32.g.dart` only exports the
/// functions/structs, not this flag) — the value itself is
/// `CRYPTPROTECT_UI_FORBIDDEN` from `wincrypt.h`, stable across Windows
/// versions.
const int _cryptProtectUiForbidden = 0x1;

/// Per-provider API token storage, encrypted at rest with Windows DPAPI
/// (`CryptProtectData`/`CryptUnprotectData`) — the same underlying
/// mechanism Windows Credential Manager itself uses: tied to the current
/// Windows user's login credentials, so only that account can decrypt it
/// (and only on this machine — DPAPI keys aren't portable across
/// machines). Implemented directly against `package:win32` (a pure-Dart
/// FFI binding — no native plugin to compile) rather than
/// `flutter_secure_storage`'s Windows plugin, which needs the "C++ ATL"
/// Visual Studio component this dev machine doesn't have installed (a
/// `CMake`-level build failure, `atlstr.h` not found) — see
/// PENDING.md's note on this.
///
/// Encrypted blobs live one file per provider under
/// `Documents/darkmoon/cloud_denoise_tokens/` — never plaintext on disk,
/// and deliberately kept separate from `_paramValues`/the catalog file
/// (which IS plain JSON on disk) — see `editor_screen.dart`'s
/// `_cloudDenoiseProviderKey` doc. `path_provider`-dependent like every
/// other cache dir in this codebase, so only call from the main isolate.
class CloudDenoiseTokenStore {
  CloudDenoiseTokenStore._();

  static Future<String> _tokenDir() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(documents.path, 'darkmoon', 'cloud_denoise_tokens'),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  static String _fileFor(String dir, CloudDenoiseProviderKind kind) =>
      p.join(dir, '${kind.name}.bin');

  /// Returns null on any failure (no saved token, a corrupt/undecryptable
  /// blob — e.g. copied from a different Windows account/machine — or a
  /// non-Windows platform, including a widget test's headless
  /// environment) — same as a real cache miss: the dialog just shows an
  /// empty token field rather than crashing.
  static Future<String?> read(CloudDenoiseProviderKind kind) async {
    try {
      final file = File(_fileFor(await _tokenDir(), kind));
      if (!await file.exists()) {
        return null;
      }
      final decrypted = _unprotect(await file.readAsBytes());
      return decrypted == null ? null : utf8.decode(decrypted);
    } catch (_) {
      return null;
    }
  }

  /// Best-effort — a failure here shouldn't block applying the cloud
  /// denoise choice itself (the caller already has the plaintext key in
  /// memory for this run regardless); it just means the key won't be
  /// remembered next time the dialog opens.
  static Future<void> write(
    CloudDenoiseProviderKind kind,
    String token,
  ) async {
    try {
      final encrypted = _protect(Uint8List.fromList(utf8.encode(token)));
      if (encrypted == null) {
        return;
      }
      final file = File(_fileFor(await _tokenDir(), kind));
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(encrypted, flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // Best-effort.
    }
  }

  static Future<void> delete(CloudDenoiseProviderKind kind) async {
    try {
      final file = File(_fileFor(await _tokenDir(), kind));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort.
    }
  }

  static Uint8List? _protect(Uint8List plain) => _dpapi(plain, encrypt: true);

  static Uint8List? _unprotect(Uint8List encrypted) =>
      _dpapi(encrypted, encrypt: false);

  /// Exposes the DPAPI round-trip directly for tests — real
  /// `CryptProtectData`/`CryptUnprotectData` calls, but skipping
  /// `path_provider`'s directory resolution (which needs a real engine/
  /// platform channel binding [read]/[write] don't have under plain
  /// `flutter test`, unlike `integration_test`) so the encryption logic
  /// itself stays testable without that dependency.
  @visibleForTesting
  static Uint8List? protectBytesForTesting(Uint8List plain) => _protect(plain);

  @visibleForTesting
  static Uint8List? unprotectBytesForTesting(Uint8List encrypted) =>
      _unprotect(encrypted);

  /// Shared CryptProtectData/CryptUnprotectData caller — the two
  /// functions have an identical enough shape (blob in, blob out, same
  /// flags) that marshaling them separately would just duplicate this
  /// pointer bookkeeping twice. Returns null on any failure (including
  /// not running on Windows) rather than throwing — every caller here
  /// already treats a null as "couldn't use the stored token", not a
  /// crash-worthy condition.
  static Uint8List? _dpapi(Uint8List input, {required bool encrypt}) {
    if (!Platform.isWindows) {
      return null;
    }
    final inBlob = calloc<CRYPT_INTEGER_BLOB>();
    final outBlob = calloc<CRYPT_INTEGER_BLOB>();
    final inData = calloc<Uint8>(input.isEmpty ? 1 : input.length);
    try {
      inData.asTypedList(input.length).setAll(0, input);
      inBlob.ref
        ..cbData = input.length
        ..pbData = inData;
      final ok = encrypt
          ? CryptProtectData(
              inBlob,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              _cryptProtectUiForbidden,
              outBlob,
            )
          : CryptUnprotectData(
              inBlob,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              _cryptProtectUiForbidden,
              outBlob,
            );
      if (ok == 0) {
        return null;
      }
      // DPAPI allocates pbData via LocalAlloc internally — ours to free
      // with LocalFree, not calloc.free (a different allocator).
      try {
        return Uint8List.fromList(
          outBlob.ref.pbData.asTypedList(outBlob.ref.cbData),
        );
      } finally {
        LocalFree(outBlob.ref.pbData);
      }
    } finally {
      calloc.free(inData);
      calloc.free(inBlob);
      calloc.free(outBlob);
    }
  }
}
