// The Albums "Frame image" action (2026-09-13): the dialog, the save of
// each photo through the export pipeline with the frame composed in,
// and the folder refresh so the framed files show up beside their
// originals. Solstice's Albums action, moved here from the export dialog
// at the user's request.
//
// A `part` of editor_screen.dart: same library, same private scope, no
// public API of its own.

part of '../editor_screen.dart';

extension _EditorFrame on _EditorScreenState {
  /// A JPEG of [file] for the dialog's preview: the preview cache's
  /// render (the edited photo) when there is one, the library thumbnail
  /// otherwise.
  Future<Uint8List?> _framePreviewJpegFor(RawFile file) async {
    final cached = await _previewCache?.lookup(file.path);
    if (cached != null) {
      return cached;
    }
    return _libraryThumbnail(file);
  }

  Future<void> _frameImages(List<RawFile> files) async {
    if (files.isEmpty || _exporting) {
      return;
    }
    final result = await showAnimatedDialog<FrameImageResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FrameImageDialog(
        files: files,
        previewJpegFor: _framePreviewJpegFor,
        save: _saveFramed,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    if (result.written.isNotEmpty) {
      // The framed files are new files in the open folder: relist it so
      // they appear, selecting the first one.
      final folder = _currentFolder;
      final first = result.written.first;
      if (folder != null && p.dirname(first) == folder) {
        await _loadFolder(folder, selectPath: first);
      }
      if (!mounted) {
        return;
      }
      _notify(
        detail: l10n.frameSavedMessage(result.written.length),
        status: l10n.frameSavedMessage(result.written.length),
      );
    }
    for (final path in result.failed) {
      _notify(
        detail: l10n.frameFailedMessage(p.basename(path)),
        status: l10n.frameFailedMessage(p.basename(path)),
      );
    }
  }

  /// Saves [file] framed as `<name>_Framed.<ext>` beside it. The export
  /// renders the editor's live state, so the photo is selected first
  /// (its saved edits load with it) and its sources awaited; every AI
  /// stage the photo uses rides along exactly as in a normal export.
  /// Returns the path written; throws when the photo is not in the open
  /// folder, cannot be decoded, or the export fails.
  Future<String> _saveFramed(RawFile file, FrameImageChoice choice) async {
    final index = _files.indexWhere((f) => f.path == file.path);
    if (index < 0) {
      throw StateError('${p.basename(file.path)} is not in the open folder');
    }
    if (_selectedIndex != index) {
      _selectIndex(index);
    }
    await _awaitEditSources(file.path);
    if (!mounted) {
      throw StateError('editor closed');
    }
    if (_editSources[file.path] == null) {
      throw StateError('${p.basename(file.path)} could not be decoded');
    }
    final dest = framedPathFor(file.path, choice.format.extension);
    final result = await _exportSelected(
      file,
      dest,
      ExportOptions(format: choice.format, quality: 95, frame: choice.frame),
      longEdge: choice.longEdge,
    );
    if (result == null) {
      throw StateError('export cancelled');
    }
    if (!result.success) {
      throw StateError(result.error ?? 'export failed');
    }
    return result.destPath!;
  }

  /// Waits for [path]'s edit sources (its decode was started by
  /// [_selectIndex]) — until they land, the file is flagged missing, or
  /// a generous deadline passes.
  Future<void> _awaitEditSources(String path) async {
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (mounted &&
        _editSources[path] == null &&
        !_missingFiles.contains(path) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
