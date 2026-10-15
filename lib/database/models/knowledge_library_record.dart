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
    this.coverTheme = 'math',
    this.coverColor = 0xFF5B90FF,
    this.sourceType = 'local',
    this.syncStatus = 'pending',
    this.syncedAt,
  });

  final int id;
  final int userId;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int documentCount;
  final String coverTheme;
  final int coverColor;
  final String sourceType, syncStatus;
  final String? syncedAt;
  bool get isFeishu => sourceType != 'local';
  String get sourceLabel =>
      {'folder': '飞书文件夹', 'wiki': '飞书知识空间', 'document': '飞书云文档'}[sourceType] ??
      '本地创建';
  String get syncLabel =>
      {
        'synced': '已同步',
        'syncing': '同步中',
        'pending': '待同步',
        'failed': '同步失败',
        'expired': '授权已失效',
      }[syncStatus] ??
      '待同步';

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
      coverTheme: map['cover_theme'] as String? ?? 'math',
      coverColor: map['cover_color'] as int? ?? 0xFF5B90FF,
      sourceType: map['source_type'] as String? ?? 'local',
      syncStatus: map['sync_status'] as String? ?? 'pending',
      syncedAt: map['synced_at'] as String?,
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
