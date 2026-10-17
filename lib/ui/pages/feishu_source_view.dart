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
import '../theme/app_theme.dart';
import '../widgets/app_kit.dart';
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
          return AppEmptyState(
            icon: Icons.cloud_off_rounded,
            accent: AppColors.error,
            title: '读取失败',
            description: '${snapshot.error}',
            actionLabel: '重试',
            onAction: () => setState(() {
              _data = _load();
            }),
          );
        }
        if (!snapshot.hasData) {
          return const AppLoadingState(label: '正在读取飞书原文…');
        }
        final data = snapshot.data!;
        final meta = data['meta'] as Map<String, Object?>?;
        final cards = data['cards'] as List;
        final needsUpdate = meta?['knowledge_needs_update'] == 1;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            // ---- 来源信息 ----
            AppCard.plain(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.tintOf(AppColors.primary, 0.12),
                          borderRadius: BorderRadius.circular(
                            AppRadii.chipSmall,
                          ),
                        ),
                        child: const Icon(
                          Icons.description_outlined,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.source.title,
                          style: AppTextStyles.title(context),
                        ),
                      ),
                    ],
                  ),
                  if (meta != null) ...[
                    const SizedBox(height: 12),
                    _MetaRow(
                      label: '飞书路径',
                      value: '${meta['relative_path'] ?? widget.source.title}',
                    ),
                    _MetaRow(
                      label: '远端更新',
                      value: _sourceTime(meta['remote_modified_time']),
                    ),
                    _MetaRow(
                      label: '同步时间',
                      value: _sourceTime(meta['synced_at']),
                    ),
                  ],
                  if (meta != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 40),
                          ),
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
                          icon: const Icon(Icons.open_in_new_rounded, size: 17),
                          label: const Text('在飞书查看原文'),
                        ),
                        if (meta['container_type'] == 'folder')
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 40),
                            ),
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
                            icon: const Icon(
                              Icons.folder_open_rounded,
                              size: 17,
                            ),
                            label: const Text('选择来源资料'),
                          ),
                      ],
                    ),
                  ],
                  if (needsUpdate) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                      decoration: BoxDecoration(
                        color: AppColors.tintOf(AppColors.accentAmber, 0.10),
                        borderRadius: BorderRadius.circular(
                          AppRadii.chipSmall,
                        ),
                        border: Border.all(
                          color: AppColors.tintOf(
                            AppColors.accentAmber,
                            0.25,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.sync_problem_rounded,
                            size: 16,
                            color: AppColors.accentAmber,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '原文已更新；已有知识点仍保留，请重新整理知识点。',
                              style: AppTextStyles.caption(
                                context,
                              ).copyWith(color: AppColors.slate),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // ---- 原文 / 知识点 ----
            Row(
              children: [
                Expanded(
                  child: AppSegmented<int>(
                    value: _tab,
                    onChanged: (v) => setState(() => _tab = v),
                    options: [
                      const AppSegmentedOption(0, '原文'),
                      AppSegmentedOption(1, '知识点 ${cards.length}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_tab == 0)
              AppCard.plain(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: MarkdownBody(
                  data: data['markdown'] as String? ?? data['text'] as String,
                  selectable: true,
                  imageBuilder: (uri, title, alt) => Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '[图片暂不支持展示，可查看飞书原文]',
                      style: AppTextStyles.caption(context),
                    ),
                  ),
                  onTapLink: (text, href, title) async {
                    final uri = Uri.tryParse(href ?? '');
                    if (uri != null && {'https', 'http'}.contains(uri.scheme)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                ),
              )
            else if (cards.isEmpty)
              const AppEmptyState(
                compact: true,
                icon: Icons.auto_awesome_rounded,
                accent: AppColors.accentViolet,
                title: '尚未生成知识点',
                description: '用 AI 把这篇原文整理成可复习的知识点，生成后会保存在本机。',
              )
            else
              for (final card in cards)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard.plain(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(card.title, style: AppTextStyles.title(context)),
                        const SizedBox(height: 5),
                        SelectableText(
                          card.content,
                          style: AppTextStyles.bodySmall(
                            context,
                          ).copyWith(height: 1.55, color: AppColors.slate),
                        ),
                      ],
                    ),
                  ),
                ),
            if (_busy) const LinearProgressIndicator(),
            if (_message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _message,
                  style: AppTextStyles.bodySmall(
                    context,
                  ).copyWith(color: AppColors.textSecondary),
                ),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: _busy ? null : _generate,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('AI 整理知识点'),
            ),
          ],
        );
      },
    ),
  );
}

/// Left label / right value row, used for the source metadata block.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 66,
          child: Text(
            label,
            style: AppTextStyles.labelSmall(
              context,
            ).copyWith(color: AppColors.textTertiary),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodySmall(
              context,
            ).copyWith(color: AppColors.textPrimary),
          ),
        ),
      ],
    ),
  );
}
