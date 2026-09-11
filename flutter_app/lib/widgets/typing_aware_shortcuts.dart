import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Whether the keyboard's focus is in a text field right now. A text
/// field's focus node is attached by a [Focus] inside its [EditableText],
/// so the editable is an ancestor of the focused context, never the
/// context's own widget.
bool get isTypingInTextField =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<EditableText>() !=
    null;

/// [CallbackShortcuts] that stands aside while a text field has focus.
///
/// A text field does not consume the printable keys it is typed into:
/// the characters arrive through the platform's text input, and the key
/// events keep bubbling up the focus tree. A plain [CallbackShortcuts]
/// bound to a digit therefore fires on every digit typed into a field
/// below it, and on Windows a handled key event is also withheld from
/// text input, so the digit never lands in the field at all. That is how
/// typing a value into a slider changed the photo's rating instead
/// (user's report, 2026-09-12). Arrow and editing keys never had the
/// problem, since a field handles those itself before they bubble.
class TypingAwareShortcuts extends StatelessWidget {
  const TypingAwareShortcuts({
    super.key,
    required this.bindings,
    required this.child,
  });

  final Map<ShortcutActivator, VoidCallback> bindings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (isTypingInTextField) {
          return KeyEventResult.ignored;
        }
        for (final entry in bindings.entries) {
          if (entry.key.accepts(event, HardwareKeyboard.instance)) {
            entry.value();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
