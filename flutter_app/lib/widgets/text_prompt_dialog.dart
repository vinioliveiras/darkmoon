import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'animated_dialog.dart';

/// A single-text-field "name this" dialog — used for naming a new preset
/// and for renaming an existing one. Returns the trimmed text, or null if
/// cancelled or left empty.
Future<String?> showTextPromptDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
}) async {
  final controller = TextEditingController(text: initialValue);
  final l10n = AppLocalizations.of(context)!;
  final result = await showAnimatedDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: DarkmoonColors.dialogBackground,
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(l10n.presetSaveLabel),
        ),
      ],
    ),
  );
  controller.dispose();
  return (result == null || result.isEmpty) ? null : result;
}
