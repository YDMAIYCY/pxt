import 'package:flutter/material.dart';
import '../../database/app_database.dart';
import '../../database/auth_repository.dart';
import '../../database/import_record_repository.dart';
import '../../database/knowledge_library_repository.dart';
import '../../database/models/import_record.dart';
import '../../database/models/knowledge_library_record.dart';
import '../theme/app_theme.dart';
import '../widgets/knowledge_components.dart';
import '../widgets/knowledge_library_editor.dart';
import 'knowledge_record_list_page.dart';
import 'import_record_detail_page.dart';
import 'knowledge_graph_page.dart';
import 'feishu_import_page.dart';
import 'feishu_library_detail_page.dart';
import '../widgets/knowledge_book_cover.dart';
import '../widgets/knowledge_add_sheet.dart';
import '../../feishu/feishu_controller.dart';
import 'feishu_job_page.dart';

class BookLibraryPage extends StatefulWidget {
  const BookLibraryPage({
    this.refreshListenable,
    this.onDataChanged,
    this.database,
    super.key,
  });
  final ValueNotifier<int>? refreshListenable;
  final VoidCallback? onDataChanged;
  final AppDatabase? database;
  @override
  State<BookLibraryPage> createState() => _BookLibraryPageState();
}

class _BookLibraryPageState extends State<BookLibraryPage> {
  late Future<
    ({
      int userId,
      List<KnowledgeLibraryRecord> libraries,
      List<ImportRecord> records,
    })
  >
  _future;
  String _query = '';
  bool _manage = false;
  bool _openingAdd = false;
  String _sourceFilter = 'all';
  KnowledgeLibraryRepository get _libraries =>
      KnowledgeLibraryRepository(database: widget.database);
  ImportRecordRepository get _records =>
      ImportRecordRepository(database: widget.database);
  @override
  void initState() {
    super.initState();
    _future = _load();
    widget.refreshListenable?.addListener(_reload);
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_reload);
    super.dispose();
  }

  Future<
    ({
      int userId,
      List<KnowledgeLibraryRecord> libraries,
      List<ImportRecord> records,
    })
  >
  _load() async {
    final auth = AuthRepository(database: widget.database);
    await auth.ensureInitialized();
    final user = await auth.getCurrentUserProfile();
    if (user == null) throw StateError('请先登录');
    return (
      userId: user.id,
      libraries: await _libraries.fetchLibraries(
        user.id,
        source: _sourceFilter,
      ),
      records: await _records.list(user.id),
    );
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _future = _load();
      });
    }
  }

  Future<void> _refresh() async {
    _reload();
    await _future;
  }

  Future<void> _edit(int userId, [KnowledgeLibraryRecord? library]) async {
    final result = await showKnowledgeLibraryEditor(
      context,
      userId: userId,
      repository: _libraries,
      library: library,
    );
    if (result != null && mounted) {
      _reload();
      widget.onDataChanged?.call();
    }
  }

  Future<void> _open(KnowledgeLibraryRecord library) async {
    if (_manage) {
      await _edit(library.userId, library);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => library.isFeishu
            ? FeishuLibraryDetailPage(
                library: library,
                database: widget.database,
              )
            : BookDetailPage(library: library, database: widget.database),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _add(int userId) async {
    if (_openingAdd) return;
    _openingAdd = true;
    try {
      final type = await showKnowledgeAddSheet(context);
      if (!mounted || type == null) return;
      if (type == 'manual') {
        await _edit(userId);
      } else if (type == 'feishu') {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                FeishuImportPage(userId: userId, database: widget.database),
          ),
        );
      } else {
        final libraries = await _libraries.fetchLibraries(userId);
        if (!mounted) return;
        final choice = await showModalBottomSheet<Object>(
          context: context,
          showDragHandle: true,
          builder: (sheet) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('选择本地资料保存位置')),
                for (final library in libraries)
                  ListTile(
                    title: Text(library.name),
                    onTap: () => Navigator.pop(sheet, library),
                  ),
                ListTile(
                  title: const Text('创建新的知识库'),
                  onTap: () => Navigator.pop(sheet, 'new'),
                ),
              ],
            ),
          ),
        );
        if (!mounted || choice == null) return;
        final target = choice is KnowledgeLibraryRecord
            ? choice
            : await showKnowledgeLibraryEditor(
                context,
                userId: userId,
                repository: _libraries,
              );
        if (target != null && mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BookDetailPage(
                library: target,
                database: widget.database,
                autoImport: true,
              ),
            ),
          );
        }
      }
      if (mounted) {
        _reload();
        widget.onDataChanged?.call();
      }
    } finally {
      _openingAdd = false;
    }
  }

  Future<void> _jobs(int userId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FeishuJobPage(
          controller: FeishuController.forUser(
            userId,
            database: widget.database,
          ),
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _openKnowledgeGraph(int userId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            KnowledgeGraphPage(userId: userId, database: widget.database),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return KnowledgeEmptyState(
          title: '暂时无法读取知识库',
          message: '${snapshot.error}',
          action: TextButton(onPressed: _reload, child: const Text('重试')),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!;
      final query = _query.toLowerCase().trim();
      final books = data.libraries
          .where((l) => query.isEmpty || l.name.toLowerCase().contains(query))
          .toList();
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 116),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Container(
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF4FBFF), Colors.white, Color(0xFFEAF9F6)],
                ),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: const Color(0xFFCDE1FF)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.collections_bookmark_outlined,
                      color: AppColors.primary,
                      size: 29,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '学习资料知识库',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          '让知识成为你自己的宝贵财富',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8D9BB3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            KnowledgeSearchField(
              hint: '搜索知识库、记录、知识点…',
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text('我的知识库', style: AppTextStyles.h2(context)),
                ),
                IconButton(
                  onPressed: () => _openKnowledgeGraph(data.userId),
                  tooltip: '知识图谱',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.hub_rounded,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _add(data.userId),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('添加', style: TextStyle(fontSize: 13)),
                ),
                TextButton(
                  onPressed: () => setState(() => _manage = !_manage),
                  child: Text(
                    _manage ? '完成' : '管理',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final filter in const [
                  ('all', '全部'),
                  ('feishu', '飞书同步'),
                  ('local', '本地创建'),
                ])
                  ChoiceChip(
                    label: Text(filter.$2),
                    selected: _sourceFilter == filter.$1,
                    showCheckmark: false,
                    onSelected: (_) {
                      _sourceFilter = filter.$1;
                      _reload();
                    },
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _jobs(data.userId),
                child: const Text('导入任务'),
              ),
            ),
            if (_manage)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  '点击书本修改名称、简介和封面；库内管理可删除知识库。',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            if (books.isEmpty)
              KnowledgeEmptyState(
                title: query.isEmpty ? '书架还空着' : '没有匹配的知识库',
                message: query.isEmpty
                    ? '创建一本书，收好每次学习的资料。'
                    : '试试其他名称，或查看下方记录搜索结果。',
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                const columns = 2;
                final cells = [
                  ...books.map<Widget>(
                    (l) => KnowledgeBookCover(
                      title: l.name,
                      subtitle:
                          '${data.records.where((r) => r.libraryId == l.id).length} 条记录${l.isFeishu ? '\n${l.sourceLabel} · ${l.syncLabel}' : ''}',
                      theme: l.coverTheme,
                      color: l.coverColor,
                      onTap: () => _open(l),
                      onLongPress: () => _edit(data.userId, l),
                    ),
                  ),
                  if (query.isEmpty) _AddBook(onTap: () => _add(data.userId)),
                ];
                final width =
                    (constraints.maxWidth - 14 * (columns - 1)) / columns;
                return Column(
                  children: [
                    for (var start = 0; start < cells.length; start += columns)
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 25),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: -16,
                              right: -16,
                              bottom: -7,
                              height: 12,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFFF4E5D3),
                                      Color(0xFFDABC9A),
                                      Color(0xFFF3DFC7),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF8093A9,
                                      ).withValues(alpha: .18),
                                      blurRadius: 13,
                                      offset: const Offset(0, 9),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (
                                  var j = start;
                                  j < start + columns;
                                  j++
                                ) ...[
                                  if (j > start) const SizedBox(width: 14),
                                  SizedBox(
                                    width: width,
                                    child: j < cells.length
                                        ? cells[j]
                                        : const SizedBox(),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            if (query.isNotEmpty)
              _RecordSearch(
                userId: data.userId,
                query: query,
                repository: _records,
                database: widget.database,
                onReturn: _reload,
              ),
          ],
        ),
      );
    },
  );
}

