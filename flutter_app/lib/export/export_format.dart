/// Output formats offered by the export dialog, mirroring the Python app's
/// `ExportOptionsDialog.FORMATS`.
enum ExportFormat {
  png('PNG', 'png'),
  tiff('TIFF', 'tiff'),
  jpeg('JPEG', 'jpg');

  const ExportFormat(this.label, this.extension);

  final String label;
  final String extension;

  bool get supportsQuality => this == ExportFormat.jpeg;
}
