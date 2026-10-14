import 'dart:async';
import 'dart:convert';

import '../database/ai_generation_repository.dart';
import '../database/app_database.dart';
import '../database/graph_repository.dart';
import '../database/models/graph_records.dart';
import '../database/models/llm_provider_config.dart';
import '../database/ocr_text_repository.dart';
import '../graph/graph_vocabulary.dart';
import '../llm/minimax_client.dart';

// ========== 知识图谱构建服务 ==========
// 从已有的原始资料 / OCR 文本 / AI 成果中抽取规范知识实体与关系。
// 只复用项目现有的大模型配置，不引入额外模型系统。
// 所有模型输出必须经过 Schema 校验、字段校验与关系端点检查后才能落库。

/// 一次构建的可观测进度。
class GraphBuildProgress {
  const GraphBuildProgress({
    required this.doneUnits,
    required this.totalUnits,
    required this.message,
  });

  final int doneUnits;
  final int totalUnits;
  final String message;

  double get ratio => totalUnits <= 0 ? 0 : doneUnits / totalUnits;
}

class GraphBuildOutcome {
  const GraphBuildOutcome({
    required this.processedDocuments,
    required this.skippedDocuments,
    required this.createdNodeCount,
    required this.createdEdgeCount,
    required this.failures,
    this.reusedDocuments = 0,
    this.cancelled = false,
  });

  final int processedDocuments;
  final int skippedDocuments;
  final int createdNodeCount;
  final int createdEdgeCount;
  final List<String> failures;

  /// 复用既有知识点、没有再次调用模型的资料数。
  final int reusedDocuments;
  final bool cancelled;

  bool get hasFailures => failures.isNotEmpty;

  String get summary {
    if (processedDocuments == 0 && reusedDocuments == 0 && failures.isNotEmpty) {
      return '构建失败：${failures.first}';
    }
    final parts = <String>[
      if (reusedDocuments > 0) '复用 $reusedDocuments 份资料的既有知识点',
      if (processedDocuments > 0) '模型抽取 $processedDocuments 份资料',
      if (skippedDocuments > 0) '跳过 $skippedDocuments 份',
      '新增 $createdNodeCount 个知识点',
      '新增 $createdEdgeCount 条关系',
    ];
    return parts.isEmpty ? '没有需要处理的资料' : parts.join('，');
  }
}

class CrossLibraryOutcome {
  const CrossLibraryOutcome({
    required this.createdEdgeCount,
    required this.candidateCount,
    required this.failures,
  });

  final int createdEdgeCount;
  final int candidateCount;
  final List<String> failures;

  bool get hasFailures => failures.isNotEmpty;
}

/// 一次构建任务的取消令牌。UI 退出或用户取消时触发。
class GraphBuildCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// 单个资料页的可抽取文本包。
class GraphSourceBundle {
  const GraphSourceBundle({
    required this.documentId,
    required this.title,
    required this.text,
    required this.hasUsableText,
    this.libraryId,
    this.importRecordId,
  });

  final int documentId;
  final int? libraryId;
  final int? importRecordId;
  final String title;
  final String text;
  final bool hasUsableText;
}

class KnowledgeGraphBuilder {
  KnowledgeGraphBuilder({
    MiniMaxClient? miniMaxClient,
    GraphRepository? graphRepository,
    OcrTextRepository? ocrTextRepository,
    AiGenerationRepository? aiGenerationRepository,
    AppDatabase? database,
  }) : _miniMaxClient = miniMaxClient ?? MiniMaxClient(),
       _graphRepository = graphRepository ?? GraphRepository(database: database),
       _ocrTextRepository =
           ocrTextRepository ?? OcrTextRepository(database: database),
       _aiGenerationRepository =
           aiGenerationRepository ?? AiGenerationRepository(database: database),
       _database = database ?? AppDatabase.instance;

  final MiniMaxClient _miniMaxClient;
  final GraphRepository _graphRepository;
  final OcrTextRepository _ocrTextRepository;
  final AiGenerationRepository _aiGenerationRepository;
  final AppDatabase _database;

  /// 单份资料送入模型的文本上限，控制 token 成本。
  static const int maxCharsPerDocument = 6000;

