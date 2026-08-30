import 'package:flutter/widgets.dart';

/// Broadcasts Settings > "Interface animations" down the widget tree, so
/// any widget that plays a transition (section-card hover, segmented-tab
/// slide, zoom, the preview's post-edit fade-in, folder expand/collapse,
/// …) can ask [AnimationsConfig.duration] for its actual duration
/// instead of every one of those widgets needing its own
/// `animationsEnabled` constructor parameter threaded down from
/// `_EditorScreenState`. Provided once, high in the tree, in
/// `editor_screen.dart`'s `_buildScaffold`.
class AnimationsConfig extends InheritedWidget {
  const AnimationsConfig({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AnimationsConfig>()?.enabled ??
      true;

  /// [base] when animations are on, [Duration.zero] (an instant snap)
  /// when the user turned them off.
  static Duration duration(BuildContext context, Duration base) =>
      of(context) ? base : Duration.zero;

  @override
  bool updateShouldNotify(AnimationsConfig oldWidget) =>
      enabled != oldWidget.enabled;
}
