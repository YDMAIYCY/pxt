import '../database/knowledge_library_repository.dart';
import '../database/models/knowledge_library_record.dart';
import '../database/models/source_document_record.dart';
import '../database/source_document_repository.dart';
import '../debug/debug_demo_data_seeder.dart';
import 'qsclaw_tool_registry.dart';

// ========== QSClaw Agent Service ==========
// Plans natural-language app tasks and executes them through registered tools.

class QsClawAgentService {
  QsClawAgentService({
    SourceDocumentRepository? sourceDocumentRepository,
    KnowledgeLibraryRepository? knowledgeLibraryRepository,
    DebugDemoDataSeeder? debugDemoDataSeeder,
    QsClawToolRegistry? toolRegistry,
  }) : _toolRegistry =
           toolRegistry ??
           QsClawToolRegistry.withCoreTools(
             sourceDocumentRepository: sourceDocumentRepository,
             knowledgeLibraryRepository: knowledgeLibraryRepository,
             debugDemoDataSeeder: debugDemoDataSeeder,
           );

  final QsClawToolRegistry _toolRegistry;

  static QsClawCommandDraft parseCommand(String command) {
    final normalized = command.trim();
    final lower = normalized.toLowerCase();
    final topic = _extractTopic(normalized);
    final fileTypes = <String>[
      if (lower.contains('pdf')) 'pdf',
      if (normalized.contains(_image) || lower.contains('image')) 'image',
    ];

    return QsClawCommandDraft(
      rawCommand: command,
      topic: topic,
      libraryName: _extractLibraryName(normalized, topic),
      fileTypes: fileTypes.isEmpty ? const ['pdf', 'image'] : fileTypes,
    );
  }

  Future<QsClawRunResult> runCommand({
    required int userId,
    required String command,
  }) async {
    final draft = parseCommand(command);
    final steps = <QsClawAgentStep>[];
    KnowledgeLibraryRecord? library;
    List<SourceDocumentRecord> matchedDocuments = const [];
    var movedCount = 0;
    String? navigationTarget;

    if (_isDemoSeedCommand(command)) {
      final result = await _toolRegistry.run(
        QsClawToolNames.seedDebugDemoData,
        userId: userId,
      );
      steps.add(QsClawAgentStep.fromToolResult(result));
      return QsClawRunResult(
        draft: draft,
        library: null,
        matchedDocuments: const [],
        movedCount: 0,
        status: QsClawRunStatus.completed,
        executedSteps: steps,
      );
    }

    if (_isNavigationCommand(command)) {
      navigationTarget = _navigationTargetFor(command);
      final result = await _toolRegistry.run(
        QsClawToolNames.navigateToPage,
        userId: userId,
        args: {'target': navigationTarget},
      );
      steps.add(QsClawAgentStep.fromToolResult(result));
      return QsClawRunResult(
        draft: draft,
        library: null,
        matchedDocuments: const [],
        movedCount: 0,
        status: QsClawRunStatus.completed,
        executedSteps: steps,
        navigationTarget: navigationTarget,
      );
    }

    if (_isCreateLibraryCommand(command) ||
        _isMaterialCollectionCommand(command)) {
      final result = await _toolRegistry.run(
        QsClawToolNames.createKnowledgeLibrary,
        userId: userId,
        args: {
          'libraryName': draft.libraryName,
          'description': 'QSClaw $_autoCreated: ${draft.topic}',
        },
      );
      steps.add(QsClawAgentStep.fromToolResult(result));
      library = result.data['library'] as KnowledgeLibraryRecord?;
    }

    if (_isMaterialCollectionCommand(command)) {
      final searchResult = await _toolRegistry.run(
        QsClawToolNames.searchDocuments,
        userId: userId,
        args: {
          'topic': draft.topic,
          'fileTypes': draft.fileTypes,
          'limit': 500,
        },
      );
      steps.add(QsClawAgentStep.fromToolResult(searchResult));
      matchedDocuments =
          (searchResult.data['documents'] as List<SourceDocumentRecord>?) ??
          const [];

      final moveResult = await _toolRegistry.run(
        QsClawToolNames.moveDocumentToLibrary,
        userId: userId,
        args: {'library': library, 'documents': matchedDocuments},
      );
      steps.add(QsClawAgentStep.fromToolResult(moveResult));
      movedCount = moveResult.data['movedCount'] as int? ?? 0;
    }

    return QsClawRunResult(
      draft: draft,
      library: library,
      matchedDocuments: matchedDocuments,
      movedCount: movedCount,
      status: matchedDocuments.isEmpty
          ? _isMaterialCollectionCommand(command)
                ? QsClawRunStatus.waitingForSources
                : QsClawRunStatus.completed
          : QsClawRunStatus.completed,
      executedSteps: steps,
      navigationTarget: navigationTarget,
    );
  }

  List<String> get availableToolNames => _toolRegistry.toolNames.toList();

  static bool _isMaterialCollectionCommand(String command) {
    final lower = command.toLowerCase();
    return lower.contains('pdf') ||
        command.contains(_material) ||
        command.contains(_organize) ||
        command.contains(_image);
  }

  static bool _isCreateLibraryCommand(String command) {
    return command.contains(_knowledgeLibrary) ||
        command.toLowerCase().contains('library');
  }

