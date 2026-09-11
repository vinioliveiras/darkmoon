import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../catalog/photo_meta_store.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';

/// The colour a label name paints — the swatch every RAW editor uses.
Color photoLabelColor(String label) => switch (label) {
  'Red' => const Color(0xFFE05A5A),
  'Yellow' => const Color(0xFFE8C547),
  'Green' => const Color(0xFF5FBF6A),
  'Blue' => const Color(0xFF5A8FE0),
  'Purple' => const Color(0xFFA56AD8),
  _ => DarkmoonColors.textMuted,
};

/// A label's name in the interface language.
String photoLabelName(AppLocalizations l10n, String label) => switch (label) {
  '' => l10n.labelNone,
  'Red' => l10n.labelRed,
  'Yellow' => l10n.labelYellow,
  'Green' => l10n.labelGreen,
  'Blue' => l10n.labelBlue,
  _ => l10n.labelPurple,
};

/// The small star row on a thumbnail.
class RatingStars extends StatelessWidget {
  const RatingStars(this.rating, {super.key, this.size = 9});

  final int rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rating; i++)
          Icon(
            CupertinoIcons.star_fill,
            size: size,
            color: Colors.white,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 2)],
          ),
      ],
    );
  }
}

/// A context menu's rating row: five stars, the current ones lit; tapping
/// the current rating clears it, as Meridian does.
class RatingPicker extends StatelessWidget {
  const RatingPicker({super.key, required this.rating, required this.onPick});

  final int rating;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Text(l10n.filmstripRatingLabel),
        const SizedBox(width: 12),
        for (var i = 1; i <= 5; i++)
          InkWell(
            onTap: () => onPick(i == rating ? 0 : i),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                i <= rating ? CupertinoIcons.star_fill : CupertinoIcons.star,
                size: 16,
                color: i <= rating
                    ? DarkmoonColors.accent
                    : DarkmoonColors.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}

/// A context menu's label row: the five colour dots and "none".
class LabelPicker extends StatelessWidget {
  const LabelPicker({super.key, required this.label, required this.onPick});

  final String label;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Text(l10n.filmstripColorLabel),
        const SizedBox(width: 12),
        for (final name in ['', ...photoLabelNames])
          Tooltip(
            message: photoLabelName(l10n, name),
            child: InkWell(
              onTap: () => onPick(name),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: LabelDot(name: name, selected: name == label),
              ),
            ),
          ),
      ],
    );
  }
}

/// One colour-label swatch; an empty [name] is the "none" ring.
class LabelDot extends StatelessWidget {
  const LabelDot({
    super.key,
    required this.name,
    required this.selected,
    this.size = 14,
  });

  final String name;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: name.isEmpty ? null : photoLabelColor(name),
        border: Border.all(
          color: selected ? Colors.white : DarkmoonColors.textMuted,
          width: selected ? 2 : 1,
        ),
      ),
    );
  }
}
