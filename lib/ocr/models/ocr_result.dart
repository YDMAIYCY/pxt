class OcrResult {
  const OcrResult({
    required this.rawText,
    required this.cleanText,
    required this.language,
  });

  final String rawText;
  final String cleanText;
  final String language;

  bool get isEmpty => rawText.trim().isEmpty && cleanText.trim().isEmpty;
}