  /// 一次批量构建最多处理的资料数，避免无控制的全量调用。
  static const int maxDocumentsPerBatch = 20;

  /// 跨库关系发现一次送入的实体上限。
  static const int maxCrossLibraryEntities = 40;

  // ================= 复用既有知识点（不调用模型） =================

  /// 把项目里已经抽取过的 per-document 知识点导入规范图谱。
  /// 这是确定性、零模型成本的路径：已有资料的初始化不会重复消耗 token。
  Future<GraphWriteSummary> importExistingConceptsForLibrary({
    required int userId,
    required int libraryId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;

    final conceptRows = await db.rawQuery('''
      SELECT concepts.id,
             concepts.name,
             concepts.summary,
             concepts.evidence_text,
             concepts.document_id,
             documents.library_id AS library_id,
             documents.import_record_id AS import_record_id
      FROM ${AppDatabase.tableKnowledgeConcepts} concepts
      LEFT JOIN ${AppDatabase.tableSourceDocuments} documents
        ON documents.id = concepts.document_id
      WHERE concepts.user_id = ? AND concepts.library_id = ?
      ORDER BY concepts.document_id ASC, concepts.id ASC
      ''', [userId, libraryId]);

    if (conceptRows.isEmpty) {
      return const GraphWriteSummary(
        createdNodeCount: 0,
        reusedNodeCount: 0,
        createdEdgeCount: 0,
        reusedEdgeCount: 0,
        skippedEdges: <String>[],
      );
    }

    final linkRows = await db.rawQuery('''
      SELECT links.relation_label,
             links.from_concept_id,
             links.to_concept_id,
             source.name AS from_name,
             source.document_id AS from_document_id,
             target.name AS to_name,
             target.document_id AS to_document_id
      FROM ${AppDatabase.tableKnowledgeConceptLinks} links
      JOIN ${AppDatabase.tableKnowledgeConcepts} source
        ON source.id = links.from_concept_id
      JOIN ${AppDatabase.tableKnowledgeConcepts} target
        ON target.id = links.to_concept_id
      WHERE links.user_id = ?
        AND source.library_id = ?
        AND target.library_id = ?
      ''', [userId, libraryId, libraryId]);

    // 按资料页分组：来源映射必须精确到页，关系只在同一页内成立。
    final byDocument = <int, List<Map<String, Object?>>>{};
    for (final row in conceptRows) {
      final documentId = (row['document_id'] as num?)?.toInt();
      if (documentId == null) continue;
      byDocument.putIfAbsent(documentId, () => []).add(row);
    }
    final linksByDocument = <int, List<Map<String, Object?>>>{};
    for (final row in linkRows) {
      final documentId = (row['from_document_id'] as num?)?.toInt();
      if (documentId == null) continue;
      if (documentId != (row['to_document_id'] as num?)?.toInt()) continue;
      linksByDocument.putIfAbsent(documentId, () => []).add(row);
    }

    var createdNodes = 0;
    var reusedNodes = 0;
    var createdEdges = 0;
    var reusedEdges = 0;

    for (final entry in byDocument.entries) {
      final documentId = entry.key;
      final rows = entry.value;
      final libraryIdOfRow =
          (rows.first['library_id'] as num?)?.toInt() ?? libraryId;
      final importRecordId =
          (rows.first['import_record_id'] as num?)?.toInt();

      final draft = GraphExtractionDraft(
        nodes: rows
            .map(
              (row) => GraphNodeDraft(
                name: (row['name'] as String?)?.trim() ?? '',
                entityType: GraphEntityTypes.concept,
                description: (row['summary'] as String?)?.trim(),
                evidenceText: (row['evidence_text'] as String?)?.trim(),
                confidence: 0.6,
              ),
            )
            .where((node) => node.name.isNotEmpty)
            .toList(growable: false),
        edges: (linksByDocument[documentId] ?? const [])
            .map(
              (row) => GraphEdgeDraft(
                fromName: (row['from_name'] as String?)?.trim() ?? '',
                toName: (row['to_name'] as String?)?.trim() ?? '',
                relationType: GraphRelationTypes.normalize(
                  row['relation_label'] as String?,
                ),
                confidence: 0.6,
              ),
            )
            .where(
              (edge) => edge.fromName.isNotEmpty && edge.toName.isNotEmpty,
            )
            .toList(growable: false),
      );
      if (draft.nodes.isEmpty) continue;

      final summary = await _graphRepository.persistExtraction(
        userId: userId,
        knowledgeBaseId: libraryIdOfRow,
        importRecordId: importRecordId,
        sourceDocumentId: documentId,
        draft: draft,
        modelVersion: 'existing-concepts',
      );
      createdNodes += summary.createdNodeCount;
      reusedNodes += summary.reusedNodeCount;
      createdEdges += summary.createdEdgeCount;
      reusedEdges += summary.reusedEdgeCount;
    }

    return GraphWriteSummary(
      createdNodeCount: createdNodes,
      reusedNodeCount: reusedNodes,
      createdEdgeCount: createdEdges,
      reusedEdgeCount: reusedEdges,
      skippedEdges: const <String>[],
    );
  }

  // ================= 单条资料构建 =================

  Future<GraphWriteSummary> buildForDocument({
    required int userId,
    required int documentId,
    LlmProviderConfig? llmConfig,
  }) async {
    final bundle = await collectSourceBundle(
      userId: userId,
      documentId: documentId,
    );
    if (bundle == null) {
      throw StateError('资料不存在或无权访问');
    }
    if (!bundle.hasUsableText) {
      throw StateError('这份资料还没有可用的 OCR 文本或 AI 成果');
    }

    final client = llmConfig == null
        ? _miniMaxClient
        : MiniMaxClient.fromConfig(llmConfig);
    final response = await client.generateStructuredJson(
      systemPrompt: _extractionSystemPrompt,
      userPrompt: _buildExtractionPrompt(bundle),
      jsonSchema: _extractionSchema,
    );
    final draft = parseExtractionResponse(response);
    if (draft.nodes.isEmpty) {
      throw const FormatException('模型没有返回可用知识点');
    }

    return _graphRepository.persistExtraction(
      userId: userId,
      knowledgeBaseId: bundle.libraryId,
      importRecordId: bundle.importRecordId,
      sourceDocumentId: bundle.documentId,
      draft: draft,
      modelVersion: client.debugModel,
    );
  }

  // ================= 知识库批量构建 =================

  /// 为整本知识库构建图谱。
  ///
  /// 顺序：先把项目里已经抽取过的知识点（per-document knowledge_concepts）
  /// 零成本导入规范图谱，再只对仍然没有贡献的资料调用模型。
  /// [force] 为真时忽略已有贡献，重新用模型抽取全部资料。
  Future<GraphBuildOutcome> buildForLibrary({
    required int userId,
    required int libraryId,
    LlmProviderConfig? llmConfig,
    bool force = false,
    int maxDocuments = maxDocumentsPerBatch,
    GraphBuildCancellation? cancellation,
    void Function(GraphBuildProgress progress)? onProgress,
  }) async {
    final bundles = await collectLibraryBundles(
      userId: userId,
      libraryId: libraryId,
    );
    var covered = <int>{};
    var importedNodes = 0;
    var importedEdges = 0;
    var reusedDocuments = 0;

    if (!force) {
      onProgress?.call(
        const GraphBuildProgress(
          doneUnits: 0,
          totalUnits: 1,
          message: '正在复用已有知识点',
        ),
      );
      final imported = await importExistingConceptsForLibrary(
        userId: userId,
        libraryId: libraryId,
      );
      importedNodes = imported.createdNodeCount;
      importedEdges = imported.createdEdgeCount;
      covered = await _graphRepository.coveredDocumentIds(
        userId: userId,
        libraryId: libraryId,
      );
      reusedDocuments = covered.length;
    }

    final pending = bundles
        .where((bundle) => !covered.contains(bundle.documentId))
        .toList(growable: false);
    final skipped = bundles.length - pending.length;
    final targets = pending.take(maxDocuments).toList(growable: false);

    if (targets.isEmpty) {
      return GraphBuildOutcome(
        processedDocuments: 0,
        skippedDocuments: skipped,
        reusedDocuments: reusedDocuments,
        createdNodeCount: importedNodes,
        createdEdgeCount: importedEdges,
        failures: const <String>[],
      );
    }

    final client = llmConfig == null
        ? _miniMaxClient
        : MiniMaxClient.fromConfig(llmConfig);
    var createdNodes = importedNodes;
    var createdEdges = importedEdges;
    var processed = 0;
    var cancelled = false;
    final failures = <String>[];

    for (var index = 0; index < targets.length; index++) {
      if (cancellation?.isCancelled ?? false) {
        cancelled = true;
        break;
      }
      final bundle = targets[index];
      onProgress?.call(
        GraphBuildProgress(
          doneUnits: index,
          totalUnits: targets.length,
          message: '正在抽取：${bundle.title}',
        ),
      );
      if (!bundle.hasUsableText) {
        failures.add('${bundle.title}：缺少可用文本');
        continue;
      }
      try {
        final response = await client.generateStructuredJson(
          systemPrompt: _extractionSystemPrompt,
          userPrompt: _buildExtractionPrompt(bundle),
          jsonSchema: _extractionSchema,
        );
        final draft = parseExtractionResponse(response);
        if (draft.nodes.isEmpty) {
          failures.add('${bundle.title}：模型未返回知识点');
          continue;
        }
        final summary = await _graphRepository.persistExtraction(
          userId: userId,
          knowledgeBaseId: bundle.libraryId,
          importRecordId: bundle.importRecordId,
          sourceDocumentId: bundle.documentId,
          draft: draft,
          modelVersion: client.debugModel,
        );
        createdNodes += summary.createdNodeCount;
        createdEdges += summary.createdEdgeCount;
        processed++;
      } catch (error) {
        failures.add('${bundle.title}：${_shortError(error)}');
      }
    }

    onProgress?.call(
      GraphBuildProgress(
        doneUnits: processed,
        totalUnits: targets.length,
        message: cancelled ? '已取消' : '构建完成',
      ),
    );

    return GraphBuildOutcome(
      processedDocuments: processed,
      skippedDocuments: skipped,
      reusedDocuments: reusedDocuments,
      createdNodeCount: createdNodes,
      createdEdgeCount: createdEdges,
      failures: failures,
      cancelled: cancelled,
    );
  }

  // ================= 跨库关系发现 =================

  /// 在选中范围内发现真实的跨库语义关系。
  /// 只对「分属不同知识库、尚未直接相连」的实体候选调用模型，并要求给出证据。
  /// 模型没有可靠依据时返回空数组，不会为了图谱好看而编造关系。
  Future<CrossLibraryOutcome> discoverCrossLibraryRelations({
    required int userId,
    required List<int> libraryIds,
    LlmProviderConfig? llmConfig,
    GraphBuildCancellation? cancellation,
    void Function(GraphBuildProgress progress)? onProgress,
  }) async {
    if (libraryIds.length < 2) {
      return const CrossLibraryOutcome(
        createdEdgeCount: 0,
        candidateCount: 0,
        failures: <String>['至少选择两本知识库才能发现跨库关系'],
      );
    }

    final view = await _graphRepository.fetchVisibleGraph(
      userId: userId,
      libraryIds: libraryIds,
    );
    if (view.nodes.length < 2) {
      return const CrossLibraryOutcome(
        createdEdgeCount: 0,
        candidateCount: 0,
        failures: <String>['当前范围内的知识点太少，暂不需要跨库关系'],
      );
    }

    final libraryNames = await _libraryNames(userId, libraryIds);
    final existingPairs = <String>{
      for (final edge in view.edges)
        _pairKey(edge.sourceId, edge.targetId),
    };

    // 候选：分属不同知识库、且当前画布上没有直接关系的实体。
    final candidates = <(GraphViewNode, GraphViewNode)>[];
    for (var i = 0; i < view.nodes.length; i++) {
      final a = view.nodes[i];
      if (a.primaryLibraryId == null) continue;
      for (var j = i + 1; j < view.nodes.length; j++) {
        final b = view.nodes[j];
        if (b.primaryLibraryId == null) continue;
        if (a.primaryLibraryId == b.primaryLibraryId) continue;
        if (existingPairs.contains(_pairKey(a.id, b.id))) continue;
        candidates.add((a, b));
        if (candidates.length >= maxCrossLibraryEntities) break;
      }
      if (candidates.length >= maxCrossLibraryEntities) break;
    }

    if (candidates.isEmpty) {
      return const CrossLibraryOutcome(
        createdEdgeCount: 0,
        candidateCount: 0,
        failures: <String>[],
      );
    }

    if (cancellation?.isCancelled ?? false) {
      return const CrossLibraryOutcome(
        createdEdgeCount: 0,
        candidateCount: 0,
        failures: <String>['已取消'],
      );
    }

    onProgress?.call(
      GraphBuildProgress(
        doneUnits: 0,
        totalUnits: 1,
        message: '正在比对 ${candidates.length} 组跨库知识点',
      ),
    );

    final client = llmConfig == null
        ? _miniMaxClient
        : MiniMaxClient.fromConfig(llmConfig);

    try {
      final response = await client.generateStructuredJson(
        systemPrompt: _crossLibrarySystemPrompt,
        userPrompt: _buildCrossLibraryPrompt(
          candidates: candidates,
          libraryNames: libraryNames,
        ),
        jsonSchema: _crossLibrarySchema,
      );
      final relations = parseCrossLibraryResponse(
        response,
        nameToNodeId: {
          for (final node in view.nodes)
            GraphNameNormalizer.normalize(node.label): node.id,
        },
      );
      if (relations.isEmpty) {
        return CrossLibraryOutcome(
          createdEdgeCount: 0,
          candidateCount: candidates.length,
          failures: const <String>[],
        );
      }

      final draft = GraphExtractionDraft(
        nodes: const <GraphNodeDraft>[],
        edges: relations,
      );
      // 跨库关系不重写任何文档的贡献，只追加证据。
      final summary = await _graphRepository.persistExtraction(
        userId: userId,
        knowledgeBaseId: null,
        importRecordId: null,
        sourceDocumentId: null,
        draft: draft,
        origin: GraphEdgeOrigin.crossLibrary,
        modelVersion: client.debugModel,
        replaceDocumentContributions: false,
      );
      return CrossLibraryOutcome(
        createdEdgeCount: summary.createdEdgeCount,
        candidateCount: candidates.length,
        failures: const <String>[],
      );
    } catch (error) {
      return CrossLibraryOutcome(
        createdEdgeCount: 0,
        candidateCount: candidates.length,
        failures: <String>[_shortError(error)],
      );
    }
  }

  // ================= 文本收集 =================

  Future<GraphSourceBundle?> collectSourceBundle({
    required int userId,
    required int documentId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableSourceDocuments,
      columns: [
        'id',
        'user_id',
        'library_id',
        'import_record_id',
        'original_title',
      ],
      where: 'id = ? AND user_id = ?',
      whereArgs: [documentId, userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;

    final text = await _composeTextForDocument(documentId);
    return GraphSourceBundle(
      documentId: documentId,
      libraryId: row['library_id'] as int?,
      importRecordId: row['import_record_id'] as int?,
      title: ((row['original_title'] as String?)?.trim().isNotEmpty ?? false)
          ? (row['original_title'] as String).trim()
          : '未命名资料',
      text: text,
      hasUsableText: text.trim().isNotEmpty,
    );
  }

  Future<List<GraphSourceBundle>> collectLibraryBundles({
    required int userId,
    required int libraryId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableSourceDocuments,
      columns: [
        'id',
        'library_id',
        'import_record_id',
        'original_title',
        'source_type',
        'page_number',
      ],
      where: 'user_id = ? AND library_id = ?',
      whereArgs: [userId, libraryId],
      orderBy: 'import_record_id ASC, page_number ASC, id ASC',
    );

    final bundles = <GraphSourceBundle>[];
    for (final row in rows) {
      final documentId = row['id'] as int;
      final text = await _composeTextForDocument(documentId);
      final title =
          ((row['original_title'] as String?)?.trim().isNotEmpty ?? false)
          ? (row['original_title'] as String).trim()
          : '第 ${row['page_number'] ?? 1} 页';
      bundles.add(
        GraphSourceBundle(
          documentId: documentId,
          libraryId: row['library_id'] as int?,
          importRecordId: row['import_record_id'] as int?,
          title: title,
          text: text,
          hasUsableText: text.trim().isNotEmpty,
        ),
      );
    }
    return bundles;
  }

  /// 组装一份资料的抽取文本：优先已校对文本，其次 OCR，最后 AI 派生成果。
  Future<String> _composeTextForDocument(int documentId) async {
    final buffer = StringBuffer();

    final ocr = await _ocrTextRepository.getByDocumentId(documentId);
    if (ocr != null) {
      final primary = ocr.effectiveText;
      if (primary.isNotEmpty) {
        buffer.writeln('【原文】');
        buffer.writeln(primary);
      }
    }

    final cards = await _aiGenerationRepository.fetchKnowledgeCards(documentId);
    if (cards.isNotEmpty) {
      buffer.writeln('【知识卡片】');
      for (final card in cards) {
        buffer.writeln('${card.title}：${card.content}');
      }
    }

    final outline = await _aiGenerationRepository.fetchReviewOutline(
      documentId,
    );
    if (outline != null && outline.outlineText.trim().isNotEmpty) {
      buffer.writeln('【复习提纲】');
      buffer.writeln(outline.outlineText.trim());
    }

    final mindmap = await _aiGenerationRepository.fetchMindmapText(documentId);
    if (mindmap != null && mindmap.mindmapText.trim().isNotEmpty) {
      buffer.writeln('【思维导图】');
      buffer.writeln(mindmap.mindmapText.trim());
    }

    final composed = buffer.toString().trim();
    if (composed.length <= maxCharsPerDocument) return composed;
    return '${composed.substring(0, maxCharsPerDocument)}\n…（内容已截断）';
  }

  Future<Map<int, String>> _libraryNames(
    int userId,
    List<int> libraryIds,
  ) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableKnowledgeLibraries,
      columns: ['id', 'name'],
      where:
          'user_id = ? AND id IN (${List.filled(libraryIds.length, '?').join(',')})',
      whereArgs: [userId, ...libraryIds],
    );
    return {
      for (final row in rows)
        (row['id'] as num).toInt(): (row['name'] as String?)?.trim() ?? '',
    };
  }

  String _pairKey(int a, int b) => a < b ? '$a-$b' : '$b-$a';

  String _shortError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    return text.length <= 60 ? text : '${text.substring(0, 60)}…';
  }

