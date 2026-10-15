/// IDs come from business pages or persisted session state, never page titles.
class EClawContext {
  const EClawContext({
    this.knowledgeBaseId,
    this.importRecordId,
    this.documentId,
    this.interviewSessionId,
  });
  final int? knowledgeBaseId;
  final int? importRecordId;
  final int? documentId;
  final int? interviewSessionId;
  Map<String, Object?> toJson() => {
    'knowledgeBaseId': knowledgeBaseId,
    'importRecordId': importRecordId,
    'documentId': documentId,
    'interviewSessionId': interviewSessionId,
  };
  factory EClawContext.fromJson(Map<String, dynamic> json) => EClawContext(
    knowledgeBaseId: json['knowledgeBaseId'] as int?,
    importRecordId: json['importRecordId'] as int?,
    documentId: json['documentId'] as int?,
    interviewSessionId: json['interviewSessionId'] as int?,
  );
}
