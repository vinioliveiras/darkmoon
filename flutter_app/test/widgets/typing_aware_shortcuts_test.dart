import 'package:darkmoon/widgets/typing_aware_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A digit shortcut fires when nothing is being typed, and stands aside
/// while a text field has focus, so the digit reaches the field.
void main() {
  testWidgets('digits go to a focused text field, not the shortcut', (
    tester,
  ) async {
    var fired = 0;
    final fieldFocus = FocusNode();
    final otherFocus = FocusNode();
    addTearDown(fieldFocus.dispose);
    addTearDown(otherFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TypingAwareShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.digit1): () => fired++,
            },
            child: Column(
              children: [
                TextField(focusNode: fieldFocus),
                Focus(focusNode: otherFocus, child: const Text('elsewhere')),
              ],
            ),
          ),
        ),
      ),
    );

    otherFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    expect(fired, 1);

    fieldFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    expect(fired, 1, reason: 'typing into the field must not rate');
  });
}