  // ================= 响应解析（可单测） =================

  static GraphExtractionDraft parseExtractionResponse(
    Map<String, dynamic> data,
  ) {
    final rawEntities = _pickList(data, const [
      'entities',
      'nodes',
      'concepts',
      'knowledge_points',
    ]);
    final nodes = <GraphNodeDraft>[];
    final seenKeys = <String>{};
    for (final item in rawEntities) {
      if (item is! Map) continue;
      final map = item.cast<String, Object?>();
      final name = _pickString(map, const ['name', 'title', 'label', 'concept']);
      if (name.isEmpty) continue;
      final entityType = GraphEntityTypes.normalize(
        _pickString(map, const ['type', 'entity_type', 'category', 'kind']),
      );
      final key = GraphNameNormalizer.canonicalKey(name, entityType);
      if (key.isEmpty || !seenKeys.add(key)) continue;
      nodes.add(
        GraphNodeDraft(
          name: name,
          entityType: entityType,
          description: _pickNullableString(map, const [
            'description',
            'summary',
            'definition',
          ]),
          aliases: _pickStringList(map, const [
            'aliases',
            'synonyms',
            'alias',
            'also_known_as',
          ]),
          evidenceText: _pickNullableString(map, const [
            'evidence',
            'evidence_text',
            'source',
          ]),
          confidence: _pickDouble(map, const ['confidence', 'score'], 0.7),
        ),
      );
    }

    final rawRelations = _pickList(data, const [
      'relations',
      'relationships',
      'edges',
      'links',
    ]);
    final edges = <GraphEdgeDraft>[];
    final seenEdges = <String>{};
    for (final item in rawRelations) {
      if (item is! Map) continue;
      final map = item.cast<String, Object?>();
      final from = _pickString(map, const ['from', 'source', 'head', 'from_name']);
      final to = _pickString(map, const ['to', 'target', 'tail', 'to_name']);
      if (from.isEmpty || to.isEmpty) continue;
      if (GraphNameNormalizer.normalize(from) ==
          GraphNameNormalizer.normalize(to)) {
        continue;
      }
      final relation = GraphRelationTypes.normalize(
        _pickString(map, const ['relation', 'relation_type', 'type', 'label']),
      );
      final key =
          '${GraphNameNormalizer.normalize(from)}>${GraphNameNormalizer.normalize(to)}:$relation';
      if (!seenEdges.add(key)) continue;
      edges.add(
        GraphEdgeDraft(
          fromName: from,
          toName: to,
          relationType: relation,
          description: _pickNullableString(map, const [
            'description',
            'reason',
            'note',
          ]),
          confidence: _pickDouble(map, const ['confidence', 'score'], 0.6),
          evidenceText: _pickNullableString(map, const [
            'evidence',
            'evidence_text',
            'source',
          ]),
        ),
      );
    }

    return GraphExtractionDraft(nodes: nodes, edges: edges);
  }

