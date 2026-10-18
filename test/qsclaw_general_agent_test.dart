import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/agent/qsclaw_agent_service.dart';
import 'package:pxt1/agent/qsclaw_tool_registry.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/models/knowledge_library_record.dart';
import 'package:pxt1/debug/debug_demo_data_seeder.dart';

void main() {
  group('QSClaw general agent', () {
    test('registers app tools by capability name', () {
      final registry = QsClawToolRegistry.withCoreTools(
        knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
      );

      expect(registry.toolNames, contains('create_knowledge_library'));
      expect(registry.toolNames, contains('navigate_to_page'));
      expect(registry.toolNames, contains('search_documents'));
      expect(registry.toolNames, contains('move_document_to_library'));
      expect(registry.toolNames, contains('seed_debug_demo_data'));
    });

    test('plans navigation commands as app actions', () async {
      final service = QsClawAgentService(
        toolRegistry: QsClawToolRegistry.withCoreTools(
          knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
        ),
      );

      final result = await service.runCommand(
        userId: 7,
        command: '$_open AI Chat',
      );

      expect(result.executedSteps.map((step) => step.toolName), [
        'navigate_to_page',
      ]);
      expect(result.navigationTarget, QsClawNavigationTarget.aiChat);
      expect(result.status, QsClawRunStatus.completed);
    });

    test(
      'executes create library commands through a registered tool',
      () async {
        final libraries = _FakeKnowledgeLibraryRepository();
        final service = QsClawAgentService(
          toolRegistry: QsClawToolRegistry.withCoreTools(
            knowledgeLibraryRepository: libraries,
          ),
        );

        final result = await service.runCommand(
          userId: 7,
          command: '$_create$_mathKnowledgeLibrary',
        );

        expect(libraries.createdNames, [_mathKnowledgeLibrary]);
        expect(result.executedSteps.map((step) => step.toolName), [
          'create_knowledge_library',
        ]);
        expect(result.library?.name, _mathKnowledgeLibrary);
      },
    );

    test('executes demo data commands through an app tool', () async {
      final seeder = _FakeDebugDemoDataSeeder();
      final service = QsClawAgentService(
        debugDemoDataSeeder: seeder,
        toolRegistry: QsClawToolRegistry.withCoreTools(
          knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
          debugDemoDataSeeder: seeder,
        ),
      );

      final result = await service.runCommand(
        userId: 7,
        command: '\u690d\u5165\u6f14\u793a\u6570\u636e',
      );

      expect(seeder.seededUserId, 7);
      expect(result.executedSteps.map((step) => step.toolName), [
        'seed_debug_demo_data',
      ]);
      expect(result.status, QsClawRunStatus.completed);
    });
  });
}

class _FakeKnowledgeLibraryRepository extends KnowledgeLibraryRepository {
  final libraries = <KnowledgeLibraryRecord>[];
  final createdNames = <String>[];

  @override
  Future<List<KnowledgeLibraryRecord>> fetchLibraries(int userId) async {
    return libraries;
  }

  @override
  Future<KnowledgeLibraryRecord> createLibrary({
    required int userId,
    required String name,
    String? description,
  }) async {
    createdNames.add(name);
    final library = KnowledgeLibraryRecord(
      id: 100 + libraries.length,
      userId: userId,
      name: name,
      description: description,
      createdAt: DateTime(2026, 6, 17),
      updatedAt: DateTime(2026, 6, 17),
    );
    libraries.add(library);
    return library;
  }
}

class _FakeDebugDemoDataSeeder extends DebugDemoDataSeeder {
  int? seededUserId;

  @override
  Future<void> seedForUser(int userId) async {
    seededUserId = userId;
  }
}

const _create = '\u521b\u5efa';
const _mathKnowledgeLibrary = '\u6570\u5b66\u77e5\u8bc6\u5e93';
const _open = '\u6253\u5f00';
