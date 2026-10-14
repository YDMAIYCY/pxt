// ========== 跨知识库动态知识图谱 · 数据模型 ==========
// 承载规范化知识实体、语义关系、来源映射与构建任务。
// 与旧的 per-document knowledge_concepts 分离：这里是可跨库复用的规范实体层。

import 'dart:convert';

/// 实体状态：正常、待确认（低置信度自动合并）、已归档（来源全部失效）。
class GraphNodeStatus {
  const GraphNodeStatus._();

  static const String active = 'active';
  static const String pendingReview = 'pending_review';
  static const String archived = 'archived';

  static String normalize(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case pendingReview:
        return pendingReview;
      case archived:
        return archived;
      default:
        return active;
    }
  }
}

/// 关系审核状态：自动生成、用户确认、用户否决。
class GraphEdgeReviewStatus {
  const GraphEdgeReviewStatus._();

  static const String auto = 'auto';
  static const String confirmed = 'confirmed';
  static const String rejected = 'rejected';

  static String normalize(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case confirmed:
        return confirmed;
      case rejected:
        return rejected;
      default:
        return auto;
    }
  }
}

/// 关系来源：文档抽取 / 跨库发现 / 人工添加。
class GraphEdgeOrigin {
  const GraphEdgeOrigin._();

  static const String document = 'document';
  static const String crossLibrary = 'cross_library';
  static const String manual = 'manual';

  static String normalize(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case crossLibrary:
        return crossLibrary;
      case manual:
        return manual;
      default:
        return document;
    }
  }
}

/// 构建任务状态。
class GraphBuildStatus {
  const GraphBuildStatus._();

  static const String pending = 'pending';
  static const String running = 'running';
  static const String success = 'success';
  static const String failed = 'failed';
  static const String cancelled = 'cancelled';

  static bool isTerminal(String status) =>
      status == success || status == failed || status == cancelled;
}

/// 构建范围。
class GraphBuildScope {
  const GraphBuildScope._();

  static const String library = 'library';
  static const String document = 'document';
  static const String record = 'record';
  static const String crossLibrary = 'cross_library';
}

// ========== 规范知识实体 ==========

class GraphNodeRecord {
  const GraphNodeRecord({
    required this.id,
    required this.userId,
    required this.canonicalKey,
    required this.canonicalName,
    required this.displayName,
    required this.entityType,
    required this.aliases,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.mergedIntoNodeId,
  });

  final int id;
  final int userId;

  /// 稳定去重键：`规范化名称|实体类型`。同一用户下唯一。
  final String canonicalKey;

  /// 规范化后的名称（用于展示回退与匹配）。
  final String canonicalName;

  /// 原始书写名称。
  final String displayName;

  final String entityType;
  final String? description;
  final List<String> aliases;
  final String status;
  final int? mergedIntoNodeId;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory GraphNodeRecord.fromMap(Map<String, Object?> map) {
    return GraphNodeRecord(
      id: _readInt(map['id']),
      userId: _readInt(map['user_id']),
      canonicalKey: (map['canonical_key'] as String?)?.trim() ?? '',
      canonicalName: (map['canonical_name'] as String?)?.trim() ?? '',
      displayName: (map['display_name'] as String?)?.trim() ?? '',
      entityType: (map['entity_type'] as String?)?.trim() ?? '概念',
      description: _readNullableString(map['description']),
      aliases: decodeStringList(map['aliases_json']),
      status: GraphNodeStatus.normalize(map['status'] as String?),
      mergedIntoNodeId: _readNullableInt(map['merged_into_node_id']),
      createdAt: _readDate(map['created_at']),
      updatedAt: _readDate(map['updated_at']),
    );
  }
}

// ========== 知识关系 ==========

class GraphEdgeRecord {
  const GraphEdgeRecord({
    required this.id,
    required this.userId,
    required this.sourceNodeId,
    required this.targetNodeId,
    required this.relationType,
    required this.directed,
    required this.confidence,
    required this.reviewStatus,
    required this.origin,
    required this.createdAt,
    required this.updatedAt,
    this.description,
  });