  /// 解析跨库关系发现结果，把名称映射回实体 ID，丢弃无法对应的候选。
  static List<GraphEdgeDraft> parseCrossLibraryResponse(
    Map<String, dynamic> data, {
    required Map<String, int> nameToNodeId,
  }) {
    final rawRelations = _pickList(data, const [
      'relations',
      'relationships',
      'edges',
      'links',
    ]);
    final edges = <GraphEdgeDraft>[];
    for (final item in rawRelations) {
      if (item is! Map) continue;
      final map = item.cast<String, Object?>();
      final from = _pickString(map, const ['from', 'source', 'a', 'from_name']);
      final to = _pickString(map, const ['to', 'target', 'b', 'to_name']);
      if (from.isEmpty || to.isEmpty) continue;
      final fromId = nameToNodeId[GraphNameNormalizer.normalize(from)];
      final toId = nameToNodeId[GraphNameNormalizer.normalize(to)];
      if (fromId == null || toId == null || fromId == toId) continue;
      final evidence = _pickNullableString(map, const [
        'evidence',
        'reason',
        'explanation',
      ]);
      // 没有可核查依据的跨库关系一律丢弃。
      if (evidence == null || evidence.trim().length < 4) continue;
      final confidence = _pickDouble(map, const ['confidence', 'score'], 0.5);
      if (confidence < 0.4) continue;
      edges.add(
        GraphEdgeDraft(
          fromName: from,
          toName: to,
          relationType: _pickString(map, const [
            'relation',
            'relation_type',
            'type',
          ]),
          description: _pickNullableString(map, const ['description', 'reason']),
          confidence: confidence,
          evidenceText: evidence,
        ),
      );
    }
    return edges;
  }

