import 'package:flutter/material.dart';

/// Drop-in replacement for [showDialog] that gives the modal an OS-like
/// entrance and exit instead of Material's abrupt fade: a quick fade
/// combined with a scale-up centered on the dialog's own middle, easing
/// out on the way in and in on the way out.
///
/// Deliberately no directional drift (2026-09-01: an earlier version also
/// slid up a couple percent from below, which — however subtle in
/// isolation — read as the dialog "rising from below" rather than
/// appearing in place; a pure center-anchored scale is what "emerges from
/// the middle of the screen" actually means).
///
/// Tuned to feel like a macOS / Windows system sheet — fast enough
/// (~170 ms) to stay out of the way, never a slow "presentation". Uses
/// [showGeneralDialog] under the hood but keeps the same barrier
/// behaviour, root-navigator default and return-value semantics as
/// [showDialog], so call sites only swap the function name.
Future<T?> showAnimatedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color barrierColor = Colors.black54,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor,
    transitionDuration: const Duration(milliseconds: 170),
    pageBuilder: (context, animation, secondaryAnimation) =>
        Builder(builder: builder),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final eased = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: eased,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(eased),
          child: child,
        ),
      );
    },
  );
}