  static bool _isNavigationCommand(String command) {
    return command.contains(_open) ||
        command.contains(_go) ||
        command.contains(_enter) ||
        command.toLowerCase().contains('open');
  }

  static bool _isDemoSeedCommand(String command) {
    return command.contains(_demo) ||
        command.contains(_seed) ||
        command.contains(_inject);
  }

  static String _navigationTargetFor(String command) {
    final lower = command.toLowerCase();
    if (lower.contains('chat') || command.contains(_chat)) {
      return QsClawNavigationTarget.aiChat;
    }
    if (command.contains(_knowledgeLibrary)) {
      return QsClawNavigationTarget.knowledge;
    }
    if (command.contains(_review) ||
        command.contains(_wrongQuestion) ||
        command.contains(_practice)) {
      return QsClawNavigationTarget.practice;
    }
    return QsClawNavigationTarget.home;
  }

  static String _extractTopic(String command) {
    final patterns = [
      RegExp('$_about(.+?)$_of\\s*(pdf|PDF|$_file|$_material|$_image)'),
      RegExp('$_organize(.+?)$_of\\s*(pdf|PDF|$_file|$_material|$_image)'),
      RegExp('$_take(.+?)$_of\\s*(pdf|PDF|$_file|$_material|$_image)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(command);
      if (match != null) {
        return _cleanTopic(match.group(1) ?? '');
      }
    }
    return _learningMaterial;
  }

  static String _extractLibraryName(String command, String topic) {
    final explicit = RegExp(
      '$_create(?:$_one?$_unit?)?(.+?$_knowledgeLibrary)',
    ).firstMatch(command);
    if (explicit != null) {
      return _cleanLibraryName(explicit.group(1) ?? '');
    }
    if (topic.contains(_math) || topic.contains(_advancedMath)) {
      return _mathKnowledgeLibrary;
    }
    return '$topic$_knowledgeLibrary';
  }

  static String _cleanTopic(String value) {
    return value
        .replaceAll(_aLittle, '')
        .replaceAll(_me, '')
        .replaceAll(_organize, '')
        .trim();
  }

  static String _cleanLibraryName(String value) {
    return value
        .replaceAll(_and, '')
        .replaceAll(_settleFolder, '')
        .replaceAll(_folder, '')
        .trim();
  }

  static const String _about = '\u5173\u4e8e';
  static const String _advancedMath = '\u9ad8\u7b49\u6570\u5b66';
  static const String _and = '\u5e76\u4e14';
  static const String _aLittle = '\u4e00\u4e0b';
  static const String _autoCreated = '\u81ea\u52a8\u521b\u5efa';
  static const String _chat = '\u804a\u5929';
  static const String _create = '\u521b\u5efa';
  static const String _file = '\u6587\u4ef6';
  static const String _folder = '\u6587\u4ef6\u5939';
  static const String _demo = '\u6f14\u793a';
  static const String _enter = '\u8fdb\u5165';
  static const String _go = '\u53bb';
  static const String _inject = '\u690d\u5165';
  static const String _image = '\u56fe\u7247';
  static const String _knowledgeLibrary = '\u77e5\u8bc6\u5e93';
  static const String _learningMaterial = '\u5b66\u4e60\u8d44\u6599';
  static const String _material = '\u8d44\u6599';
  static const String _math = '\u6570\u5b66';
  static const String _mathKnowledgeLibrary = '\u6570\u5b66\u77e5\u8bc6\u5e93';
  static const String _me = '\u6211';
  static const String _of = '\u7684';
  static const String _one = '\u4e00';
  static const String _open = '\u6253\u5f00';
  static const String _organize = '\u6574\u7406';
  static const String _practice = '\u7ec3\u4e60';
  static const String _review = '\u590d\u4e60';
  static const String _seed = '\u6ce8\u5165';
  static const String _settleFolder = '\u6c89\u6dc0\u6587\u4ef6\u5939';
  static const String _take = '\u628a';
  static const String _unit = '\u4e2a';
  static const String _wrongQuestion = '\u9519\u9898';
}

class QsClawCommandDraft {
  const QsClawCommandDraft({
    required this.rawCommand,
    required this.topic,
    required this.libraryName,
    required this.fileTypes,
  });

  final String rawCommand;
  final String topic;
  final String libraryName;
  final List<String> fileTypes;
}

class QsClawRunResult {
  const QsClawRunResult({
    required this.draft,
    required this.library,
    required this.matchedDocuments,
    required this.movedCount,
    required this.status,
    this.executedSteps = const [],
    this.navigationTarget,
  });

  final QsClawCommandDraft draft;
  final KnowledgeLibraryRecord? library;
  final List<SourceDocumentRecord> matchedDocuments;
  final int movedCount;
  final String status;
  final List<QsClawAgentStep> executedSteps;
  final String? navigationTarget;
}

class QsClawAgentStep {
  const QsClawAgentStep({required this.toolName, required this.message});

  factory QsClawAgentStep.fromToolResult(QsClawToolResult result) {
    return QsClawAgentStep(toolName: result.toolName, message: result.message);
  }

  final String toolName;
  final String message;
}

class QsClawRunStatus {
  const QsClawRunStatus._();

  static const String completed = 'completed';
  static const String waitingForSources = 'waiting_for_sources';
}
