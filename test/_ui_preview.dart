// Dev-only visual harness. Not named *_test.dart on purpose: it must not run
// as part of the suite. Render pages with:
//   flutter test test/_ui_preview.dart
// Output lands in build/ui_preview/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/common/app_assets.dart';
import 'package:pxt1/community/chat_outbox_repository.dart';
import 'package:pxt1/community/cloud_identity_repository.dart';
import 'package:pxt1/community/community_repository.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/agent/qsclaw_agent_service.dart';
import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/document_batch_repository.dart';
import 'package:pxt1/database/favorite_repository.dart';
import 'package:pxt1/database/practice_session_repository.dart';
import 'package:pxt1/database/import_record_repository.dart';
import 'package:pxt1/database/knowledge_graph_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/ocr_text_repository.dart';
import 'package:pxt1/database/models/ai_result_records.dart';
import 'package:pxt1/database/models/import_record.dart';
import 'package:pxt1/database/models/knowledge_library_record.dart';
import 'package:pxt1/database/models/source_document_record.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/focus/repository/focus_repository.dart';
import 'package:pxt1/feishu/feishu_controller.dart';
import 'package:pxt1/learning/learning_task_repository.dart';
import 'package:pxt1/ui/pages/book_library_page.dart';
import 'package:pxt1/ui/pages/community/account_security_page.dart';
import 'package:pxt1/ui/pages/community/community_widgets.dart';
import 'package:pxt1/ui/pages/community/chat_page.dart';
import 'package:pxt1/ui/pages/community/community_page.dart';
import 'package:pxt1/ui/pages/community/publish_question_page.dart';
import 'package:pxt1/ui/pages/community/question_detail_page.dart';
import 'package:pxt1/ui/pages/community/social_pages.dart';
import 'package:pxt1/ui/pages/ai_generation_page.dart';
import 'package:pxt1/ui/pages/document_batch_detail_page.dart';
import 'package:pxt1/ui/pages/document_detail_page.dart';
import 'package:pxt1/ui/pages/feishu_import_confirm_page.dart';
import 'package:pxt1/ui/pages/feishu_job_page.dart';
import 'package:pxt1/ui/pages/feishu_library_detail_page.dart';
import 'package:pxt1/ui/pages/feishu_source_view.dart';
import 'package:pxt1/ui/pages/image_crop_selection_page.dart';
import 'package:pxt1/ui/pages/import_record_detail_page.dart';
import 'package:pxt1/ui/pages/ocr_result_page.dart';
import 'package:pxt1/ui/pages/practice_review_page.dart';
import 'package:pxt1/ui/pages/record_results_page.dart';
import 'package:pxt1/ui/pages/wrong_question_page.dart';
import 'package:pxt1/ui/pages/guide_page.dart';
import 'package:pxt1/ui/pages/interview/interview_prepare_page.dart';
import 'package:pxt1/ui/pages/knowledge_record_list_page.dart';
import 'package:pxt1/ui/pages/library_practice_page.dart';
import 'package:pxt1/ui/pages/login_page.dart';
import 'package:pxt1/ui/pages/qsclaw_agent_page.dart';
import 'package:pxt1/ui/pages/tabs/focus_tab_page.dart';
import 'package:pxt1/ui/pages/tabs/home_tab_page.dart';
import 'package:pxt1/ui/pages/tabs/knowledge_tab_page.dart';
import 'package:pxt1/ui/pages/tabs/profile_tab_page.dart';
import 'package:pxt1/ui/pages/tabs/tasks_tab_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

const double _width = 390;
const double _height = 1500;

/// A realistic phone viewport. Layouts that centre themselves (welcome screens,
/// empty states, the login card) look wrong on the tall 1500 canvas, so the
/// pages that depend on available height are also shot at device size.
const double _deviceHeight = 844;

Future<void> _loadCjkFont() async {
  // The test bundle ships MaterialIcons; without it every icon is a box.
  try {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  } catch (error) {
    // ignore: avoid_print
    print('MaterialIcons load failed: $error');
  }

  // Flutter's test font has no CJK glyphs, so Chinese renders as boxes unless a
  // real font is registered. Best-effort: layout is still judgeable without it.
  for (final path in [
    r'C:\Windows\Fonts\msyh.ttc',
    r'C:\Windows\Fonts\simsun.ttc',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final bytes = await file.readAsBytes();
      final data = ByteData.view(Uint8List.fromList(bytes).buffer);
      // Flutter's test font has no CJK glyphs, so Chinese renders as filled
      // boxes. Register the real font under every family name the app can end
      // up resolving to: the theme family, and the names used by inline
      // `styleFrom(textStyle: ...)` / `DefaultTextStyle` fallbacks, which carry
      // no family and would otherwise fall through to the box font.
      for (final family in [
        'Microsoft YaHei',
        'Roboto',
        'FlutterTest',
        'Ahem',
        'sans-serif',
      ]) {
        final loader = FontLoader(family)..addFont(Future.value(data));
        await loader.load();
      }
      // ignore: avoid_print
      print('loaded CJK font: $path');
      return;
    } catch (error) {
      // ignore: avoid_print
      print('font load failed for $path: $error');
    }
  }
}

