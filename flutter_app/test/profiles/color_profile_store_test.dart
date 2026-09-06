import 'dart:io';
import 'dart:math' as math;

import 'package:darkmoon/profiles/color_profile_store.dart';
import 'package:darkmoon/render/color_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The store is what stands between a photo and the profile it says it
/// uses, so the cases that matter are the ones where a reference could
/// quietly come to mean something else: an id colliding on import, a
/// rename leaving the old file behind, a corrupt file taking the library
/// down with it.
void main() {
  late Directory dir;

  ColorProfile profile({
    required int id,
    String name = 'Test',
    double bend = 0.0,
  }) => ColorProfile(
    tone: [
      for (var i = 0; i < colorProfileTonePoints; i++)
        (i / (colorProfileTonePoints - 1) + bend).clamp(0.0, 1.0),
    ],
    hueShift: List<double>.filled(colorProfileBins, 0),
    satMul: List<double>.filled(colorProfileBins, 1),
    lumMul: List<double>.filled(colorProfileBins, 1),
    name: name,
    id: id,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('darkmoon_profiles_test');
    debugColorProfilesDirOverride = dir;
  });

  tearDown(() async {
    debugColorProfilesDirOverride = null;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  test('a saved profile comes back with its id and curve intact', () async {
    await saveUserColorProfile(profile(id: 1000, name: 'Warm', bend: 0.05));

    final loaded = await loadUserColorProfiles();
    expect(loaded.keys, [1000]);
    expect(loaded[1000]!.name, 'Warm');
    expect(loaded[1000]!.toneIsIdentity, isFalse);
  });

  test('ids stay clear of the reserved band', () {
    final rng = math.Random(7);
    for (var i = 0; i < 200; i++) {
      final id = newColorProfileId(rng);
      expect(id, greaterThanOrEqualTo(reservedColorProfileIds));
      expect(id, lessThan(0xFFFFFFFF));
    }
  });

  test('two profiles with the same name get distinct files', () async {
    final a = await saveUserColorProfile(profile(id: 1000, name: 'Portrait'));
    final b = await saveUserColorProfile(profile(id: 1001, name: 'Portrait'));

    expect(a.name, 'Portrait');
    expect(b.name, 'Portrait (2)');
    expect((await loadUserColorProfiles()).length, 2);
  });

  test('renaming replaces the old file rather than leaving a copy', () async {
    final saved = await saveUserColorProfile(
      profile(id: 1000, name: 'Original'),
    );
    await saveUserColorProfile(saved.withName('Renamed'));

    final files = dir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .toList();
    expect(files, [
      'Renamed.json',
    ], reason: 'the old name must not survive as a second profile');
    expect((await loadUserColorProfiles()).keys, [1000]);
  });

  test('the filename wins over the name stored inside the JSON', () async {
    await saveUserColorProfile(profile(id: 1000, name: 'Inside'));
    await File(
      p.join(dir.path, 'Inside.json'),
    ).rename(p.join(dir.path, 'Renamed by hand.json'));

    final loaded = await loadUserColorProfiles();
    expect(
      loaded[1000]!.name,
      'Renamed by hand',
      reason: 'renaming the file is how a profile is renamed',
    );
  });

  test('one corrupt file does not take the others down', () async {
    await saveUserColorProfile(profile(id: 1000, name: 'Good'));
    await File(p.join(dir.path, 'Broken.json')).writeAsString('{ not json');

    final loaded = await loadUserColorProfiles();
    expect(loaded.keys, [1000]);
  });

  test('importing a profile whose id is taken gets a fresh id', () async {
    await saveUserColorProfile(profile(id: 1000, name: 'Mine', bend: 0.05));

    // Someone else's profile that happens to have drawn the same number.
    final incoming = File(p.join(dir.parent.path, 'theirs.json'));
    await incoming.writeAsString(
      profile(id: 1000, name: 'Theirs', bend: 0.2).encode(),
    );
    addTearDown(() async => incoming.delete());

    final imported = await importColorProfile(incoming.path);
    expect(imported.id, isNot(1000));
    expect(imported.id, greaterThanOrEqualTo(reservedColorProfileIds));

    final loaded = await loadUserColorProfiles();
    expect(loaded.length, 2, reason: 'neither profile may displace the other');
    expect(loaded[1000]!.name, 'Mine');
  });

  test('re-importing the same profile updates it in place', () async {
    final original = profile(id: 1000, name: 'Shared', bend: 0.05);
    await saveUserColorProfile(original);

    final incoming = File(p.join(dir.parent.path, 'shared.json'));
    await incoming.writeAsString(original.encode());
    addTearDown(() async => incoming.delete());

    final imported = await importColorProfile(incoming.path);
    expect(
      imported.id,
      1000,
      reason: 'a re-import must not orphan the photos already pointing here',
    );
    expect((await loadUserColorProfiles()).length, 1);
  });

  test('deleting removes only the profile asked for', () async {
    await saveUserColorProfile(profile(id: 1000, name: 'Keep'));
    await saveUserColorProfile(profile(id: 1001, name: 'Drop'));

    await deleteUserColorProfile(1001);

    expect((await loadUserColorProfiles()).keys, [1000]);
  });

  test('export writes a file import can read back', () async {
    final saved = await saveUserColorProfile(
      profile(id: 1000, name: 'Round trip', bend: 0.1),
    );
    final out = File(p.join(dir.parent.path, 'exported.json'));
    addTearDown(() async => out.delete());

    await exportColorProfile(saved, out.path);
    final reread = ColorProfile.decode(await out.readAsString());

    expect(reread.id, saved.id);
    expect(reread.name, saved.name);
    expect(reread.tone, saved.tone);
  });
}
