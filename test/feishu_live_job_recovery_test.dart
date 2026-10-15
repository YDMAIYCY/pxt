// Opt-in recovery check: a private copy of the phone DB and a freshly read real document.
// This never changes the phone database or substitutes a fixture for a provider response.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/feishu/feishu_client.dart';
import 'package:pxt1/feishu/feishu_controller.dart';

class _CapturedDocumentClient extends FeishuClient {
  _CapturedDocumentClient(this.document);
  final Map<String,dynamic> document;
  @override
  Future<Map<String,dynamic>> request(String method,String path,{Map<String,String>? query,Object? body}) async {
    if(method!='GET' || path!='/documents/${document['document_id']}') throw StateError('Unexpected request');
    return document;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final path=Platform.environment['FEISHU_LIVE_JOB_DB'];
  final body=Platform.environment['FEISHU_LIVE_JOB_DOCUMENT'];
  test('failed phone job recovers with its actual docx, preserving libraries and existing AI data', () async {
    final doc=jsonDecode(await File(body!).readAsString()) as Map<String,dynamic>;
    final app=await AppDatabase.openForTesting(databaseFactoryFfi,path:path!);
    final db=await app.database;
    final client=_CapturedDocumentClient(doc);
    FeishuController? controller;
    try {
      final job=(await db.query('feishu_import_jobs',where:'id=1')).single;
      final libraries=await db.query('knowledge_libraries');
      final cards=await db.query('knowledge_cards',columns:['id']);
      final before=await db.query('source_documents',columns:['id']);
      controller=FeishuController(userId:job['user_id'] as int,database:app,client:client)
        ..connected=true ..connection={'account_id':job['account_id']};
      await controller.run(1).timeout(const Duration(seconds:15));
      expect((await db.query('feishu_import_jobs',where:'id=1')).single['status'],'done');
      expect(controller.completed,1);
      expect(await db.query('knowledge_libraries'),libraries);
      expect(await db.query('knowledge_cards',columns:['id']),cards);
      expect(await db.query('source_documents',columns:['id']),hasLength(before.length+1));
      final source=(await db.query('feishu_documents',where:'document_id=?',whereArgs:[doc['document_id']])).single['source_id'];
      await controller.run(1);
      expect((await db.query('feishu_documents',where:'document_id=?',whereArgs:[doc['document_id']])).single['source_id'],source);
      expect(await db.query('source_documents',columns:['id']),hasLength(before.length+1));
      await File('.dart_tool/feishu_live_job_recovery_result.json').writeAsString(jsonEncode({
        'phone_database_copy':true,'actual_provider_document':true,'job_id':1,'status':'done',
        'completed':1,'total':1,'duplicate_created':false,'existing_ai_preserved':true,
      }));
    } finally { controller?.dispose(); client.close(); await db.close(); }
  },skip:path==null || body==null ? 'Requires copied phone job DB and a real provider document; no fixtures' : false);
}
