// darkmoon's motion standard (2026-09-12).
//
// Three durations and two curves cover everything that moves in the app.
// Before this file each widget carried its own literal (90 to 300 ms, six
// curves), so the same kind of change — a panel folding, a menu opening,
// a selection moving — took a different time in each place. Pick by what
// the change *is*, not by where it happens:
//
// - [DarkmoonMotion.fast]: state feedback on something already on screen.
//   Hover tints, a selection ring moving to the next tile, a chevron
//   turning, a slider thumb snapping back to its default.
// - [DarkmoonMotion.base]: something appearing or growing into place. A
//   section or folder expanding, a dialog or menu opening, a row sliding
//   aside in selection mode, the loading scrim fading in.
// - [DarkmoonMotion.slow]: a change of scene. Editor to Albums, one photo
//   cross-fading into the next, the view zooming to fit.
//
// Enter with [DarkmoonMotion.enter] (ease-out: quick to start, settles
// gently) and leave with [DarkmoonMotion.exit] (ease-in: the reverse), so
// a thing that opens and closes reads as one motion played both ways.
// Things that pop in (dialogs, menus) also scale from [popScale].
//
// Every duration goes through [DarkmoonMotion.of], which is
// `AnimationsConfig.duration`: the Settings switch that turns animations
// off collapses all of them to zero at once, and so do the tests that
// pump with it off.

import 'package:flutter/widgets.dart';

import 'animations_config.dart';

abstract final class DarkmoonMotion {
  /// Feedback on something already on screen — hover, selection, chevrons.
  static const Duration fast = Duration(milliseconds: 120);

  /// Something appearing or growing into place — sections, menus, dialogs.
  static const Duration base = Duration(milliseconds: 180);

  /// A change of scene — mode switches, photo cross-fades, zoom to fit.
  static const Duration slow = Duration(milliseconds: 240);

  /// For things coming in or opening.
  static const Curve enter = Curves.easeOutCubic;

  /// For things going out or closing.
  static const Curve exit = Curves.easeInCubic;

  /// Where a dialog or menu starts its scale-in from.
  static const double popScale = 0.94;

  /// [base] honouring the user's animations switch — zero when off.
  static Duration of(BuildContext context, Duration base) =>
      AnimationsConfig.duration(context, base);
}

/// Tracks whether the pointer is over [child] and rebuilds [builder] with
/// it — the one piece every hover tint needs and none should re-implement.
///
/// Pure hit-testing: no Material, no ink, no cursor change unless the
/// caller asks for one with [cursor]. Touch screens never hover, so a
/// widget built on this must read fine with `hovered` permanently false.
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = MouseCursor.defer,
    this.child,
  });

  final Widget Function(BuildContext context, bool hovered, Widget? child)
  builder;
  final MouseCursor cursor;

  /// Passed through to [builder] unchanged, so a subtree that does not
  /// depend on hover is built once rather than on every enter/exit.
  final Widget? child;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered, widget.child),
    );
  }
}