  // ================= 提示词与 Schema =================

  static const String _extractionSystemPrompt =
      '你是学科知识图谱构建助手。只返回可解析 JSON。'
      '只抽取资料中真实出现的知识点，不要编造；无法确定的字段留空。'
      '关系必须有原文依据，不要为了图谱好看而随意连线。';

  static String _buildExtractionPrompt(GraphSourceBundle bundle) {
    return '''
请从下面的学习资料中抽取知识实体与它们之间的关系。

要求：
1. entities：知识点，name 用简短规范名称（例如「函数极限」「梯度」）。
2. entities.type 只能取：概念 / 定义 / 定理 / 公式 / 方法 / 算法 / 模型 / 性质 / 应用 / 术语 / 命题 / 结构 / 其他。
3. entities.aliases 写同义说法或英文名，例如「梯度」可写 ["gradient","梯度向量"]。
4. entities.evidence 抄写资料中支撑该知识点的原句片段。
5. relations：from/to 必须与某个 entity 的 name 完全一致。
6. relations.relation 只能取：前置知识 / 属于 / 包含 / 应用于 / 相关 / 扩展 / 依赖于。
7. relations.confidence 取 0 到 1；relations.evidence 写支撑这条关系的原句。
8. 只返回 JSON，不要 markdown。

资料标题：${bundle.title}

资料内容：
${bundle.text}
''';
  }

