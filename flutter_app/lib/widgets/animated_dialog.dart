import 'package:flutter/material.dart';

/// Drop-in replacement for [showDialog] that gives the modal an OS-like
/// entrance and exit instead of Material's abrupt fade: a quick fade
/// combined with a subtle scale-up and a few pixels of upward drift,
/// easing out on the way in and in on the way out.
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
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(eased),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.965, end: 1).animate(eased),
            child: child,
          ),
        ),
      );
    },
  );
}
