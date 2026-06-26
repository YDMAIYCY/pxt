import '../database/knowledge_library_repository.dart';
import '../database/models/knowledge_library_record.dart';
import '../database/models/source_document_record.dart';
import '../database/source_document_repository.dart';
import '../debug/debug_demo_data_seeder.dart';

// ========== QSClaw Tool Registry ==========
// Registers safe in-app capabilities that QSClaw can call from natural language.
typedef QsClawToolHandler =
    Future<QsClawToolResult> Function(QsClawToolContext context);

class QsClawToolRegistry {
  QsClawToolRegistry(Iterable<QsClawTool> tools)
    : _tools = {for (final tool in tools) tool.name: tool};

  factory QsClawToolRegistry.withCoreTools({
    SourceDocumentRepository? sourceDocumentRepository,
    KnowledgeLibraryRepository? knowledgeLibraryRepository,
    DebugDemoDataSeeder? debugDemoDataSeeder,
  }) {
    final sourceDocuments =
        sourceDocumentRepository ?? SourceDocumentRepository();
    final libraries =
        knowledgeLibraryRepository ?? KnowledgeLibraryRepository();
    final demoSeeder = debugDemoDataSeeder ?? DebugDemoDataSeeder();

    return QsClawToolRegistry([
      QsClawTool(
        name: QsClawToolNames.createKnowledgeLibrary,
        description: 'Create or reuse a knowledge library.',
        handler: (context) async {
          final name = context.stringArg('libraryName', fallback: '学习资料知识库');
          final existing = await libraries.fetchLibraries(context.userId);
          final matched = existing.cast<KnowledgeLibraryRecord?>().firstWhere(
            (library) => library?.name == name,
            orElse: () => null,
          );
          final library =
              matched ??
              await libraries.createLibrary(
                userId: context.userId,
                name: name,
                description: context.stringArg('description'),
              );
          return QsClawToolResult(
            toolName: QsClawToolNames.createKnowledgeLibrary,
            message: '已准备知识库：${library.name}',
            data: {'library': library},
          );
        },
      ),
      QsClawTool(
        name: QsClawToolNames.searchDocuments,
        description: 'Search imported documents by topic and file type.',
        handler: (context) async {
          final documents = await sourceDocuments.fetchAllSourceDocuments(
            userId: context.userId,
            limit: context.intArg('limit', fallback: 500),
          );
          final topic = context.stringArg('topic').toLowerCase();
          final fileTypes = context.stringListArg('fileTypes');
          final matched = documents
              .where(
                (document) =>
                    _matchesType(document, fileTypes) &&
                    _matchesTopic(document, topic),
              )
              .toList(growable: false);
          return QsClawToolResult(
            toolName: QsClawToolNames.searchDocuments,
            message: '找到 ${matched.length} 份匹配资料。',
            data: {'documents': matched},
          );
        },
      ),
      QsClawTool(
        name: QsClawToolNames.moveDocumentToLibrary,
        description: 'Move imported documents into a knowledge library.',
        handler: (context) async {
          final library = context.objectArg<KnowledgeLibraryRecord>('library');
          final documents = context.objectListArg<SourceDocumentRecord>(
            'documents',
          );
          if (library == null || documents.isEmpty) {
            return const QsClawToolResult(
              toolName: QsClawToolNames.moveDocumentToLibrary,
              message: '没有需要移动的资料。',
            );
          }

          var movedCount = 0;
          for (final document in documents) {
            if (document.libraryId == library.id) continue;
            await sourceDocuments.moveDocumentToLibrary(
              userId: context.userId,
              documentId: document.id,
              libraryId: library.id,
            );
            movedCount++;
          }

          return QsClawToolResult(
            toolName: QsClawToolNames.moveDocumentToLibrary,
            message: '已移动 $movedCount 份资料。',
            data: {'movedCount': movedCount},
          );
        },
      ),
      QsClawTool(
        name: QsClawToolNames.navigateToPage,
        description: 'Navigate to an app page.',
        handler: (context) async {
          final target = context.stringArg('target');
          return QsClawToolResult(
            toolName: QsClawToolNames.navigateToPage,
            message: '正在打开：${QsClawNavigationTarget.labelOf(target)}。',
            data: {'navigationTarget': target},
          );
        },
      ),
      QsClawTool(
        name: QsClawToolNames.seedDebugDemoData,
        description: 'Seed local debug demo data for the current user.',
        handler: (context) async {
          await demoSeeder.seedForUser(context.userId);
          return const QsClawToolResult(
            toolName: QsClawToolNames.seedDebugDemoData,
            message: '已为当前调试账号植入演示数据。',
          );
        },
      ),
    ]);
  }

