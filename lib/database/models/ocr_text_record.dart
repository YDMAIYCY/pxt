class OcrTextRecord {
  const OcrTextRecord({
    required this.id,
    required this.documentId,
    required this.rawText,
    required this.cleanText,
    required this.language,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int documentId;
  final String rawText;
  final String cleanText;
  final String language;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory OcrTextRecord.fromMap(Map<String, Object?> map) {
    final createdAt = (map['created_at'] as String?) ?? '';
    final updatedAt = (map['updated_at'] as String?) ?? '';

    return OcrTextRecord(
      id: map['id'] as int,
      documentId: map['document_id'] as int,
      rawText: (map['raw_text'] as String?)?.trim() ?? '',
      cleanText: (map['clean_text'] as String?)?.trim() ?? '',
      language: (map['language'] as String?)?.trim() ?? 'zh-CN',
      createdAt: DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now(),
      updatedAt: DateTime.tryParse(updatedAt)?.toLocal() ?? DateTime.now(),
    );
  }
}
