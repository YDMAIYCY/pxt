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
    this.recordId,
    this.pageNumber,
    this.blockStart,
  });

  final int documentId;
  final String documentTitle;
  final String sourceType;
  final String sourceLabel;
  final String title;
  final String snippet;
  final int? sourceId;
  final int? recordId;
  final int? pageNumber;
  final int? blockStart;

  String get location => pageNumber != null
      ? '第 $pageNumber 页'
      : '文本块 ${(blockStart ?? 0) ~/ 420 + 1}';
  Map<String, Object?> toJson() => {
    'documentId': documentId,
    'documentTitle': documentTitle,
    'sourceType': sourceType,
    'sourceLabel': sourceLabel,
    'sourceId': sourceId,
    'recordId': recordId,
    'pageNumber': pageNumber,
    'blockStart': blockStart,
    'title': title,
    'snippet': snippet,
  };
  factory KnowledgeContextSource.fromJson(Map<String, dynamic> json) =>
      KnowledgeContextSource(
        documentId: json['documentId'] as int,
        documentTitle: json['documentTitle'] as String,
        sourceType: json['sourceType'] as String,
        sourceLabel: json['sourceLabel'] as String,
        sourceId: json['sourceId'] as int?,
        recordId: json['recordId'] as int?,
        pageNumber: json['pageNumber'] as int?,
        blockStart: json['blockStart'] as int?,
        title: json['title'] as String,
        snippet: json['snippet'] as String,
      );

  String get citationTitle {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      return '$sourceLabel: $documentTitle';
    }
    return '$sourceLabel: $normalizedTitle';
  }
}
