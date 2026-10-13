import 'source_document_record.dart';

class ImportRecord {
  const ImportRecord({
    required this.id,
    required this.userId,
    required this.title,
    required this.createdAt,
    required this.sources,
    required this.counts,
    this.libraryId,
    this.tags = const [],
    this.needsLibraryReview = false,
    this.runningTasks = 0,
    this.failedTasks = 0,
    this.errors = const [],
  });
  final int id, userId;
  final int? libraryId;
  final String title;
  final DateTime createdAt;
  final List<SourceDocumentRecord> sources;
  final Map<String, int> counts;
  final List<String> tags, errors;
  final bool needsLibraryReview;
  final int runningTasks, failedTasks;
  List<SourceDocumentRecord> get pages =>
      sources.where((s) => s.sourceType != 'pdf_document').toList();
  SourceDocumentRecord get anchor => sources.firstWhere(
    (s) => s.sourceType == 'pdf_document',
    orElse: () => sources.first,
  );
  bool get isPdf => sources.any(
    (s) => s.sourceType == 'pdf_document' || s.sourceType == 'pdf_page',
  );
  bool get isCamera => sources.any((s) => s.sourceType == 'camera_capture');
  String get sourceLabel => isPdf
      ? 'PDF 导入'
      : isCamera
      ? '拍照导入'
      : '图片导入';
  String get pageLabel => '${pages.length} ${isPdf ? '页' : '张'}';
  int get resourceCount => counts.values.fold(0, (a, b) => a + b);
  String get statusLabel {
    if (runningTasks > 0) return 'AI 生成中';
    if (pages.any((s) => s.ocrStatus == 'processing')) return 'OCR 处理中';
    if (failedTasks > 0 || pages.any((s) => s.ocrFailed)) {
      return resourceCount > 0 || pages.any((s) => s.ocrDone) ? '部分完成' : '处理失败';
    }
    if (pages.any((s) => s.ocrStatus == 'needs_review')) return '待校对';
    if (pages.isEmpty || pages.any((s) => !s.ocrDone)) return '待 OCR 识别';
    return [
          'knowledge_cards',
          'review_outlines',
          'mindmap_texts',
          'practice_questions',
        ].every((k) => (counts[k] ?? 0) > 0)
        ? '已完成'
        : '部分完成';
  }
}