  final Map<String, QsClawTool> _tools;

  Iterable<String> get toolNames => _tools.keys;

  Future<QsClawToolResult> run(
    String toolName, {
    required int userId,
    Map<String, Object?> args = const {},
  }) async {
    final tool = _tools[toolName];
    if (tool == null) {
      throw StateError('QSClaw tool is not registered: $toolName');
    }
    return tool.handler(QsClawToolContext(userId: userId, args: args));
  }

  static bool _matchesType(
    SourceDocumentRecord document,
    List<String> fileTypes,
  ) {
    if (fileTypes.isEmpty) return true;
    final wantsPdf = fileTypes.contains('pdf');
    final wantsImage = fileTypes.contains('image');
    return wantsPdf &&
            document.sourceType == SourceDocumentSourceType.pdfPage ||
        wantsImage && document.sourceType != SourceDocumentSourceType.pdfPage;
  }

  static bool _matchesTopic(SourceDocumentRecord document, String topic) {
    if (topic.isEmpty || topic == '学习资料') return true;
    final title = document.title.toLowerCase();
    return title.contains(topic) ||
        _topicTokens(topic).any((token) => title.contains(token));
  }

  static Iterable<String> _topicTokens(String topic) sync* {
    yield topic;
    if (topic.contains('高等数学') || topic.contains('数学')) {
      yield '高数';
      yield '函数';
      yield '极限';
      yield '导数';
      yield '微分';
      yield '积分';
      yield '线代';
    }
  }
}

class QsClawTool {
  const QsClawTool({
    required this.name,
    required this.description,
    required this.handler,
  });

  final String name;
  final String description;
  final QsClawToolHandler handler;
}

class QsClawToolContext {
  const QsClawToolContext({required this.userId, required this.args});

  final int userId;
  final Map<String, Object?> args;

  String stringArg(String key, {String fallback = ''}) {
    final value = args[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
  }

  int intArg(String key, {int fallback = 0}) {
    final value = args[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  List<String> stringListArg(String key) {
    final value = args[key];
    if (value is List<String>) return value;
    if (value is Iterable) {
      return value.whereType<String>().toList(growable: false);
    }
    return const [];
  }

  T? objectArg<T>(String key) {
    final value = args[key];
    return value is T ? value : null;
  }

  List<T> objectListArg<T>(String key) {
    final value = args[key];
    if (value is List<T>) return value;
    if (value is Iterable) {
      return value.whereType<T>().toList(growable: false);
    }
    return const [];
  }
}

class QsClawToolResult {
  const QsClawToolResult({
    required this.toolName,
    required this.message,
    this.data = const {},
  });

  final String toolName;
  final String message;
  final Map<String, Object?> data;
}

class QsClawToolNames {
  const QsClawToolNames._();

  static const String createKnowledgeLibrary = 'create_knowledge_library';
  static const String searchDocuments = 'search_documents';
  static const String moveDocumentToLibrary = 'move_document_to_library';
  static const String navigateToPage = 'navigate_to_page';
  static const String seedDebugDemoData = 'seed_debug_demo_data';
}

class QsClawNavigationTarget {
  const QsClawNavigationTarget._();

  static const String home = 'home';
  static const String aiChat = 'ai_chat';
  static const String knowledge = 'knowledge';
  static const String practice = 'practice';

  static String labelOf(String target) {
    switch (target) {
      case aiChat:
        return 'AI 伴学问答';
      case knowledge:
        return '知识库';
      case practice:
        return '练习题';
      default:
        return '首页';
    }
  }
}