  final int id;
  final int userId;
  final int sourceNodeId;
  final int targetNodeId;
  final String relationType;
  final bool directed;
  final double confidence;
  final String reviewStatus;
  final String origin;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory GraphEdgeRecord.fromMap(Map<String, Object?> map) {
    return GraphEdgeRecord(
      id: _readInt(map['id']),
      userId: _readInt(map['user_id']),
      sourceNodeId: _readInt(map['source_node_id']),
      targetNodeId: _readInt(map['target_node_id']),
      relationType: (map['relation_type'] as String?)?.trim() ?? '相关',
      directed: _readBool(map['directed'], fallback: true),
      confidence: _readDouble(map['confidence'], fallback: 0.6),
      reviewStatus: GraphEdgeReviewStatus.normalize(
        map['review_status'] as String?,
      ),
      origin: GraphEdgeOrigin.normalize(map['origin'] as String?),
      description: _readNullableString(map['description']),
      createdAt: _readDate(map['created_at']),
      updatedAt: _readDate(map['updated_at']),
    );
  }
}

// ========== 实体来源映射 ==========

class GraphNodeSourceRecord {
  const GraphNodeSourceRecord({
    required this.id,
    required this.nodeId,
    required this.userId,
    required this.createdAt,
    this.knowledgeBaseId,
    this.importRecordId,
    this.sourceDocumentId,
    this.sourcePageId,
    this.sourceTextRange,
    this.evidenceText,
  });

  final int id;
  final int nodeId;
  final int userId;
  final int? knowledgeBaseId;
  final int? importRecordId;
  final int? sourceDocumentId;
  final int? sourcePageId;
  final String? sourceTextRange;
  final String? evidenceText;
  final DateTime createdAt;

  factory GraphNodeSourceRecord.fromMap(Map<String, Object?> map) {
    return GraphNodeSourceRecord(
      id: _readInt(map['id']),
      nodeId: _readInt(map['node_id']),
      userId: _readInt(map['user_id']),
      knowledgeBaseId: _readNullableInt(map['knowledge_base_id']),
      importRecordId: _readNullableInt(map['import_record_id']),
      sourceDocumentId: _readNullableInt(map['source_document_id']),
      sourcePageId: _readNullableInt(map['source_page_id']),
      sourceTextRange: _readNullableString(map['source_text_range']),
      evidenceText: _readNullableString(map['evidence_text']),
      createdAt: _readDate(map['created_at']),
    );
  }
}

// ========== 关系证据 ==========

class GraphEdgeEvidenceRecord {
  const GraphEdgeEvidenceRecord({
    required this.id,
    required this.edgeId,
    required this.userId,
    required this.confidence,
    required this.createdAt,
    this.knowledgeBaseId,
    this.importRecordId,
    this.sourceDocumentId,
    this.sourcePageId,
    this.evidenceText,
  });

  final int id;
  final int edgeId;
  final int userId;
  final int? knowledgeBaseId;
  final int? importRecordId;
  final int? sourceDocumentId;
  final int? sourcePageId;
  final String? evidenceText;
  final double confidence;
  final DateTime createdAt;

  factory GraphEdgeEvidenceRecord.fromMap(Map<String, Object?> map) {
    return GraphEdgeEvidenceRecord(
      id: _readInt(map['id']),
      edgeId: _readInt(map['edge_id']),
      userId: _readInt(map['user_id']),
      knowledgeBaseId: _readNullableInt(map['knowledge_base_id']),
      importRecordId: _readNullableInt(map['import_record_id']),
      sourceDocumentId: _readNullableInt(map['source_document_id']),
      sourcePageId: _readNullableInt(map['source_page_id']),
      evidenceText: _readNullableString(map['evidence_text']),
      confidence: _readDouble(map['confidence'], fallback: 0.6),
      createdAt: _readDate(map['created_at']),
    );
  }
}

// ========== 图谱构建任务 ==========

class GraphBuildJobRecord {
  const GraphBuildJobRecord({
    required this.id,
    required this.userId,
    required this.scope,
    required this.status,
    required this.progress,
    required this.totalUnits,
    required this.doneUnits,
    required this.createdAt,
    required this.updatedAt,
    this.scopeId,
    this.sourceVersion,
    this.modelVersion,
    this.errorMessage,
    this.completedAt,
  });

  final int id;
  final int userId;
  final String scope;
  final int? scopeId;
  final String status;
  final int progress;
  final int totalUnits;
  final int doneUnits;
  final String? sourceVersion;
  final String? modelVersion;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  bool get isTerminal => GraphBuildStatus.isTerminal(status);

