CREATE TABLE android_metadata (locale TEXT);
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
        FOREIGN KEY(library_id) REFERENCES knowledge_libraries(id) ON DELETE SET NULL
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
        created_at TEXT NOT NULL, import_record_id INTEGER REFERENCES import_records(id) ON DELETE CASCADE, original_file_path TEXT, file_page_number INTEGER,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(library_id) REFERENCES knowledge_libraries(id) ON DELETE SET NULL,
        FOREIGN KEY(batch_id) REFERENCES document_batches(id) ON DELETE CASCADE
      );
CREATE TABLE ocr_texts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL UNIQUE,
        raw_text TEXT NOT NULL,
        clean_text TEXT,
        language TEXT NOT NULL DEFAULT 'zh-CN',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL, final_text TEXT, quality_score INTEGER, quality_level TEXT, quality_reasons_json TEXT,
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
        created_at TEXT NOT NULL, options_json TEXT, rubric_json TEXT, expected_keywords_json TEXT, source_version_id INTEGER REFERENCES record_source_versions(id) ON DELETE SET NULL,
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
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_sessions_user_id ON auth_sessions(user_id);
CREATE INDEX idx_libraries_user_id ON knowledge_libraries(user_id);
CREATE INDEX idx_document_batches_user_id ON document_batches(user_id);
CREATE INDEX idx_document_batches_library_id ON document_batches(library_id);
CREATE INDEX idx_documents_user_id ON source_documents(user_id);
CREATE INDEX idx_documents_library_id ON source_documents(library_id);
CREATE INDEX idx_documents_batch_id ON source_documents(batch_id);
CREATE INDEX idx_documents_ocr_status ON source_documents(ocr_status);
CREATE INDEX idx_ai_tasks_document_id ON ai_generation_tasks(document_id);
CREATE INDEX idx_ai_tasks_status ON ai_generation_tasks(status);
CREATE INDEX idx_practice_document_id ON practice_questions(document_id);
CREATE INDEX idx_practice_review_status ON practice_questions(review_status);
CREATE INDEX idx_practice_next_review_at ON practice_questions(next_review_at);
CREATE INDEX idx_practice_parent_question_id ON practice_questions(parent_question_id);
CREATE INDEX idx_wrong_question_trainings_question_id ON wrong_question_trainings(wrong_question_id);
CREATE INDEX idx_wrong_question_trainings_status ON wrong_question_trainings(status);
CREATE INDEX idx_llm_configs_user_id ON llm_provider_configs(user_id);
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
CREATE INDEX idx_ai_chat_sessions_user_id ON ai_chat_sessions(user_id);
CREATE INDEX idx_ai_chat_sessions_updated_at ON ai_chat_sessions(updated_at);
CREATE INDEX idx_ai_chat_messages_session_id ON ai_chat_messages(session_id);
CREATE INDEX idx_ai_chat_messages_created_at ON ai_chat_messages(created_at);
CREATE TABLE pomodoro_tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        estimated_pomodoros INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );
CREATE TABLE pomodoro_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        task_id INTEGER NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        completed INTEGER NOT NULL DEFAULT 0,
        pomodoro_mode TEXT NOT NULL DEFAULT '25/5',
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(task_id) REFERENCES pomodoro_tasks(id) ON DELETE CASCADE
      );
