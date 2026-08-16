import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/main.dart';

void main() {
  testWidgets('Editor screen renders the placeholder and White Balance section', (WidgetTester tester) async {
    await tester.pumpWidget(const DarkmoonApp());

    expect(find.text('Open a folder with RAW files to get started'), findsOneWidget);
    expect(find.text('WHITE BALANCE'), findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
  });

  testWidgets('Portuguese layout has no overflow (its strings run longer than English)', (WidgetTester tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('pt');
    tester.platformDispatcher.localesTestValue = const [Locale('pt')];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const DarkmoonApp());
    await tester.pumpAndSettle();

    expect(find.text('Abra uma pasta com arquivos RAW para começar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
