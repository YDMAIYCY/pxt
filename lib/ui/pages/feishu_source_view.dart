import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../agent/eclaw_context.dart';
import '../../database/app_database.dart';
import '../../database/ai_generation_repository.dart';
import '../../database/feishu_import_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/source_document_record.dart';
import '../../database/models/ai_generation_task_record.dart';
import '../../database/ocr_text_repository.dart';
import '../../generator/ai_generation_orchestrator.dart';
import '../widgets/ask_eclaw_button.dart';
import 'feishu_import_page.dart';
import '../../feishu/docx_markdown.dart';

String _sourceTime(Object? value) {
  if (value == null || '$value'.isEmpty) return '接口未提供';
  final epoch = int.tryParse('$value');
  final parsed = epoch == null
      ? DateTime.tryParse('$value')
      : DateTime.fromMillisecondsSinceEpoch(
          epoch < 100000000000 ? epoch * 1000 : epoch,
          isUtc: true,
        );
  return parsed?.toLocal().toString().split('.').first ?? '$value';
}

class FeishuSourceView extends StatefulWidget {
  const FeishuSourceView({required this.source, this.database, super.key});
  final SourceDocumentRecord source;
  final AppDatabase? database;
  @override
  State<FeishuSourceView> createState() => _FeishuSourceViewState();
}

class _FeishuSourceViewState extends State<FeishuSourceView> {
  bool _busy = false;
  String _message = '';
  int _tab = 0;
  late Future<Map<String, Object?>> _data = _load();
  FeishuImportRepository get _repo =>
      FeishuImportRepository(database: widget.database);

  Future<Map<String, Object?>> _load() async {
    final meta = await _repo.sourceInfo(widget.source.userId, widget.source.id);
    return {
      'meta': meta,
      'markdown': meta == null
          ? null
          : await compute(docxMarkdown, meta['blocks_json'] as String),
      'text':
          (await OcrTextRepository(
            database: widget.database,
          ).getByDocumentId(widget.source.id))?.effectiveText ??
          '',
      'cards': await AiGenerationRepository(
        database: widget.database,
      ).fetchKnowledgeCards(widget.source.id),
    };
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _message = '正在整理知识点…';
    });
    try {
      final config = await LlmConfigRepository(
        database: widget.database,
      ).getByUserId(widget.source.userId);
      if (config?.isConfigured != true) throw StateError('请先在“我的”中配置大模型服务');
      final before = await _repo.sourceInfo(
        widget.source.userId,
        widget.source.id,
      );
      final text =
          (await OcrTextRepository(
            database: widget.database,
          ).getByDocumentId(widget.source.id))?.effectiveText ??
          '';
      if (text.trim().isEmpty) throw StateError('文档没有可用文字');
      final result =
          await AiGenerationOrchestrator(
            aiGenerationRepository: AiGenerationRepository(
              database: widget.database,
            ),
          ).generateSingle(
            documentId: widget.source.id,
            ocrText: text,
            taskType: AiTaskType.knowledgeCards,
            llmConfig: config,
            appendResults: true,
          );
      if (result.success && before != null) {
        final db = await (widget.database ?? AppDatabase.instance).database;
        // A concurrent sync must not mark cards based on an older source as current.
        await db.update(
          'feishu_documents',
          {'knowledge_needs_update': 0},
          where: 'source_id=? AND user_id=? AND content_hash=?',
          whereArgs: [
            widget.source.id,
            widget.source.userId,
            before['content_hash'],
          ],
        );
      }
      if (mounted) {
        setState(() {
          _message = result.message;
          _data = _load();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('飞书原文与知识点'),
      actions: [
        AskEClawButton(
          database: widget.database,
          scope: EClawContext(
            knowledgeBaseId: widget.source.libraryId,
            importRecordId: widget.source.importRecordId,
            documentId: widget.source.id,
          ),
        ),
      ],
    ),
    body: FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('读取失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final meta = data['meta'] as Map<String, Object?>?;
        final cards = data['cards'] as List;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.source.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (meta != null) ...[
              Text(
                '飞书来源：${meta['relative_path'] ?? widget.source.title}\n远端更新时间：${_sourceTime(meta['remote_modified_time'])}\n同步时间：${_sourceTime(meta['synced_at'])}',
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      final url = Uri.parse(meta['source_url'] as String);
                      if (url.scheme != 'https' ||
                          !(url.host == 'feishu.cn' ||
                              url.host.endsWith('.feishu.cn'))) {
                        return;
                      }
                      await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    child: const Text('在飞书查看原文'),
                  ),
                  if (meta['container_type'] == 'folder')
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FeishuImportPage(
                                    userId: widget.source.userId,
                                    database: widget.database,
                                    initialFolder:
                                        meta['container_id'] as String,
                                  ),
                                ),
                              );
                              if (mounted) {
                                setState(() {
                                  _data = _load();
                                });
                              }
                            },
                      child: const Text('选择来源资料'),
                    ),
                ],
              ),
              if (meta['knowledge_needs_update'] == 1)
                const Text('原文已更新；已有知识点仍保留，请重新整理知识点。'),
            ],
            const SizedBox(height: 16),
            Text(
              _busy
                  ? '知识整理：处理中'
                  : meta?['knowledge_needs_update'] == 1
                  ? '知识整理：原文已更新，待重新整理'
                  : cards.isEmpty
                  ? '知识整理：尚未生成'
                  : '知识整理：已生成 ${cards.length} 个知识点',
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _tab = 0),
                  child: const Text('原文'),
                ),
                TextButton(
                  onPressed: () => setState(() => _tab = 1),
                  child: Text('知识点 (${cards.length})'),
                ),
              ],
            ),
            if (_tab == 0)
              MarkdownBody(
                data: data['markdown'] as String? ?? data['text'] as String,
                selectable: true,
                imageBuilder: (uri, title, alt) => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('[图片暂不支持展示，可查看飞书原文]'),
                ),
                onTapLink: (text, href, title) async {
                  final uri = Uri.tryParse(href ?? '');
                  if (uri != null && {'https', 'http'}.contains(uri.scheme)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _generate,
              child: const Text('AI 整理知识点'),
            ),
            Text(_message),
            if (_busy) const LinearProgressIndicator(),
            if (_tab == 1 && cards.isEmpty) const Text('尚未生成知识点'),
            if (_tab == 1)
              for (final card in cards)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(card.title), Text(card.content)],
                    ),
                  ),
                ),
          ],
        );
      },
    ),
  );
}