CREATE TABLE checkin_records (
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
CREATE INDEX idx_pomodoro_tasks_user_id ON pomodoro_tasks(user_id);
CREATE INDEX idx_pomodoro_records_user_id ON pomodoro_records(user_id);
CREATE INDEX idx_pomodoro_records_task_id ON pomodoro_records(task_id);
CREATE INDEX idx_pomodoro_records_started_at ON pomodoro_records(started_at);
CREATE INDEX idx_checkin_records_user_id ON checkin_records(user_id);
CREATE INDEX idx_checkin_records_date ON checkin_records(date);
CREATE TABLE knowledge_concepts (
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
CREATE TABLE knowledge_concept_links (
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
CREATE INDEX idx_knowledge_concepts_user_id ON knowledge_concepts(user_id);
CREATE INDEX idx_knowledge_concepts_library_id ON knowledge_concepts(library_id);
CREATE INDEX idx_knowledge_concepts_document_id ON knowledge_concepts(document_id);
CREATE INDEX idx_knowledge_concepts_weakness_score ON knowledge_concepts(weakness_score);
CREATE INDEX idx_knowledge_links_library_id ON knowledge_concept_links(library_id);
CREATE INDEX idx_knowledge_links_from_concept ON knowledge_concept_links(from_concept_id);
CREATE TABLE favorites (
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
CREATE INDEX idx_favorites_user_type ON favorites(user_id, target_type);
CREATE INDEX idx_favorites_target ON favorites(target_type, target_id);
CREATE TABLE document_library_links (
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    library_id INTEGER NOT NULL REFERENCES knowledge_libraries(id) ON DELETE CASCADE,
    PRIMARY KEY(document_id, library_id)
  );
CREATE TABLE concept_documents (
    concept_id INTEGER NOT NULL REFERENCES knowledge_concepts(id) ON DELETE CASCADE,
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    PRIMARY KEY(concept_id, document_id)
  );
CREATE TABLE learning_resources (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    concept_id INTEGER REFERENCES knowledge_concepts(id) ON DELETE SET NULL,
    type TEXT NOT NULL, title TEXT NOT NULL, content TEXT NOT NULL,
    input_fingerprint TEXT NOT NULL, model TEXT NOT NULL,
    version INTEGER NOT NULL, created_at TEXT NOT NULL, source_version_id INTEGER REFERENCES record_source_versions(id) ON DELETE SET NULL,
    UNIQUE(document_id, type, version)
  );
CREATE TABLE question_concepts (
    question_id INTEGER NOT NULL REFERENCES practice_questions(id) ON DELETE CASCADE,
    concept_id INTEGER NOT NULL REFERENCES knowledge_concepts(id) ON DELETE CASCADE,
    PRIMARY KEY(question_id, concept_id)
  );
CREATE TABLE learning_errors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    concept_id INTEGER REFERENCES knowledge_concepts(id) ON DELETE SET NULL,
    question_id INTEGER REFERENCES practice_questions(id) ON DELETE SET NULL,
    origin TEXT NOT NULL, prompt TEXT NOT NULL, answer TEXT NOT NULL,
    correction TEXT NOT NULL, resolved INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
  , submission_id INTEGER REFERENCES practice_submissions(id) ON DELETE CASCADE);
CREATE TABLE learning_attempts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    concept_id INTEGER REFERENCES knowledge_concepts(id) ON DELETE SET NULL,
    question_id INTEGER REFERENCES practice_questions(id) ON DELETE SET NULL,
    origin TEXT NOT NULL, prompt TEXT NOT NULL, answer TEXT NOT NULL,
    score INTEGER NOT NULL, feedback TEXT NOT NULL, created_at TEXT NOT NULL
  , submission_id INTEGER REFERENCES practice_submissions(id) ON DELETE CASCADE);
CREATE TABLE flashcard_reviews (
    resource_id INTEGER NOT NULL REFERENCES learning_resources(id) ON DELETE CASCADE,
    card_index INTEGER NOT NULL, interval_days INTEGER NOT NULL DEFAULT 0,
    rating INTEGER NOT NULL DEFAULT 0, next_review_at TEXT NOT NULL, fsrs_state_json TEXT,
    PRIMARY KEY(resource_id, card_index)
  );
CREATE TABLE image_understandings (
    document_id INTEGER PRIMARY KEY REFERENCES source_documents(id) ON DELETE CASCADE,
    content TEXT NOT NULL, model TEXT NOT NULL, created_at TEXT NOT NULL
  );
CREATE INDEX idx_resource_document_type ON learning_resources(document_id, type, version);
CREATE INDEX idx_error_user ON learning_errors(user_id, resolved);
CREATE TABLE import_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id INTEGER REFERENCES knowledge_libraries(id) ON DELETE SET NULL,
    operation_id TEXT NOT NULL,
    request_id TEXT,
    title TEXT NOT NULL,
    needs_library_review INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
    UNIQUE(user_id, operation_id), UNIQUE(user_id, request_id)
  );
CREATE INDEX idx_source_record ON source_documents(import_record_id);
CREATE TABLE record_source_versions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_id INTEGER NOT NULL REFERENCES import_records(id) ON DELETE CASCADE,
    fingerprint TEXT NOT NULL, content TEXT NOT NULL, created_at TEXT NOT NULL,
    UNIQUE(record_id, fingerprint)
  );
CREATE TABLE flashcard_review_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    resource_id INTEGER NOT NULL REFERENCES learning_resources(id) ON DELETE CASCADE,
    card_index INTEGER NOT NULL, review_log TEXT NOT NULL, created_at TEXT NOT NULL
  );
CREATE TABLE practice_submissions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    question_id INTEGER NOT NULL REFERENCES practice_questions(id) ON DELETE CASCADE,
    request_id TEXT NOT NULL, answer TEXT NOT NULL,
    correct INTEGER NOT NULL, revision INTEGER NOT NULL DEFAULT 0,
    question_snapshot TEXT NOT NULL,
    source_version_id INTEGER REFERENCES record_source_versions(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL, UNIQUE(user_id, request_id)
  );
CREATE TABLE practice_revisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    submission_id INTEGER NOT NULL REFERENCES practice_submissions(id) ON DELETE CASCADE,
    previous_correct INTEGER NOT NULL, correct INTEGER NOT NULL,
    reason TEXT NOT NULL, created_at TEXT NOT NULL
  );
CREATE INDEX idx_submission_question ON practice_submissions(question_id, created_at);
CREATE TABLE wrong_question_training_versions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    question_id INTEGER NOT NULL REFERENCES practice_questions(id) ON DELETE CASCADE,
    fingerprint TEXT NOT NULL, content TEXT NOT NULL, created_at TEXT NOT NULL,
    UNIQUE(question_id, fingerprint)
  );
