import 'dart:io';

import 'package:darkmoon/catalog/photo_meta_store.dart';
import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late String folder;
  final meta = <String, PhotoMeta>{};
  final ratings = <String, int>{};
  LibraryOpenRequest? result;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('darkmoon_library_');
    folder = p.join(dir.path, 'shoot');
    await Directory(folder).create();
    for (final name in ['alpha.jpg', 'beta.jpg', 'gamma.jpg']) {
      await File(p.join(folder, name)).writeAsBytes([0xFF, 0xD8, 0xFF]);
    }
    meta.clear();
    ratings.clear();
    result = null;
    meta[p.join(folder, 'beta.jpg')] = const PhotoMeta(rating: 4, label: 'Red');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Widget app({required List<String> folders}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open'),
              onPressed: () async {
                result = await Navigator.of(context).push<LibraryOpenRequest>(
                  MaterialPageRoute(
                    builder: (_) => LibraryScreen(
                      libraryFolders: () => folders,
                      recentFiles: () => const [],
                      rawOnly: () => false,
                      includeSubfolders: () => false,
                      initialFolder: folders.isEmpty ? null : folders.first,
                      thumbnailFor: (_) async => null,
                      metaOf: (path) => meta[path],
                      isEdited: (_) => false,
                      onSetRating: (file, rating) =>
                          ratings[file.path] = rating,
                      onSetLabel: (_, _) {},
                      onRawOnlyChanged: (_) {},
                      onIncludeSubfoldersChanged: (_) {},
                      onAddFolder: () async {},
                      onRemoveFolder: (_) {},
                      onOpenFile: () async {},
                      onRemoveRecentFile: (_) {},
                      onShowOnDisk: (_) {},
                      onResetEdits: (_) {},
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('lists the folder, filters by name and rating, opens on '
      'double tap', (tester) async {
    await tester.pumpWidget(app(folders: [folder]));
    // Listing the folder is real file I/O, which the test's fake clock
    // never advances past — run it in real time, then settle.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('open')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();

    expect(find.text('alpha.jpg'), findsOneWidget);
    expect(find.text('beta.jpg'), findsOneWidget);
    expect(find.text('gamma.jpg'), findsOneWidget);
    expect(find.text('3 photos'), findsOneWidget);

    // Name filter.
    await tester.enterText(find.byType(TextField), 'bet');
    await tester.pumpAndSettle();
    expect(find.text('alpha.jpg'), findsNothing);
    expect(find.text('beta.jpg'), findsOneWidget);
    expect(find.text('1 photo'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    // Rating filter: at least 4 stars keeps only beta.
    await tester.tap(find.byTooltip('Show photos rated 4 stars or more'));
    await tester.pumpAndSettle();
    expect(find.text('gamma.jpg'), findsNothing);
    expect(find.text('beta.jpg'), findsOneWidget);
    await tester.tap(find.byTooltip('Show photos rated 4 stars or more'));
    await tester.pumpAndSettle();
    expect(find.text('gamma.jpg'), findsOneWidget);

    // Select a photo, then Enter opens it: the screen pops with its path.
    // A tile has both onTap and onDoubleTap, so the tap only lands once
    // the double-tap window has passed — a timer, which pumpAndSettle
    // does not wait for.
    await tester.tap(find.text('gamma.jpg'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsNothing);
    // The push future was awaited inside runAsync, so its continuation
    // runs in that real-time zone — give it a turn.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(result?.path, p.join(folder, 'gamma.jpg'));
    expect(result?.folder, folder);
  });

  testWidgets('with no library folders it offers to add one', (tester) async {
    await tester.pumpWidget(app(folders: const []));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(
      find.text('Add a folder to the library to browse it here'),
      findsOneWidget,
    );
  });
}