  static const Map<String, dynamic> _extractionSchema = {
    'name': 'knowledge_graph_extraction',
    'schema': {
      'type': 'object',
      'properties': {
        'entities': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
              'type': {'type': 'string'},
              'description': {'type': 'string'},
              'aliases': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'evidence': {'type': 'string'},
              'confidence': {'type': 'number'},
            },
            'required': ['name', 'type'],
          },
        },
        'relations': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'from': {'type': 'string'},
              'to': {'type': 'string'},
              'relation': {'type': 'string'},
              'description': {'type': 'string'},
              'evidence': {'type': 'string'},
              'confidence': {'type': 'number'},
            },
            'required': ['from', 'to', 'relation'],
          },
        },
      },
      'required': ['entities', 'relations'],
    },
  };

  static const String _crossLibrarySystemPrompt =
      '你是跨学科知识关联助手。只返回可解析 JSON。'
      '只有当两个知识点之间存在明确的、可以用一句话说清并给出依据的语义关系时才返回。'
      '如果没有可靠关联，返回空的 relations 数组，不要勉强连线。';

  static String _buildCrossLibraryPrompt({
    required List<(GraphViewNode, GraphViewNode)> candidates,
    required Map<int, String> libraryNames,
  }) {
    final buffer = StringBuffer()
      ..writeln('下面是来自不同知识库的知识点候选对。')
      ..writeln('请判断每一对之间是否存在真实的语义关系（例如「梯度」应用于「梯度下降」）。')
      ..writeln('只在确有依据时输出；关系类型只能取：前置知识 / 属于 / 包含 / 应用于 / 相关 / 扩展 / 依赖于。')
      ..writeln('每条关系必须给出 evidence（为什么成立），confidence 取 0 到 1，低于 0.4 的不要输出。')
      ..writeln('只返回 JSON：{"relations":[{"from":"","to":"","relation":"","evidence":"","confidence":0.8}]}')
      ..writeln();

    for (final (a, b) in candidates) {
      final aLib = libraryNames[a.primaryLibraryId] ?? '知识库A';
      final bLib = libraryNames[b.primaryLibraryId] ?? '知识库B';
      buffer.writeln('候选对：');
      buffer.writeln('  A[$aLib] ${a.label}（${a.entityType}）'
          '${a.description == null ? '' : '：${a.description}'}');
      buffer.writeln('  B[$bLib] ${b.label}（${b.entityType}）'
          '${b.description == null ? '' : '：${b.description}'}');
    }
    return buffer.toString();
  }

  static const Map<String, dynamic> _crossLibrarySchema = {
    'name': 'cross_library_relations',
    'schema': {
      'type': 'object',
      'properties': {
        'relations': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'from': {'type': 'string'},
              'to': {'type': 'string'},
              'relation': {'type': 'string'},
              'description': {'type': 'string'},
              'evidence': {'type': 'string'},
              'confidence': {'type': 'number'},
            },
            'required': ['from', 'to', 'relation', 'evidence'],
          },
        },
      },
      'required': ['relations'],
    },
  };

  // ================= 解析辅助 =================

  static List<Object?> _pickList(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is List) return value;
    }
    return const <Object?>[];
  }

  static String _pickString(Map<String, Object?> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is num) return '$value';
    }
    return '';
  }

  static String? _pickNullableString(
    Map<String, Object?> source,
    List<String> keys,
  ) {
    final value = _pickString(source, keys);
    return value.isEmpty ? null : value;
  }

  static List<String> _pickStringList(
    Map<String, Object?> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is List) {
        return value
            .map((item) => '$item'.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
      if (value is String && value.trim().isNotEmpty) {
        return value
            .split(RegExp(r'[,，、;；]'))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
    }
    return const <String>[];
  }

  static double _pickDouble(
    Map<String, Object?> source,
    List<String> keys,
    double fallback,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is num) return value.toDouble().clamp(0.0, 1.0);
      if (value is String) {
        final parsed = double.tryParse(value.trim());
        if (parsed != null) return parsed.clamp(0.0, 1.0);
      }
    }
    return fallback;
  }

  /// 供测试使用：验证一次模型输出是否被正确校验。
  static String describeDraft(GraphExtractionDraft draft) =>
      jsonEncode({
        'nodes': draft.nodes.length,
        'edges': draft.edges.length,
      });
}
