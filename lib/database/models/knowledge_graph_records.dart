class KnowledgeConceptRecord {
  const KnowledgeConceptRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.masteryScore,
    required this.weaknessScore,
    required this.createdAt,
    required this.updatedAt,
    this.libraryId,
    this.documentId,
    this.summary,
    this.evidenceText,
    this.sourceType = 'generated',
    this.sourceId,
  });

  final int id;
  final int userId;
  final int? libraryId;
  final int? documentId;
  final String name;
  final String? summary;
  final String? evidenceText;
  final String sourceType;
  final int? sourceId;
  final int masteryScore;
  final int weaknessScore;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory KnowledgeConceptRecord.fromMap(Map<String, Object?> map) {
    return KnowledgeConceptRecord(
      id: _readInt(map['id']),
      userId: _readInt(map['user_id']),
      libraryId: _readNullableInt(map['library_id']),
      documentId: _readNullableInt(map['document_id']),
      name: (map['name'] as String?)?.trim() ?? '',
      summary: _readNullableString(map['summary']),
      evidenceText: _readNullableString(map['evidence_text']),
      sourceType: (map['source_type'] as String?)?.trim() ?? 'generated',
      sourceId: _readNullableInt(map['source_id']),
      masteryScore: _readInt(map['mastery_score']),
      weaknessScore: _readInt(map['weakness_score']),
      createdAt: _readDate(map['created_at']),
      updatedAt: _readDate(map['updated_at']),
    );
  }
}

class KnowledgeConceptLinkRecord {
  const KnowledgeConceptLinkRecord({
    required this.id,
    required this.userId,
    required this.fromConceptId,
    required this.toConceptId,
    required this.relationLabel,
    required this.createdAt,
    this.libraryId,
  });

  final int id;
  final int userId;
  final int? libraryId;
  final int fromConceptId;
  final int toConceptId;
  final String relationLabel;
  final DateTime createdAt;

  factory KnowledgeConceptLinkRecord.fromMap(Map<String, Object?> map) {
    return KnowledgeConceptLinkRecord(
      id: _readInt(map['id']),
      userId: _readInt(map['user_id']),
      libraryId: _readNullableInt(map['library_id']),
      fromConceptId: _readInt(map['from_concept_id']),
      toConceptId: _readInt(map['to_concept_id']),
      relationLabel: (map['relation_label'] as String?)?.trim() ?? '',
      createdAt: _readDate(map['created_at']),
    );
  }
}

class KnowledgeConceptWithDocument {
  const KnowledgeConceptWithDocument({
    required this.concept,
    required this.documentTitle,
  });

  final KnowledgeConceptRecord concept;
  final String documentTitle;
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

int? _readNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String? _readNullableString(Object? value) {
  final text = (value as String?)?.trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime _readDate(Object? value) {
  final text = (value as String?)?.trim() ?? '';
  return DateTime.tryParse(text)?.toLocal() ?? DateTime.now();
}
