import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String databaseName = 'paixuetong.db';
  static const int databaseVersion = 1;

  static const String tableUsers = 'users';
  static const String tableAuthSessions = 'auth_sessions';
  static const String tableKnowledgeLibraries = 'knowledge_libraries';
  static const String tableSourceDocuments = 'source_documents';
  static const String tableOcrTexts = 'ocr_texts';
  static const String tableAiGenerationTasks = 'ai_generation_tasks';
  static const String tableKnowledgeCards = 'knowledge_cards';
  static const String tableReviewOutlines = 'review_outlines';
  static const String tableMindmapTexts = 'mindmap_texts';
  static const String tablePracticeQuestions = 'practice_questions';
  static const String tableWrongQuestionExplanations =
      'wrong_question_explanations';

  Database? _database;

  Future<Database> get database async {
    _database ??= await _open();
    return _database!;
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
    );
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableUsers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        password_salt TEXT NOT NULL,
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
      CREATE TABLE $tableSourceDocuments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        library_id INTEGER,
        source_type TEXT NOT NULL,
        image_path TEXT NOT NULL,
        original_title TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE,
        FOREIGN KEY(library_id) REFERENCES $tableKnowledgeLibraries(id) ON DELETE SET NULL
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
        created_at TEXT NOT NULL,
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
        created_at TEXT NOT NULL,
        FOREIGN KEY(document_id) REFERENCES $tableSourceDocuments(id) ON DELETE CASCADE
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
      'CREATE INDEX idx_documents_user_id ON $tableSourceDocuments(user_id);',
    );
    await db.execute(
      'CREATE INDEX idx_ai_tasks_document_id ON $tableAiGenerationTasks(document_id);',
    );
    await db.execute(
      'CREATE INDEX idx_practice_document_id ON $tablePracticeQuestions(document_id);',
    );
  }
}
