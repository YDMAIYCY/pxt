class OcrTextCleaner {
  const OcrTextCleaner._();

  static String clean(String source) {
    final normalized = source
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u3000', ' ')
        .replaceAll('\t', ' ');

    final compacted = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');

    return compacted.replaceAll(RegExp(r'[ ]{2,}'), ' ').trim();
  }
}
