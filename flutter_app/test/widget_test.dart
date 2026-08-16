import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/main.dart';

void main() {
  testWidgets('Editor screen renders the placeholder and White Balance section', (WidgetTester tester) async {
    await tester.pumpWidget(const DarkmoonApp());

    expect(find.text('Open a folder with RAW files to get started'), findsOneWidget);
    expect(find.text('WHITE BALANCE'), findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
  });
}
