// The collapsible section chrome the controls panel is built from.
//
// A `part` of editor_screen.dart: same library, same private scope, no
// imports of its own — the split (2026-09-10) is for navigation, not
// decoupling. Imports live in editor_screen.dart.
part of '../editor_screen.dart';

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.collapsed,
    required this.onTap,
    this.enabled,
    this.onEnabledChanged,
    this.onHoverChanged,
  });

  final String label;
  final bool collapsed;
  final VoidCallback onTap;

  /// Reports hover enter/exit on just this header's own hit area, so the
  /// enclosing [_SectionCard] can highlight the *whole* card while only
  /// the header itself is actually hoverable/clickable.
  final ValueChanged<bool>? onHoverChanged;

  /// When non-null (only for the sections in [_sections], which map
  /// straight onto sliders — Tone Curve/Color Mixer/etc. have their own
  /// editors and aren't covered), shows a switch that turns off this
  /// whole category's contribution to the render without discarding its
  /// slider values, so the user can A/B a category the way a solo/mute
  /// button works in an audio mixer.
  final bool? enabled;
  final ValueChanged<bool>? onEnabledChanged;

  /// Bolder, larger, sentence-scale label — replaces the old tiny
  /// tight-tracked all-caps style with something closer to Photomator's
  /// plain bold section titles (no boxed background/border bar to match).
  static const _labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: DarkmoonColors.textPrimary,
  );

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHoverChanged?.call(true),
      onExit: (_) => onHoverChanged?.call(false),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          // The enclosing MouseRegion already drives the whole
          // _SectionCard's hover tint — this InkWell's own default
          // hover/highlight overlay would otherwise paint a *second*,
          // smaller one on just the header row on top of it.
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: _labelStyle.copyWith(
                      color: enabled == false ? DarkmoonColors.textMuted : null,
                    ),
                  ),
                ),
                if (enabled != null && onEnabledChanged != null) ...[
                  // SizedBox+FittedBox (not Transform.scale) so the
                  // switch's *layout* box shrinks along with its paint —
                  // Transform.scale only shrinks what's drawn, leaving the
                  // full-size unscaled switch still reserving space in the
                  // Row and forcing the whole header taller than it looks
                  // like it should be.
                  SizedBox(
                    width: 34,
                    height: 21,
                    child: FittedBox(
                      child: Switch(
                        value: enabled!,
                        onChanged: onEnabledChanged,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(
                  collapsed
                      ? CupertinoIcons.chevron_right
                      : CupertinoIcons.chevron_down,
                  size: 13,
                  color: DarkmoonColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps a section's header and collapsible body together in one
/// rounded, bordered card sitting on the panel's own background —
/// Photomator-style grouped section, replacing the old flat list of
/// headers/sliders with no visual boundary between sections.
///
/// Builds [_SectionHeader] itself (rather than taking a pre-built header
/// widget) so it can wire up [_SectionHeader.onHoverChanged] and use that
/// to highlight the *whole* card on hover, even though only the header
/// itself is the actual hoverable/clickable hit area — hovering a slider
/// or curve editor in [body] must never trigger this.
class _SectionCard extends StatefulWidget {
  const _SectionCard({
    required this.label,
    required this.collapsed,
    required this.onTap,
    this.enabled,
    this.onEnabledChanged,
    required this.body,
  });

  final String label;
  final bool collapsed;
  final VoidCallback onTap;
  final bool? enabled;
  final ValueChanged<bool>? onEnabledChanged;
  final Widget body;

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  bool _headerHovered = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AnimationsConfig.duration(
        context,
        const Duration(milliseconds: 120),
      ),
      margin: const EdgeInsets.only(top: 10),
      // Real bug (2026-09-01, user report): the old fromLTRB(10, 0, 10, 4)
      // read as visibly uneven — the header used to carry its own extra
      // top/bottom padding on top of this, so the effective top gap (card
      // padding + header's own) didn't match the effective bottom gap
      // (card padding + the body's last item's own trailing space). The
      // header's own padding is gone now (folded in here): 16 + the
      // header's remaining 4px inner padding = 20 top, matched against
      // an 8px card bottom + the body's typical last-item trailing space
      // (12px) = 20 bottom too — but only while expanded. Collapsed, the
      // body contributes zero height (see _CollapsibleSection), so the
      // bottom padding alone has to reach 20 on its own then, or a
      // collapsed card reads as 20 top / 8 bottom (the same complaint,
      // just newly visible with the section closed).
      padding: EdgeInsets.fromLTRB(12, 16, 12, widget.collapsed ? 20 : 8),
      decoration: BoxDecoration(
        color: _headerHovered
            ? Color.alphaBlend(
                Colors.white.withValues(alpha: 0.03),
                DarkmoonColors.sectionCardBackground,
              )
            : DarkmoonColors.sectionCardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DarkmoonColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            label: widget.label,
            collapsed: widget.collapsed,
            onTap: widget.onTap,
            enabled: widget.enabled,
            onEnabledChanged: widget.onEnabledChanged,
            onHoverChanged: (hovered) =>
                setState(() => _headerHovered = hovered),
          ),
          widget.body,
        ],
      ),
    );
  }
}

/// Animates a section's content growing/shrinking under its
/// [_SectionHeader] instead of popping in/out — [child] stays mounted the
/// whole time (so its own state, e.g. a slider mid-drag, survives a
/// collapse/expand), just laid out at zero height and fully transparent
/// while [collapsed]. `ClipRect` hides the part of [child] that doesn't
/// fit during the animation (`AnimatedAlign`'s `heightFactor` shrinks the
/// space it's *given*, not [child]'s own painted size, so without the
/// clip it would bleed into the next section while collapsing).
class _CollapsibleSection extends StatelessWidget {
  const _CollapsibleSection({required this.collapsed, required this.child});

  final bool collapsed;
  final Widget child;

  static const _duration = Duration(milliseconds: 160);

  @override
  Widget build(BuildContext context) {
    final duration = AnimationsConfig.duration(context, _duration);
    return ClipRect(
      child: AnimatedAlign(
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        heightFactor: collapsed ? 0.0 : 1.0,
        child: AnimatedOpacity(
          duration: duration,
          curve: Curves.easeOutCubic,
          opacity: collapsed ? 0.0 : 1.0,
          child: child,
        ),
      ),
    );
  }
}
