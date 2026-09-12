// The Albums "Convert negative" action: the dialog, the per-file
// conversion off the UI thread, and the folder refresh so the positives
// show up next to their negatives.
//
// A `part` of editor_screen.dart: same library, same private scope, no
// public API of its own.

part of '../editor_screen.dart';

extension _NegativeConversion on _EditorScreenState {
  /// A JPEG of [file] for the dialog's preview: the preview cache's
  /// render when there is one, the library thumbnail otherwise.
  Future<Uint8List?> _negativePreviewJpegFor(RawFile file) async {
    final cached = await _previewCache?.lookup(file.path);
    if (cached != null) {
      return cached;
    }
    return _libraryThumbnail(file);
  }

  Future<void> _convertNegatives(List<RawFile> files) async {
    if (files.isEmpty) {
      return;
    }
    final result = await showAnimatedDialog<NegativeConversionResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NegativeConversionDialog(
        files: files,
        previewJpegFor: _negativePreviewJpegFor,
        convert: (file, params) =>
            compute(convertNegativeFile, (path: file.path, params: params)),
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    if (result.written.isNotEmpty) {
      // The positives are new files in the open folder: relist it so they
      // appear, selecting the first one.
      final folder = _currentFolder;
      final first = result.written.first;
      if (folder != null && p.dirname(first) == folder) {
        await _loadFolder(folder, selectPath: first);
      }
      if (!mounted) {
        return;
      }
      _notify(
        detail: l10n.negativeSavedMessage(result.written.length),
        status: l10n.negativeSavedMessage(result.written.length),
      );
    }
    for (final path in result.failed) {
      _notify(
        detail: l10n.negativeFailedMessage(p.basename(path)),
        status: l10n.negativeFailedMessage(p.basename(path)),
      );
    }
  }
}
