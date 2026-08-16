import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets/slider_row.dart';

class _SliderSpec {
  const _SliderSpec(this.name, this.min, this.max, this.defaultValue, {this.decimals = 2});

  final String name;
  final double min;
  final double max;
  final double defaultValue;
  final int decimals;
}

const _sections = <String, List<_SliderSpec>>{
  'WHITE BALANCE': [
    _SliderSpec('Temperature', 2000, 50000, 5500, decimals: 0),
    _SliderSpec('Tint', -100, 100, 0),
  ],
  'TONE': [
    _SliderSpec('Exposure', -100, 100, 0),
    _SliderSpec('Brightness', -100, 100, 0),
    _SliderSpec('Contrast', -100, 100, 0),
    _SliderSpec('Highlights', -100, 100, 0),
    _SliderSpec('Shadows', -100, 100, 0),
    _SliderSpec('Whites', -100, 100, 0),
    _SliderSpec('Blacks', -100, 100, 0),
  ],
  'PRESENCE': [
    _SliderSpec('Texture', -100, 100, 0),
    _SliderSpec('Clarity', -100, 100, 0),
    _SliderSpec('Dehaze', -100, 100, 0),
    _SliderSpec('Vibrance', -100, 100, 0),
    _SliderSpec('Saturation', -100, 100, 0),
  ],
};

/// Layout-only port of the Python app's main window: image viewer + toolbar
/// on the left, adjustment panel on the right, filmstrip along the bottom.
/// Nothing here is wired to real RAW decoding or image processing yet.
class EditorScreen extends StatelessWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const _TopMenuBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                Expanded(child: _ImageArea()),
                _ControlsPanel(),
              ],
            ),
          ),
          const _Filmstrip(),
        ],
      ),
    );
  }
}

class _TopMenuBar extends StatelessWidget {
  const _TopMenuBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: DarkmoonColors.background,
        border: Border(bottom: BorderSide(color: DarkmoonColors.divider)),
      ),
      child: Row(
        children: const [
          _MenuBarLabel('File'),
          SizedBox(width: 4),
          _MenuBarLabel('Settings...'),
        ],
      ),
    );
  }
}

class _MenuBarLabel extends StatelessWidget {
  const _MenuBarLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(text, style: const TextStyle(color: DarkmoonColors.textSecondary, fontSize: 12.5)),
    );
  }
}

class _ImageArea extends StatelessWidget {
  const _ImageArea();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            color: DarkmoonColors.canvas,
            alignment: Alignment.center,
            child: const Text(
              'Open a folder with RAW files to get started',
              style: TextStyle(color: DarkmoonColors.textMuted),
            ),
          ),
        ),
        const _ViewerToolbar(),
      ],
    );
  }
}

class _ViewerToolbar extends StatelessWidget {
  const _ViewerToolbar();

  static final _compactButtonStyle = ElevatedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    textStyle: const TextStyle(fontSize: 12),
    minimumSize: Size.zero,
  );

  static final _compactIconButtonStyle = IconButton.styleFrom(
    padding: EdgeInsets.zero,
    minimumSize: const Size(26, 26),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: DarkmoonColors.background,
      child: Row(
        children: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.remove, size: 14),
            style: _compactIconButtonStyle,
          ),
          const SizedBox(
            width: 34,
            child: Text('Fit', textAlign: TextAlign.center, style: TextStyle(color: DarkmoonColors.textSecondary, fontSize: 11.5)),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.add, size: 14),
            style: _compactIconButtonStyle,
          ),
          const SizedBox(width: 6),
          ElevatedButton(onPressed: () {}, style: _compactButtonStyle, child: const Text('Fit to window')),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () {},
            style: _compactButtonStyle,
            icon: const Icon(Icons.compare, size: 14),
            label: const Text('Before/After (\\)'),
          ),
        ],
      ),
    );
  }
}

class _ControlsPanel extends StatelessWidget {
  const _ControlsPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      color: DarkmoonColors.panel,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('Export...'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(onPressed: () {}, icon: const Icon(Icons.refresh, size: 16)),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: DarkmoonColors.canvas,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            for (final entry in _sections.entries) ...[
              const SizedBox(height: 10),
              if (entry.key != _sections.keys.first) const Divider(),
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 2),
                child: Text(entry.key, style: Theme.of(context).textTheme.labelSmall),
              ),
              for (final spec in entry.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SliderRow(
                    name: spec.name,
                    min: spec.min,
                    max: spec.max,
                    defaultValue: spec.defaultValue,
                    decimals: spec.decimals,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Filmstrip extends StatelessWidget {
  const _Filmstrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 114,
      color: DarkmoonColors.filmstrip,
      alignment: Alignment.center,
      child: const Text(
        'No folder open',
        style: TextStyle(color: DarkmoonColors.textMuted, fontSize: 11),
      ),
    );
  }
}
