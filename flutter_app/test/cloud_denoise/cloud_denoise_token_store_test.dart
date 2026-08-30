import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/cloud_denoise/cloud_denoise_provider.dart';
import 'package:darkmoon/cloud_denoise/cloud_denoise_token_store.dart';

void main() {
  // Real DPAPI (via package:win32's direct FFI bindings, not a platform
  // channel) — this runs against the actual Windows crypto APIs even
  // under plain `flutter test`. [read]/[write]/[delete] themselves aren't
  // exercised here: they also need `path_provider`'s directory
  // resolution, which — unlike DPAPI — DOES need a real engine/platform
  // channel binding plain `flutter test` doesn't have (confirmed: calling
  // them here silently no-ops via their own best-effort try/catch,
  // exactly as designed for a headless environment — see their doc
  // comments). `protectBytesForTesting`/`unprotectBytesForTesting` isolate
  // just the DPAPI round-trip, which has no such dependency.
  group('CloudDenoiseTokenStore DPAPI round-trip', () {
    test('encrypting then decrypting recovers the exact original bytes', () {
      final plain = Uint8List.fromList(
        utf8.encode('sk-a-real-looking-test-token-1234'),
      );
      final encrypted = CloudDenoiseTokenStore.protectBytesForTesting(plain);
      expect(encrypted, isNotNull);
      expect(encrypted, isNot(equals(plain)));

      final decrypted = CloudDenoiseTokenStore.unprotectBytesForTesting(
        encrypted!,
      );
      expect(decrypted, isNotNull);
      expect(utf8.decode(decrypted!), 'sk-a-real-looking-test-token-1234');
    }, skip: !Platform.isWindows ? 'Windows-only (DPAPI)' : false);

    test('decrypting garbage bytes fails gracefully (returns null, does '
        'not throw)', () {
      final garbage = Uint8List.fromList(List.generate(32, (i) => i));
      expect(
        CloudDenoiseTokenStore.unprotectBytesForTesting(garbage),
        isNull,
      );
    }, skip: !Platform.isWindows ? 'Windows-only (DPAPI)' : false);

    test('empty input round-trips too', () {
      final encrypted = CloudDenoiseTokenStore.protectBytesForTesting(
        Uint8List(0),
      );
      expect(encrypted, isNotNull);
      final decrypted = CloudDenoiseTokenStore.unprotectBytesForTesting(
        encrypted!,
      );
      expect(decrypted, isNotNull);
      expect(decrypted!.isEmpty, isTrue);
    }, skip: !Platform.isWindows ? 'Windows-only (DPAPI)' : false);
  });

  group('CloudDenoiseTokenStore.read/write/delete', () {
    test(
      'no-op (returns null / does not throw) without a real platform '
      'binding for path_provider — plain flutter test has no engine to '
      'service that channel, unlike a real app run',
      () async {
        // Exercises every public entry point purely to confirm none of
        // them throw in this environment — the actual persistence is
        // covered by the DPAPI-only tests above plus real manual/release-
        // build verification (path_provider itself is out of scope to
        // fake here, same as every other cache dir in this codebase).
        await CloudDenoiseTokenStore.write(
          CloudDenoiseProviderKind.topaz,
          'irrelevant',
        );
        final token = await CloudDenoiseTokenStore.read(
          CloudDenoiseProviderKind.topaz,
        );
        expect(token, isNull);
        await CloudDenoiseTokenStore.delete(CloudDenoiseProviderKind.topaz);
      },
    );
  });
}
