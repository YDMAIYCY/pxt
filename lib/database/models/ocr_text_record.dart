import 'dart:convert';

class OcrTextRecord {
  const OcrTextRecord({
    required this.id,
    required this.documentId,
    required this.rawText,
    required this.cleanText,
    required this.language,
    required this.createdAt,
    required this.updatedAt,
    this.finalText,
    this.qualityScore,
    this.qualityLevel,
    this.qualityReasons = const <String>[],
  });

  final int id;
  final int documentId;
  final String rawText;
  final String cleanText;
  final String? finalText;
  final int? qualityScore;
  final String? qualityLevel;
  final List<String> qualityReasons;
  final String language;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get effectiveText {
    final finalValue = finalText?.trim() ?? '';
    if (finalValue.isNotEmpty) {
      return finalValue;
    }
    final cleanValue = cleanText.trim();
    if (cleanValue.isNotEmpty) {
      return cleanValue;
    }
    return rawText.trim();
  }

  bool get hasFinalText => (finalText?.trim().isNotEmpty ?? false);

  bool get isLowQuality => qualityLevel?.trim().toLowerCase() == 'low';

  bool get isUsableForAutomation =>
      effectiveText.isNotEmpty && (!isLowQuality || hasFinalText);

  factory OcrTextRecord.fromMap(Map<String, Object?> map) {
    final createdAt = (map['created_at'] as String?) ?? '';
    final updatedAt = (map['updated_at'] as String?) ?? '';
    final finalText = (map['final_text'] as String?)?.trim();
    final qualityLevel = (map['quality_level'] as String?)?.trim();

    return OcrTextRecord(
      id: map['id'] as int,
      documentId: map['document_id'] as int,
      rawText: (map['raw_text'] as String?)?.trim() ?? '',
      cleanText: (map['clean_text'] as String?)?.trim() ?? '',
      finalText: finalText == null || finalText.isEmpty ? null : finalText,
      qualityScore: _readInt(map['quality_score']),
      qualityLevel: qualityLevel == null || qualityLevel.isEmpty
          ? null
          : qualityLevel,
      qualityReasons: _readReasons(map['quality_reasons_json']),
      language: (map['language'] as String?)?.trim() ?? 'zh-CN',
      createdAt: DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now(),
      updatedAt: DateTime.tryParse(updatedAt)?.toLocal() ?? DateTime.now(),
    );
  }

  static int? _readInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString().trim());
  }

  static List<String> _readReasons(Object? value) {
    if (value == null) {
      return const <String>[];
    }
    final text = value.toString().trim();
    if (text.isEmpty) {
      return const <String>[];
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
    } on FormatException {
      return text
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    return const <String>[];
  }
}