/// Registers the loaded CJK family as the theme's font, otherwise Flutter's
/// box-glyph test font renders every character as a filled rectangle.
///
/// Component themes carry their own `textStyle` with a null family, so the
/// text theme alone is not enough — buttons and chips need patching too.
ThemeData _withPreviewFont(ThemeData base) {
  const family = 'Microsoft YaHei';
  TextStyle f(TextStyle? s, {double? size, FontWeight? weight}) =>
      (s ?? const TextStyle()).copyWith(
        fontFamily: family,
        fontSize: size ?? s?.fontSize,
        fontWeight: weight ?? s?.fontWeight,
      );

  WidgetStatePropertyAll<TextStyle?>? button(TextStyle? s) =>
      s == null ? null : WidgetStatePropertyAll(f(s));

  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: family),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: f(base.appBarTheme.titleTextStyle),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        textStyle: button(
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        textStyle: button(
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style?.copyWith(
        textStyle: button(
          const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: f(base.chipTheme.labelStyle),
      secondaryLabelStyle: f(base.chipTheme.secondaryLabelStyle),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      titleTextStyle: f(base.listTileTheme.titleTextStyle),
      subtitleTextStyle: f(base.listTileTheme.subtitleTextStyle),
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelStyle: f(base.tabBarTheme.labelStyle),
      unselectedLabelStyle: f(base.tabBarTheme.unselectedLabelStyle),
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      textStyle: f(base.popupMenuTheme.textStyle),
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      textStyle: f(base.tooltipTheme.textStyle),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      contentTextStyle: f(base.snackBarTheme.contentTextStyle),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late KnowledgeLibraryRecord libraryFixture;
  late int batchId;
  late int documentId;
  late int recordId;
  late PracticeQuestionWithDocument wrongItem;
  late ImportRecord importRecordFixture;
  late SourceDocumentRecord feishuSourceFixture;
  final now = DateTime.now().toUtc();

  setUpAll(() async {
    await _loadCjkFont();
  });

  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    await db.insert('users', {
      'id': 1,
      'username': 'ydm',
      'display_name': 'ydm',
      'bio': '记录今天的学习灵感，慢慢长成自己的知识库。',
      'password_hash': 't',
      'password_salt': 't',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await db.insert('auth_sessions', {
      'user_id': 1,
      'session_token': 'fixture',
      'created_at': now.toIso8601String(),
    });

    final libraries = [
      (1, '软件设计模式', 'math', 0xFF5B90FF, 40, 68, 56),
      (2, '数据结构', 'network', 0xFF62BBA0, 30, 42, 32),
      (3, '计算机网络', 'building', 0xFFF2A37D, 25, 75, 28),
    ];
    var conceptId = 0;
    var questionId = 0;
    for (final (id, name, theme, color, concepts, mastery, questions)
        in libraries) {
      await db.insert('knowledge_libraries', {
        'id': id,
        'user_id': 1,
        'name': name,
        'description': '课程资料与练习。',
        'cover_theme': theme,
        'cover_color': color,
        'created_at': now.toIso8601String(),
        'updated_at': now.subtract(Duration(days: id)).toIso8601String(),
      });
      await db.insert('source_documents', {
        'id': id,
        'user_id': 1,
        'library_id': id,
        'source_type': 'gallery_import',
        'image_path': '',
        'original_title': id == 1 ? '设计模式课堂笔记' : '$name 讲义',
        'created_at': now.subtract(Duration(hours: id * 5)).toIso8601String(),
      });
      for (var i = 0; i < concepts; i++) {
        conceptId++;
        await db.insert('knowledge_concepts', {
          'id': conceptId,
          'user_id': 1,
          'library_id': id,
          'document_id': id,
          'name': i == 0 && id == 1 ? '策略模式' : '$name 知识点 ${i + 1}',
          'summary': '核心概念说明。',
          'evidence_text': '证据原文。',
          'mastery_score': mastery,
          'weakness_score': 100 - mastery,
          'created_at': now.toIso8601String(),
          'updated_at': now.subtract(Duration(hours: i)).toIso8601String(),
        });
      }
      for (var i = 0; i < questions; i++) {
        questionId++;
        final wrong = id == 1 && i < 3;
        await db.insert('practice_questions', {
          'id': questionId,
          'document_id': id,
          'question_text': '$name 练习题 ${i + 1}',
          'answer_text': '参考答案',
          'review_status': wrong ? 'wrong' : 'pending',
          'wrong_count': wrong ? 2 : 0,
          'mastery_score': mastery,
          'next_review_at': now
              .add(Duration(days: i < 4 ? -2 : 3))
              .toIso8601String(),
          'created_at': now.toIso8601String(),
        });
      }
    }

    for (final concept in [1, 41]) {
      final question = concept == 1 ? 1 : 60;
      await db.insert('question_concepts', {
        'question_id': question,
        'concept_id': concept,
      });
      await db.insert('practice_submissions', {
        'user_id': 1,
        'question_id': question,
        'request_id': 'req-$question',
        'answer': 'A',
        'correct': 0,
        'question_snapshot': '{}',
        'created_at': now.subtract(const Duration(days: 1)).toIso8601String(),
      });
    }

    await db.insert('pomodoro_tasks', {
      'id': 1,
      'user_id': 1,
      'title': '完成设计模式练习',
      'kind': 'practice',
      'status': 'in_progress',
      'document_id': 1,
      'question_id': 1,
      'focused_seconds': 1800,
      'estimated_pomodoros': 2,
      'created_at': now.toIso8601String(),
    });

    // Fetch here, not inside a testWidgets body: sqflite_common_ffi needs real
    // async I/O, and the widget-test zone is fake-async (it would deadlock).
    libraryFixture = (await KnowledgeLibraryRepository(
      database: app,
    ).fetchLibraries(1)).first;

    // ---- 资料与导入：真实存在的图片、批次、OCR 与生成任务 ----
    // Point documents at a real bundled image, otherwise every document page
    // renders its "资料读取失败" state instead of the layout under review.
    const previewImage = 'assets/images/1.png';
    await db.insert('document_batches', {
      'id': 1,
      'user_id': 1,
      'library_id': 1,
      'source_type': 'pdf',
      'title': '设计模式课堂笔记（扫描版）',
      'original_file_path': previewImage,
      'page_count': 3,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    for (final id in [1, 2, 3]) {
      await db.update(
        'source_documents',
        {
          'batch_id': 1,
          'page_number': id,
          'image_path': previewImage,
          'ocr_status': 'success',
          'ocr_updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    // Give the first nine seeded questions real stems/answers so the AI result
    // section is judged on realistic content, not "xx 练习题 N / 参考答案".
    final stems = <(String, String, String, String)>[
      (
        '策略模式中，把「一组算法」抽象成接口的主要收益是什么？',
        '让算法的变化独立于使用它的客户端，可以在运行时切换行为。',
        '关键在于「变化点」被封装了。调用方只依赖抽象策略，新增算法时不需要修改已有代码，符合开闭原则。',
        '基础',
      ),
      (
        '上下文（Context）为什么通常持有策略接口而不是具体实现？',
        '为了不依赖具体算法类，从而支持任意实现与运行时替换。',
        '持有具体实现会把上下文和某个算法绑死；持有接口只是「知道能力」，解耦才成立。',
        '基础',
      ),
      (
        '下面哪种场景最不适合用策略模式？',
        '算法只有一种且未来几乎不会新增。',
        '策略模式引入了一层抽象。若行为固定不变，多出来的接口和工厂只会增加阅读成本。',
        '中等',
      ),
      (
        '策略对象需要访问上下文内部状态时，应该如何设计？',
        '由上下文把所需数据作为参数传给策略方法，或让上下文实现一个回调接口。',
        '让策略反向持有上下文会造成循环依赖，也难以测试；用参数或回调注入数据更干净。',
        '中等',
      ),
      (
        '简单工厂 + 策略的组合，各自负责什么？',
        '工厂负责「怎么拿到策略」，策略负责「拿到之后怎么切换行为」。',
        '把对象创建与行为选择拆开，调用方既不需要知道实现类，也不需要写 switch。',
        '中等',
      ),
      (
        '如果把策略选择逻辑写进上下文的条件分支里，会有什么问题？',
        '新增策略必须改上下文，违反开闭原则，且分支会不断膨胀。',
        '这就是「策略模式用错位置」的典型症状：行为封装了，但选择逻辑又硬编码回去了。',
        '进阶',
      ),
      (
        '策略模式与状态模式在结构上相似，判断依据是什么？',
        '切换是否由对象自身驱动：状态模式通常由状态自己触发转移，策略多由外部选择。',
        '两者都依赖组合与接口，但意图不同——一个表达「不同算法」，一个表达「对象生命周期中的状态迁移」。',
        '进阶',
      ),
      (
        '策略对象能否做成无状态的单例？',
        '可以，只要策略不保存会话数据，就能共享同一实例。',
        '无状态策略可以安全复用，省去重复创建；一旦持有可变字段就必须每次新建或做隔离。',
        '进阶',
      ),
      (
        '用策略模式重构一段 if-else 时，最需要先确认的是什么？',
        '这些分支是否在描述同一件事的不同算法，且未来还会继续增加。',
        '若分支描述的是互不相关的业务规则，拆成策略只会制造一堆只有几行的类，反而更难维护。',
        '进阶',
      ),
    ];
    // A dedicated 9-question document keeps the results page representative:
    // binding the whole batch would show every seeded question at once.
    await db.insert('source_documents', {
      'id': 90,
      'user_id': 1,
      'library_id': 1,
      'batch_id': 1,
      'page_number': 4,
      'source_type': 'pdf_document',
      'image_path': previewImage,
      'original_title': '策略模式习题与讲解',
      'ocr_status': 'success',
      'ocr_updated_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
    });
    for (final (i, (stem, answer, analysis, difficulty)) in stems.indexed) {
      await db.insert('practice_questions', {
        'id': 900 + i,
        'document_id': 90,
        'question_text': stem,
        'answer_text': answer,
        'analysis_text': analysis,
        'difficulty': difficulty,
        'review_status': i < 3 ? 'wrong' : 'pending',
        'wrong_count': i < 3 ? i + 1 : 0,
        'mastery_score': 40 + i * 5,
        'next_review_at': now
            .add(Duration(days: i < 4 ? -1 : 4))
            .toIso8601String(),
        'created_at': now.toIso8601String(),
      });
    }

    await db.insert('ocr_texts', {
      'document_id': 90,
      'raw_text': '策略模式定义了一组算法，把它们一个个封装起来，并且使它们可互相替换。',
      'clean_text': '策略模式定义了一组算法，把它们一个个封装起来，并且使它们可互相替换。',
      'final_text':
          '策略模式（Strategy）定义了一组算法，把它们一个个封装起来，并且使它们可以互相替换。\n\n它让算法的变化独立于使用它的客户端。',
      'quality_score': 88,
      'quality_level': 'good',
      'language': 'zh-CN',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await db.insert('ai_generation_tasks', {
      'document_id': 90,
      'task_type': 'summary',
      'input_text': '策略模式定义了一组算法……',
      'status': 'completed',
      'provider': 'DeepSeek',
      'result_text': '这一页讲的是策略模式：把一组算法分别封装成类，让它们可以互相替换，'
          '客户端只依赖抽象接口。它解决的是「运行时切换行为」的问题。',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'completed_at': now.toIso8601String(),
    });
    await db.insert('ai_generation_tasks', {
      'document_id': 90,
      'task_type': 'quiz',
      'input_text': '策略模式定义了一组算法……',
      'status': 'completed',
      'provider': 'DeepSeek',
      'result_text': '已生成 9 道练习题。',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'completed_at': now.toIso8601String(),
    });

    // 错题强化训练：一条训练记录 + 三道相似题（其中一道已掌握），这样
    // WrongQuestionPage 渲染的是「有错因、有进度」的真实形态。
    await db.insert('wrong_question_trainings', {
      'wrong_question_id': 900,
      'cause_tags_json': '["概念混淆","忽略边界条件"]',
      'status': 'pending',
      'created_at': now.toIso8601String(),
    });
    for (final (i, text) in [
      '策略模式中，把算法封装成接口后，新增算法需要修改哪一部分？',
      '上下文持有接口与持有实现，哪一种更利于单元测试？',
      '如果策略对象内部保存了上一次的计算结果，会带来什么风险？',
    ].indexed) {
      await db.insert('practice_questions', {
        'id': 800 + i,
        'document_id': 90,
        'parent_question_id': 900,
        'question_text': text,
        'answer_text': '参考答案 ${i + 1}',
        'analysis_text': '解析 ${i + 1}',
        'question_kind': 'similar',
        'difficulty': ['中等', '基础', '进阶'][i],
        'review_status': i == 0 ? 'mastered' : 'pending',
        'mastery_score': i == 0 ? 90 : 40 + i * 10,
        'wrong_count': i == 0 ? 0 : 1,
        'created_at': now.toIso8601String(),
      });
    }

    // 飞书来源：一条 feishu_documents 元信息 + 两个知识点，用来验证
    // FeishuSourceView 的来源信息区和「知识点」tab。
    await db.insert('source_documents', {
      'id': 91,
      'user_id': 1,
      'library_id': 1,
      'source_type': 'feishu_docx',
      'image_path': previewImage,
      'original_title': '登录模块需求说明',
      'ocr_status': 'success',
      'ocr_updated_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
    });
    await db.insert('feishu_documents', {
      'user_id': 1,
      'account_id': 'acc-1',
      'document_id': 'doc-91',
      'source_id': 91,
      'library_id': 1,
      'relative_path': '/产品需求文档/登录模块需求说明.docx',
      'container_type': 'folder',
      'container_id': 'fld-1',
      'node_token': 'nod-1',
      'source_url': 'https://demo.feishu.cn/docx/doc-91',
      'remote_modified_time': '${now.millisecondsSinceEpoch ~/ 1000 - 3600}',
      'revision_id': 12,
      'blocks_json': '['
          '{"block_id":"root","block_type":1,"children":["b1","b2","b3"]},'
          '{"block_id":"b1","block_type":2,"parent_id":"root","text":{"elements":[{"text_run":{"content":"登录模块需求说明","text_element_style":{"bold":true}}}]}},'
          '{"block_id":"b2","block_type":2,"parent_id":"root","text":{"elements":[{"text_run":{"content":"本文档描述登录、注册与第三方授权三条链路的交互与校验规则。"}}]}},'
          '{"block_id":"b3","block_type":2,"parent_id":"root","text":{"elements":[{"text_run":{"content":"手机号验证码登录失败 3 次后，需要图形验证码；账号被锁定时给出解锁入口。"}}]}}'
          ']',
      'content_hash': 'hash-91',
      'synced_at': now.toIso8601String(),
      'knowledge_needs_update': 0,
    });
    for (final (i, (title, content)) in [
      ('登录方式', '支持手机号验证码、密码与第三方授权三种登录方式，优先级依次降低。'),
      ('失败处理', '连续失败 3 次触发图形验证码，5 次锁定 15 分钟并提示解锁入口。'),
    ].indexed) {
      await db.insert('knowledge_cards', {
        'id': 91 + i,
        'document_id': 91,
        'title': title,
        'content': content,
        'created_at': now.toIso8601String(),
      });
    }

    batchId = 1;
    // Document 90 carries the realistic 9-question set plus the OCR text, so
    // document-detail / ocr-result / ai-generation all show representative data.
    documentId = 90;
    // Take a record from `list()` rather than a raw row: only records that
    // actually resolve to documents can be opened by ImportRecordDetailPage.
    recordId = (await ImportRecordRepository(database: app).list(1)).first.id;

    // Bind the documents to that record, otherwise results() joins on
    // `source_documents.import_record_id` and finds nothing.
    await db.update(
      'source_documents',
      {'import_record_id': recordId},
      where: 'id = 90',
    );
    importRecordFixture =
        (await ImportRecordRepository(database: app).get(1, recordId))!;
    wrongItem = (await AiGenerationRepository(
      database: app,
    ).fetchPracticeQuestionByUserAndId(userId: 1, questionId: 900))!;
    feishuSourceFixture = (await SourceDocumentRepository(
      database: app,
    ).getSourceDocumentById(userId: 1, documentId: 91))!;
  });

  tearDown(() async => db.close());

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 22; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget page, {
    bool scrollToBottom = false,
    double height = _height,
    Future<void> Function(WidgetTester tester)? interact,
  }) async {
    await tester.binding.setSurfaceSize(Size(_width, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _withPreviewFont(AppTheme.light),
          home: Scaffold(
            backgroundColor: AppColors.background,
            body: page,
          ),
        ),
      ),
    );
    await flush(tester);

    if (scrollToBottom) {
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isNotEmpty) {
        await tester.drag(scrollable.first, const Offset(0, -900));
        await flush(tester);
      }
    }

    if (interact != null) {
      await interact(tester);
      await tester.pumpAndSettle();
    }

    // toImage must run inside runAsync, otherwise it deadlocks the binding.
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/ui_preview').create(recursive: true);
      await File(
        'build/ui_preview/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    // ignore: avoid_print
    print('rendered build/ui_preview/$name.png');
  }

  /// Community surfaces are judged on a real phone viewport: the 1500 canvas
  /// leaves reversed lists (chat) anchored far below the fold.
  Future<void> shootDevice(
    WidgetTester tester,
    String name,
    Widget page, {
    Future<void> Function(WidgetTester tester)? interact,
  }) => shoot(
    tester,
    name,
    page,
    height: _deviceHeight,
    interact: interact,
  );

  testWidgets('home', (tester) async {
    await shoot(
      tester,
      'home',
      HomeTabPage(
        database: app,
        authRepository: AuthRepository(database: app),
        sourceDocumentRepository: SourceDocumentRepository(database: app),
        knowledgeLibraryRepository: KnowledgeLibraryRepository(database: app),
      ),
    );
  });

  testWidgets('tasks', (tester) async {
    await shoot(
      tester,
      'tasks',
      TasksTabPage(
        authRepository: AuthRepository(database: app),
        sourceDocumentRepository: SourceDocumentRepository(database: app),
        aiGenerationRepository: AiGenerationRepository(database: app),
        learningTaskRepository: LearningTaskRepository(database: app),
      ),
    );
  });

  testWidgets('tasks-scrolled', (tester) async {
    await shoot(
      tester,
      'tasks-scrolled',
      TasksTabPage(
        authRepository: AuthRepository(database: app),
        sourceDocumentRepository: SourceDocumentRepository(database: app),
        aiGenerationRepository: AiGenerationRepository(database: app),
        learningTaskRepository: LearningTaskRepository(database: app),
      ),
      scrollToBottom: true,
    );
  });

  testWidgets('profile', (tester) async {
    await shoot(
      tester,
      'profile',
      ProfileTabPage(
        authRepository: AuthRepository(database: app),
        llmConfigRepository: LlmConfigRepository(database: app),
        aiGenerationRepository: AiGenerationRepository(database: app),
        focusRepository: FocusRepository(database: app),
      ),
    );
  });

  testWidgets('profile-scrolled', (tester) async {
    await shoot(
      tester,
      'profile-scrolled',
      ProfileTabPage(
        authRepository: AuthRepository(database: app),
        llmConfigRepository: LlmConfigRepository(database: app),
        aiGenerationRepository: AiGenerationRepository(database: app),
        focusRepository: FocusRepository(database: app),
      ),
      scrollToBottom: true,
    );
  });

  testWidgets('shelf', (tester) async {
    await shoot(tester, 'shelf', BookLibraryPage(database: app));
  });

  testWidgets('focus', (tester) async {
    await shoot(
      tester,
      'focus',
      FocusTabPage(
        authRepository: AuthRepository(database: app),
        focusRepository: FocusRepository(database: app),
        learningTaskRepository: LearningTaskRepository(database: app),
      ),
    );
  });

  testWidgets('focus-scrolled', (tester) async {
    await shoot(
      tester,
      'focus-scrolled',
      FocusTabPage(
        authRepository: AuthRepository(database: app),
        focusRepository: FocusRepository(database: app),
        learningTaskRepository: LearningTaskRepository(database: app),
      ),
      scrollToBottom: true,
    );
  });

  // ---- Knowledge base interior (the shelf itself is the protected surface;
  // these are the pages reached after opening a book) ----
  testWidgets('book-detail', (tester) async {
    await shoot(
      tester,
      'book-detail',
      BookDetailPage(library: libraryFixture, database: app),
    );
  });

  testWidgets('practice', (tester) async {
    await shoot(
      tester,
      'practice',
      LibraryPracticePage(questionIds: const [1, 2, 3], database: app),
    );
  });

  testWidgets('document-detail', (tester) async {
    await shoot(
      tester,
      'document-detail',
      DocumentDetailPage(
        documentId: documentId,
        authRepository: AuthRepository(database: app),
        sourceDocumentRepository: SourceDocumentRepository(database: app),
        ocrTextRepository: OcrTextRepository(database: app),
        aiGenerationRepository: AiGenerationRepository(database: app),
      ),
    );
  });

  // The collapsed list is the default; this proves the expanded answer block
  // renders correctly (it is the whole point of the redesign).
  testWidgets('document-detail-expanded', (tester) async {
    await shoot(
      tester,
      'document-detail-expanded',
      DocumentDetailPage(
        documentId: documentId,
        authRepository: AuthRepository(database: app),
        sourceDocumentRepository: SourceDocumentRepository(database: app),
        ocrTextRepository: OcrTextRepository(database: app),
        aiGenerationRepository: AiGenerationRepository(database: app),
      ),
      interact: (tester) async {
        final target = find.textContaining('抽象成接口的主要收益').first;
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
      },
    );
  });

  testWidgets('knowledge-legacy', (tester) async {
    await shoot(
      tester,
      'knowledge-legacy',
      KnowledgeTabPage(
        authRepository: AuthRepository(database: app),
        sourceDocumentRepository: SourceDocumentRepository(database: app),
        aiGenerationRepository: AiGenerationRepository(database: app),
        documentBatchRepository: DocumentBatchRepository(database: app),
        knowledgeGraphRepository: KnowledgeGraphRepository(database: app),
        knowledgeLibraryRepository: KnowledgeLibraryRepository(database: app),
      ),
    );
  });

  // ---- EClaw / community / account ----
  testWidgets('eclaw', (tester) async {
    await shoot(
      tester,
      'eclaw',
      QsClawAgentPage(
        authRepository: AuthRepository(database: app),
        agentService: QsClawAgentService(),
        database: app,
      ),
    );
  });

  testWidgets('community', (tester) async {
    await shoot(tester, 'community', CommunityPage(repository: _PreviewCommunity()));
  });

  testWidgets('community-bookmarks', (tester) async {
    await shootDevice(
      tester,
      'community-bookmarks',
      CommunityPage(repository: _PreviewCommunity(), bookmarks: true),
    );
  });

  testWidgets('community-search', (tester) async {
    await shootDevice(
      tester,
      'community-search',
      CommunityPage(repository: _PreviewCommunity(), search: true),
    );
  });

  testWidgets('question-detail', (tester) async {
    await shootDevice(
      tester,
      'question-detail',
      QuestionDetailPage(questionId: 'q-1', repository: _PreviewCommunity()),
    );
  });

  testWidgets('publish-question', (tester) async {
    await shootDevice(
      tester,
      'publish-question',
      PublishQuestionPage(
        initialTitle: '红黑树的删除为什么要分四种情况讨论？',
        initialBody: '插入我还能理解，删除的四种情况记不住，有没有统一的思路可以推导出来？',
        repository: _PreviewCommunity(),
      ),
    );
  });

  testWidgets('community-user', (tester) async {
    await shootDevice(
      tester,
      'community-user',
      CommunityUserPage(userId: 'u-1', repository: _PreviewCommunity()),
    );
  });

  testWidgets('friends-chat', (tester) async {
    await shootDevice(
      tester,
      'friends-chat',
      FriendsChatPage(repository: _PreviewCommunity()),
    );
  });

  testWidgets('user-search', (tester) async {
    await shootDevice(
      tester,
      'user-search',
      UserSearchPage(repository: _PreviewCommunity()),
    );
  });

  testWidgets('learning-notifications', (tester) async {
    await shootDevice(
      tester,
      'learning-notifications',
      LearningNotificationsPage(repository: _PreviewCommunity()),
    );
  });

  testWidgets('chat', (tester) async {
    final repo = _PreviewCommunity();
    await shootDevice(
      tester,
      'chat',
      ChatPage(
        conversationId: 'conv-1',
        repository: repo,
        outbox: _PreviewOutbox(community: repo),
      ),
    );
  });


  // ---- 资料与导入 ----
  testWidgets('document-batch', (tester) async {
    await shootDevice(
      tester,
      'document-batch',
      DocumentBatchDetailPage(
        batchId: batchId,
        authRepository: AuthRepository(database: app),
        documentBatchRepository: DocumentBatchRepository(database: app),
      ),
    );
  });

  testWidgets('import-record', (tester) async {
    await shootDevice(
      tester,
      'import-record',
      ImportRecordDetailPage(
        recordId: recordId,
        userId: 1,
        database: app,
        libraryId: 1,
      ),
    );
  });

  testWidgets('ocr-result', (tester) async {
    await shootDevice(
      tester,
      'ocr-result',
      OcrResultPage(
        documentId: documentId,
        authRepository: AuthRepository(database: app),
        sourceDocumentRepository: SourceDocumentRepository(database: app),
        ocrTextRepository: OcrTextRepository(database: app),
        llmConfigRepository: LlmConfigRepository(database: app),
      ),
    );
  });

  testWidgets('ai-generation', (tester) async {
    await shootDevice(
      tester,
      'ai-generation',
      AiGenerationPage(
        documentId: documentId,
        authRepository: AuthRepository(database: app),
        sourceDocumentRepository: SourceDocumentRepository(database: app),
        ocrTextRepository: OcrTextRepository(database: app),
        aiGenerationRepository: AiGenerationRepository(database: app),
        llmConfigRepository: LlmConfigRepository(database: app),
      ),
    );
  });

  testWidgets('image-crop', (tester) async {
    await shootDevice(
      tester,
      'image-crop',
      const ImageCropSelectionPage(imagePath: 'assets/images/1.png'),
    );
  });

  testWidgets('feishu-library', (tester) async {
    await shootDevice(
      tester,
      'feishu-library',
      FeishuLibraryDetailPage(library: libraryFixture, database: app),
    );
  });

  testWidgets('feishu-source', (tester) async {
    await shootDevice(
      tester,
      'feishu-source',
      FeishuSourceView(source: feishuSourceFixture, database: app),
    );
  });

  testWidgets('feishu-source-cards', (tester) async {
    await shootDevice(
      tester,
      'feishu-source-cards',
      FeishuSourceView(source: feishuSourceFixture, database: app),
      interact: (tester) async {
        await tester.tap(find.textContaining('知识点 2'));
      },
    );
  });

  testWidgets('feishu-job', (tester) async {
    await shootDevice(
      tester,
      'feishu-job',
      FeishuJobPage(controller: FeishuController(userId: 1, database: app)),
    );
  });

  testWidgets('feishu-confirm', (tester) async {
    await shootDevice(
      tester,
      'feishu-confirm',
      FeishuImportConfirmPage(
        controller: FeishuController(userId: 1, database: app),
        roots: const [],
        plan: const {
          'scan_complete': true,
          'errors': <Object>[],
          'covered_selections': <Object>[],
          'roots': [
            {
              'name': '产品需求文档',
              'kind': 'folder',
              'target_library_id': 1,
              'documents': [
                {'title': '登录模块需求说明', 'kind': 'docx', 'relative_path': '/产品需求文档/登录模块需求说明.docx'},
                {'title': '消息中心 PRD', 'kind': 'docx', 'relative_path': '/产品需求文档/消息中心 PRD.docx'},
                {'title': '搜索排序规则', 'kind': 'docx', 'relative_path': '/产品需求文档/搜索排序规则.docx'},
              ],
            },
            {
              'name': '设计模式讲义.docx',
              'kind': 'docx',
              'target_library_id': 1,
              'documents': [
                {'title': '设计模式讲义', 'kind': 'docx', 'relative_path': '/设计模式讲义.docx'},
              ],
            },
          ],
        },
      ),
    );
  });

  // ---- 练习与复习 ----
  testWidgets('practice-review', (tester) async {
    await shootDevice(
      tester,
      'practice-review',
      PracticeReviewPage(
        recordId: recordId,
        authRepository: AuthRepository(database: app),
        aiGenerationRepository: AiGenerationRepository(database: app),
        favoriteRepository: FavoriteRepository(database: app),
      ),
    );
  });

  // 作答提交后的「答案 + 解析」态：这才是这一页的核心信息。
  testWidgets('practice-review-revealed', (tester) async {
    await shootDevice(
      tester,
      'practice-review-revealed',
      PracticeReviewPage(
        recordId: recordId,
        authRepository: AuthRepository(database: app),
        aiGenerationRepository: AiGenerationRepository(database: app),
        favoriteRepository: FavoriteRepository(database: app),
      ),
      interact: (tester) async {
        await tester.enterText(find.byType(TextField).first, '把算法封装起来，让调用方只依赖接口。');
        await tester.pump();
        await tester.ensureVisible(find.text('完成'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('完成'));
      },
    );
  });

  testWidgets('wrong-question', (tester) async {
    await shootDevice(
      tester,
      'wrong-question',
      WrongQuestionPage(
        item: wrongItem,
        recordId: recordId,
        aiGenerationRepository: AiGenerationRepository(database: app),
        authRepository: AuthRepository(database: app),
        llmConfigRepository: LlmConfigRepository(database: app),
      ),
    );
  });

  testWidgets('record-results', (tester) async {
    await shootDevice(
      tester,
      'record-results',
      RecordResultsPage(
        record: importRecordFixture,
        type: 'practice_questions',
        title: '练习题',
        database: app,
      ),
    );
  });

  testWidgets('account-security', (tester) async {
    await shootDevice(
      tester,
      'account-security',
      const AccountSecurityPage(
        profile: UserProfile(
          id: 1,
          username: 'ydm',
          displayName: 'ydm',
          bio: '记录今天的学习灵感，慢慢长成自己的知识库。',
          gender: 'unknown',
          avatarStyle: 'default',
          backgroundStyle: 'default',
        ),
      ),
    );
  });

  testWidgets('login', (tester) async {
    await shoot(tester, 'login', const LoginPage());
  });

  testWidgets('guide', (tester) async {
    await shoot(tester, 'guide', const GuidePage());
  });

  testWidgets('interview-prepare', (tester) async {
    await shoot(
      tester,
      'interview-prepare',
      InterviewPreparePage(userId: 1, database: app),
    );
  });

  testWidgets('favorites', (tester) async {
    await shoot(
      tester,
      'favorites',
      FavoritesPage(userId: 1, favoriteRepository: FavoriteRepository(database: app)),
    );
  });

  testWidgets('favorites-populated', (tester) async {
    final repo = FavoriteRepository(database: app);
    await tester.runAsync(() async {
      await repo.toggleFavorite(userId: 1, targetType: FavoriteTargetType.knowledgeCard, targetId: 91);
      await repo.toggleFavorite(userId: 1, targetType: FavoriteTargetType.practiceQuestion, targetId: 900);
    });
    await shootDevice(tester, 'favorites-populated', FavoritesPage(userId: 1, favoriteRepository: repo));
  });

  testWidgets('favorites-category', (tester) async {
    final repo = FavoriteRepository(database: app);
    final category = (await tester.runAsync(() async {
      await repo.toggleFavorite(userId: 1, targetType: FavoriteTargetType.knowledgeCard, targetId: 91);
      return (await repo.fetchCategorySummaries(1)).first;
    }))!;
    await shootDevice(tester, 'favorites-category', FavoriteCategoryPage(userId: 1, category: category, favoriteRepository: repo));
  });

  testWidgets('scoped-practice-selected', (tester) async {
    final question = (await tester.runAsync(() async {
      await db.update('practice_questions', {'question_kind': 'multiple_choice', 'options_json': '["面向接口编程","依赖具体实现"]', 'answer_text': 'A'}, where: 'id=900');
      return AiGenerationRepository(database: app).fetchPracticeQuestionByUserAndId(userId: 1, questionId: 900);
    }))!;
    await shootDevice(tester, 'scoped-practice-selected', ScopedPracticeRunner(
      scope: const PracticeScope(userId: 1, libraryId: 1), questions: [question], database: app,
    ), interact: (tester) async {
      await tester.tap(find.text('面向接口编程'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'A');
    });
  });

  testWidgets('friends-profile-navigation', (tester) async {
    final repo = _PreviewCommunity();
    await shootDevice(tester, 'friends-profile-navigation', FriendsChatPage(repository: repo), interact: (tester) async {
      await tester.tap(find.byType(CommunityAvatar).first);
      await flush(tester);
      expect(find.byType(CommunityUserPage), findsOneWidget);
    });
  });

  testWidgets('publish-question-keyboard', (tester) async {
    await shootDevice(tester, 'publish-question-keyboard', PublishQuestionPage(repository: _PreviewCommunity()), interact: (tester) async {
      tester.view.viewInsets = FakeViewPadding(bottom: 280 * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.showKeyboard(find.byType(TextField).at(1));
      await tester.pump();
      expect(find.widgetWithText(FilledButton, '发布问题'), findsOneWidget);
      expect(tester.getRect(find.widgetWithText(FilledButton, '发布问题')).bottom, lessThanOrEqualTo(_deviceHeight - 280));
    });
  });

  // Icon sheet for the bottom dock: five tabs must read as one family.
  testWidgets('nav-icons', (tester) async {    const assets = [
      AppAssets.navHome,
      AppAssets.navKnowledge,
      AppAssets.navCommunity,
      AppAssets.navTask,
      AppAssets.navProfile,
    ];
    await shoot(
      tester,
      'nav-icons',
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final a in assets)
                  SvgPicture.asset(
                    a,
                    width: 60,
                    height: 60,
                    colorFilter: const ColorFilter.mode(
                      AppColors.primary,
                      BlendMode.srcIn,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final a in assets)
                  SvgPicture.asset(
                    a,
                    width: 22,
                    height: 22,
                    colorFilter: const ColorFilter.mode(
                      AppColors.textTertiary,
                      BlendMode.srcIn,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  });

  // ---- Device-size shots: these pages centre themselves, so they must be
  // judged on a real phone viewport rather than the tall 1500 canvas. ----
  testWidgets('eclaw@device', (tester) async {
    await shoot(
      tester,
      'eclaw@device',
      QsClawAgentPage(
        authRepository: AuthRepository(database: app),
        agentService: QsClawAgentService(),
        database: app,
      ),
      height: _deviceHeight,
    );
  });

  testWidgets('login@device', (tester) async {
    await shoot(tester, 'login@device', const LoginPage(), height: _deviceHeight);
  });

  testWidgets('guide@device', (tester) async {
    await shoot(tester, 'guide@device', const GuidePage(), height: _deviceHeight);
  });

  testWidgets('favorites@device', (tester) async {
    await shoot(
      tester,
      'favorites@device',
      FavoritesPage(
        userId: 1,
        favoriteRepository: FavoriteRepository(database: app),
      ),
      height: _deviceHeight,
    );
  });

  testWidgets('community@device', (tester) async {
    await shoot(tester, 'community@device', const CommunityPage(), height: _deviceHeight);
  });

  testWidgets('llm-config', (tester) async {
    await shoot(
      tester,
      'llm-config',
      LlmConfigEditPage(
        config: LlmProviderConfig(
          id: 1,
          userId: 1,
          provider: LlmProvider.deepseek,
          apiMode: 'chat_completions',
          apiKey: 'sk-preview-placeholder',
          baseUrl: 'https://api.deepseek.com',
          model: 'deepseek-chat',
          maxTokens: 4096,
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 1),
          displayName: 'DeepSeek',
        ),
      ),
      height: _deviceHeight,
    );
  });
}

/// Minimal deterministic community data for the visual previews. Only the
/// calls the rendered pages actually make are covered — everything else keeps
/// the production behaviour.
class _PreviewCommunity extends CommunityRepository {
  static final _now = DateTime.now();
  static String _ago(int minutes) =>
      _now.subtract(Duration(minutes: minutes)).toIso8601String();

  // The detail page compares this against `author_id` to decide whether to
  // show owner-only actions; without a cloud client the real getter throws.
  @override
  String get uid => 'u-me';

  static const _people = ['陈默', '周舟', '苏禾', '林晓'];

  static Json _author(int i) => {
    'id': 'u-$i',
    'nickname': _people[i % _people.length],
    'avatar_path': null,
  };

  static final List<Json> _feed = [
    {
      'id': 'q-1',
      'author_id': 'u-0',
      'title': '策略模式和简单工厂一起用，到底解决了什么问题？',
      'body': '教材里的例题同时出现策略和工厂，我单独用策略感觉也能跑通。多这一层工厂，收益到底在哪里？',
      'created_at': _ago(26),
      'profile': _author(0),
      'tags': ['设计模式'],
      'image_paths': <String>[],
      'accepted_answer_id': 'a-1',
      'answer_count': 4,
      'bookmark_count': 12,
      'bookmarked': true,
    },
    {
      'id': 'q-2',
      'author_id': 'u-1',
      'title': '红黑树的删除为什么要分四种情况讨论？',
      'body': '插入我还能理解，删除的四种情况记不住，有没有统一的思路可以推导出来？',
      'created_at': _ago(95),
      'profile': _author(1),
      'tags': ['数据结构', '算法'],
      'image_paths': <String>[],
      'accepted_answer_id': null,
      'answer_count': 2,
      'bookmark_count': 5,
      'bookmarked': false,
    },
    {
      'id': 'q-3',
      'author_id': 'u-2',
      'title': 'TCP 三次握手如果最后一次丢了会怎样？',
      'body': '一直没想明白第三次握手丢失时服务端会进入什么状态，会不会一直卡在半连接？',
      'created_at': _ago(180),
      'profile': _author(2),
      'tags': ['计算机网络'],
      'image_paths': <String>[],
      'accepted_answer_id': null,
      'answer_count': 0,
      'bookmark_count': 1,
      'bookmarked': false,
    },
    {
      'id': 'q-4',
      'author_id': 'u-3',
      'title': '考研数学一轮复习，笔记要记多细？',
      'body': '记太细怕时间不够，记太粗又怕后面看不懂，大家一般怎么把握这个度？',
      'created_at': _ago(300),
      'profile': _author(3),
      'tags': ['考研'],
      'image_paths': <String>[],
      'accepted_answer_id': null,
      'answer_count': 0,
      'bookmark_count': 3,
      'bookmarked': true,
    },
  ];

  static final Json _question = {
    'id': 'q-1',
    'author_id': 'u-0',
    'title': '策略模式和简单工厂一起用，到底解决了什么问题？',
    'body':
        '教材里的例题同时出现策略和工厂，我单独用策略感觉也能跑通。\n\n多这一层工厂，收益到底在哪里？',
    'created_at': _ago(26),
    'updated_at': _ago(26),
    'profile': _author(0),
    'tags': ['设计模式'],
    'image_paths': <String>[],
    'accepted_answer_id': 'a-1',
    'answer_count': 2,
  };

  static final List<Json> _answers = [
    {
      'id': 'a-1',
      'question_id': 'q-1',
      'author_id': 'u-1',
      'body': '工厂解决的是「怎么拿到策略」，策略解决的是「拿到之后怎么切换行为」。两件事拆开，调用方就不需要知道具体实现类。',
      'created_at': _ago(20),
      'profile': _author(1),
    },
    {
      'id': 'a-2',
      'question_id': 'q-1',
      'author_id': 'u-2',
      'body': '补充一点：如果策略数量少、创建成本低，直接 new 也完全没问题，工厂不是必须的。',
      'created_at': _ago(12),
      'profile': _author(2),
    },
  ];

  @override
  CloudIdentityRepository get identity => _PreviewIdentity();

  static final List<Json> _friends = [
    {
      'id': 'u-1',
      'nickname': '陈默',
      'public_id': 'chenmo_0721',
      'avatar_path': null,
    },
    {
      'id': 'u-2',
      'nickname': '周舟',
      'public_id': 'zhouzhou',
      'avatar_path': null,
    },
  ];

  static final List<Json> _requests = [
    {
      'id': 'r-1',
      'sender_id': 'u-3',
      'recipient_id': 'u-me',
      'status': 'pending',
      'sender': {'id': 'u-3', 'nickname': '苏禾', 'avatar_path': null},
      'recipient': {'id': 'u-me', 'nickname': '我', 'avatar_path': null},
    },
  ];

  static final List<Json> _inbox = [
    {
      'id': 'conv-1',
      'profile': {'id': 'u-1', 'nickname': '陈默', 'avatar_path': null},
      'latest': {
        'created_at': _ago(7),
        'kind': 'text',
        'body': '那本设计模式的书，第 42 页的例子你看了吗？',
      },
      'unread': 2,
    },
    {
      'id': 'conv-2',
      'profile': {'id': 'u-2', 'nickname': '周舟', 'avatar_path': null},
      'latest': {
        'created_at': _ago(140),
        'kind': 'text',
        'body': '红黑树那题我整理了一份推导，回头发你。',
      },
      'unread': 0,
    },
  ];

  static final List<Json> _messages = [
    {
      'id': 'm-1',
      'conversation_id': 'conv-1',
      'sender_id': 'u-1',
      'body': '那本设计模式的书，第 42 页的例子你看了吗？',
      'created_at': _ago(30),
      'profile': {'id': 'u-1', 'nickname': '陈默', 'avatar_path': null},
    },
    {
      'id': 'm-2',
      'conversation_id': 'conv-1',
      'sender_id': 'u-me',
      'body': '看了，工厂那层我一直没想通为什么要拆出来。',
      'created_at': _ago(24),
      'profile': {'id': 'u-me', 'nickname': '我', 'avatar_path': null},
    },
    {
      'id': 'm-3',
      'conversation_id': 'conv-1',
      'sender_id': 'u-1',
      'body': '我把推导写在笔记里了，等下拍给你。',
      'created_at': _ago(7),
      'profile': {'id': 'u-1', 'nickname': '陈默', 'avatar_path': null},
    },
  ];

  static final List<Json> _notifications = [
    {
      'id': 'n-1',
      'kind': 'answer',
      'actor': {'nickname': '周舟', 'avatar_path': null},
      'created_at': _ago(9),
      'read_at': null,
      'question_id': 'q-1',
    },
    {
      'id': 'n-2',
      'kind': 'accepted',
      'actor': {'nickname': '陈默', 'avatar_path': null},
      'created_at': _ago(120),
      'read_at': _ago(100),
      'question_id': 'q-1',
    },
    {
      'id': 'n-3',
      'kind': 'friend_request',
      'actor': {'nickname': '苏禾', 'avatar_path': null},
      'created_at': _ago(240),
      'read_at': _ago(200),
    },
    {
      'id': 'n-4',
      'kind': 'message',
      'actor': {'nickname': '陈默', 'avatar_path': null},
      'created_at': _ago(400),
      'read_at': _ago(380),
      'conversation_id': 'conv-1',
    },
  ];

  static final Json _profile = {
    'id': 'u-1',
    'nickname': '陈默',
    'bio': '在准备考研，主攻数据结构与算法。习惯把推导过程写下来。',
    'public_id': 'chenmo_0721',
    'avatar_path': null,
  };

  static final List<Json> _userAnswers = [
    {
      'id': 'ua-1',
      'question_id': 'q-2',
      'body':
          '红黑树的删除本质是「先按 BST 删除，再用旋转和变色修复黑高」，四种情况其实是修复时要处理的四种父子关系。',
      'question': {'title': '红黑树的删除为什么要分四种情况讨论？'},
    },
  ];

  @override
  Future<List<Json>> friends() async => _friends;

  @override
  Future<List<Json>> requests() async => _requests;

  @override
  Future<List<Json>> inbox() async => _inbox;

  @override
  Future<List<Json>> messages(String id, {Json? before}) async =>
      before == null ? _messages : const [];

  @override
  Future<List<Json>> notifications({int offset = 0}) async =>
      offset == 0 ? _notifications : const [];

  @override
  Future<int> unreadCount() async => 1;

  @override
  Future<Json> profile(String id) async => _profile;

  @override
  Future<List<Json>> userAnswers(String id, {int offset = 0}) async =>
      offset == 0 ? _userAnswers : const [];

  @override
  Future<String> friendStatus(String id) async => 'friend';

  @override
  Future<List<Json>> searchUsers(String query, {int offset = 0}) async =>
      offset == 0 ? _friends : const [];

  @override
  Future<String> openConversation(String id) async => 'conv-1';

  @override
  Future<void> sendMessage({
    required String conversation,
    required String token,
    required String body,
    String? image,
    String? expectedSender,
  }) async {}

  @override
  Future<void> markRead(String conversation, String message) async {}

  @override
  Future<void> readNotification(String id) async {}

  @override
  Future<List<Json>> blocks() async => const [];

  @override
  Future<List<Json>> feed({
    String mode = 'latest',
    String keyword = '',
    int offset = 0,
    String? author,
    bool bookmarks = false,
  }) async {
    if (offset > 0) return const [];
    var items = List<Json>.from(_feed);
    if (author != null) {
      items = items.where((q) => q['author_id'] == author).toList();
    }
    if (bookmarks) {
      items = items.where((q) => q['bookmarked'] == true).toList();
    }
    if (mode == 'unanswered') {
      items = items.where((q) => (q['answer_count'] as int) == 0).toList();
    }
    if (keyword.isNotEmpty) {
      items = items
          .where((q) => '${q['title']}${q['body']}'.contains(keyword))
          .toList();
    }
    return items;
  }

  @override
  Future<Json> question(String id) async => _question;

  @override
  Future<List<Json>> answers(String id, {int offset = 0}) async =>
      offset == 0 ? _answers : const [];

  @override
  Future<List<Json>> comments(String answer, {int offset = 0}) async =>
      const [];

  @override
  Future<bool> bookmarked(String id) async => true;
}

/// Lets the preview pages believe the account is linked, so CommunityUserPage /
/// ChatPage / FriendsChatPage can render their real layout instead of an error.
class _PreviewIdentity extends CloudIdentityRepository {
  @override
  Future<String> requireLinked() async => 'u-me';
}

/// The real outbox reads the local sqflite database, which cannot be awaited
/// from inside a fake-async widget test; pending sends are irrelevant to layout.
class _PreviewOutbox extends ChatOutboxRepository {
  _PreviewOutbox({required CommunityRepository community})
    : super(community: community);

  @override
  Future<List<Json>> pending(String conversation) async => const [];
}
