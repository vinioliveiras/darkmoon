import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../theme.dart';

/// The standard shape for every app dialog (Settings, About, AI Denoise,
/// Export, confirmation prompts, etc.) — rounded corners with a subtle
/// border, pairing with [DarkmoonColors.dialogBackground]'s near-black
/// fill. Use as `AlertDialog`'s `shape:` so every window shares the same
/// silhouette instead of falling back to Material's default (sharper
/// corners, no border).
const dialogShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(12)),
  side: BorderSide(color: DarkmoonColors.border),
);

/// A small circular "×" — the system-panel convention for dismissing a
/// preferences/info panel (macOS System Settings, iOS Settings) — used
/// instead of a bottom "Close" text button so these dialogs read less like
/// a generic Material alert and more like a native settings panel.
class DialogCloseButton extends StatelessWidget {
  const DialogCloseButton({super.key, required this.tooltip});

  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        iconSize: 15,
        style: IconButton.styleFrom(
          backgroundColor: DarkmoonColors.dialogBackground,
          foregroundColor: DarkmoonColors.textSecondary,
          shape: const CircleBorder(),
        ),
        icon: const Icon(CupertinoIcons.xmark),
      ),
    );
  }
}

/// A dialog title row: the title on the left, [DialogCloseButton] pinned to
/// the right — drop-in replacement for a plain `Text` title plus a bottom
/// "Close" action button.
class DialogTitleRow extends StatelessWidget {
  const DialogTitleRow({
    super.key,
    required this.title,
    required this.closeTooltip,
  });

  final String title;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        DialogCloseButton(tooltip: closeTooltip),
      ],
    );
  }
}

/// Small uppercase label above a [SettingsGroup] — iOS/macOS
/// `.insetGrouped` convention: the section title sits outside the card,
/// not as a row inside it.
class SettingsGroupHeader extends StatelessWidget {
  const SettingsGroupHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: DarkmoonColors.textMuted,
        ),
      ),
    );
  }
}

/// A rounded, bordered card holding a set of related settings rows, each
/// separated by a hairline divider — the "grouped" part of iOS/macOS'
/// `.insetGrouped` style, replacing what used to be a single loose column
/// of controls with no visual boundary between unrelated settings.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DarkmoonColors.dialogBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DarkmoonColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 12,
                endIndent: 12,
                color: DarkmoonColors.divider,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: children[i],
            ),
          ],
        ],
      ),
    );
  }
}
