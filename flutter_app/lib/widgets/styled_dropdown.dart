import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../theme.dart';

/// A single entry in a [StyledDropdown]. Carries the raw value plus its
/// label and (optional) leading icon so the dropdown can render both the
/// selected state and the popup rows with the same visual template — no
/// callers need to hand-build `Row(Icon, Text)` children just to get an
/// icon next to a label.
class StyledDropdownItem<T> {
  const StyledDropdownItem({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

/// The app's standard dropdown: a dark pill button that, on tap, opens
/// a menu directly below it — same width as the button, options rendered
/// with matching icon+label rows. Modeled on the mask selector's pill so
/// pickers throughout the app share one look.
///
/// If [selectedValue] doesn't match any item's [StyledDropdownItem.value],
/// the button falls back to showing [placeholder] (or the first item when
/// no placeholder is provided) — this is the "nothing chosen yet" state,
/// e.g. the Add-mask button, which has no persistent selection.
class StyledDropdown<T> extends StatefulWidget {
  const StyledDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.width,
    this.placeholder,
    this.leadingIcon,
    this.showChevron = true,
    this.menuWidth,
    this.menuAlignRight = false,
    this.searchable = false,
    this.searchHintText,
    this.noMatchesText,
    this.maxMenuHeight = 320,
  });

  final T? value;
  final List<StyledDropdownItem<T>> items;
  final ValueChanged<T> onChanged;
  final String? label;
  final double? width;

  /// Text shown on the button when [value] doesn't match any item — useful
  /// for menu-style dropdowns (like "Add mask") that never carry a
  /// persistent selection. Ignored when a matching item exists.
  final String? placeholder;

  /// Icon shown on the button when [value] doesn't match any item. Falls
  /// back to the placeholder-mode default (no icon) when null.
  final IconData? leadingIcon;

  /// Show the trailing chevron on the button. Defaults to true; set false
  /// for menu-style triggers ("Add …") that shouldn't look like a picker
  /// with a current value.
  final bool showChevron;

  /// Width of the popup. Defaults to the button's own width so the menu
  /// reads as a continuation of the pill. Override only when the trigger
  /// is too narrow to host a readable list — e.g. a square icon button.
  final double? menuWidth;

  /// Anchor the menu's right edge to the button's right edge instead of
  /// the left. Needed when a narrow trigger with a wider [menuWidth] sits
  /// at the right edge of a panel — left-anchoring would run it off-screen.
  final bool menuAlignRight;

  /// Adds a text field at the top of the popup that filters [items] live
  /// by [StyledDropdownItem.label] as the user types — for lists too long
  /// to scan by eye (e.g. the lens-profile picker's ~1500 entries).
  final bool searchable;

  /// Placeholder shown in the search field. Ignored unless [searchable].
  final String? searchHintText;

  /// Shown in place of the list when a search matches nothing. Ignored
  /// unless [searchable].
  final String? noMatchesText;

  /// Cap on the popup's height. The default (320) forces a scroll for
  /// long lists (the lens-profile picker); raise it for a short fixed
  /// list that should show every option at once.
  final double maxMenuHeight;

  @override
  State<StyledDropdown<T>> createState() => _StyledDropdownState<T>();
}

class _StyledDropdownState<T> extends State<StyledDropdown<T>>
    with SingleTickerProviderStateMixin {
  final GlobalKey _buttonKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  // Drives the popup's open/close animation: a quick fade + scale-from-the
  // -top, the way an OS menu unfolds from its trigger. On close we run it
  // in reverse and only pull the overlay once it's finished, so the menu
  // eases out instead of vanishing.
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 110),
    );
  }

  void _toggleMenu() {
    if (_isOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    if (_overlayEntry != null) {
      // A close animation is still running — reopen the same entry.
      _animController.forward();
      setState(() => _isOpen = true);
      return;
    }
    final RenderBox buttonBox =
        _buttonKey.currentContext!.findRenderObject()! as RenderBox;
    final buttonRect = buttonBox.localToGlobal(Offset.zero) & buttonBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => _StyledDropdownMenu<T>(
        buttonRect: buttonRect,
        animation: _animController.view,
        menuWidth: widget.menuWidth,
        alignRight: widget.menuAlignRight,
        items: widget.items,
        selectedValue: widget.value,
        searchable: widget.searchable,
        searchHintText: widget.searchHintText,
        noMatchesText: widget.noMatchesText,
        maxHeight: widget.maxMenuHeight,
        onSelected: (value) {
          widget.onChanged(value);
          _closeMenu();
        },
        onDismissed: _closeMenu,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    _animController.forward(from: 0);
    setState(() => _isOpen = true);
  }

  void _closeMenu() {
    if (_overlayEntry == null) {
      return;
    }
    if (mounted) {
      setState(() => _isOpen = false);
    }
    _animController.reverse().whenComplete(() {
      // Skip the teardown if the menu was reopened mid-close.
      if (_animController.status == AnimationStatus.dismissed) {
        _overlayEntry?.remove();
        _overlayEntry = null;
      }
    });
  }

  @override
  void dispose() {
    // Not _closeMenu(): during a whole-subtree teardown the framework
    // calls dispose() on an element that's already defunct, so `mounted`
    // being true here doesn't mean setState is safe — it still asserts.
    // Only the overlay entry needs cleaning up; `_isOpen` dies with the
    // widget either way.
    _overlayEntry?.remove();
    _overlayEntry = null;
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Find the currently-selected item; if there isn't one, the button
    // shows the placeholder (menu-style dropdown, no persistent value).
    StyledDropdownItem<T>? selectedItem;
    for (final item in widget.items) {
      if (item.value == widget.value) {
        selectedItem = item;
        break;
      }
    }

    final label =
        selectedItem?.label ??
        widget.placeholder ??
        (widget.items.isNotEmpty ? widget.items.first.label : '');
    final icon = selectedItem?.icon ?? widget.leadingIcon;

    // An empty label means an icon-only trigger (e.g. the square "+"
    // button): drop the text slot entirely and center the icon, otherwise
    // the fixed padding + text slot overflows a 34px-wide button.
    final iconOnly = label.isEmpty && icon != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
        ],
        GestureDetector(
          key: _buttonKey,
          onTap: _toggleMenu,
          child: Container(
            width: widget.width,
            height: 34,
            padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 10),
            decoration: BoxDecoration(
              color: DarkmoonColors.dropdownBackground,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: _isOpen ? DarkmoonColors.accent : DarkmoonColors.border,
              ),
            ),
            child: iconOnly
                ? Center(
                    child: Icon(
                      icon,
                      size: 16,
                      color: DarkmoonColors.textSecondary,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(
                          icon,
                          size: 15,
                          color: DarkmoonColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: DarkmoonColors.textPrimary,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      if (widget.showChevron) ...[
                        const SizedBox(width: 8),
                        Icon(
                          _isOpen
                              ? CupertinoIcons.chevron_up
                              : CupertinoIcons.chevron_down,
                          size: 13,
                          color: DarkmoonColors.textMuted,
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _StyledDropdownMenu<T> extends StatefulWidget {
  const _StyledDropdownMenu({
    required this.buttonRect,
    required this.animation,
    required this.menuWidth,
    required this.alignRight,
    required this.items,
    required this.selectedValue,
    required this.onSelected,
    required this.onDismissed,
    required this.maxHeight,
    this.searchable = false,
    this.searchHintText,
    this.noMatchesText,
  });

  final Rect buttonRect;
  final Animation<double> animation;
  final double? menuWidth;
  final bool alignRight;
  final List<StyledDropdownItem<T>> items;
  final T? selectedValue;
  final ValueChanged<T> onSelected;
  final VoidCallback onDismissed;
  final double maxHeight;
  final bool searchable;
  final String? searchHintText;
  final String? noMatchesText;

  @override
  State<_StyledDropdownMenu<T>> createState() => _StyledDropdownMenuState<T>();
}

class _StyledDropdownMenuState<T> extends State<_StyledDropdownMenu<T>> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StyledDropdownItem<T>> get _filteredItems {
    if (!widget.searchable || _query.isEmpty) {
      return widget.items;
    }
    final q = _query.toLowerCase();
    return widget.items
        .where((item) => item.label.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // Menu is anchored to the button's left edge and sits directly below
    // it, matching the button's width exactly so the popup looks like a
    // continuation of the pill rather than a floating detached menu.
    final menuTop = widget.buttonRect.bottom + 4;
    final width = widget.menuWidth ?? widget.buttonRect.width;
    final menuLeft = widget.alignRight
        ? widget.buttonRect.right - width
        : widget.buttonRect.left;
    final filtered = _filteredItems;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismissed,
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: menuLeft,
          top: menuTop,
          width: width,
          child: _MenuReveal(
            animation: widget.animation,
            alignment: widget.alignRight
                ? Alignment.topRight
                : Alignment.topLeft,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: DarkmoonColors.dropdownBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DarkmoonColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                constraints: BoxConstraints(maxHeight: widget.maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.searchable)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          onChanged: (v) => setState(() => _query = v),
                          style: const TextStyle(
                            color: DarkmoonColors.textPrimary,
                            fontSize: 12.5,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: widget.searchHintText,
                            hintStyle: const TextStyle(
                              color: DarkmoonColors.textMuted,
                              fontSize: 12.5,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            filled: true,
                            fillColor: DarkmoonColors.panel,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                color: DarkmoonColors.border,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                color: DarkmoonColors.border,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                color: DarkmoonColors.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Flexible(
                      child: filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                              child: Text(
                                widget.noMatchesText ?? '',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: DarkmoonColors.textMuted,
                                  fontSize: 12.5,
                                ),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: DarkmoonColors.border,
                                thickness: 0.5,
                              ),
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                final isSelected =
                                    item.value == widget.selectedValue;
                                return InkWell(
                                  onTap: () => widget.onSelected(item.value),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        if (item.icon != null) ...[
                                          Icon(
                                            item.icon,
                                            size: 15,
                                            color: isSelected
                                                ? DarkmoonColors.accent
                                                : DarkmoonColors.textSecondary,
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Expanded(
                                          child: Text(
                                            item.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isSelected
                                                  ? DarkmoonColors.accent
                                                  : DarkmoonColors.textPrimary,
                                              fontSize: 12.5,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The popup's entrance/exit: fades in while scaling up from [alignment]
/// (the corner nearest the trigger button), so the menu appears to unfold
/// out of the pill rather than blink into place. Reversing [animation]
/// plays the same motion backwards on close.
class _MenuReveal extends StatelessWidget {
  const _MenuReveal({
    required this.animation,
    required this.alignment,
    required this.child,
  });

  final Animation<double> animation;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final eased = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: eased,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(eased),
        alignment: alignment,
        child: child,
      ),
    );
  }
}
