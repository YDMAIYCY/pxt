-- Schema captured from HEAD before the phase 0-3 migration - no user data.
CREATE TABLE users (
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

CREATE TABLE auth_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        session_token TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        expired_at TEXT,
        logged_out_at TEXT,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

CREATE TABLE knowledge_libraries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

CREATE TABLE document_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        library_id INTEGER,
        source_type TEXT NOT NULL,
        title TEXT NOT NULL,
        original_file_path TEXT,
        page_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(library_id) REFERENCES knowledge_libraries(id) ON DELETE CASCADE
      );

CREATE TABLE source_documents (
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
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(library_id) REFERENCES knowledge_libraries(id) ON DELETE CASCADE,
        FOREIGN KEY(batch_id) REFERENCES document_batches(id) ON DELETE CASCADE
      );

CREATE TABLE ocr_texts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL UNIQUE,
        raw_text TEXT NOT NULL,
        clean_text TEXT,
        final_text TEXT,
        quality_score INTEGER,
        quality_level TEXT,
        quality_reasons_json TEXT,
        language TEXT NOT NULL DEFAULT 'zh-CN',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(document_id) REFERENCES source_documents(id) ON DELETE CASCADE
      );

CREATE TABLE ai_generation_tasks (
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
        FOREIGN KEY(document_id) REFERENCES source_documents(id) ON DELETE CASCADE
      );

CREATE TABLE knowledge_cards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(document_id) REFERENCES source_documents(id) ON DELETE CASCADE
      );

CREATE TABLE review_outlines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        outline_text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(document_id) REFERENCES source_documents(id) ON DELETE CASCADE
      );

CREATE TABLE mindmap_texts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        mindmap_text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(document_id) REFERENCES source_documents(id) ON DELETE CASCADE
      );

CREATE TABLE practice_questions (
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
        options_json TEXT,
        rubric_json TEXT,
        expected_keywords_json TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(document_id) REFERENCES source_documents(id) ON DELETE CASCADE,
        FOREIGN KEY(parent_question_id) REFERENCES practice_questions(id) ON DELETE CASCADE
      );

CREATE TABLE llm_provider_configs (
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
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

CREATE TABLE wrong_question_explanations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        practice_question_id INTEGER NOT NULL,
        user_answer TEXT,
        correct_answer TEXT,
        explanation_text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(practice_question_id) REFERENCES practice_questions(id) ON DELETE CASCADE
      );

CREATE TABLE wrong_question_trainings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        wrong_question_id INTEGER NOT NULL,
        cause_tags_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        completed_at TEXT,
        FOREIGN KEY(wrong_question_id) REFERENCES practice_questions(id) ON DELETE CASCADE
      );

CREATE TABLE ai_chat_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        last_message_preview TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

CREATE TABLE ai_chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        provider TEXT,
        model TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(session_id) REFERENCES ai_chat_sessions(id) ON DELETE CASCADE
      );

CREATE TABLE IF NOT EXISTS pomodoro_tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        estimated_pomodoros INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

CREATE TABLE IF NOT EXISTS pomodoro_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        task_id INTEGER NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        completed INTEGER NOT NULL DEFAULT 0,
        pomodoro_mode TEXT NOT NULL DEFAULT '正向',
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(task_id) REFERENCES pomodoro_tasks(id) ON DELETE CASCADE
      );

CREATE TABLE IF NOT EXISTS checkin_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        study_seconds INTEGER NOT NULL DEFAULT 0,
        pomodoro_count INTEGER NOT NULL DEFAULT 0,
        points_earned INTEGER NOT NULL DEFAULT 0,
        is_makeup INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

CREATE TABLE IF NOT EXISTS knowledge_concepts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        library_id INTEGER,
        document_id INTEGER,
        name TEXT NOT NULL,
        summary TEXT,
        evidence_text TEXT,
        source_type TEXT NOT NULL DEFAULT 'generated',
        source_id INTEGER,
        mastery_score INTEGER NOT NULL DEFAULT 0,
        weakness_score INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(library_id) REFERENCES knowledge_libraries(id) ON DELETE CASCADE,
        FOREIGN KEY(document_id) REFERENCES source_documents(id) ON DELETE CASCADE
      );

