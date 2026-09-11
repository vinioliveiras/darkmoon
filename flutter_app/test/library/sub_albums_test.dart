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

  testWidgets('lists the sub-albums with their counts and opens on a click', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
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
            treeToken: 0,
            onAddFolder: () async {},
            onSetRating: (_, _) {},
            onSetLabel: (_, _) {},
            onSetTags: (_, _) {},
            onMovePhotos: (paths, target) async =>
                const MoveOutcome(moved: {}, skipped: []),
            onCreateFolder: (parent, name) async => null,
            onDelete: (_) async => 0,
            onShowOnDisk: (_) {},
            onResetEdits: (_) {},
          ),
        ),
      ),
    );
    // Listing the folders, then each folder's files, is real I/O started
    // from the widget's own (fake-clock) zone: each round needs real time
    // to complete and a pump to deliver it.
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (find.textContaining('2 photos').evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();

    expect(find.textContaining('Day 1'), findsOneWidget);
    expect(find.textContaining('Day 2'), findsOneWidget);
    expect(find.textContaining('2 photos'), findsOneWidget);
    expect(find.text('cover.jpg'), findsOneWidget);

    await tester.tap(find.textContaining('Day 2'));
    await tester.pumpAndSettle();
    expect(openedAlbum, p.join(folder, 'Day 2'));
  });
}
