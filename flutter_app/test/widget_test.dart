import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/main.dart';

/// The default 800x600 test surface is narrower than this desktop app ever
/// actually runs at, and is tight enough that the viewer toolbar's fixed-
/// width segments (Undo/Redo, AI Denoise, Before/After/HD) overflow purely
/// as a test-harness artifact — not a real layout bug on an actual desktop
/// window. Widened to a realistic minimum desktop size instead.
void _setDesktopSurfaceSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'Editor screen renders the placeholder and White Balance section',
    (WidgetTester tester) async {
      _setDesktopSurfaceSize(tester);
      await tester.pumpWidget(const DarkmoonApp());
      // DarkmoonApp's splash screen holds a fixed-duration Future.delayed
      // timer (see main.dart's _splashMinDuration) that's still pending
      // after a single pump — the test harness asserts no timers are left
      // running when the test ends, so it must actually fire before this
      // test finishes, not just before the assertions below run.
      await tester.pump(const Duration(seconds: 5));

      expect(
        find.text('Open a folder with RAW files to get started'),
        findsOneWidget,
      );
      expect(find.text('WHITE BALANCE'), findsOneWidget);
      expect(find.text('Temperature'), findsOneWidget);
    },
  );

  testWidgets(
    'Portuguese layout has no overflow (its strings run longer than English)',
    (WidgetTester tester) async {
      _setDesktopSurfaceSize(tester);
      tester.platformDispatcher.localeTestValue = const Locale('pt');
      tester.platformDispatcher.localesTestValue = const [Locale('pt')];
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(const DarkmoonApp());
      // Same splash-timer reasoning as the test above — pumpAndSettle
      // alone doesn't advance a bare Future.delayed that isn't itself
      // scheduling animation frames.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(
        find.text('Abra uma pasta com arquivos RAW para começar'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
