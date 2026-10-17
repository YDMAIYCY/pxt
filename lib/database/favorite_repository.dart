import 'dart:convert';

import 'app_database.dart';
import 'models/favorite_annotation.dart';

export 'models/favorite_annotation.dart';

class FavoriteTargetType {
  const FavoriteTargetType._();

  static const String knowledgeCard = 'knowledge_card';
  static const String wrongQuestion = 'wrong_question';
  static const String reviewOutline = 'review_outline';
  static const String mindmapText = 'mindmap_text';
  static const String practiceQuestion = 'practice_question';
}

class FavoriteCategorySummary {
  const FavoriteCategorySummary({
    required this.type,
    required this.title,
    required this.count,
    required this.iconName,
  });

  final String type;
  final String title;
  final int count;
  final String iconName;
}

class FavoriteItemRecord {
  const FavoriteItemRecord({
    required this.favoriteId,
    required this.targetType,
    required this.targetId,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.createdAt,
    this.documentId,
    this.note,
    this.highlightText,
    this.annotations = const [],
  });

  final int favoriteId;
  final String targetType;
  final int targetId;
  final int? documentId;
  final String title;
  final String subtitle;
  final String body;
  final String? note;
  final String? highlightText;
  final List<FavoriteAnnotation> annotations;
  final DateTime createdAt;
}

