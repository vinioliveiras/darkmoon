import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../render/color_profile.dart';

/// Overrides where profiles live, for tests.
///
/// `path_provider` needs a real platform channel, which plain
/// `flutter test` has no engine to serve — see
/// `cloud_denoise_token_store_test.dart`, which had to work around the
/// same thing. Without this hook the collision, rename and import logic
/// below could only be exercised by hand.
@visibleForTesting
Directory? debugColorProfilesDirOverride;

/// User-authored "darkmoon Color" profiles, one `.json` per profile in
/// `Documents/darkmoon/profiles` — the same shape `preset_store.dart` uses
/// for presets, and for the same reasons: a plain folder of readable files
/// the user can copy, back up or hand to someone else without the app
/// being involved.
///
/// The file *name* is the display name, so renaming is a real rename and
/// there is no second copy of the name to drift. The `id` inside the JSON
/// is what a photo or preset actually references, so renaming a profile
/// never breaks the photos already using it.
Future<Directory> colorProfilesDir() async {
  final dir =
      debugColorProfilesDirOverride ??
      Directory(
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          'darkmoon',
          'profiles',
        ),
      );
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

String _sanitizeFileBase(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? 'profile' : cleaned;
}

/// Ids below this belong to the built-in profiles and to the COLOR PROFILE
/// dropdown, which identifies its entries by a single int: a
/// `ColorProfileMode` index for the built-ins, a profile id for everything
/// else. Keeping user ids out of the low band means those two can never be
/// confused for one another, however many built-in modes are added later.
const int reservedColorProfileIds = 256;

/// A fresh profile id: 32 bits of randomness, above the reserved band.
///
/// See [ColorProfile.id] for why this is 32 bits rather than 64.
int newColorProfileId([math.Random? random]) {
  final rng = random ?? math.Random.secure();
  return reservedColorProfileIds +
      rng.nextInt(0xFFFFFFFF - reservedColorProfileIds);
}

/// Every readable profile in [colorProfilesDir], keyed by id.
///
/// A file that fails to parse is skipped rather than allowed to take the
/// whole list down with it — one hand-edited or truncated JSON should cost
/// its own profile, not every other one.
///
/// Two files carrying the same id can only happen through an import (see
/// [importColorProfile], which reassigns on collision) or a hand copy. The
/// first one read wins and the other is dropped; silently rendering with
/// whichever the filesystem happened to list last would be worse.
Future<Map<int, ColorProfile>> loadUserColorProfiles() async {
  final dir = await colorProfilesDir();
  final result = <int, ColorProfile>{};
  final entries = await dir.list().toList();
  entries.sort((a, b) => a.path.compareTo(b.path));
  for (final entry in entries) {
    if (entry is! File || p.extension(entry.path).toLowerCase() != '.json') {
      continue;
    }
    try {
      final profile = ColorProfile.decode(await entry.readAsString());
      if (profile.id < reservedColorProfileIds ||
          result.containsKey(profile.id)) {
        continue;
      }
      // The filename is the name, so a renamed file renames the profile
      // even though the JSON still carries the old string.
      result[profile.id] = profile.withName(
        p.basenameWithoutExtension(entry.path),
      );
    } catch (_) {
      // Unreadable or not a profile — skip it.
    }
  }
  return result;
}

/// Writes [profile] out, returning it with whatever name the file ended up
/// with (a collision gets a numeric suffix, as presets do).
///
/// Replaces the file that already holds this id, wherever it sits and
/// whatever it is called, so saving after a rename does not leave the old
/// file behind as a duplicate under the old name.
Future<ColorProfile> saveUserColorProfile(ColorProfile profile) async {
  assert(
    profile.id >= reservedColorProfileIds,
    'a user profile id must sit above the reserved band',
  );
  final dir = await colorProfilesDir();

  File? existing;
  for (final entry in await dir.list().toList()) {
    if (entry is! File || p.extension(entry.path).toLowerCase() != '.json') {
      continue;
    }
    try {
      if (ColorProfile.decode(await entry.readAsString()).id == profile.id) {
        existing = entry;
        break;
      }
    } catch (_) {
      // Not ours to worry about.
    }
  }

  final base = _sanitizeFileBase(profile.name);
  var name = base;
  var target = File(p.join(dir.path, '$name.json'));
  var n = 2;
  while (await target.exists() &&
      p.equals(target.path, existing?.path ?? '') == false) {
    name = '$base ($n)';
    target = File(p.join(dir.path, '$name.json'));
    n++;
  }

  final saved = profile.withName(name);
  await target.writeAsString(saved.encode());
  if (existing != null && !p.equals(existing.path, target.path)) {
    await existing.delete();
  }
  return saved;
}

Future<void> deleteUserColorProfile(int id) async {
  final dir = await colorProfilesDir();
  for (final entry in await dir.list().toList()) {
    if (entry is! File || p.extension(entry.path).toLowerCase() != '.json') {
      continue;
    }
    try {
      if (ColorProfile.decode(await entry.readAsString()).id == id) {
        await entry.delete();
        return;
      }
    } catch (_) {
      // Skip.
    }
  }
}

/// Reads a profile from an arbitrary path and adds it to the library.
///
/// The id is reassigned when it is already taken by a *different* profile,
/// which is the case two people independently creating profiles can
/// eventually produce. Re-importing a profile that is already here keeps
/// its id, so it updates in place instead of quietly becoming a second
/// copy that the photos referencing the first one cannot see.
Future<ColorProfile> importColorProfile(String path) async {
  final raw = await File(path).readAsString();
  var profile = ColorProfile.decode(raw);
  final existing = await loadUserColorProfiles();

  if (profile.id < reservedColorProfileIds ||
      (existing.containsKey(profile.id) &&
          !_sameContent(existing[profile.id]!, profile))) {
    profile = profile.withId(newColorProfileId());
  }
  if (profile.name.trim().isEmpty) {
    profile = profile.withName(p.basenameWithoutExtension(path));
  }
  return saveUserColorProfile(profile);
}

/// Exports [profile] to [path] exactly as it is stored.
Future<void> exportColorProfile(ColorProfile profile, String path) =>
    File(path).writeAsString(profile.encode());

/// Compares everything that affects the render, plus the name — ignoring
/// the id, which is the thing being decided.
bool _sameContent(ColorProfile a, ColorProfile b) {
  if (a.name != b.name) {
    return false;
  }
  for (final pair in [
    (a.tone, b.tone),
    (a.hueShift, b.hueShift),
    (a.satMul, b.satMul),
    (a.lumMul, b.lumMul),
  ]) {
    if (pair.$1.length != pair.$2.length) {
      return false;
    }
    for (var i = 0; i < pair.$1.length; i++) {
      if (pair.$1[i] != pair.$2[i]) {
        return false;
      }
    }
  }
  return true;
}

/// Decodes a profile without touching the filesystem — for callers that
/// already hold the text (a paste, a test).
ColorProfile decodeColorProfile(String source) =>
    ColorProfile.fromJson(jsonDecode(source) as Map<String, dynamic>);
