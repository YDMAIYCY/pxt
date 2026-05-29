import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// ========== SQLite 数据库入口 ==========
// 统一管理数据库打开、建表与升级逻辑。

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String databaseName = 'paixuetong.db';
  static const int databaseVersion = 9;

  static const String tableUsers = 'users';
  static const String tableAuthSessions = 'auth_sessions';
  static const String tableKnowledgeLibraries = 'knowledge_libraries';
  static const String tableDocumentBatches = 'document_batches';
  static const String tableSourceDocuments = 'source_documents';
  static const String tableOcrTexts = 'ocr_texts';
  static const String tableAiGenerationTasks = 'ai_generation_tasks';
  static const String tableKnowledgeCards = 'knowledge_cards';
  static const String tableReviewOutlines = 'review_outlines';
  static const String tableMindmapTexts = 'mindmap_texts';
  static const String tablePracticeQuestions = 'practice_questions';
  static const String tableLlmProviderConfigs = 'llm_provider_configs';
  static const String tableWrongQuestionExplanations =
      'wrong_question_explanations';
  static const String tableWrongQuestionTrainings = 'wrong_question_trainings';

  Database? _database;

  Future<Database> get database async {
    _database ??= await _open();
    return _database!;
  }

  Future<void> ensureSchemaReady() async {
    final db = await database;
    await _ensureSchemaConsistency(db);
  }

  Future<Database> _open() async {
    final dbDirectory = await getDatabasesPath();
    final dbPath = p.join(dbDirectory, databaseName);

    return openDatabase(
      dbPath,
      version: databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: _createTables,
      onUpgrade: _upgradeTables,
      onOpen: _ensureSchemaConsistency,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableUsers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        password_salt TEXT NOT NULL,
        display_name TEXT,
        bio TEXT,
        gender TEXT,
        age INTEGER,
        avatar_style TEXT,
        background_style TEXT,
        avatar_image_path TEXT,
        background_image_path TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_login_at TEXT,
        is_active INTEGER NOT NULL DEFAULT 1
      );
    ''');

    await db.execute('''
      CREATE TABLE $tableAuthSessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        session_token TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        expired_at TEXT,
        logged_out_at TEXT,
        FOREIGN KEY(user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE $tableKnowledgeLibraries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE $tableDocumentBatches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        library_id INTEGER,
        source_type TEXT NOT NULL,
        title TEXT NOT NULL,
        original_file_path TEXT,
        page_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE,
        FOREIGN KEY(library_id) REFERENCES $tableKnowledgeLibraries(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE $tableSourceDocuments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        library_id INTEGER,
        batch_id INTEGER,
        page_number INTEGER,
        source_type TEXT NOT NULL,
        image_path TEXT NOT NULL,
        original_title TEXT,
        ocr_status TEXT NOT NULL DEFAULT 'pending',
        ocr_error_message TEXT,
        ocr_updated_at TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE,
        FOREIGN KEY(library_id) REFERENCES $tableKnowledgeLibraries(id) ON DELETE CASCADE,
        FOREIGN KEY(batch_id) REFERENCES $tableDocumentBatches(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE $tableOcrTexts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL UNIQUE,
        raw_text TEXT NOT NULL,
        clean_text TEXT,
        language TEXT NOT NULL DEFAULT 'zh-CN',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(document_id) REFERENCES $tableSourceDocuments(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE $tableAiGenerationTasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        task_type TEXT NOT NULL,
        input_text TEXT NOT NULL,
        prompt_template TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        provider TEXT NOT NULL DEFAULT 'MiniMax-2.7',
        result_text TEXT,
        error_message TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        completed_at TEXT,
        FOREIGN KEY(document_id) REFERENCES $tableSourceDocuments(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE $tableKnowledgeCards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(document_id) REFERENCES $tableSourceDocuments(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE $tableReviewOutlines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        outline_text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(document_id) REFERENCES $tableSourceDocuments(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE $tableMindmapTexts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        mindmap_text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(document_id) REFERENCES $tableSourceDocuments(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE $tablePracticeQuestions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        question_text TEXT NOT NULL,
        answer_text TEXT,
        analysis_text TEXT,
        difficulty TEXT,
        review_status TEXT NOT NULL DEFAULT 'pending',
        last_user_answer TEXT,
        last_reviewed_at TEXT,
        wrong_count INTEGER NOT NULL DEFAULT 0,
        next_review_at TEXT,
        mastery_score INTEGER NOT NULL DEFAULT 0,
        review_interval_days INTEGER NOT NULL DEFAULT 0,
        correct_streak INTEGER NOT NULL DEFAULT 0,
        parent_question_id INTEGER,
        question_kind TEXT NOT NULL DEFAULT 'normal',
        created_at TEXT NOT NULL,
        FOREIGN KEY(document_id) REFERENCES $tableSourceDocuments(id) ON DELETE CASCADE,
        FOREIGN KEY(parent_question_id) REFERENCES $tablePracticeQuestions(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE $tableLlmProviderConfigs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL UNIQUE,
        provider TEXT NOT NULL DEFAULT 'minimax',
        api_mode TEXT NOT NULL DEFAULT 'token_plan',
        api_key TEXT NOT NULL,
        base_url TEXT,
        model TEXT,
        max_tokens INTEGER NOT NULL DEFAULT 4096,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE $tableWrongQuestionExplanations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        practice_question_id INTEGER NOT NULL,
        user_answer TEXT,
        correct_answer TEXT,
        explanation_text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(practice_question_id) REFERENCES $tablePracticeQuestions(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE $tableWrongQuestionTrainings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        wrong_question_id INTEGER NOT NULL,
        cause_tags_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        completed_at TEXT,
        FOREIGN KEY(wrong_question_id) REFERENCES $tablePracticeQuestions(id) ON DELETE CASCADE
      );
    ''');

    await db.execute(
      'CREATE INDEX idx_users_username ON $tableUsers(username);',
    );
    await db.execute(
      'CREATE INDEX idx_sessions_user_id ON $tableAuthSessions(user_id);',
    );
    await db.execute(
      'CREATE INDEX idx_libraries_user_id ON $tableKnowledgeLibraries(user_id);',
    );
    await db.execute(
      'CREATE INDEX idx_document_batches_user_id ON $tableDocumentBatches(user_id);',
    );
    await db.execute(
      'CREATE INDEX idx_document_batches_library_id ON $tableDocumentBatches(library_id);',
    );
    await db.execute(
      'CREATE INDEX idx_documents_user_id ON $tableSourceDocuments(user_id);',
    );
    await db.execute(
      'CREATE INDEX idx_documents_library_id ON $tableSourceDocuments(library_id);',
    );
    await db.execute(
      'CREATE INDEX idx_documents_batch_id ON $tableSourceDocuments(batch_id);',
    );
    await db.execute(
      'CREATE INDEX idx_documents_ocr_status ON $tableSourceDocuments(ocr_status);',
    );
    await db.execute(
      'CREATE INDEX idx_ai_tasks_document_id ON $tableAiGenerationTasks(document_id);',
    );
    await db.execute(
      'CREATE INDEX idx_ai_tasks_status ON $tableAiGenerationTasks(status);',
    );
    await db.execute(
      'CREATE INDEX idx_practice_document_id ON $tablePracticeQuestions(document_id);',
    );
    await db.execute(
      'CREATE INDEX idx_practice_review_status ON $tablePracticeQuestions(review_status);',
    );
    await db.execute(
      'CREATE INDEX idx_practice_next_review_at ON $tablePracticeQuestions(next_review_at);',
    );
    await db.execute(
      'CREATE INDEX idx_practice_parent_question_id ON $tablePracticeQuestions(parent_question_id);',
    );
    await db.execute(
      'CREATE INDEX idx_wrong_question_trainings_question_id ON $tableWrongQuestionTrainings(wrong_question_id);',
    );
    await db.execute(
      'CREATE INDEX idx_wrong_question_trainings_status ON $tableWrongQuestionTrainings(status);',
    );
    await db.execute(
      'CREATE INDEX idx_llm_configs_user_id ON $tableLlmProviderConfigs(user_id);',
    );
  }

  Future<void> _upgradeTables(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _upgradeUsersToV2(db);
    }
    if (oldVersion < 3) {
      await _upgradeUsersToV3(db);
    }
    if (oldVersion < 4) {
      await _upgradeSourceDocumentsToV4(db);
    }
    if (oldVersion < 5) {
      await _upgradeAiTasksAndOcrTextsToV5(db);
    }
    if (oldVersion < 6) {
      await _upgradeLlmConfigsToV6(db);
    }
    if (oldVersion < 7) {
      await _upgradePracticeQuestionsToV7(db);
    }
    if (oldVersion < 8) {
      await _upgradeDocumentBatchesToV8(db);
    }
    if (oldVersion < 9) {
      await _upgradePracticeSchedulingToV9(db);
    }
  }

  Future<void> _upgradeUsersToV2(Database db) async {
    await _addColumnIfMissing(db, tableUsers, 'display_name', 'TEXT');
    await _addColumnIfMissing(db, tableUsers, 'bio', 'TEXT');
    await _addColumnIfMissing(db, tableUsers, 'gender', 'TEXT');
    await _addColumnIfMissing(db, tableUsers, 'age', 'INTEGER');
    await _addColumnIfMissing(db, tableUsers, 'avatar_style', 'TEXT');
    await _addColumnIfMissing(db, tableUsers, 'background_style', 'TEXT');
  }

  Future<void> _upgradeUsersToV3(Database db) async {
    await _addColumnIfMissing(db, tableUsers, 'avatar_image_path', 'TEXT');
    await _addColumnIfMissing(db, tableUsers, 'background_image_path', 'TEXT');
  }

  Future<void> _upgradeSourceDocumentsToV4(Database db) async {
    await _addColumnIfMissing(
      db,
      tableSourceDocuments,
      'ocr_status',
      "TEXT NOT NULL DEFAULT 'pending'",
    );
    await _addColumnIfMissing(
      db,
      tableSourceDocuments,
      'ocr_error_message',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      tableSourceDocuments,
      'ocr_updated_at',
      'TEXT',
    );

    await db.execute('''
      UPDATE $tableSourceDocuments
      SET ocr_status = 'pending'
      WHERE ocr_status IS NULL OR TRIM(ocr_status) = '';
      ''');

    await db.execute('''
      UPDATE $tableSourceDocuments
      SET
        ocr_status = 'success',
        ocr_updated_at = COALESCE(ocr_updated_at, created_at)
      WHERE id IN (SELECT document_id FROM $tableOcrTexts);
      ''');
  }

  Future<void> _upgradeAiTasksAndOcrTextsToV5(Database db) async {
    await _addColumnIfMissing(db, tableOcrTexts, 'updated_at', 'TEXT');
    await db.execute('''
      UPDATE $tableOcrTexts
      SET updated_at = COALESCE(updated_at, created_at)
      WHERE updated_at IS NULL OR TRIM(updated_at) = '';
      ''');

    await _addColumnIfMissing(
      db,
      tableAiGenerationTasks,
      'error_message',
      'TEXT',
    );
    await _addColumnIfMissing(db, tableAiGenerationTasks, 'updated_at', 'TEXT');
    await db.execute('''
      UPDATE $tableAiGenerationTasks
      SET updated_at = COALESCE(updated_at, created_at)
      WHERE updated_at IS NULL OR TRIM(updated_at) = '';
      ''');
  }

  Future<void> _upgradeLlmConfigsToV6(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableLlmProviderConfigs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL UNIQUE,
        provider TEXT NOT NULL DEFAULT 'minimax',
        api_mode TEXT NOT NULL DEFAULT 'token_plan',
        api_key TEXT NOT NULL,
        base_url TEXT,
        model TEXT,
        max_tokens INTEGER NOT NULL DEFAULT 4096,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
      );
    ''');

    await _addColumnIfMissing(
      db,
      tableLlmProviderConfigs,
      'provider',
      "TEXT NOT NULL DEFAULT 'minimax'",
    );
    await _addColumnIfMissing(
      db,
      tableLlmProviderConfigs,
      'api_mode',
      "TEXT NOT NULL DEFAULT 'token_plan'",
    );
    await _addColumnIfMissing(db, tableLlmProviderConfigs, 'base_url', 'TEXT');
    await _addColumnIfMissing(db, tableLlmProviderConfigs, 'model', 'TEXT');
    await _addColumnIfMissing(
      db,
      tableLlmProviderConfigs,
      'max_tokens',
      'INTEGER NOT NULL DEFAULT 4096',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_llm_configs_user_id ON $tableLlmProviderConfigs(user_id);',
    );
  }

  Future<void> _upgradePracticeQuestionsToV7(Database db) async {
    if (!await _tableExists(db, tablePracticeQuestions)) {
      return;
    }

    await _addColumnIfMissing(
      db,
      tablePracticeQuestions,
      'review_status',
      "TEXT NOT NULL DEFAULT 'pending'",
    );
    await _addColumnIfMissing(
      db,
      tablePracticeQuestions,
      'last_user_answer',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      tablePracticeQuestions,
      'last_reviewed_at',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      tablePracticeQuestions,
      'wrong_count',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('''
      UPDATE $tablePracticeQuestions
      SET review_status = 'pending'
      WHERE review_status IS NULL OR TRIM(review_status) = '';
      ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_practice_review_status ON $tablePracticeQuestions(review_status);',
    );
  }

  Future<void> _upgradeDocumentBatchesToV8(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableDocumentBatches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        library_id INTEGER,
        source_type TEXT NOT NULL,
        title TEXT NOT NULL,
        original_file_path TEXT,
        page_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE,
        FOREIGN KEY(library_id) REFERENCES $tableKnowledgeLibraries(id) ON DELETE CASCADE
      );
    ''');

    if (await _tableExists(db, tableSourceDocuments)) {
      await _addColumnIfMissing(
        db,
        tableSourceDocuments,
        'batch_id',
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        tableSourceDocuments,
        'page_number',
        'INTEGER',
      );
    }

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_document_batches_user_id ON $tableDocumentBatches(user_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_document_batches_library_id ON $tableDocumentBatches(library_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_documents_batch_id ON $tableSourceDocuments(batch_id);',
    );
  }

  Future<void> _upgradePracticeSchedulingToV9(Database db) async {
    if (!await _tableExists(db, tablePracticeQuestions)) {
      return;
    }

    await _addColumnIfMissing(
      db,
      tablePracticeQuestions,
      'next_review_at',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      tablePracticeQuestions,
      'mastery_score',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      tablePracticeQuestions,
      'review_interval_days',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      tablePracticeQuestions,
      'correct_streak',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      tablePracticeQuestions,
      'parent_question_id',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      tablePracticeQuestions,
      'question_kind',
      "TEXT NOT NULL DEFAULT 'normal'",
    );

    final now = DateTime.now().toUtc();
    final nowText = now.toIso8601String();
    final masteredReviewText = now
        .add(const Duration(days: 30))
        .toIso8601String();
    await db.rawUpdate(
      '''
      UPDATE $tablePracticeQuestions
      SET next_review_at = CASE
            WHEN review_status = 'mastered' THEN ?
            ELSE ?
          END,
          mastery_score = CASE
            WHEN review_status = 'mastered' THEN 100
            WHEN review_status = 'wrong' THEN 20
            ELSE 0
          END,
          review_interval_days = CASE
            WHEN review_status = 'mastered' THEN 30
            ELSE 0
          END,
          question_kind = 'normal'
      WHERE next_review_at IS NULL
         OR TRIM(next_review_at) = ''
         OR question_kind IS NULL
         OR TRIM(question_kind) = '';
      ''',
      [masteredReviewText, nowText],
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableWrongQuestionTrainings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        wrong_question_id INTEGER NOT NULL,
        cause_tags_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        completed_at TEXT,
        FOREIGN KEY(wrong_question_id) REFERENCES $tablePracticeQuestions(id) ON DELETE CASCADE
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_practice_next_review_at ON $tablePracticeQuestions(next_review_at);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_practice_parent_question_id ON $tablePracticeQuestions(parent_question_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_wrong_question_trainings_question_id ON $tableWrongQuestionTrainings(wrong_question_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_wrong_question_trainings_status ON $tableWrongQuestionTrainings(status);',
    );
  }

  // 兼容历史版本中“版本号已升级但列缺失”的异常状态，启动时自动补齐。
  Future<void> _ensureSchemaConsistency(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableKnowledgeLibraries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_libraries_user_id ON $tableKnowledgeLibraries(user_id);',
    );
    if (await _tableExists(db, tableUsers)) {
      final now = DateTime.now().toUtc().toIso8601String();
      await db.rawInsert(
        '''
        INSERT INTO $tableKnowledgeLibraries (
          user_id,
          name,
          description,
          created_at,
          updated_at
        )
        SELECT
          users.id,
          '默认知识库',
          '系统为用户自动创建的默认知识库',
          ?,
          ?
        FROM $tableUsers users
        WHERE NOT EXISTS (
          SELECT 1
          FROM $tableKnowledgeLibraries libraries
          WHERE libraries.user_id = users.id
        );
        ''',
        [now, now],
      );
    }

    if (await _tableExists(db, tableSourceDocuments)) {
      await _addColumnIfMissing(
        db,
        tableSourceDocuments,
        'library_id',
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        tableSourceDocuments,
        'batch_id',
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        tableSourceDocuments,
        'page_number',
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        tableSourceDocuments,
        'ocr_status',
        "TEXT NOT NULL DEFAULT 'pending'",
      );
      await _addColumnIfMissing(
        db,
        tableSourceDocuments,
        'ocr_error_message',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        tableSourceDocuments,
        'ocr_updated_at',
        'TEXT',
      );

      await db.execute('''
        UPDATE $tableSourceDocuments
        SET ocr_status = 'pending'
        WHERE ocr_status IS NULL OR TRIM(ocr_status) = '';
        ''');

      if (await _tableExists(db, tableOcrTexts)) {
        await db.execute('''
          UPDATE $tableSourceDocuments
          SET
            ocr_status = 'success',
            ocr_updated_at = COALESCE(ocr_updated_at, created_at)
          WHERE id IN (SELECT document_id FROM $tableOcrTexts);
          ''');
      }

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_documents_ocr_status ON $tableSourceDocuments(ocr_status);',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_documents_library_id ON $tableSourceDocuments(library_id);',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_documents_batch_id ON $tableSourceDocuments(batch_id);',
      );
      await db.execute('''
        UPDATE $tableSourceDocuments
        SET library_id = (
          SELECT libraries.id
          FROM $tableKnowledgeLibraries libraries
          WHERE libraries.user_id = $tableSourceDocuments.user_id
          ORDER BY libraries.id ASC
          LIMIT 1
        )
        WHERE library_id IS NULL
          OR NOT EXISTS (
            SELECT 1
            FROM $tableKnowledgeLibraries libraries
            WHERE libraries.id = $tableSourceDocuments.library_id
              AND libraries.user_id = $tableSourceDocuments.user_id
          );
        ''');
    }

    if (await _tableExists(db, tableOcrTexts)) {
      await _addColumnIfMissing(db, tableOcrTexts, 'updated_at', 'TEXT');
      await db.execute('''
        UPDATE $tableOcrTexts
        SET updated_at = COALESCE(updated_at, created_at)
        WHERE updated_at IS NULL OR TRIM(updated_at) = '';
        ''');
    }

    if (await _tableExists(db, tableAiGenerationTasks)) {
      await _addColumnIfMissing(
        db,
        tableAiGenerationTasks,
        'error_message',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        tableAiGenerationTasks,
        'updated_at',
        'TEXT',
      );
      await db.execute('''
        UPDATE $tableAiGenerationTasks
        SET updated_at = COALESCE(updated_at, created_at)
        WHERE updated_at IS NULL OR TRIM(updated_at) = '';
        ''');

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ai_tasks_status ON $tableAiGenerationTasks(status);',
      );
    }

    await _upgradeDocumentBatchesToV8(db);
    await _upgradeLlmConfigsToV6(db);
    await _upgradePracticeQuestionsToV7(db);
    await _upgradePracticeSchedulingToV9(db);
  }

  Future<bool> _tableExists(Database db, String tableName) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;",
      [tableName],
    );

    return rows.isNotEmpty;
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String tableName,
    String columnName,
    String definition,
  ) async {
    final tableInfo = await db.rawQuery('PRAGMA table_info($tableName);');
    final hasColumn = tableInfo.any((row) => row['name'] == columnName);

    if (!hasColumn) {
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN $columnName $definition;',
      );
    }
  }
}
