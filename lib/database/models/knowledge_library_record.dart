// ========== 知识库模型 ==========
// 承载用户自定义知识库和其资料数量，用于导入选择与知识库页筛选。

class KnowledgeLibraryRecord {
  const KnowledgeLibraryRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.documentCount = 0,
  });

  final int id;
  final int userId;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int documentCount;

  factory KnowledgeLibraryRecord.fromMap(Map<String, Object?> map) {
    final createdAt = (map['created_at'] as String?) ?? '';
    final updatedAt = (map['updated_at'] as String?) ?? '';

    return KnowledgeLibraryRecord(
      id: map['id'] as int,
      userId: map['user_id'] as int,
      name: (map['name'] as String?)?.trim() ?? '未命名知识库',
      description: (map['description'] as String?)?.trim(),
      createdAt: DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now(),
      updatedAt: DateTime.tryParse(updatedAt)?.toLocal() ?? DateTime.now(),
      documentCount: _readInt(map['document_count']),
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
