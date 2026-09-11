import 'package:flutter/material.dart';

/// Shows or hides [child] by folding it downwards: as it leaves, its box
/// shrinks from the bottom while the content slides down out of it, so a
/// strip along the bottom of a screen reads as being drawn down and
/// away, like a drawer closing. Reversed on the way back.
///
/// While fully hidden nothing is built, so the child costs nothing and
/// starts fresh when it returns.
class CollapseDown extends StatefulWidget {
  const CollapseDown({
    super.key,
    required this.shown,
    required this.duration,
    required this.child,
  });

  final bool shown;
  final Duration duration;
  final Widget child;

  @override
  State<CollapseDown> createState() => _CollapseDownState();
}

class _CollapseDownState extends State<CollapseDown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.shown ? 1 : 0,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void didUpdateWidget(covariant CollapseDown oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (oldWidget.shown != widget.shown) {
      if (widget.shown) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      child: SizedBox(width: double.infinity, child: widget.child),
      builder: (context, child) {
        final t = _progress.value;
        if (t <= 0 && !widget.shown) {
          return const SizedBox.shrink();
        }
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: t,
            child: FractionalTranslation(
              translation: Offset(0, 1 - t),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