CREATE TABLE IF NOT EXISTS knowledge_concept_links (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        library_id INTEGER,
        from_concept_id INTEGER NOT NULL,
        to_concept_id INTEGER NOT NULL,
        relation_label TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(library_id) REFERENCES knowledge_libraries(id) ON DELETE CASCADE,
        FOREIGN KEY(from_concept_id) REFERENCES knowledge_concepts(id) ON DELETE CASCADE,
        FOREIGN KEY(to_concept_id) REFERENCES knowledge_concepts(id) ON DELETE CASCADE
      );

CREATE TABLE IF NOT EXISTS favorites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        target_type TEXT NOT NULL,
        target_id INTEGER NOT NULL,
        note TEXT,
        highlight_text TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(user_id, target_type, target_id),
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );

CREATE TABLE IF NOT EXISTS document_library_links (
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    library_id INTEGER NOT NULL REFERENCES knowledge_libraries(id) ON DELETE CASCADE,
    PRIMARY KEY(document_id, library_id)
  );

CREATE TABLE IF NOT EXISTS concept_documents (
    concept_id INTEGER NOT NULL REFERENCES knowledge_concepts(id) ON DELETE CASCADE,
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    PRIMARY KEY(concept_id, document_id)
  );

CREATE TABLE IF NOT EXISTS learning_resources (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    concept_id INTEGER REFERENCES knowledge_concepts(id) ON DELETE SET NULL,
    type TEXT NOT NULL, title TEXT NOT NULL, content TEXT NOT NULL,
    input_fingerprint TEXT NOT NULL, model TEXT NOT NULL,
    version INTEGER NOT NULL, created_at TEXT NOT NULL,
    UNIQUE(document_id, type, version)
  );

CREATE TABLE IF NOT EXISTS question_concepts (
    question_id INTEGER NOT NULL REFERENCES practice_questions(id) ON DELETE CASCADE,
    concept_id INTEGER NOT NULL REFERENCES knowledge_concepts(id) ON DELETE CASCADE,
    PRIMARY KEY(question_id, concept_id)
  );

CREATE TABLE IF NOT EXISTS learning_errors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    concept_id INTEGER REFERENCES knowledge_concepts(id) ON DELETE SET NULL,
    question_id INTEGER REFERENCES practice_questions(id) ON DELETE SET NULL,
    origin TEXT NOT NULL, prompt TEXT NOT NULL, answer TEXT NOT NULL,
    correction TEXT NOT NULL, resolved INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
  );

CREATE TABLE IF NOT EXISTS learning_attempts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    concept_id INTEGER REFERENCES knowledge_concepts(id) ON DELETE SET NULL,
    question_id INTEGER REFERENCES practice_questions(id) ON DELETE SET NULL,
    origin TEXT NOT NULL, prompt TEXT NOT NULL, answer TEXT NOT NULL,
    score INTEGER NOT NULL, feedback TEXT NOT NULL, created_at TEXT NOT NULL
  );

CREATE TABLE IF NOT EXISTS flashcard_reviews (
    resource_id INTEGER NOT NULL REFERENCES learning_resources(id) ON DELETE CASCADE,
    card_index INTEGER NOT NULL, interval_days INTEGER NOT NULL DEFAULT 0,
    rating INTEGER NOT NULL DEFAULT 0, next_review_at TEXT NOT NULL,
    PRIMARY KEY(resource_id, card_index)
  );

CREATE TABLE IF NOT EXISTS image_understandings (
    document_id INTEGER PRIMARY KEY REFERENCES source_documents(id) ON DELETE CASCADE,
    content TEXT NOT NULL, model TEXT NOT NULL, created_at TEXT NOT NULL
  );
