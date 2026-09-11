import 'package:darkmoon/catalog/photo_meta_store.dart';
import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/library/library_screen.dart';
import 'package:darkmoon/library/photo_mover.dart';
import 'package:darkmoon/raw_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final folder = p.join('D:', 'shoot');
  final files = [
    for (final name in ['alpha.jpg', 'beta.jpg', 'gamma.jpg'])
      RawFile(p.join(folder, name), DateTime(2026, 9, 11)),
  ];
  final meta = <String, PhotoMeta>{};
  final ratings = <String, int>{};
  RawFile? opened;
  var wentBack = 0;

  setUp(() {
    meta.clear();
    ratings.clear();
    opened = null;
    wentBack = 0;
    meta[p.join(folder, 'beta.jpg')] = const PhotoMeta(rating: 4, label: 'Red');
  });

  Widget app({
    List<RawFile>? photos,
    bool hasLibrary = true,
    bool canGoBack = false,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: LibraryBody(
          files: photos ?? files,
          folder: folder,
          title: 'shoot',
          hasLibrary: hasLibrary,
          canGoBack: canGoBack,
          onBack: () => wentBack++,
          thumbnails: const {},
          thumbnailFor: (_) async => null,
          metaOf: (path) => meta[path],
          isEdited: (_) => false,
          libraryFolders: () => [folder],
          onOpen: (file) => opened = file,
          onSelectionChanged: (_) {},
          onOpenAlbum: (_) {},
          rawOnly: false,
          onShowAllFormats: () {},
          treeToken: 0,
          onAddFolder: () async {},
          onSetRating: (file, rating) => ratings[file.path] = rating,
          onSetLabel: (_, _) {},
          onSetTags: (file, tags) => meta[file.path] =
              (meta[file.path] ?? const PhotoMeta()).copyWith(tags: tags),
          onMovePhotos: (paths, target) async =>
              const MoveOutcome(moved: {}, skipped: []),
          onCreateFolder: (parent, name) async => p.join(parent, name),
          onDelete: (targets) async => 0,
          onShowOnDisk: (_) {},
          onResetEdits: (_) {},
        ),
      ),
    );
  }

  testWidgets('lists the album, filters by name and rating, opens on Enter', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('alpha.jpg'), findsOneWidget);
    expect(find.text('beta.jpg'), findsOneWidget);
    expect(find.text('gamma.jpg'), findsOneWidget);
    expect(find.text('3 photos'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bet');
    await tester.pumpAndSettle();
    expect(find.text('alpha.jpg'), findsNothing);
    expect(find.text('1 photo'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show photos rated 4 stars or more'));
    await tester.pumpAndSettle();
    expect(find.text('gamma.jpg'), findsNothing);
    expect(find.text('beta.jpg'), findsOneWidget);
    await tester.tap(find.byTooltip('Show photos rated 4 stars or more'));
    await tester.pumpAndSettle();

    // A tile has onTap and onDoubleTap, so the tap lands once the
    // double-tap window has passed — a timer pumpAndSettle does not wait
    // for.
    await tester.tap(find.text('gamma.jpg'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened?.name, 'gamma.jpg');
  });

  testWidgets('the back arrow follows canGoBack', (tester) async {
    await tester.pumpWidget(app(canGoBack: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to the previous album'));
    await tester.pumpAndSettle();
    expect(wentBack, 0);
    await tester.pumpWidget(app(canGoBack: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to the previous album'));
    await tester.pumpAndSettle();
    expect(wentBack, 1);
  });

  testWidgets('with no library it offers to add a folder', (tester) async {
    await tester.pumpWidget(app(photos: const [], hasLibrary: false));
    await tester.pumpAndSettle();
    expect(
      find.text('Add a folder to the library to browse it here'),
      findsOneWidget,
    );
  });

  testWidgets('Ctrl-click builds a selection and a rating key rates it all', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('alpha.jpg'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('gamma.jpg'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 selected'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pumpAndSettle();
    expect(ratings[p.join(folder, 'alpha.jpg')], 2);
    expect(ratings[p.join(folder, 'gamma.jpg')], 2);
    expect(ratings.containsKey(p.join(folder, 'beta.jpg')), isFalse);
  });
}