class FavoriteRepository {
  FavoriteRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Set<String>> fetchFavoriteKeys(int userId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableFavorites,
      columns: ['target_type', 'target_id'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return rows
        .map(
          (row) => favoriteKey(
            row['target_type'] as String,
            row['target_id'] as int,
          ),
        )
        .toSet();
  }

  Future<bool> isFavorited({
    required int userId,
    required String targetType,
    required int targetId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableFavorites,
      columns: ['id'],
      where: 'user_id = ? AND target_type = ? AND target_id = ?',
      whereArgs: [userId, targetType, targetId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> toggleFavorite({
    required int userId,
    required String targetType,
    required int targetId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final existing = await isFavorited(
      userId: userId,
      targetType: targetType,
      targetId: targetId,
    );
    if (existing) {
      await db.delete(
        AppDatabase.tableFavorites,
        where: 'user_id = ? AND target_type = ? AND target_id = ?',
        whereArgs: [userId, targetType, targetId],
      );
      return false;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(AppDatabase.tableFavorites, {
      'user_id': userId,
      'target_type': targetType,
      'target_id': targetId,
      'note': null,
      'highlight_text': null,
      'created_at': now,
      'updated_at': now,
    });
    return true;
  }

  Future<void> updateFavoriteNote({
    required int favoriteId,
    required String note,
    String? highlightText,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    await db.update(
      AppDatabase.tableFavorites,
      {
        'note': _emptyToNull(note),
        'highlight_text': _emptyToNull(highlightText),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [favoriteId],
    );
  }

  Future<void> updateFavoriteNoteOnly({
    required int favoriteId,
    required String note,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    await db.update(
      AppDatabase.tableFavorites,
      {
        'note': _emptyToNull(note),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [favoriteId],
    );
  }

  Future<void> updateFavoriteHighlightOnly({
    required int favoriteId,
    required String highlightText,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    await db.update(
      AppDatabase.tableFavorites,
      {
        'highlight_text': _emptyToNull(highlightText),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [favoriteId],
    );
  }

  Future<void> removeFavoriteById(int favoriteId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    await db.delete(
      AppDatabase.tableFavorites,
      where: 'id = ?',
      whereArgs: [favoriteId],
    );
  }

  Future<void> saveAnnotations({
    required int userId,
    required int favoriteId,
    required List<FavoriteAnnotation> annotations,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final changed = await db.update(
      AppDatabase.tableFavorites,
      {
        'annotations_json': jsonEncode(
          annotations.map((a) => a.toJson()).toList(),
        ),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND user_id = ?',
      whereArgs: [favoriteId, userId],
    );
    if (changed == 0) throw StateError('收藏已不存在或账号已改变，请重新打开');
  }

  Future<List<FavoriteCategorySummary>> fetchCategorySummaries(
    int userId,
  ) async {
    final summaries = <FavoriteCategorySummary>[];
    for (final item in favoriteCategories) {
      final records = await fetchFavoritesByType(
        userId: userId,
        targetType: item.type,
        limit: 100000,
      );
      if (records.isEmpty) {
        continue;
      }
      summaries.add(
        FavoriteCategorySummary(
          type: item.type,
          title: item.title,
          count: records.length,
          iconName: item.iconName,
        ),
      );
    }
    return summaries;
  }

  Future<List<FavoriteItemRecord>> fetchFavoritesByType({
    required int userId,
    required String targetType,
    int limit = 200,
  }) async {
    await _database.ensureSchemaReady();
    switch (targetType) {
      case FavoriteTargetType.knowledgeCard:
        return _fetchKnowledgeCardFavorites(userId, limit);
      case FavoriteTargetType.wrongQuestion:
        return _fetchQuestionFavorites(userId, limit, onlyWrong: true);
      case FavoriteTargetType.practiceQuestion:
        return _fetchQuestionFavorites(userId, limit);
      case FavoriteTargetType.reviewOutline:
        return _fetchOutlineFavorites(userId, limit);
      case FavoriteTargetType.mindmapText:
        return _fetchMindmapFavorites(userId, limit);
      default:
        return const <FavoriteItemRecord>[];
    }
  }

  Future<List<FavoriteItemRecord>> _fetchKnowledgeCardFavorites(
    int userId,
    int limit,
  ) {
    return _queryFavorites(
      '''
      SELECT favorites.*, cards.document_id, cards.title, cards.content AS body,
             COALESCE(documents.original_title, '') AS document_title
      FROM ${AppDatabase.tableFavorites} favorites
      JOIN ${AppDatabase.tableKnowledgeCards} cards ON cards.id = favorites.target_id
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = cards.document_id
      WHERE favorites.user_id = ? AND favorites.target_type = ?
      ORDER BY favorites.updated_at DESC, favorites.id DESC
      LIMIT ?
      ''',
      [userId, FavoriteTargetType.knowledgeCard, limit],
      '知识卡片',
    );
  }

  Future<List<FavoriteItemRecord>> _fetchQuestionFavorites(
    int userId,
    int limit, {
    bool onlyWrong = false,
  }) async {
    final db = await _database.database;
    final targetType = onlyWrong
        ? FavoriteTargetType.wrongQuestion
        : FavoriteTargetType.practiceQuestion;
    final rows = await db.rawQuery(
      '''
      SELECT favorites.*, questions.document_id,
             questions.question_text,
             questions.answer_text,
             questions.analysis_text,
             questions.difficulty,
             questions.options_json,
             COALESCE(documents.original_title, '') AS document_title
      FROM ${AppDatabase.tableFavorites} favorites
      JOIN ${AppDatabase.tablePracticeQuestions} questions ON questions.id = favorites.target_id
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = questions.document_id
      WHERE favorites.user_id = ? AND favorites.target_type = ?
        ${onlyWrong ? "AND questions.review_status = 'wrong'" : ''}
      ORDER BY favorites.updated_at DESC, favorites.id DESC
      LIMIT ?
      ''',
      [userId, targetType, limit],
    );

    return rows
        .map((row) {
          final createdAt = (row['created_at'] as String?) ?? '';
          final documentTitle = (row['document_title'] as String?)?.trim();
          final questionText = (row['question_text'] as String?)?.trim() ?? '';
          final answerText = (row['answer_text'] as String?)?.trim() ?? '';
          final analysisText = (row['analysis_text'] as String?)?.trim() ?? '';
          final difficulty = (row['difficulty'] as String?)?.trim() ?? '';
          final options = _decodeStringList(row['options_json'] as String?);
          return FavoriteItemRecord(
            favoriteId: row['id'] as int,
            targetType: row['target_type'] as String,
            targetId: row['target_id'] as int,
            documentId: row['document_id'] as int?,
            title: questionText,
            subtitle:
                '${_documentTitle(documentTitle)} / ${onlyWrong ? '错题' : '练习题'}',
            body: _formatQuestionBody(
              questionText: questionText,
              options: options,
              answerText: answerText,
              analysisText: analysisText,
              difficulty: difficulty,
            ),
            note: (row['note'] as String?)?.trim(),
            highlightText: (row['highlight_text'] as String?)?.trim(),
            annotations: _decodeAnnotations(row['annotations_json']),
            createdAt:
                DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now(),
          );
        })
        .toList(growable: false);
  }

  Future<List<FavoriteItemRecord>> _fetchOutlineFavorites(
    int userId,
    int limit,
  ) {
    return _queryFavorites(
      '''
      SELECT favorites.*, outlines.document_id, outlines.title,
             outlines.outline_text AS body,
             COALESCE(documents.original_title, '') AS document_title
      FROM ${AppDatabase.tableFavorites} favorites
      JOIN ${AppDatabase.tableReviewOutlines} outlines ON outlines.id = favorites.target_id
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = outlines.document_id
      WHERE favorites.user_id = ? AND favorites.target_type = ?
      ORDER BY favorites.updated_at DESC, favorites.id DESC
      LIMIT ?
      ''',
      [userId, FavoriteTargetType.reviewOutline, limit],
      '复习提纲',
    );
  }

  Future<List<FavoriteItemRecord>> _fetchMindmapFavorites(
    int userId,
    int limit,
  ) {
    return _queryFavorites(
      '''
      SELECT favorites.*, mindmaps.document_id,
             '思维导图文字版' AS title,
             mindmaps.mindmap_text AS body,
             COALESCE(documents.original_title, '') AS document_title
      FROM ${AppDatabase.tableFavorites} favorites
      JOIN ${AppDatabase.tableMindmapTexts} mindmaps ON mindmaps.id = favorites.target_id
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = mindmaps.document_id
      WHERE favorites.user_id = ? AND favorites.target_type = ?
      ORDER BY favorites.updated_at DESC, favorites.id DESC
      LIMIT ?
      ''',
      [userId, FavoriteTargetType.mindmapText, limit],
      '思维导图',
    );
  }

  Future<List<FavoriteItemRecord>> _queryFavorites(
    String sql,
    List<Object?> args,
    String label,
  ) async {
    final db = await _database.database;
    final rows = await db.rawQuery(sql, args);
    return rows
        .map((row) {
          final createdAt = (row['created_at'] as String?) ?? '';
          final documentTitle = (row['document_title'] as String?)?.trim();
          return FavoriteItemRecord(
            favoriteId: row['id'] as int,
            targetType: row['target_type'] as String,
            targetId: row['target_id'] as int,
            documentId: row['document_id'] as int?,
            title: (row['title'] as String?)?.trim() ?? '',
            subtitle: '${_documentTitle(documentTitle)} / $label',
            body: (row['body'] as String?)?.trim() ?? '',
            note: (row['note'] as String?)?.trim(),
            highlightText: (row['highlight_text'] as String?)?.trim(),
            annotations: _decodeAnnotations(row['annotations_json']),
            createdAt:
                DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now(),
          );
        })
        .toList(growable: false);
  }

  static String favoriteKey(String targetType, int targetId) =>
      '$targetType:$targetId';

  static List<FavoriteAnnotation> _decodeAnnotations(Object? value) {
    if (value is! String || value.isEmpty) return const [];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    return decoded
        .map(FavoriteAnnotation.fromJson)
        .whereType<FavoriteAnnotation>()
        .toList();
  }

  static String targetTypeForGeneratedContent(String contentType) {
    switch (contentType) {
      case 'knowledge_cards':
        return FavoriteTargetType.knowledgeCard;
      case 'review_outline':
        return FavoriteTargetType.reviewOutline;
      case 'mindmap_text':
        return FavoriteTargetType.mindmapText;
      case 'practice_questions':
        return FavoriteTargetType.practiceQuestion;
      default:
        return contentType;
    }
  }

  static String _formatQuestionBody({
    required String questionText,
    required List<String> options,
    required String answerText,
    required String analysisText,
    required String difficulty,
  }) {
    return [
      if (difficulty.isNotEmpty) '难度：$difficulty',
      '题目：$questionText',
      if (options.isNotEmpty) '选项：\n${options.join('\n')}',
      if (answerText.isNotEmpty) '答案：$answerText',
      if (analysisText.isNotEmpty) '解析：$analysisText',
    ].where((item) => item.trim().isNotEmpty).join('\n\n');
  }

  static List<String> _decodeStringList(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {
      return const <String>[];
    }
    return const <String>[];
  }

  static String _documentTitle(String? title) {
    final normalized = title?.trim();
    if (normalized == null || normalized.isEmpty) {
      return '未命名资料';
    }
    return normalized;
  }

  static String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}

class FavoriteCategoryDefinition {
  const FavoriteCategoryDefinition({
    required this.type,
    required this.title,
    required this.iconName,
  });

  final String type;
  final String title;
  final String iconName;
}

const favoriteCategories = [
  FavoriteCategoryDefinition(
    type: FavoriteTargetType.knowledgeCard,
    title: '知识卡片',
    iconName: 'style',
  ),
  FavoriteCategoryDefinition(
    type: FavoriteTargetType.wrongQuestion,
    title: '错题',
    iconName: 'wrong',
  ),
  FavoriteCategoryDefinition(
    type: FavoriteTargetType.reviewOutline,
    title: '复习提纲',
    iconName: 'outline',
  ),
  FavoriteCategoryDefinition(
    type: FavoriteTargetType.mindmapText,
    title: '思维导图',
    iconName: 'mindmap',
  ),
  FavoriteCategoryDefinition(
    type: FavoriteTargetType.practiceQuestion,
    title: '练习题',
    iconName: 'quiz',
  ),
];
