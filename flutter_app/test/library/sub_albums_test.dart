import 'dart:io';

import 'package:darkmoon/catalog/photo_meta_store.dart';
import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/library/library_screen.dart';
import 'package:darkmoon/library/photo_mover.dart';
import 'package:darkmoon/raw_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Sub-albums (folders inside the open one) show as tiles in the grid,
/// before the photos, and one click opens them.
void main() {
  late Directory dir;
  late String folder;
  String? openedAlbum;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('darkmoon_subalbums_');
    folder = p.join(dir.path, 'trip');
    await Directory(p.join(folder, 'Day 1')).create(recursive: true);
    await Directory(p.join(folder, 'Day 2')).create(recursive: true);
    await File(p.join(folder, 'Day 1', 'a.jpg')).writeAsBytes([0]);
    await File(p.join(folder, 'Day 1', 'b.jpg')).writeAsBytes([0]);
    openedAlbum = null;
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Widget host({required int treeToken}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: LibraryBody(
        files: [RawFile(p.join(folder, 'cover.jpg'), DateTime(2026))],
        folder: folder,
        title: 'trip',
        hasLibrary: true,
        canGoBack: false,
        onBack: () {},
        thumbnails: const {},
        thumbnailFor: (_) async => null,
        metaOf: (_) => const PhotoMeta(),
        isEdited: (_) => false,
        libraryFolders: () => [folder],
        onOpen: (_) {},
        onSelectionChanged: (_) {},
        onOpenAlbum: (album) => openedAlbum = album,
        rawOnly: false,
        onShowAllFormats: () {},
        treeToken: treeToken,
        onAddFolder: () async {},
        onSetRating: (_, _) {},
        onSetLabel: (_, _) {},
        onSetTags: (_, _) {},
        onMovePhotos: (paths, target) async =>
            const MoveOutcome(moved: {}, skipped: []),
        onCreateFolder: (parent, name) async => null,
        onDelete: (_) async => 0,
        onConvertNegatives: (_) {},
        onShowOnDisk: (_) {},
        onResetEdits: (_) {},
      ),
    ),
  );

  /// Listing the folders, then each folder's files, is real I/O started
  /// from the widget's own (fake-clock) zone: each round needs real time
  /// to complete and a pump to deliver it.
  Future<void> settleUntil(WidgetTester tester, String text) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (find.textContaining(text).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  testWidgets('lists the sub-albums with their counts and opens on a click', (
    tester,
  ) async {
    await tester.pumpWidget(host(treeToken: 0));
    await settleUntil(tester, '2 photos');

    expect(find.textContaining('Day 1'), findsOneWidget);
    expect(find.textContaining('Day 2'), findsOneWidget);
    expect(find.textContaining('2 photos'), findsOneWidget);
    expect(find.text('cover.jpg'), findsOneWidget);

    await tester.tap(find.textContaining('Day 2'));
    await tester.pumpAndSettle();
    expect(openedAlbum, p.join(folder, 'Day 2'));
  });

  testWidgets('reads every cover again when the tree changes', (tester) async {
    await tester.pumpWidget(host(treeToken: 0));
    // Day 1 is listed first; wait for Day 2's own count.
    await settleUntil(tester, 'No photos');
    expect(find.textContaining('Day 2  ·  No photos'), findsOneWidget);

    // A photo lands in Day 2 (moved there, say); the editor bumps the
    // token after any move.
    // Real I/O, so outside the fake clock.
    await tester.runAsync(
      () => File(p.join(folder, 'Day 2', 'c.jpg')).writeAsBytes([0]),
    );
    await tester.pumpWidget(host(treeToken: 1));
    // The whole label: the album's own header already says "1 photo".
    await settleUntil(tester, 'Day 2  ·  1 photo');
    expect(find.textContaining('Day 2  ·  1 photo'), findsOneWidget);
  });
}
