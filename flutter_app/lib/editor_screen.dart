import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'raw_files.dart';
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

/// Main window: image viewer + toolbar, adjustment panel, and a filmstrip
/// that now lists real RAW files from a chosen folder. Selecting a file only
/// updates the placeholder text for now — RAW decoding isn't wired up yet.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  List<RawFile> _files = const [];
  int? _selectedIndex;
  bool _loading = false;

  Future<void> _openFolder() async {
    final folder = await FilePicker.getDirectoryPath(dialogTitle: 'Open Folder');
    if (folder == null) {
      return;
    }
    await _loadFolder(folder);
  }

  Future<void> _openFile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open RAW File',
      type: FileType.custom,
      allowedExtensions: rawExtensions.map((ext) => ext.substring(1)).toList(),
    );
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    await _loadFolder(p.dirname(path), selectPath: path);
  }

  Future<void> _loadFolder(String folder, {String? selectPath}) async {
    setState(() => _loading = true);
    final files = await listRawFiles(folder);
    if (!mounted) {
      return;
    }
    final index = selectPath == null ? 0 : files.indexWhere((f) => f.path == selectPath);
    setState(() {
      _files = files;
      _selectedIndex = files.isEmpty ? null : (index < 0 ? 0 : index);
      _loading = false;
    });
  }

  void _selectIndex(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex != null ? _files[_selectedIndex!] : null;
    return Scaffold(
      body: Column(
        children: [
          _TopMenuBar(onOpenFile: _openFile, onOpenFolder: _openFolder),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _ImageArea(selected: selected, loading: _loading)),
                const _ControlsPanel(),
              ],
            ),
          ),
          _Filmstrip(files: _files, selectedIndex: _selectedIndex, onSelect: _selectIndex),
        ],
      ),
    );
  }
}

class _TopMenuBar extends StatelessWidget {
  const _TopMenuBar({required this.onOpenFile, required this.onOpenFolder});

  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;

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
        children: [
          PopupMenuButton<VoidCallback>(
            tooltip: '',
            color: DarkmoonColors.surfaceRaised,
            offset: const Offset(0, 26),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: DarkmoonColors.border),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(value: onOpenFile, child: const Text('Open File...')),
              PopupMenuItem(value: onOpenFolder, child: const Text('Open Folder...')),
            ],
            onSelected: (callback) => callback(),
            child: const _MenuBarLabel('File'),
          ),
          const SizedBox(width: 4),
          const _MenuBarLabel('Settings...'),
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
  const _ImageArea({required this.selected, required this.loading});

  final RawFile? selected;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final String message;
    if (loading) {
      message = 'Loading folder...';
    } else if (selected != null) {
      message = '${selected!.name}\n(preview not implemented yet)';
    } else {
      message = 'Open a folder with RAW files to get started';
    }
    return Column(
      children: [
        Expanded(
          child: Container(
            color: DarkmoonColors.canvas,
            alignment: Alignment.center,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: DarkmoonColors.textMuted),
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
  const _Filmstrip({required this.files, required this.selectedIndex, required this.onSelect});

  final List<RawFile> files;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
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
    return Container(
      height: 114,
      color: DarkmoonColors.filmstrip,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          final isSelected = index == selectedIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => onSelect(index),
              child: Container(
                width: 104,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isSelected ? DarkmoonColors.accent.withValues(alpha: 0.28) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF26262A),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_outlined, color: DarkmoonColors.textMuted, size: 22),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: DarkmoonColors.textSecondary, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
