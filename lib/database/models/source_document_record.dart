// ========== 资料来源常量 ==========
// 统一约束原始资料在数据库中的来源类型，避免页面层直接写字符串。

class SourceDocumentSourceType {
  const SourceDocumentSourceType._();

  static const String cameraCapture = 'camera_capture';
  static const String galleryImport = 'gallery_import';
  static const String pdfPage = 'pdf_page';
}

class SourceDocumentOcrStatus {
  const SourceDocumentOcrStatus._();

  static const String pending = 'pending';
  static const String processing = 'processing';
  static const String needsReview = 'needs_review';
  static const String success = 'success';
  static const String failed = 'failed';

  static String normalize(String? status, {bool fallbackDone = false}) {
    final raw = (status ?? '').trim().toLowerCase();
    switch (raw) {
      case pending:
      case processing:
      case needsReview:
      case success:
      case failed:
        return raw;
      default:
        return fallbackDone ? success : pending;
    }
  }
}

// ========== 原始资料模型 ==========
// 承载首页最近记录和资料详情页所需的原始资料信息。

class SourceDocumentRecord {
  const SourceDocumentRecord({
    required this.id,
    required this.userId,
    required this.sourceType,
    required this.imagePath,
    required this.title,
    required this.createdAt,
    required this.ocrStatus,
    required this.aiDone,
    this.libraryId,
    this.batchId,
    this.pageNumber,
    this.ocrErrorMessage,
    this.ocrUpdatedAt,
  });

  final int id;
  final int userId;
  final int? libraryId;
  final int? batchId;
  final int? pageNumber;
  final String sourceType;
  final String imagePath;
  final String title;
  final DateTime createdAt;
  final String ocrStatus;
  final bool aiDone;
  final String? ocrErrorMessage;
  final DateTime? ocrUpdatedAt;

  bool get ocrDone => ocrStatus == SourceDocumentOcrStatus.success;

  bool get ocrFailed => ocrStatus == SourceDocumentOcrStatus.failed;

  String get ocrStatusLabel {
    switch (ocrStatus) {
      case SourceDocumentOcrStatus.pending:
        return '\u5f85\u8bc6\u522b';
      case SourceDocumentOcrStatus.processing:
        return '\u8bc6\u522b\u4e2d';
      case SourceDocumentOcrStatus.needsReview:
        return '\u5f85\u6821\u5bf9';
      case SourceDocumentOcrStatus.success:
        return '\u8bc6\u522b\u6210\u529f';
      case SourceDocumentOcrStatus.failed:
        return '\u8bc6\u522b\u5931\u8d25';
      default:
        return '\u5f85\u8bc6\u522b';
    }
  }

  String get sourceTypeLabel {
    switch (sourceType) {
      case SourceDocumentSourceType.cameraCapture:
        return '\u62cd\u7167';
      case SourceDocumentSourceType.galleryImport:
        return '\u76f8\u518c';
      case SourceDocumentSourceType.pdfPage:
        return 'PDF';
      default:
        return '\u8d44\u6599';
    }
  }

  String get createdAtLabel {
    final localTime = createdAt;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final targetDay = DateTime(localTime.year, localTime.month, localTime.day);

    if (targetDay == today) {
      return '今天 ${_twoDigits(localTime.hour)}:${_twoDigits(localTime.minute)}';
    }
    if (targetDay == yesterday) {
      return '昨天 ${_twoDigits(localTime.hour)}:${_twoDigits(localTime.minute)}';
    }

    return '${localTime.year}-${_twoDigits(localTime.month)}-${_twoDigits(localTime.day)} '
        '${_twoDigits(localTime.hour)}:${_twoDigits(localTime.minute)}';
  }

  factory SourceDocumentRecord.fromMap(Map<String, Object?> map) {
    final rawCreatedAt = (map['created_at'] as String?)?.trim() ?? '';
    final ocrDoneFallback = _readBool(map['ocr_done']);
    final rawOcrUpdatedAt = (map['ocr_updated_at'] as String?)?.trim() ?? '';

    return SourceDocumentRecord(
      id: map['id'] as int,
      userId: map['user_id'] as int,
      libraryId: map['library_id'] as int?,
      batchId: map['batch_id'] as int?,
      pageNumber: map['page_number'] as int?,
      sourceType: (map['source_type'] as String?)?.trim() ?? '',
      imagePath: (map['image_path'] as String?)?.trim() ?? '',
      title: ((map['original_title'] as String?)?.trim().isNotEmpty ?? false)
          ? (map['original_title'] as String).trim()
          : '未命名资料',
      createdAt: DateTime.tryParse(rawCreatedAt)?.toLocal() ?? DateTime.now(),
      ocrStatus: SourceDocumentOcrStatus.normalize(
        map['ocr_status'] as String?,
        fallbackDone: ocrDoneFallback,
      ),
      aiDone: _readBool(map['ai_done']),
      ocrErrorMessage: (map['ocr_error_message'] as String?)?.trim(),
      ocrUpdatedAt: rawOcrUpdatedAt.isEmpty
          ? null
          : DateTime.tryParse(rawOcrUpdatedAt)?.toLocal(),
    );
  }

  static bool _readBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is int) {
      return value == 1;
    }
    if (value is num) {
      return value == 1;
    }
    if (value is String) {
      return value == '1' || value.toLowerCase() == 'true';
    }

    return false;
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