  factory GraphBuildJobRecord.fromMap(Map<String, Object?> map) {
    return GraphBuildJobRecord(
      id: _readInt(map['id']),
      userId: _readInt(map['user_id']),
      scope: (map['scope'] as String?)?.trim() ?? GraphBuildScope.library,
      scopeId: _readNullableInt(map['scope_id']),
      status: (map['status'] as String?)?.trim() ?? GraphBuildStatus.pending,
      progress: _readInt(map['progress']),
      totalUnits: _readInt(map['total_units']),
      doneUnits: _readInt(map['done_units']),
      sourceVersion: _readNullableString(map['source_version']),
      modelVersion: _readNullableString(map['model_version']),
      errorMessage: _readNullableString(map['error_message']),
      createdAt: _readDate(map['created_at']),
      updatedAt: _readDate(map['updated_at']),
      completedAt: _readNullableDate(map['completed_at']),
    );
  }
}

// ========== 画布视图模型（只读，供渲染层使用） ==========

/// 画布上的一个节点：规范实体 + 它的来源知识库集合。
class GraphViewNode {
  const GraphViewNode({
    required this.id,
    required this.label,
    required this.entityType,
    required this.description,
    required this.libraryIds,
    required this.status,
    required this.degree,
    required this.aliases,
    this.primaryLibraryId,
  });

  final int id;
  final String label;
  final String entityType;
  final String? description;

  /// 该实体来源覆盖到的知识库集合（可能多本）。
  final List<int> libraryIds;
  final int? primaryLibraryId;
  final String status;

  /// 当前可见子图中的连接数，用于节点尺寸。
  final int degree;
  final List<String> aliases;

  bool get isShared => libraryIds.length > 1;
}

/// 画布上的一条边。
class GraphViewEdge {
  const GraphViewEdge({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.relationType,
    required this.directed,
    required this.confidence,
    required this.isCrossLibrary,
    this.description,
  });

  final int id;
  final int sourceId;
  final int targetId;
  final String relationType;
  final bool directed;
  final double confidence;
  final bool isCrossLibrary;
  final String? description;
}

/// 一次查询得到的完整可见子图。
class GraphViewData {
  const GraphViewData({
    required this.nodes,
    required this.edges,
    required this.libraryIds,
    required this.totalNodeCount,
  });

  const GraphViewData.empty()
    : nodes = const <GraphViewNode>[],
      edges = const <GraphViewEdge>[],
      libraryIds = const <int>[],
      totalNodeCount = 0;

  final List<GraphViewNode> nodes;
  final List<GraphViewEdge> edges;
  final List<int> libraryIds;
  final int totalNodeCount;

  bool get isEmpty => nodes.isEmpty;
}

// ========== 节点详情（含来源与邻居） ==========

class GraphNodeSourceView {
  const GraphNodeSourceView({
    required this.source,
    required this.libraryName,
    required this.recordTitle,
    required this.documentTitle,
  });

  final GraphNodeSourceRecord source;
  final String libraryName;
  final String recordTitle;
  final String documentTitle;
}

class GraphNodeNeighborView {
  const GraphNodeNeighborView({
    required this.node,
    required this.edge,
    required this.isOutgoing,
  });

  final GraphNodeRecord node;
  final GraphEdgeRecord edge;
  final bool isOutgoing;
}

class GraphNodeDetail {
  const GraphNodeDetail({
    required this.node,
    required this.sources,
    required this.neighbors,
    required this.libraryNames,
  });

  final GraphNodeRecord node;
  final List<GraphNodeSourceView> sources;
  final List<GraphNodeNeighborView> neighbors;
  final List<String> libraryNames;
}

// ========== JSON 列表编解码 ==========

List<String> decodeStringList(Object? value) {
  if (value is List) {
    return value
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  final text = (value as String?)?.trim() ?? '';
  if (text.isEmpty) return const <String>[];
  try {
    final decoded = jsonDecode(text);
    if (decoded is List) {
      return decoded
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
  } catch (_) {
    // 忽略损坏的 JSON，回退为空别名列表。
  }
  return const <String>[];
}

String encodeStringList(List<String> values) => jsonEncode(
  values
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false),
);

// ========== 读取辅助 ==========

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

double _readDouble(Object? value, {required double fallback}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

bool _readBool(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final text = value.trim().toLowerCase();
    if (text == '1' || text == 'true') return true;
    if (text == '0' || text == 'false') return false;
  }
  return fallback;
}

String? _readNullableString(Object? value) {
  final text = (value as String?)?.trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime _readDate(Object? value) {
  final text = (value as String?)?.trim() ?? '';
  return DateTime.tryParse(text)?.toLocal() ?? DateTime.now();
}

DateTime? _readNullableDate(Object? value) {
  final text = (value as String?)?.trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}