class _AddBook extends StatelessWidget {
  const _AddBook({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: .70,
    child: Material(
      color: Colors.white.withValues(alpha: .3),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFCBD8EA)),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(12),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFE6ECF5),
                child: Icon(Icons.add, color: AppColors.textSecondary),
              ),
              SizedBox(height: 12),
              Text(
                '添加知识库',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              SizedBox(height: 6),
              Text(
                '创建你的专属\n知识书籍',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RecordSearch extends StatelessWidget {
  const _RecordSearch({
    required this.userId,
    required this.query,
    required this.repository,
    required this.onReturn,
    this.database,
  });
  final int userId;
  final String query;
  final ImportRecordRepository repository;
  final VoidCallback onReturn;
  final AppDatabase? database;
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: repository.list(userId, query: query),
    builder: (context, snapshot) {
      if (snapshot.hasError) return Text('搜索失败：${snapshot.error}');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('记录与知识点', style: AppTextStyles.h3(context)),
          if (snapshot.data!.isEmpty)
            const KnowledgeEmptyState(
              title: '没有匹配的记录或知识点',
              message: '换一个关键词再试试。',
            ),
          ...snapshot.data!.map(
            (r) => Card(
              child: ListTile(
                title: Text(r.title),
                subtitle: Text('${r.sourceLabel} · ${r.pageLabel}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ImportRecordDetailPage(
                        recordId: r.id,
                        userId: userId,
                        database: database,
                      ),
                    ),
                  );
                  onReturn();
                },
              ),
            ),
          ),
        ],
      );
    },
  );
}
