import 'package:flutter/material.dart';
import '../../agent/eclaw_context.dart';
import '../widgets/ask_eclaw_button.dart';
import '../../camera/document_input_contract.dart';
import '../../database/app_database.dart';
import '../../database/document_batch_repository.dart';
import '../../database/import_record_repository.dart';
import '../../database/knowledge_library_repository.dart';
import '../../database/models/import_record.dart';
import '../../database/models/knowledge_library_record.dart';
import '../../database/source_document_repository.dart';
import '../../pipeline/document_ingest_service.dart';
import '../theme/app_theme.dart';
import '../widgets/knowledge_book_cover.dart';
import '../widgets/knowledge_components.dart';
import '../widgets/knowledge_library_editor.dart';
import '../widgets/premium_app_chrome.dart';
import 'import_record_detail_page.dart';
import 'knowledge_graph_page.dart';

class BookDetailPage extends StatefulWidget {
  const BookDetailPage({required this.library, this.database, this.autoImport = false, super.key});
  final KnowledgeLibraryRecord library;
  final AppDatabase? database;
  final bool autoImport;
  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  late KnowledgeLibraryRecord _library = widget.library;
  late Future<List<ImportRecord>> _future;
  String _query = '';
  String? _source;
  bool _oldest = false, _importing = false;
  ImportRecordRepository get _records =>
      ImportRecordRepository(database: widget.database);
  @override
  void initState() {
    super.initState();
    _future = _load();
    if (widget.autoImport) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _import(); });
  }

  Future<List<ImportRecord>> _load() =>
      _records.list(_library.userId, libraryId: _library.id, query: _query);
  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _manage() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('修改名称、简介和封面'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('删除知识库，保留学习资料'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    final repo = KnowledgeLibraryRepository(database: widget.database);
    try {
      if (action == 'edit') {
        final result = await showKnowledgeLibraryEditor(
          context,
          userId: _library.userId,
          repository: repo,
          library: _library,
        );
        if (result != null && mounted) setState(() => _library = result);
      } else if (action == 'delete' &&
          await knowledgeConfirmDelete(
            context,
            '删除“${_library.name}”？\n所有导入记录、原文件和学习成果会移到“待整理”，不会丢失。',
          )) {
        await repo.deleteLibraryKeepingRecords(
          userId: _library.userId,
          libraryId: _library.id,
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _import() async {
    if (_importing) return;
    final source = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in {
              'camera': '拍照导入',
              'gallery': '相册导入',
              'document': '文档导入',
            }.entries)
              ListTile(
                leading: Icon(
                  e.key == 'document'
                      ? Icons.description_outlined
                      : Icons.add_photo_alternate_outlined,
                ),
                title: Text(e.value),
                onTap: () => Navigator.pop(context, e.key),
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _importing = true);
    try {
      final ingest = DocumentIngestService(
        sourceDocumentRepository: SourceDocumentRepository(
          database: widget.database,
        ),
        documentBatchRepository: DocumentBatchRepository(
          database: widget.database,
        ),
      );
      ImportRecord? record;
      if (source == 'camera') {
        final doc = await ingest.importFromInput(
          userId: _library.userId,
          libraryId: _library.id,
          source: ImageInputSource.camera,
        );
        if (doc != null) {
          record = await _records.forDocument(_library.userId, doc.id);
        }
      } else {
        final batch = await ingest.importBatchFromInput(
          userId: _library.userId,
          libraryId: _library.id,
          source: source == 'document'
              ? BatchDocumentInputSource.document
              : BatchDocumentInputSource.multiImage,
        );
        if (batch != null) {
          final sources = await DocumentBatchRepository(
            database: widget.database,
          ).getBatchWithPages(userId: _library.userId, batchId: batch.id);
          if (sources != null && sources.pages.isNotEmpty) {
            record = await _records.forDocument(
              _library.userId,
              sources.pages.first.id,
            );
          }
        }
      }
      if (!mounted) return;
      await _refresh();
      if (record != null && mounted) await _open(record, autoOcr: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入未完成：$error')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _open(ImportRecord record, {bool autoOcr = false}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImportRecordDetailPage(
          recordId: record.id,
          userId: record.userId,
          libraryId: _library.id,
          database: widget.database,
          autoOcr: autoOcr,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  /// 进入知识图谱，默认只选中当前知识库；用户仍可在图谱里组合其他知识库。
  Future<void> _openKnowledgeGraph() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KnowledgeGraphPage(
          initialLibraryIds: <int>[_library.id],
          userId: _library.userId,
          database: widget.database,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: PremiumPageBackground(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder(
            future: _future,
            builder: (context, snapshot) {
              final all = snapshot.data ?? <ImportRecord>[];
              final records = all
                  .where(
                    (r) =>
                        _source == null ||
                        (_source == 'document' ? r.isDocument : r.isCamera),
                  )
                  .toList();
              if (_oldest) {
                records.sort((a, b) => a.createdAt.compareTo(b.createdAt));
              }
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 116),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 20,
                        ),
                      ),
                      const Spacer(),
                      AskEClawButton(database:widget.database,
                        scope:EClawContext(knowledgeBaseId:widget.library.id)),
                      TextButton.icon(
                        onPressed: _manage,
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label: const Text('管理'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 78,
                        child: KnowledgeBookCover(
                          title: _library.name,
                          theme: _library.coverTheme,
                          color: _library.coverColor,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _library.name.endsWith('知识库')
                                  ? _library.name
                                  : '${_library.name}知识库',
                              maxLines: 3,
                              style: AppTextStyles.h1(context),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${all.length} 条记录 · ${_library.description?.isNotEmpty == true ? _library.description : '让知识成为你自己的宝贵财富'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _KnowledgeGraphEntry(
                    libraryName: _library.name,
                    onTap: _openKnowledgeGraph,
                  ),
                  const SizedBox(height: 14),
                  KnowledgeSearchField(
                    hint: '搜索记录、知识点…',
                    onChanged: (v) {
                      _query = v;
                      _refresh();
                    },
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final e in <String?, String>{
                          null: '全部',
                          'camera': '拍照',
                          'document': '文档',
                        }.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              showCheckmark: false,
                              visualDensity: VisualDensity.compact,
                              labelStyle: const TextStyle(fontSize: 12),
                              labelPadding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              label: Text(
                                '${e.value} (${e.key == null ? all.length : all.where((r) => e.key == 'pdf' ? r.isPdf : r.isCamera).length})',
                              ),
                              selected: _source == e.key,
                              onSelected: (_) =>
                                  setState(() => _source = e.key),
                            ),
                          ),
                        PopupMenuButton<bool>(
                          tooltip: '排序',
                          initialValue: _oldest,
                          onSelected: (v) => setState(() => _oldest = v),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: false,
                              child: Text('最近导入优先'),
                            ),
                            const PopupMenuItem(
                              value: true,
                              child: Text('最早导入优先'),
                            ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.schedule,
                                  size: 18,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 5),
                                Text(_oldest ? '最早' : '最近'),
                                const Icon(Icons.expand_more, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _importing ? null : _import,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(_importing ? '导入中…' : '导入资料'),
                    ),
                  ),
                  if (snapshot.connectionState != ConnectionState.done)
                    const LinearProgressIndicator(),
                  if (snapshot.hasError)
                    KnowledgeEmptyState(
                      title: '读取失败',
                      message: '${snapshot.error}',
                      action: TextButton(
                        onPressed: _refresh,
                        child: const Text('重试'),
                      ),
                    )
                  else if (snapshot.connectionState == ConnectionState.done &&
                      records.isEmpty)
                    KnowledgeEmptyState(
                      title: all.isEmpty && _query.isEmpty
                          ? '还没有导入记录'
                          : '没有匹配的记录',
                      message: '一次拍照、相册或文档导入，归档为一条记录。',
                      action: FilledButton.icon(
                        onPressed: _importing ? null : _import,
                        icon: const Icon(Icons.add),
                        label: const Text('导入第一份资料'),
                      ),
                    ),
                  ...records.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ImportRecordTile(record: r, onTap: () => _open(r)),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class ImportRecordTile extends StatelessWidget {
  const ImportRecordTile({
    required this.record,
    required this.onTap,
    super.key,
  });
  final ImportRecord record;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .97),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SourceThumbnail(
              source: record.pages.firstOrNull ?? record.anchor,
              width: 62,
              height: 89,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          record.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.textSecondary,
                        size: 22,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${record.anchor.createdAtLabel} · ${record.sourceLabel} · ${record.pageLabel}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF889AB7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 7,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Wrap(
                      spacing: 9,
                      runSpacing: 4,
                      children: [
                        for (final e in {
                          'knowledge_cards': '卡片',
                          'review_outlines': '提纲',
                          'practice_questions': '练习题',
                        }.entries)
                          Text(
                            '${e.value} ${record.counts[e.key] ?? 0}',
                            style: TextStyle(
                              fontSize: 11,
                              color: e.key == 'review_outlines'
                                  ? AppColors.accentOrange
                                  : e.key == 'practice_questions'
                                  ? AppColors.success
                                  : AppColors.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    record.needsLibraryReview
                        ? '${record.statusLabel} · 待整理归属'
                        : record.statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: record.errors.isNotEmpty
                          ? AppColors.error
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 单本知识库内的「查看知识图谱」入口。
class _KnowledgeGraphEntry extends StatelessWidget {
  const _KnowledgeGraphEntry({required this.libraryName, required this.onTap});

  final String libraryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.fromLTRB(15, 13, 12, 13),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFEFF6FF), Colors.white, Color(0xFFF5F3FF)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD7E4FB)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFFD7E4FB)),
              ),
              child: const Icon(
                Icons.hub_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '查看知识图谱',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '默认选中「$libraryName」，可再组合其他知识库',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption(context),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    ),
  );
}
