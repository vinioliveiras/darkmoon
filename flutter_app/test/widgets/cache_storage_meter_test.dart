import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/catalog/cache_usage.dart';
import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/settings/app_settings.dart';
import 'package:darkmoon/widgets/cache_storage_meter.dart';

/// The meter answers one question — "how close am I to the limit?" — and
/// the answer has to survive the two states that are easy to get wrong: no
/// measurement yet, and no limit set.
void main() {
  final cleared = <CacheCategory>[];

  setUp(cleared.clear);

  Future<AppLocalizations> pump(
    WidgetTester tester, {
    required CacheUsage? usage,
    required int maxBytes,
    bool clearable = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: CacheStorageMeter(
              usage: usage,
              maxBytes: maxBytes,
              onClear: clearable ? cleared.add : null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.delegate.load(const Locale('en'));
  }

  const gb = 1024 * 1024 * 1024;

  testWidgets('it reads used against the limit', (tester) async {
    final l10n = await pump(
      tester,
      usage: const CacheUsage({
        CacheCategory.previews: 1 * gb,
        CacheCategory.fullSources: 2 * gb,
      }),
      maxBytes: 5 * gb,
    );
    expect(
      find.text(l10n.settingsCacheUsedOf('3.0 GB', '5.0 GB')),
      findsOneWidget,
    );
  });

  testWidgets('with no limit it reports a total, not a fraction', (
    tester,
  ) async {
    // "3.0 GB of 0 B" would be nonsense, and the bar has no ceiling to
    // draw against — it becomes a breakdown of what exists instead.
    final l10n = await pump(
      tester,
      usage: const CacheUsage({CacheCategory.previews: 3 * gb}),
      maxBytes: unlimitedCacheBytes,
    );
    // Twice: the header total, and Previews in the legend, which here
    // holds all of it.
    expect(find.text('3.0 GB'), findsNWidgets(2));
    expect(
      find.text(l10n.settingsCacheUsedOf('3.0 GB', '0 B')),
      findsNothing,
      reason: '"3.0 GB of 0 B" is what an unhandled no-limit looks like',
    );
  });

  testWidgets('before the first measurement it says so', (tester) async {
    // Rather than reporting a confident zero, which would read as "the
    // cache is empty" at exactly the moment it is most likely not.
    final l10n = await pump(tester, usage: null, maxBytes: 5 * gb);
    expect(find.text(l10n.settingsCacheMeasuring), findsOneWidget);
    expect(find.text(l10n.settingsCacheUsedOf('0 B', '5.0 GB')), findsNothing);
  });

  testWidgets('every category is named, even at zero', (tester) async {
    // The legend is what explains the bar. Hiding an empty category would
    // change the legend's shape as the cache fills, and leave the user
    // unable to tell what is not there.
    final l10n = await pump(
      tester,
      usage: const CacheUsage({CacheCategory.previews: 100}),
      maxBytes: 5 * gb,
    );
    expect(find.text(l10n.settingsCachePreviews), findsOneWidget);
    expect(find.text(l10n.settingsCacheFullSources), findsOneWidget);
    expect(find.text(l10n.settingsCacheThumbnails), findsOneWidget);
    expect(find.text(l10n.settingsCacheAiResults), findsOneWidget);
  });

  testWidgets('a category with nothing in it offers no clear button', (
    tester,
  ) async {
    // The button would do nothing and say nothing about why.
    await pump(
      tester,
      usage: const CacheUsage({CacheCategory.previews: 100}),
      maxBytes: 5 * gb,
      clearable: true,
    );
    expect(find.byType(IconButton), findsOneWidget);
  });

  testWidgets('clearing one category asks for exactly that one', (
    tester,
  ) async {
    await pump(
      tester,
      usage: const CacheUsage({
        CacheCategory.previews: 100,
        CacheCategory.aiResults: 200,
      }),
      maxBytes: 5 * gb,
      clearable: true,
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    // Reached through the row that names the category, not by position:
    // the rows are built from a fixed order, so an index would keep
    // passing if the button were wired to the wrong row.
    final aiRow = find
        .ancestor(
          of: find.text(l10n.settingsCacheAiResults),
          matching: find.byType(Row),
        )
        .first;
    await tester.tap(
      find.descendant(of: aiRow, matching: find.byType(IconButton)),
    );
    await tester.pumpAndSettle();
    expect(cleared, [
      CacheCategory.aiResults,
    ], reason: 'the row acted on has to be the row that was clicked');
  });

  testWidgets('with no handler the rows are a read-only breakdown', (
    tester,
  ) async {
    await pump(
      tester,
      usage: const CacheUsage({CacheCategory.previews: 100}),
      maxBytes: 5 * gb,
    );
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('over the limit it still draws, scaled to the total', (
    tester,
  ) async {
    // Being over is a real state — the sweep is debounced, and AI results
    // are never evicted — so the bar has to keep meaning something rather
    // than overflowing its own box.
    await pump(
      tester,
      usage: const CacheUsage({CacheCategory.aiResults: 9 * gb}),
      maxBytes: 1 * gb,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(CacheStorageMeter), findsOneWidget);
  });
}
