import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../theme.dart';

/// A dropdown button styled like the mask selector's pill menu — dark
/// surface, accent border when open, no Material ripple, and the popup
/// positioned so its left edge aligns with the button's left edge.
class StyledDropdown<T> extends StatefulWidget {
  const StyledDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.width,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? label;
  final double? width;

  @override
  State<StyledDropdown<T>> createState() => _StyledDropdownState<T>();
}

class _StyledDropdownState<T> extends State<StyledDropdown<T>> {
  final GlobalKey _buttonKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  void _toggleMenu() {
    if (_isOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    final RenderBox buttonBox =
        _buttonKey.currentContext!.findRenderObject()! as RenderBox;
    final buttonRect = buttonBox.localToGlobal(Offset.zero) &
        buttonBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => _StyledDropdownMenu<T>(
        buttonRect: buttonRect,
        items: widget.items,
        selectedValue: widget.value,
        onSelected: (value) {
          widget.onChanged(value);
          _closeMenu();
        },
        onDismissed: _closeMenu,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _closeMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      setState(() => _isOpen = false);
    }
  }

  @override
  void dispose() {
    _closeMenu();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedItem = widget.items.firstWhere(
      (item) => item.value == widget.value,
      orElse: () => widget.items.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 8),
        ],
        GestureDetector(
          key: _buttonKey,
          onTap: _toggleMenu,
          child: Container(
            width: widget.width,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: DarkmoonColors.surfaceRaised,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: _isOpen ? DarkmoonColors.accent : DarkmoonColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: DefaultTextStyle(
                    style: TextStyle(
                      color: DarkmoonColors.textPrimary,
                      fontSize: 12.5,
                    ),
                    child: selectedItem.child ??
                        Text(selectedItem.value.toString()),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _isOpen
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 14,
                  color: DarkmoonColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StyledDropdownMenu<T> extends StatelessWidget {
  const _StyledDropdownMenu({
    required this.buttonRect,
    required this.items,
    required this.selectedValue,
    required this.onSelected,
    required this.onDismissed,
  });

  final Rect buttonRect;
  final List<DropdownMenuItem<T>> items;
  final T selectedValue;
  final ValueChanged<T> onSelected;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    // Calculate menu position - align left edge with button, place below
    final menuLeft = buttonRect.left;
    final menuTop = buttonRect.bottom + 4; // 4px gap
    final menuWidth = buttonRect.width;

    return Stack(
      children: [
        // Dismiss on tap outside
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismissed,
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
        ),
        // Menu positioned relative to button
        Positioned(
          left: menuLeft,
          top: menuTop,
          width: menuWidth,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: DarkmoonColors.surfaceRaised,
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
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: DarkmoonColors.border, thickness: 0.5),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isSelected = item.value == selectedValue;
                  return InkWell(
                    onTap: () => onSelected(item.value!),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: DefaultTextStyle(
                        style: TextStyle(
                          color: isSelected
                              ? DarkmoonColors.accent
                              : DarkmoonColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        child: item.child ??
                            Text(item.value.toString()),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}