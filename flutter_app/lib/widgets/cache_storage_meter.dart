import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../catalog/cache_usage.dart';
import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../theme.dart';

/// A storage meter for the rebuildable caches — one segmented bar and a
/// legend, the shape an operating system's own disk readout takes.
///
/// **Greys, not colours.** Every other storage meter in the world is
/// colour-coded, and this one deliberately is not: it sits in a photo
/// editor whose entire interface is neutral on purpose, so that nothing on
/// screen tints how the photograph beside it is judged. Four steps of
/// lightness carry the same information without putting a saturated hue in
/// the same window as the image.
class CacheStorageMeter extends StatelessWidget {
  const CacheStorageMeter({
    super.key,
    required this.usage,
    required this.maxBytes,
    this.onClear,
  });

  /// Null while the first measurement is still running — the meter draws
  /// its empty track rather than collapsing, so the row does not jump
  /// once the number arrives.
  final CacheUsage? usage;

  final int maxBytes;

  /// Empties one category. Null leaves the rows as a read-only breakdown.
  ///
  /// The legend doubles as the controls on purpose: a separate list of
  /// "Clear previews / Clear thumbnails / ..." buttons would name the same
  /// four things twice and let the two lists disagree about what exists.
  final void Function(CacheCategory category)? onClear;

  /// A category label, for the legend and for the confirmation text.
  static String labelOf(AppLocalizations l10n, CacheCategory category) =>
      _label(l10n, category);

  /// Brightest first, in the order the bar stacks them: the two the limit
  /// actually governs lead, so the segments that can be evicted read as
  /// the substance of the bar.
  static const _order = [
    CacheCategory.fullSources,
    CacheCategory.previews,
    CacheCategory.aiResults,
    CacheCategory.thumbnails,
  ];

  static const _shades = {
    CacheCategory.fullSources: Color(0xFFE5E6E8),
    CacheCategory.previews: Color(0xFFA8A9AB),
    CacheCategory.aiResults: Color(0xFF6E6F71),
    CacheCategory.thumbnails: Color(0xFF48494B),
  };

  static String _label(AppLocalizations l10n, CacheCategory category) =>
      switch (category) {
        CacheCategory.previews => l10n.settingsCachePreviews,
        CacheCategory.fullSources => l10n.settingsCacheFullSources,
        CacheCategory.thumbnails => l10n.settingsCacheThumbnails,
        CacheCategory.aiResults => l10n.settingsCacheAiResults,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final measured = usage ?? CacheUsage.empty;
    final total = measured.total;
    final unlimited = maxBytes == unlimitedCacheBytes;

    // What the bar is drawn against. With a limit, the limit — that is the
    // question the meter answers ("how close am I?"). Without one there is
    // no such question, so the bar becomes a breakdown of what exists and
    // fills completely.
    final scale = unlimited ? total : (total > maxBytes ? total : maxBytes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.settingsCacheStorageLabel,
                style: const TextStyle(
                  fontSize: 12,
                  color: DarkmoonColors.textSecondary,
                ),
              ),
            ),
            Text(
              usage == null
                  ? l10n.settingsCacheMeasuring
                  : unlimited
                  ? formatCacheBytes(total)
                  : l10n.settingsCacheUsedOf(
                      formatCacheBytes(total),
                      formatCacheBytes(maxBytes),
                    ),
              style: const TextStyle(
                fontSize: 12,
                color: DarkmoonColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: DarkmoonColors.dropdownBackground),
                ),
                Row(
                  children: [
                    for (final category in _order)
                      if (measured[category] > 0 && scale > 0)
                        Expanded(
                          // Integer flex, so a category too small to round
                          // to a pixel still occupies one rather than
                          // vanishing — a segment that exists should be
                          // visible, even if barely.
                          flex: (measured[category] * 10000 / scale)
                              .round()
                              .clamp(1, 10000),
                          child: ColoredBox(color: _shades[category]!),
                        ),
                    if (scale > total)
                      Expanded(
                        flex: ((scale - total) * 10000 / scale).round().clamp(
                          1,
                          10000,
                        ),
                        child: const SizedBox.shrink(),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        for (final category in _order)
          _LegendRow(
            color: _shades[category]!,
            label: _label(l10n, category),
            value: formatCacheBytes(measured[category]),
            // Nothing to reclaim, so the button would do nothing and say
            // nothing about why.
            onClear: measured[category] > 0 && onClear != null
                ? () => onClear!(category)
                : null,
            clearTooltip: l10n.settingsClearCacheTooltip(
              _label(l10n, category),
            ),
          ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
    required this.onClear,
    required this.clearTooltip,
  });

  final Color color;
  final String label;
  final String value;
  final VoidCallback? onClear;
  final String clearTooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: DarkmoonColors.textMuted,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              color: DarkmoonColors.textSecondary,
            ),
          ),
          SizedBox(
            width: 32,
            height: 28,
            child: onClear == null
                ? null
                : Tooltip(
                    message: clearTooltip,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      splashRadius: 14,
                      color: DarkmoonColors.textMuted,
                      icon: const Icon(CupertinoIcons.delete),
                      onPressed: onClear,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
