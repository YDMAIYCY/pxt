import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/agent/qsclaw_agent_service.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/models/knowledge_library_record.dart';
import 'package:pxt1/database/models/source_document_record.dart';
import 'package:pxt1/database/source_document_repository.dart';

void main() {
  group('QSClaw agent service', () {
    test('parses learning material collection command', () {
      final draft = QsClawAgentService.parseCommand(
        [
          _go,
          _wechat,
          _fileTransfer,
          _helpMe,
          _organize,
          _aLittle,
          _about,
          _advancedMath,
          _of,
          'pdf',
          _and,
          _create,
          _one,
          _mathKnowledgeLibrary,
          _settleFolder,
        ].join(),
      );

      expect(draft.topic, _advancedMath);
      expect(draft.libraryName, _mathKnowledgeLibrary);
      expect(draft.fileTypes, contains('pdf'));
    });

    test('creates a library and moves matching existing documents', () async {
      final sourceDocuments = _FakeSourceDocumentRepository([
        _document(id: 1, title: '$_advancedMath $_limit$_and$_derivative.pdf'),
        _document(id: 2, title: '$_english$_cet4$_listening.pdf'),
      ]);
      final libraries = _FakeKnowledgeLibraryRepository();
      final service = QsClawAgentService(
        sourceDocumentRepository: sourceDocuments,
        knowledgeLibraryRepository: libraries,
      );

      final result = await service.runCommand(
        userId: 7,
        command:
            '$_helpMe$_organize$_about$_advancedMath${_of}pdf$_comma$_create$_mathKnowledgeLibrary',
      );

      expect(result.library?.name, _mathKnowledgeLibrary);
      expect(result.matchedDocuments.map((item) => item.id), [1]);
      expect(sourceDocuments.movedDocumentIds, [1]);
      expect(sourceDocuments.targetLibraryIds, [100]);
      expect(result.status, QsClawRunStatus.completed);
    });
  });
}

SourceDocumentRecord _document({required int id, required String title}) {
  return SourceDocumentRecord(
    id: id,
    userId: 7,
    sourceType: SourceDocumentSourceType.pdfPage,
    imagePath: 'missing.png',
    title: title,
    createdAt: DateTime(2026, 6, 17),
    ocrStatus: SourceDocumentOcrStatus.success,
    aiDone: false,
  );
}

class _FakeSourceDocumentRepository extends SourceDocumentRepository {
  _FakeSourceDocumentRepository(this.documents);

  final List<SourceDocumentRecord> documents;
  final movedDocumentIds = <int>[];
  final targetLibraryIds = <int>[];

  @override
  Future<List<SourceDocumentRecord>> fetchAllSourceDocuments({
    required int userId,
    int? libraryId,
    int limit = 100,
  }) async {
    return documents;
  }

  @override
  Future<void> moveDocumentToLibrary({
    required int userId,
    required int documentId,
    required int libraryId,
  }) async {
    movedDocumentIds.add(documentId);
    targetLibraryIds.add(libraryId);
  }
}

class _FakeKnowledgeLibraryRepository extends KnowledgeLibraryRepository {
  final libraries = <KnowledgeLibraryRecord>[];

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
    final library = KnowledgeLibraryRecord(
      id: 100,
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

const _about = '\u5173\u4e8e';
const _advancedMath = '\u9ad8\u7b49\u6570\u5b66';
const _and = '\u5e76\u4e14';
const _aLittle = '\u4e00\u4e0b';
const _cet4 = '\u56db\u7ea7';
const _comma = '\uff0c';
const _create = '\u521b\u5efa';
const _derivative = '\u5bfc\u6570';
const _english = '\u82f1\u8bed';
const _fileTransfer = '\u6587\u4ef6\u4f20\u8f93\u52a9\u624b';
const _go = '\u53bb';
const _helpMe = '\u5e2e\u6211';
const _limit = '\u6781\u9650';
const _listening = '\u542c\u529b';
const _mathKnowledgeLibrary = '\u6570\u5b66\u77e5\u8bc6\u5e93';
const _of = '\u7684';
const _one = '\u4e00';
const _organize = '\u6574\u7406';
const _settleFolder = '\u6c89\u6dc0\u6587\u4ef6\u5939';
const _wechat = '\u5fae\u4fe1';
