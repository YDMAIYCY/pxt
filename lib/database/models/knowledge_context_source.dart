class KnowledgeContextSourceType {
  const KnowledgeContextSourceType._();

  static const String ocrText = 'ocr_text';
  static const String knowledgeCard = 'knowledge_card';
  static const String reviewOutline = 'review_outline';
  static const String practiceQuestion = 'practice_question';
  static const String knowledgeGraph = 'knowledge_graph';
}

class KnowledgeContextSource {
  const KnowledgeContextSource({
    required this.documentId,
    required this.documentTitle,
    required this.sourceType,
    required this.sourceLabel,
    required this.title,
    required this.snippet,
    this.sourceId,
  });

  final int documentId;
  final String documentTitle;
  final String sourceType;
  final String sourceLabel;
  final String title;
  final String snippet;
  final int? sourceId;

  String get citationTitle {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      return '$sourceLabel: $documentTitle';
    }
    return '$sourceLabel: $normalizedTitle';
  }
}
