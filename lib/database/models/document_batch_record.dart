import 'source_document_record.dart';

// ========== 学习包类型 ==========
// 描述多页资料的来源，学习包下的每一页仍会落到 source_documents。

class DocumentBatchSourceType {
  const DocumentBatchSourceType._();

  static const String multiImage = 'multi_image';
  static const String pdf = 'pdf';

  static String labelOf(String value) {
    switch (value) {
      case multiImage:
        return '\u591a\u56fe\u5bfc\u5165';
      case pdf:
        return 'PDF \u5bfc\u5165';
      default:
        return '\u5b66\u4e60\u5305';
    }
  }
}

// ========== 学习包模型 ==========
// 承载多图/PDF 导入后形成的多页资料分组。

class DocumentBatchRecord {
  const DocumentBatchRecord({
    required this.id,
    required this.userId,
    required this.sourceType,
    required this.title,
    required this.pageCount,
    required this.createdAt,
    required this.updatedAt,
    this.libraryId,
    this.originalFilePath,
  });

  final int id;
  final int userId;
  final int? libraryId;
  final String sourceType;
  final String title;
  final String? originalFilePath;
  final int pageCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get sourceTypeLabel => DocumentBatchSourceType.labelOf(sourceType);

  String get createdAtLabel {
    final localTime = createdAt;
    final month = localTime.month.toString().padLeft(2, '0');
    final day = localTime.day.toString().padLeft(2, '0');
    final hour = localTime.hour.toString().padLeft(2, '0');
    final minute = localTime.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  factory DocumentBatchRecord.fromMap(Map<String, Object?> map) {
    final rawCreatedAt = (map['created_at'] as String?)?.trim() ?? '';
    final rawUpdatedAt = (map['updated_at'] as String?)?.trim() ?? '';

    return DocumentBatchRecord(
      id: map['id'] as int,
      userId: map['user_id'] as int,
      libraryId: map['library_id'] as int?,
      sourceType: (map['source_type'] as String?)?.trim() ?? '',
      title: ((map['title'] as String?)?.trim().isNotEmpty ?? false)
          ? (map['title'] as String).trim()
          : '未命名学习包',
      originalFilePath: (map['original_file_path'] as String?)?.trim(),
      pageCount: _readInt(map['page_count']),
      createdAt: DateTime.tryParse(rawCreatedAt)?.toLocal() ?? DateTime.now(),
      updatedAt: DateTime.tryParse(rawUpdatedAt)?.toLocal() ?? DateTime.now(),
    );
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}

class DocumentBatchWithPages {
  const DocumentBatchWithPages({required this.batch, required this.pages});

  final DocumentBatchRecord batch;
  final List<SourceDocumentRecord> pages;
}

class DocumentBatchPageDraft {
  const DocumentBatchPageDraft({
    required this.savedPath,
    required this.title,
    required this.pageNumber,
  });

  final String savedPath;
  final String title;
  final int pageNumber;
}
