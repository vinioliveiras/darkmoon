import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/widgets/folder_sidebar.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The "+" that opens a file or adds a folder sits in the FOLDERS heading,
/// in the same column as the remove button on each folder row. That is a
/// claim about pixels, so it is measured rather than eyeballed.
void main() {
  Future<void> pump(WidgetTester tester, {required List<String> roots}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            children: [
              FolderSidebar(
                roots: roots,
                recentFiles: const [],
                selectedPath: null,
                selectedRecentFile: null,
                onSelect: (_) {},
                onRemove: (_) {},
                onSelectRecentFile: (_) {},
                onRemoveRecentFile: (_) {},
                rawOnly: false,
                onRawOnlyChanged: (_) {},
                includeSubfolders: false,
                onIncludeSubfoldersChanged: (_) {},
                onOpenFile: () {},
                onOpenFolder: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the + lines up with the folder rows\' remove buttons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pump(tester, roots: const [r'D:\photos']);

    final add = tester.getRect(find.byIcon(CupertinoIcons.add));
    final remove = tester.getRect(find.byIcon(CupertinoIcons.xmark).first);

    expect(
      add.right,
      closeTo(remove.right, 1.0),
      reason:
          'the + and the remove buttons have to share a right edge, or the '
          'heading reads as a floating control rather than part of the '
          'column',
    );
  });

  testWidgets('and stays put when the first folder is added', (tester) async {
    // The populated branch draws the heading inside a scroll view that
    // reserves the scrollbar's gutter; the empty one does not. Without
    // the same inset on both, the button jumps sideways the moment a
    // folder appears.
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Measured against the sidebar's own right edge, not the screen's:
    // the empty sidebar is 300 wide and the populated one 220, so the
    // button legitimately moves in absolute terms. What must not change
    // is how far in from the edge it sits.
    double insetFromRight(WidgetTester tester) =>
        tester.getRect(find.byType(FolderSidebar)).right -
        tester.getRect(find.byIcon(CupertinoIcons.add)).right;

    await pump(tester, roots: const []);
    final empty = insetFromRight(tester);

    await pump(tester, roots: const [r'D:\photos']);
    final populated = insetFromRight(tester);

    expect(empty, closeTo(populated, 0.01));
  });
}
