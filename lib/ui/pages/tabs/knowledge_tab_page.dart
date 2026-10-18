import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../database/ai_generation_repository.dart';
import '../../../database/auth_repository.dart';
import '../../../database/document_batch_repository.dart';
import '../../../database/favorite_repository.dart';
import '../../../database/knowledge_context_repository.dart';
import '../../../database/knowledge_graph_repository.dart';
import '../../../database/knowledge_library_repository.dart';
import '../../../database/models/ai_result_records.dart';
import '../../../database/models/document_batch_record.dart';
import '../../../database/models/knowledge_context_source.dart';
import '../../../database/models/knowledge_graph_records.dart';
import '../../../database/models/knowledge_library_record.dart';
import '../../../database/models/source_document_record.dart';
import '../../../database/source_document_repository.dart';
import '../../../common/app_assets.dart';
import '../../theme/app_theme.dart';
import '../../widgets/create_knowledge_library_dialog.dart';
import '../document_batch_detail_page.dart';
import '../document_detail_page.dart';

class KnowledgeTabPage extends StatefulWidget {
  const KnowledgeTabPage({
    this.authRepository,
    this.sourceDocumentRepository,
    this.aiGenerationRepository,
    this.documentBatchRepository,
    this.knowledgeGraphRepository,
    this.knowledgeLibraryRepository,
    this.refreshVersion = 0,
    this.refreshListenable,
    this.activeTabListenable,
    this.tabIndex,
    this.initialType,
    this.onDataChanged,
    super.key,
  });

  static const typeDocuments = _KnowledgeType.documents;
  static const typeBatches = _KnowledgeType.batches;
  static const typeCards = _KnowledgeType.cards;
  static const typeOutlines = _KnowledgeType.outlines;
  static const typeMindmaps = _KnowledgeType.mindmaps;
  static const typeQuestions = _KnowledgeType.questions;
  static const typeGraph = _KnowledgeType.graph;

  final AuthRepository? authRepository;
  final SourceDocumentRepository? sourceDocumentRepository;
  final AiGenerationRepository? aiGenerationRepository;
  final DocumentBatchRepository? documentBatchRepository;
  final KnowledgeGraphRepository? knowledgeGraphRepository;
  final KnowledgeLibraryRepository? knowledgeLibraryRepository;
  final int refreshVersion;
  final ValueListenable<int>? refreshListenable;
  final ValueListenable<int>? activeTabListenable;
  final int? tabIndex;
  final String? initialType;
  final VoidCallback? onDataChanged;

  @override
  State<KnowledgeTabPage> createState() => _KnowledgeTabPageState();
}

class _KnowledgeTabPageState extends State<KnowledgeTabPage> {
  late final AuthRepository _authRepository;
  late final SourceDocumentRepository _sourceDocumentRepository;
  late final AiGenerationRepository _aiGenerationRepository;
  late final DocumentBatchRepository _documentBatchRepository;
  late final KnowledgeGraphRepository _knowledgeGraphRepository;
  late final KnowledgeLibraryRepository _knowledgeLibraryRepository;
  late final FavoriteRepository _favoriteRepository;
  late final KnowledgeContextRepository _knowledgeContextRepository;
  late Future<_KnowledgeData> _future;
  late int _handledRefreshVersion;
  bool _reloadScheduled = false;
  late String _selectedType;
  int? _selectedLibraryId;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _sourceDocumentRepository =
        widget.sourceDocumentRepository ?? SourceDocumentRepository();
    _aiGenerationRepository =
        widget.aiGenerationRepository ?? AiGenerationRepository();
    _documentBatchRepository =
        widget.documentBatchRepository ?? DocumentBatchRepository();
    _knowledgeGraphRepository =
        widget.knowledgeGraphRepository ?? KnowledgeGraphRepository();
    _knowledgeLibraryRepository =
        widget.knowledgeLibraryRepository ?? KnowledgeLibraryRepository();
    _favoriteRepository = FavoriteRepository();
    _knowledgeContextRepository = KnowledgeContextRepository();
    _selectedType = _normalizeType(widget.initialType);
    _handledRefreshVersion = widget.refreshVersion;
    widget.refreshListenable?.addListener(_handleExternalRefresh);
    widget.activeTabListenable?.addListener(_handleExternalRefresh);
    _future = _loadData();
  }

  @override
  void didUpdateWidget(covariant KnowledgeTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_handleExternalRefresh);
      widget.refreshListenable?.addListener(_handleExternalRefresh);
    }
    if (oldWidget.activeTabListenable != widget.activeTabListenable) {
      oldWidget.activeTabListenable?.removeListener(_handleExternalRefresh);
      widget.activeTabListenable?.addListener(_handleExternalRefresh);
    }
    if (widget.refreshVersion != _handledRefreshVersion) {
      _handledRefreshVersion = widget.refreshVersion;
      _scheduleReload();
    }
    if (oldWidget.initialType != widget.initialType &&
        widget.initialType != null) {
      setState(() => _selectedType = _normalizeType(widget.initialType));
    }
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_handleExternalRefresh);
    widget.activeTabListenable?.removeListener(_handleExternalRefresh);
    super.dispose();
  }

  bool get _canHandleExternalRefresh {
    final tabIndex = widget.tabIndex;
    final activeTab = widget.activeTabListenable?.value;
    return tabIndex == null || activeTab == null || activeTab == tabIndex;
  }

  void _handleExternalRefresh() {
    if (!_canHandleExternalRefresh) return;
    _scheduleReload();
  }

  String _normalizeType(String? type) {
    const supportedTypes = {
      _KnowledgeType.documents,
      _KnowledgeType.batches,
      _KnowledgeType.cards,
      _KnowledgeType.outlines,
      _KnowledgeType.mindmaps,
      _KnowledgeType.questions,
      _KnowledgeType.graph,
    };
    return supportedTypes.contains(type) ? type! : _KnowledgeType.documents;
  }

  void _scheduleReload() {
    if (!mounted || _reloadScheduled) return;
    _reloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reloadScheduled = false;
      _reload();
    });
  }

  Future<_KnowledgeData> _loadData() async {
    await _authRepository.ensureInitialized();
    final user = await _authRepository.getCurrentUserProfile();
    if (user == null) throw StateError('登录状态已失效');

    final libraries = await _knowledgeLibraryRepository.fetchLibraries(user.id);
    final selectedLibrary = _resolveSelectedLibrary(libraries);
    final documents = await _sourceDocumentRepository.fetchAllSourceDocuments(
      userId: user.id,
      libraryId: selectedLibrary.id,
      limit: 300,
    );
    final batches = await _documentBatchRepository.fetchRecentBatches(
      userId: user.id,
      libraryId: selectedLibrary.id,
      limit: 300,
    );
    final contents = await _aiGenerationRepository.fetchRecentGeneratedContents(
      userId: user.id,
      libraryId: selectedLibrary.id,
      limit: 300,
    );
    final weakConcepts = await _knowledgeGraphRepository.fetchWeakConcepts(
      userId: user.id,
      libraryId: selectedLibrary.id,
      limit: 500,
    );
    final graphLinks = await _knowledgeGraphRepository.fetchLinksByLibrary(
      userId: user.id,
      libraryId: selectedLibrary.id,
      limit: 300,
    );
    final favoriteKeys = await _fetchFavoriteKeysSafely(user.id);

    return _KnowledgeData(
      userId: user.id,
      libraries: libraries,
      selectedLibrary: selectedLibrary,
      batches: batches,
      documents: documents,
      contents: contents,
      weakConcepts: weakConcepts,
      graphLinks: graphLinks,
      favoriteKeys: favoriteKeys,
    );
  }

  KnowledgeLibraryRecord _resolveSelectedLibrary(
    List<KnowledgeLibraryRecord> libraries,
  ) {
    final selected = libraries.cast<KnowledgeLibraryRecord?>().firstWhere(
      (library) => library?.id == _selectedLibraryId,
      orElse: () => null,
    );
    final fallback = selected ?? libraries.first;
    _selectedLibraryId = fallback.id;
    return fallback;
  }

  Future<void> _refresh() async {
    final future = _reload();
    await future;
  }

  Future<_KnowledgeData> _reload() {
    final future = _loadData();
    setState(() {
      _future = future;
    });
    return future;
  }

  Future<void> _afterDataChanged() async {
    final onDataChanged = widget.onDataChanged;
    if (onDataChanged != null) {
      onDataChanged();
      return;
    }
    await _refresh();
  }

  Future<Set<String>> _fetchFavoriteKeysSafely(int userId) async {
    try {
      return await _favoriteRepository.fetchFavoriteKeys(userId);
    } catch (_) {
      return const <String>{};
    }
  }

  Future<void> _openSearch(_KnowledgeData data) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _KnowledgeSearchPage(
          userId: data.userId,
          libraryId: data.selectedLibrary.id,
          libraryName: data.selectedLibrary.name,
          knowledgeContextRepository: _knowledgeContextRepository,
          onOpenDocument: _openDocument,
        ),
      ),
    );
  }

  Future<void> _toggleGeneratedFavorite(GeneratedContentRecord item) async {
    final data = await _future;
    final favorited = await _favoriteRepository.toggleFavorite(
      userId: data.userId,
      targetType: FavoriteRepository.targetTypeForGeneratedContent(
        item.contentType,
      ),
      targetId: item.sourceId,
    );
    if (!mounted) return;
    _showMessage(favorited ? '已加入收藏' : '已取消收藏');
    await _reload();
  }

  void _selectLibrary(int libraryId) {
    setState(() {
      _selectedLibraryId = libraryId;
      _future = _loadData();
    });
  }

  Future<void> _openTypePage(
    _KnowledgeData data,
    String type,
    List<_KnowledgeTypeItem> typeItems,
  ) async {
    setState(() => _selectedType = type);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _KnowledgeTypeDetailPage(
          libraryName: data.selectedLibrary.name,
          typeTitle: _typeTitle(typeItems, type),
          count: _typeCount(typeItems, type),
          child: _buildTypeList(data, type),
        ),
      ),
    );
    if (mounted) await _afterDataChanged();
  }

  Future<void> _openDocument(int documentId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentDetailPage(documentId: documentId),
      ),
    );
    if (mounted) await _afterDataChanged();
  }

  Future<void> _openBatch(int batchId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentBatchDetailPage(batchId: batchId),
      ),
    );
    if (mounted) await _afterDataChanged();
  }

  Future<void> _createLibrary(int userId) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const CreateKnowledgeLibraryDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      final library = await _knowledgeLibraryRepository.createLibrary(
        userId: userId,
        name: name,
      );
      _selectedLibraryId = library.id;
      if (mounted) {
        _showMessage('已创建知识库：${library.name}');
        await _afterDataChanged();
      }
    } catch (error) {
      if (mounted) _showMessage('创建知识库失败：$error');
    }
  }

  Future<void> _deleteCurrentLibrary(_KnowledgeData data) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除"${data.selectedLibrary.name}"？'),
        content: Text(
          '会同时删除这个知识库下的 ${data.documents.length} 份资料，以及相关 OCR 文本、AI 结果、练习题和错题记录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _knowledgeLibraryRepository.deleteLibraryAndContents(
        userId: data.userId,
        libraryId: data.selectedLibrary.id,
      );
      _selectedLibraryId = null;
      if (mounted) {
        _showMessage('知识库已删除');
        await _afterDataChanged();
      }
    } catch (error) {
      if (mounted) _showMessage('删除知识库失败：$error');
    }
  }

  Future<void> _moveDocument(_KnowledgeData data, int documentId) async {
    final targetLibraries = data.libraries
        .where((library) => library.id != data.selectedLibrary.id)
        .toList(growable: false);
    if (targetLibraries.isEmpty) {
      _showMessage('请先创建另一个知识库');
      return;
    }

    final targetId = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('移动到哪个知识库', style: AppTextStyles.h3(sheetContext)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView(
                  shrinkWrap: true,
                  children: targetLibraries
                      .map(
                        (library) => ListTile(
                          leading: const Icon(Icons.drive_file_move_rounded),
                          title: Text(library.name),
                          subtitle: Text('${library.documentCount} 份资料'),
                          onTap: () =>
                              Navigator.of(sheetContext).pop(library.id),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (targetId == null) return;
    try {
      await _sourceDocumentRepository.moveDocumentToLibrary(
        userId: data.userId,
        documentId: documentId,
        libraryId: targetId,
      );
      if (mounted) {
        _showMessage('已移动到目标知识库');
        await _afterDataChanged();
      }
    } catch (error) {
      if (mounted) _showMessage('移动失败：$error');
    }
  }

  Future<void> _deleteDocument(_KnowledgeData data, int documentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这份资料？'),
        content: const Text('会同时删除它的 OCR 文本、AI 结果、练习题和错题记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _sourceDocumentRepository.deleteDocument(
        userId: data.userId,
        documentId: documentId,
      );
      if (mounted) {
        _showMessage('资料已删除');
        await _afterDataChanged();
      }
    } catch (error) {
      if (mounted) _showMessage('删除失败：$error');
    }
  }

  Future<void> _deleteBatch(_KnowledgeData data, int batchId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这个学习包？'),
        content: const Text('会同时删除学习包下全部页资料、OCR 文本、AI 结果、练习题和错题记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _documentBatchRepository.deleteBatch(
        userId: data.userId,
        batchId: batchId,
      );
      if (mounted) {
        _showMessage('学习包已删除');
        await _afterDataChanged();
      }
    } catch (error) {
      if (mounted) _showMessage('删除学习包失败：$error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_KnowledgeData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _StatePanel(
            icon: Icons.error_outline_rounded,
            title: '知识库加载失败',
            description: '请稍后重试。',
            onPressed: _refresh,
          );
        }
        final data = snapshot.data!;
        final typeItems = _buildTypeItems(data);

        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 100),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(data: data),
                      const SizedBox(height: 14),
                      _SearchEntry(
                        libraryName: data.selectedLibrary.name,
                        onTap: () => _openSearch(data),
                      ),
                      const SizedBox(height: 14),
                      _LibrarySelector(
                        libraries: data.libraries,
                        selectedLibrary: data.selectedLibrary,
                        onSelected: _selectLibrary,
                        onCreate: () => _createLibrary(data.userId),
                        onDeleteSelected: () => _deleteCurrentLibrary(data),
                      ),
                      const SizedBox(height: 14),
                      _TypeSelector(
                        items: typeItems,
                        selectedType: _selectedType,
                        onSelected: (type) =>
                            _openTypePage(data, type, typeItems),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<_KnowledgeTypeItem> _buildTypeItems(_KnowledgeData data) {
    return [
      _KnowledgeTypeItem(
        type: _KnowledgeType.batches,
        title: '学习包',
        count: data.batchImportGroups.length,
        icon: Icons.folder_copy_rounded,
        color: const Color(0xFFF0FDFA),
        foreground: AppColors.primary,
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.documents,
        title: '讲义资料',
        count: data.documentImportGroups.length,
        icon: Icons.menu_book_rounded,
        color: const Color(0xFFEFF6FF),
        foreground: AppColors.secondaryBlue,
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.cards,
        title: '知识卡片',
        count: data.contentImportGroupsOf(_KnowledgeType.cards).length,
        icon: Icons.style_rounded,
        color: const Color(0xFFF0FDF4),
        foreground: AppColors.success,
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.outlines,
        title: '复习提纲',
        count: data.contentImportGroupsOf(_KnowledgeType.outlines).length,
        icon: Icons.list_alt_rounded,
        color: const Color(0xFFFFF7ED),
        foreground: AppColors.accentOrange,
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.mindmaps,
        title: '思维导图文字',
        count: data.contentImportGroupsOf(_KnowledgeType.mindmaps).length,
        icon: Icons.account_tree_rounded,
        color: const Color(0xFFF5F3FF),
        foreground: AppColors.secondaryPurple,
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.questions,
        title: '练习题',
        count: data.contentImportGroupsOf(_KnowledgeType.questions).length,
        icon: Icons.quiz_rounded,
        color: const Color(0xFFFDF2F8),
        foreground: AppColors.error,
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.graph,
        title: '知识图谱',
        count: data.weakConcepts.length,
        icon: Icons.hub_rounded,
        color: const Color(0xFFEFF6FF),
        foreground: AppColors.info,
      ),
    ];
  }

  String _typeTitle(List<_KnowledgeTypeItem> items, String type) {
    return items
        .firstWhere((item) => item.type == type, orElse: () => items.first)
        .title;
  }

  int _typeCount(List<_KnowledgeTypeItem> items, String type) {
    return items
        .firstWhere((item) => item.type == type, orElse: () => items.first)
        .count;
  }

  Widget _buildTypeList(_KnowledgeData data, String type) {
    if (type == _KnowledgeType.batches) {
      final groups = data.batchImportGroups;
      if (groups.isEmpty) {
        return const _EmptyListHint(text: '这个知识库还没有多页学习包。');
      }
      return Column(
        children: groups
            .map(
              (group) => _ImportRecordGroupTile(
                group: group,
                onDelete: group.batch == null
                    ? null
                    : () => _deleteBatch(data, group.batch!.id),
                children: [
                  _GroupActionTile(
                    icon: Icons.open_in_new_rounded,
                    title: '打开学习包',
                    subtitle: '进入后可逐页 OCR、生成 AI 结果和刷题',
                    onTap: group.batch == null
                        ? null
                        : () => _openBatch(group.batch!.id),
                  ),
                  ...group.documents.map(
                    (document) => _DocumentTile(
                      document: document,
                      onTap: () => _openDocument(document.id),
                      onMove: () => _moveDocument(data, document.id),
                      onDelete: () => _deleteDocument(data, document.id),
                    ),
                  ),
                ],
              ),
            )
            .toList(growable: false),
      );
    }

    if (type == _KnowledgeType.documents) {
      final groups = data.documentImportGroups;
      if (groups.isEmpty) {
        return const _EmptyListHint(text: '这个知识库还没有讲义资料。');
      }
      return Column(
        children: groups
            .map(
              (group) => _ImportRecordGroupTile(
                group: group,
                children: group.documents
                    .map(
                      (document) => _DocumentTile(
                        document: document,
                        onTap: () => _openDocument(document.id),
                        onMove: () => _moveDocument(data, document.id),
                        onDelete: () => _deleteDocument(data, document.id),
                      ),
                    )
                    .toList(growable: false),
              ),
            )
            .toList(growable: false),
      );
    }

    if (type == _KnowledgeType.graph) {
      if (data.weakConcepts.isEmpty) {
        return const _EmptyListHint(text: '生成 AI 学习成果后，这里会展示知识点和薄弱程度。');
      }
      return _KnowledgeGraphPanel(
        concepts: data.weakConcepts,
        links: data.graphLinks,
        documents: data.documents,
        onOpenConcept: (item) {
          final documentId = item.concept.documentId;
          if (documentId == null) return;
          _openDocument(documentId);
        },
      );
    }

    final groups = data.contentImportGroupsOf(type);
    if (groups.isEmpty) return const _EmptyListHint(text: '这个知识库的分类还没有真实结果。');
    return Column(
      children: groups
          .map(
            (group) => _ImportRecordGroupTile(
              group: group,
              children: group.contents
                  .map(
                    (item) => _ContentTile(
                      title: item.title,
                      subtitle: '${item.documentTitle} / ${item.contentLabel}',
                      body: item.summary,
                      onTap: () => _openDocument(item.documentId),
                      onMove: () => _moveDocument(data, item.documentId),
                      onDelete: () => _deleteDocument(data, item.documentId),
                      isFavorited: data.favoriteKeys.contains(
                        FavoriteRepository.favoriteKey(
                          FavoriteRepository.targetTypeForGeneratedContent(
                            item.contentType,
                          ),
                          item.sourceId,
                        ),
                      ),
                      onFavorite: () => _toggleGeneratedFavorite(item),
                    ),
                  )
                  .toList(growable: false),
            ),
          )
          .toList(growable: false),
    );
  }
}

// ========== Knowledge Search ==========
class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.libraryName, required this.onTap});

  final String libraryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: AppShadows.cardSoftList,
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '搜索题目、知识点、错题、资料标题、AI 总结',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(context).copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                libraryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall(context).copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KnowledgeSearchPage extends StatefulWidget {
  const _KnowledgeSearchPage({
    required this.userId,
    required this.libraryId,
    required this.libraryName,
    required this.knowledgeContextRepository,
    required this.onOpenDocument,
  });

  final int userId;
  final int? libraryId;
  final String libraryName;
  final KnowledgeContextRepository knowledgeContextRepository;
  final ValueChanged<int> onOpenDocument;

  @override
  State<_KnowledgeSearchPage> createState() => _KnowledgeSearchPageState();
}

class _KnowledgeSearchPageState extends State<_KnowledgeSearchPage> {
  final TextEditingController _controller = TextEditingController();
  Future<List<KnowledgeContextSource>>? _future;
  String _selectedType = 'all';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _runSearch() {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _future = widget.knowledgeContextRepository.search(
        userId: widget.userId,
        libraryId: widget.libraryId,
        query: query,
        limit: 40,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('搜索知识库')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                hintText: '搜索',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: _runSearch,
                ),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: AppColors.borderLight),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _SearchFilterChips(
              selectedType: _selectedType,
              onChanged: (type) => setState(() => _selectedType = type),
            ),
            const SizedBox(height: 14),
            Text(
              '当前搜索 ${widget.libraryName}。支持关键词搜索；类似“我之前拍过一道关于二次函数顶点的题”这类自然语言，会先按关键词召回相关资料。',
              style: AppTextStyles.bodySmall(
                context,
              ).copyWith(color: AppColors.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 16),
            if (_future == null)
              const _EmptyListHint(text: '输入关键词后开始搜索。')
            else
              FutureBuilder<List<KnowledgeContextSource>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final results = _filteredResults(snapshot.data ?? const []);
                  if (results.isEmpty) {
                    return const _EmptyListHint(text: '没有找到匹配内容，换个关键词试试。');
                  }
                  return Column(
                    children: results
                        .map(
                          (source) => _SearchResultTile(
                            source: source,
                            onTap: () =>
                                widget.onOpenDocument(source.documentId),
                          ),
                        )
                        .toList(growable: false),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  List<KnowledgeContextSource> _filteredResults(
    List<KnowledgeContextSource> results,
  ) {
    if (_selectedType == 'all') return results;
    if (_selectedType == 'wrong') {
      return results
          .where(
            (item) =>
                item.sourceType ==
                    KnowledgeContextSourceType.practiceQuestion &&
                item.snippet.contains('错'),
          )
          .toList(growable: false);
    }
    return results
        .where((item) => item.sourceType == _selectedType)
        .toList(growable: false);
  }
}

class _SearchFilterChips extends StatelessWidget {
  const _SearchFilterChips({
    required this.selectedType,
    required this.onChanged,
  });

  final String selectedType;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const filters = [
      ('all', '全部'),
      (KnowledgeContextSourceType.knowledgeGraph, '知识点'),
      (KnowledgeContextSourceType.knowledgeCard, '知识卡片'),
      (KnowledgeContextSourceType.practiceQuestion, '题目'),
      (KnowledgeContextSourceType.ocrText, '资料/OCR'),
      (KnowledgeContextSourceType.reviewOutline, 'AI 总结'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(item.$2),
                  selected: selectedType == item.$1,
                  onSelected: (_) => onChanged(item.$1),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.source, required this.onTap});

  final KnowledgeContextSource source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _BaseTile(
      icon: _iconFor(source.sourceType),
      title: source.title.isEmpty ? source.documentTitle : source.title,
      subtitle: '${source.documentTitle} / ${source.sourceLabel}',
      body: source.snippet,
      onTap: onTap,
      onMove: null,
      onDelete: () {},
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case KnowledgeContextSourceType.knowledgeGraph:
        return Icons.hub_rounded;
      case KnowledgeContextSourceType.knowledgeCard:
        return Icons.style_rounded;
      case KnowledgeContextSourceType.practiceQuestion:
        return Icons.quiz_rounded;
      case KnowledgeContextSourceType.reviewOutline:
        return Icons.summarize_rounded;
      default:
        return Icons.description_rounded;
    }
  }
}

// ========== Header ==========
class _Header extends StatelessWidget {
  const _Header({required this.data});
  final _KnowledgeData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primarySoft.withValues(alpha: 0.72),
            Colors.white,
            const Color(0xFFEFF9FF),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primaryLight),
        boxShadow: AppShadows.cardSoftList,
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 2,
            bottom: 2,
            width: 500,
            child: Opacity(
              opacity: 0.5,
              child: Image.asset(
                AppAssets.knowledgeHeaderIllustration,
                fit: BoxFit.contain,
                alignment: Alignment.centerRight,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppShadows.cardSoftList,
                ),
                child: const Icon(
                  Icons.collections_bookmark_rounded,
                  color: AppColors.primary,
                  size: 25,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 72),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.selectedLibrary.name,
                        maxLines: 3,
                        softWrap: true,
                        style: AppTextStyles.h1(
                          context,
                        ).copyWith(fontWeight: FontWeight.w900, fontSize: 22),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ========== Library Selector ==========
class _LibrarySelector extends StatelessWidget {
  const _LibrarySelector({
    required this.libraries,
    required this.selectedLibrary,
    required this.onSelected,
    required this.onCreate,
    required this.onDeleteSelected,
  });
  final List<KnowledgeLibraryRecord> libraries;
  final KnowledgeLibraryRecord selectedLibrary;
  final ValueChanged<int> onSelected;
  final VoidCallback onCreate;
  final VoidCallback onDeleteSelected;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '选择知识库',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: '新建知识库',
            child: TextButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              label: const Text('添加'),
            ),
          ),
          Container(width: 1, height: 18, color: AppColors.borderLight),
          Tooltip(
            message: '删除当前知识库',
            child: TextButton.icon(
              onPressed: onDeleteSelected,
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              label: const Text('删除'),
            ),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: libraries
              .map((library) {
                final selected = library.id == selectedLibrary.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: InkWell(
                    onTap: () => onSelected(library.id),
                    borderRadius: BorderRadius.circular(14),
                    child: Ink(
                      width: 180,
                      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primarySoft
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : AppColors.borderLight,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (selected) ...[
                            const Icon(
                              Icons.check_rounded,
                              color: AppColors.textSecondary,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  library.name,
                                  maxLines: 2,
                                  softWrap: true,
                                  style: AppTextStyles.bodySmall(context)
                                      .copyWith(
                                        color: selected
                                            ? AppColors.primaryDark
                                            : AppColors.textSecondary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${library.documentCount} 条',
                                  style: AppTextStyles.bodySmall(context)
                                      .copyWith(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w700,
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
              })
              .toList(growable: false),
        ),
      ),
    );
  }
}

class CurrentTypeHeader extends StatelessWidget {
  const CurrentTypeHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '当前：$title',
            maxLines: 2,
            softWrap: true,
            style: AppTextStyles.h3(
              context,
            ).copyWith(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

// ========== Type Selector ==========
class _KnowledgeTypeDetailPage extends StatelessWidget {
  const _KnowledgeTypeDetailPage({
    required this.libraryName,
    required this.typeTitle,
    required this.count,
    required this.child,
  });

  final String libraryName;
  final String typeTitle;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(typeTitle)),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.borderLight),
                        boxShadow: AppShadows.cardSoftList,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            libraryName,
                            maxLines: 2,
                            softWrap: true,
                            style: AppTextStyles.bodySmall(context).copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            typeTitle,
                            maxLines: 2,
                            softWrap: true,
                            style: AppTextStyles.h1(
                              context,
                            ).copyWith(fontSize: 24),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '共 $count 条，按导入/生成时间排序',
                            style: AppTextStyles.bodySmall(context).copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    child,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({
    required this.items,
    required this.selectedType,
    required this.onSelected,
  });
  final List<_KnowledgeTypeItem> items;
  final String selectedType;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: itemWidth,
                  child: _TypeCard(
                    item: item,
                    selected: selectedType == item.type,
                    onTap: () => onSelected(item.type),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final _KnowledgeTypeItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          height: 124,
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
          decoration: BoxDecoration(
            color: item.color,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
            boxShadow: AppShadows.cardSoftList,
          ),
          child: Stack(
            children: [
              Positioned(
                right: -8,
                bottom: -12,
                child: Icon(
                  item.icon,
                  color: item.foreground.withValues(alpha: 0.045),
                  size: 34,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: item.foreground,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(item.icon, color: Colors.white, size: 18),
                  ),
                  const Spacer(),
                  Text(
                    item.title,
                    maxLines: 2,
                    softWrap: true,
                    style: AppTextStyles.h3(
                      context,
                    ).copyWith(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${item.count} 条',
                    style: AppTextStyles.bodySmall(context).copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========== Import Record Groups ==========
class _ImportRecordGroupTile extends StatelessWidget {
  const _ImportRecordGroupTile({
    required this.group,
    required this.children,
    this.onDelete,
  });

  final _ImportRecordGroup group;
  final List<Widget> children;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final iconColor = group.color;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppShadows.cardSoftList,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(group.icon, color: iconColor),
          ),
          title: Text(
            group.title,
            maxLines: 3,
            softWrap: true,
            style: AppTextStyles.h3(
              context,
            ).copyWith(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              group.subtitle,
              maxLines: 3,
              softWrap: true,
              style: AppTextStyles.bodySmall(context).copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${group.itemCount}',
                  style: AppTextStyles.bodySmall(
                    context,
                  ).copyWith(color: iconColor, fontWeight: FontWeight.w900),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.textTertiary,
              ),
              if (onDelete != null)
                PopupMenuButton<String>(
                  tooltip: '导入记录操作',
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: AppColors.textTertiary,
                  ),
                  onSelected: (_) => onDelete?.call(),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'delete', child: Text('删除这次导入')),
                  ],
                ),
            ],
          ),
          children: children,
        ),
      ),
    );
  }
}

class _GroupActionTile extends StatelessWidget {
  const _GroupActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.body(context).copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: AppTextStyles.bodySmall(context).copyWith(
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ========== Content Tiles ==========
class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.onTap,
    required this.onMove,
    required this.onDelete,
  });
  final SourceDocumentRecord document;
  final VoidCallback onTap, onMove, onDelete;

  @override
  Widget build(BuildContext context) {
    return _BaseTile(
      icon: Icons.picture_as_pdf_rounded,
      title: document.title,
      subtitle: '${document.sourceTypeLabel} | ${document.createdAtLabel}',
      body:
          'OCR ${document.ocrStatusLabel} | AI ${document.aiDone ? '已生成' : '待生成'}',
      onTap: onTap,
      onMove: onMove,
      onDelete: onDelete,
    );
  }
}

class _ContentTile extends StatelessWidget {
  const _ContentTile({
    required this.title,
    required this.subtitle,
    required this.body,
    required this.onTap,
    required this.onMove,
    required this.onDelete,
    this.isFavorited = false,
    this.onFavorite,
  });
  final String title, subtitle, body;
  final VoidCallback onTap, onDelete;
  final VoidCallback? onMove;
  final bool isFavorited;
  final VoidCallback? onFavorite;

  @override
  Widget build(BuildContext context) {
    return _BaseTile(
      icon: Icons.auto_stories_rounded,
      title: title,
      subtitle: subtitle,
      body: body,
      onTap: onTap,
      onMove: onMove,
      onDelete: onDelete,
      trailing: onFavorite == null
          ? null
          : IconButton(
              tooltip: isFavorited ? '取消收藏' : '收藏',
              onPressed: onFavorite,
              icon: Icon(
                isFavorited ? Icons.star_rounded : Icons.star_border_rounded,
                color: isFavorited
                    ? const Color(0xFFF59E0B)
                    : AppColors.textSecondary,
              ),
            ),
    );
  }
}

class _ConceptTile extends StatelessWidget {
  const _ConceptTile({required this.item, required this.onTap});

  final KnowledgeConceptWithDocument item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final concept = item.concept;
    final bodyParts = <String>[
      if (concept.summary?.isNotEmpty == true) concept.summary!,
      if (concept.evidenceText?.isNotEmpty == true)
        '证据：${concept.evidenceText!}',
    ];

    return _BaseTile(
      icon: Icons.hub_rounded,
      title: concept.name,
      subtitle:
          '${item.documentTitle} / 薄弱 ${concept.weaknessScore} / 掌握 ${concept.masteryScore}',
      body: bodyParts.join('\n'),
      onTap: onTap,
      onMove: null,
      onDelete: () {},
    );
  }
}

// ========== Knowledge Graph View ==========
enum _GraphViewMode { library, document }

class _KnowledgeGraphPanel extends StatefulWidget {
  const _KnowledgeGraphPanel({
    required this.concepts,
    required this.links,
    required this.documents,
    required this.onOpenConcept,
  });

  final List<KnowledgeConceptWithDocument> concepts;
  final List<KnowledgeConceptLinkRecord> links;
  final List<SourceDocumentRecord> documents;
  final ValueChanged<KnowledgeConceptWithDocument> onOpenConcept;

  @override
  State<_KnowledgeGraphPanel> createState() => _KnowledgeGraphPanelState();
}

class _KnowledgeGraphPanelState extends State<_KnowledgeGraphPanel> {
  _GraphViewMode _mode = _GraphViewMode.library;
  int? _selectedDocumentId;
  int? _selectedNodeId;
  int? _selectedLinkId;
  final TransformationController _transformController =
      TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  Set<int> _highlightedNodeIds(
    int? nodeId,
    int? linkId,
    List<_GraphNode> nodes,
    List<KnowledgeConceptLinkRecord> links,
  ) {
    final connected = <int>{};
    if (nodeId != null) {
      connected.add(nodeId);
    }
    if (linkId != null) {
      for (final link in links) {
        if (link.id != linkId) continue;
        connected
          ..add(link.fromConceptId)
          ..add(link.toConceptId);
      }
    }
    if (connected.isEmpty) return {};
    for (final link in links) {
      if (nodeId != null && link.fromConceptId == nodeId) {
        connected.add(link.toConceptId);
      }
      if (nodeId != null && link.toConceptId == nodeId) {
        connected.add(link.fromConceptId);
      }
    }
    return connected;
  }

  void _showNodeDetail(KnowledgeConceptWithDocument item) {
    final concept = item.concept;
    final status = _masteryStatus(concept);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _masteryColor(status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.psychology_rounded,
                    color: _masteryColor(status),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        concept.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _masteryLabel(status),
                        style: TextStyle(
                          color: _masteryColor(status),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (concept.summary != null && concept.summary!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                concept.summary!,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Color(0xFF475569),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                _MiniBadge(label: '掌握度', value: '${concept.masteryScore}'),
                const SizedBox(width: 12),
                _MiniBadge(label: '薄弱指数', value: '${concept.weaknessScore}'),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  widget.onOpenConcept(item);
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('查看来源资料'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showLinkDetail(
    KnowledgeConceptLinkRecord link,
    Map<int, _GraphNode> nodeById,
  ) {
    final from = nodeById[link.fromConceptId]?.item;
    final to = nodeById[link.toConceptId]?.item;
    final relation = link.relationLabel.trim().isEmpty
        ? '关联'
        : link.relationLabel.trim();
    final color = _KnowledgeGraphPainter.relationColor(relation);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.35)),
                  ),
                  child: Icon(Icons.call_split_rounded, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        relation,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${from?.concept.name ?? '未知知识点'}  →  ${to?.concept.name ?? '未知知识点'}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              _relationExplanation(relation),
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _MiniBadge(
                    label: '起点掌握',
                    value: '${from?.concept.masteryScore ?? 0}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniBadge(
                    label: '终点掌握',
                    value: '${to?.concept.masteryScore ?? 0}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _relationExplanation(String relation) {
    if (relation.contains('前置') || relation.contains('依赖')) {
      return '这条边表示左侧知识点是右侧知识点的前置基础。若终点掌握不稳，优先回到起点补基础。';
    }
    if (relation.contains('易错') || relation.contains('漏洞')) {
      return '这条边表示两个知识点之间存在常见混淆或错因传导，需要通过错题和专项训练一起巩固。';
    }
    if (relation.contains('包含') || relation.contains('属于')) {
      return '这条边表示知识点之间存在层级归属关系，可从上位概念进入分支细节。';
    }
    return '这条边表示两个知识点在当前资料中存在学习关联，适合放在同一次复习中一起理解。';
  }

  @override
  Widget build(BuildContext context) {
    final documentsWithGraph = widget.documents
        .where(
          (document) => widget.concepts.any(
            (item) => item.concept.documentId == document.id,
          ),
        )
        .toList(growable: false);
    final resolvedMode =
        _mode == _GraphViewMode.document && documentsWithGraph.isNotEmpty
        ? _GraphViewMode.document
        : _GraphViewMode.library;
    final selectedDocumentId = _resolveSelectedDocumentId(documentsWithGraph);
    final scopedConcepts = resolvedMode == _GraphViewMode.document
        ? widget.concepts
              .where((item) => item.concept.documentId == selectedDocumentId)
              .toList(growable: false)
        : widget.concepts;
    final visibleConcepts = scopedConcepts.take(36).toList(growable: false);
    final visibleConceptIds = visibleConcepts
        .map((item) => item.concept.id)
        .toSet();
    final visibleLinks = widget.links
        .where(
          (link) =>
              visibleConceptIds.contains(link.fromConceptId) &&
              visibleConceptIds.contains(link.toConceptId),
        )
        .take(120)
        .toList(growable: false);
    final rootConcept = visibleConcepts.first.concept;
    final graphScopeLabel = resolvedMode == _GraphViewMode.document
        ? _documentTitle(documentsWithGraph, selectedDocumentId)
        : '整个知识库';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: AppShadows.cardSoftList,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.hub_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '知识图谱',
                          style: AppTextStyles.h3(
                            context,
                          ).copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$graphScopeLabel · 主干：${rootConcept.name} · ${visibleConcepts.length} 个知识点 · ${visibleLinks.length} 条关系',
                          maxLines: 2,
                          softWrap: true,
                          style: AppTextStyles.bodySmall(context).copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _GraphModeChip(
                    label: '整个知识库',
                    selected: resolvedMode == _GraphViewMode.library,
                    onTap: () => setState(() => _mode = _GraphViewMode.library),
                  ),
                  _GraphModeChip(
                    label: '单次导入资料',
                    selected: resolvedMode == _GraphViewMode.document,
                    onTap: documentsWithGraph.isEmpty
                        ? null
                        : () => setState(() {
                            _mode = _GraphViewMode.document;
                            _selectedDocumentId ??= documentsWithGraph.first.id;
                          }),
                  ),
                  if (resolvedMode == _GraphViewMode.document)
                    _GraphDocumentDropdown(
                      documents: documentsWithGraph,
                      selectedDocumentId: selectedDocumentId,
                      onChanged: (documentId) {
                        if (documentId == null) return;
                        setState(() => _selectedDocumentId = documentId);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _MasteryMapSummary(concepts: visibleConcepts),
              const SizedBox(height: 14),
              SizedBox(
                height: 430,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      // 图谱画布
                      DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8FAFC),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final graphMetrics = _GraphCanvasMetrics.fromGraph(
                              concepts: visibleConcepts,
                              links: visibleLinks,
                            );
                            final graphWidth = graphMetrics.widthFor(
                              constraints.maxWidth,
                            );
                            final graphHeight = graphMetrics.heightFor(
                              constraints.maxHeight,
                            );

                            // 计算节点布局（供边线和 widget 共用）
                            final computedNodes =
                                _KnowledgeGraphPainter.computeLayout(
                                  visibleConcepts,
                                  visibleLinks,
                                  Size(graphWidth, graphHeight),
                                );
                            final highlightedIds = _highlightedNodeIds(
                              _selectedNodeId,
                              _selectedLinkId,
                              computedNodes,
                              visibleLinks,
                            );
                            final nodeById = {
                              for (final node in computedNodes)
                                node.item.concept.id: node,
                            };

                            return InteractiveViewer(
                              constrained: false,
                              minScale: 0.25,
                              maxScale: 6.0,
                              transformationController: _transformController,
                              boundaryMargin: const EdgeInsets.symmetric(
                                horizontal: 800,
                                vertical: 600,
                              ),
                              child: SizedBox(
                                width: graphWidth,
                                height: graphHeight,
                                child: Stack(
                                  children: [
                                    CustomPaint(
                                      painter: _GraphVectorPainter(
                                        nodes: computedNodes,
                                        links: visibleLinks,
                                        selectedNodeId: _selectedNodeId,
                                        selectedLinkId: _selectedLinkId,
                                        highlightedNodeIds: highlightedIds,
                                      ),
                                      size: Size(graphWidth, graphHeight),
                                    ),
                                    ...visibleLinks.map(
                                      (link) => _GraphLinkHitTarget(
                                        link: link,
                                        nodeById: nodeById,
                                        onTap: () {
                                          setState(() {
                                            _selectedNodeId = null;
                                            _selectedLinkId =
                                                _selectedLinkId == link.id
                                                ? null
                                                : link.id;
                                          });
                                          _showLinkDetail(link, nodeById);
                                        },
                                      ),
                                    ),
                                    ...computedNodes.map(
                                      (node) => _GraphNodeHitTarget(
                                        rect: node.rect,
                                        onTap: () {
                                          setState(() {
                                            final alreadySelected =
                                                _selectedNodeId ==
                                                node.item.concept.id;
                                            _selectedNodeId = alreadySelected
                                                ? null
                                                : node.item.concept.id;
                                            _selectedLinkId = null;
                                          });
                                          _showNodeDetail(node.item);
                                        },
                                      ),
                                    ),
                                    // 无节点占位
                                    if (computedNodes.isEmpty)
                                      const Center(
                                        child: Text(
                                          '暂无知识点数据',
                                          style: TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      // 顶部：缩放控件
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ZoomButton(
                              icon: Icons.add_rounded,
                              onTap: () {
                                final scale = _transformController.value
                                    .getMaxScaleOnAxis();
                                _transformController.value =
                                    Matrix4.diagonal3Values(
                                      (scale * 1.3).clamp(0.25, 6.0),
                                      (scale * 1.3).clamp(0.25, 6.0),
                                      1,
                                    );
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 4),
                            _ZoomButton(
                              icon: Icons.remove_rounded,
                              onTap: () {
                                final scale = _transformController.value
                                    .getMaxScaleOnAxis();
                                _transformController.value =
                                    Matrix4.diagonal3Values(
                                      (scale / 1.3).clamp(0.25, 6.0),
                                      (scale / 1.3).clamp(0.25, 6.0),
                                      1,
                                    );
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 4),
                            _ZoomButton(
                              icon: Icons.fit_screen_rounded,
                              size: 18,
                              onTap: () {
                                _transformController.value = Matrix4.identity();
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                      // 选中节点时显示提示
                      if (_selectedNodeId != null)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Text(
                              '点击空白取消选中',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _GraphLegend(label: '掌握', color: AppColors.success),
                  _GraphLegend(label: '待巩固', color: Color(0xFFF59E0B)),
                  _GraphLegend(label: '薄弱/危险', color: AppColors.error),
                  _GraphLegend(label: '未学习', color: Color(0xFF94A3B8)),
                  _GraphLegend(label: '前置依赖线', color: Color(0xFF7C3AED)),
                  _GraphLegend(label: '包含归属线', color: Color(0xFF0F766E)),
                  _GraphLegend(label: '易错风险线', color: AppColors.error),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          resolvedMode == _GraphViewMode.document ? '本资料知识点' : '主干知识点',
          style: AppTextStyles.h3(
            context,
          ).copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        ...visibleConcepts
            .take(12)
            .map(
              (item) => _ConceptTile(
                item: item,
                onTap: () => widget.onOpenConcept(item),
              ),
            ),
      ],
    );
  }

  int? _resolveSelectedDocumentId(List<SourceDocumentRecord> documents) {
    if (documents.isEmpty) return null;
    final selected = _selectedDocumentId;
    if (selected != null &&
        documents.any((document) => document.id == selected)) {
      return selected;
    }
    return documents.first.id;
  }

  String _documentTitle(List<SourceDocumentRecord> documents, int? documentId) {
    final matched = documents.cast<SourceDocumentRecord?>().firstWhere(
      (document) => document?.id == documentId,
      orElse: () => null,
    );
    return matched?.title ?? '单次导入资料';
  }
}

class _GraphModeChip extends StatelessWidget {
  const _GraphModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall(context).copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _GraphDocumentDropdown extends StatelessWidget {
  const _GraphDocumentDropdown({
    required this.documents,
    required this.selectedDocumentId,
    required this.onChanged,
  });

  final List<SourceDocumentRecord> documents;
  final int? selectedDocumentId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: selectedDocumentId,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          items: documents
              .map(
                (document) => DropdownMenuItem<int>(
                  value: document.id,
                  child: Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _MasteryMapSummary extends StatelessWidget {
  const _MasteryMapSummary({required this.concepts});

  final List<KnowledgeConceptWithDocument> concepts;

  @override
  Widget build(BuildContext context) {
    final mastered = concepts
        .where(
          (item) => _masteryStatus(item.concept) == _MasteryStatus.mastered,
        )
        .length;
    final reviewing = concepts
        .where(
          (item) => _masteryStatus(item.concept) == _MasteryStatus.reviewing,
        )
        .length;
    final weak = concepts
        .where((item) => _masteryStatus(item.concept) == _MasteryStatus.weak)
        .length;
    final untouched = concepts
        .where(
          (item) => _masteryStatus(item.concept) == _MasteryStatus.untouched,
        )
        .length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '知识点掌握地图',
            style: AppTextStyles.h3(
              context,
            ).copyWith(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MasteryStatPill(
                label: '掌握',
                count: mastered,
                color: AppColors.success,
              ),
              _MasteryStatPill(
                label: '待巩固',
                count: reviewing,
                color: const Color(0xFFF59E0B),
              ),
              _MasteryStatPill(
                label: '薄弱',
                count: weak,
                color: AppColors.error,
              ),
              _MasteryStatPill(
                label: '未学习',
                count: untouched,
                color: const Color(0xFF94A3B8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...concepts.take(6).map((item) {
            final concept = item.concept;
            final status = _masteryStatus(concept);
            final color = _masteryColor(status);
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          concept.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall(
                            context,
                          ).copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        '${_masteryLabel(status)} ${concept.masteryScore}%',
                        style: AppTextStyles.bodySmall(
                          context,
                        ).copyWith(color: color, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 7,
                      value: concept.masteryScore.clamp(0, 100) / 100,
                      backgroundColor: color.withValues(alpha: 0.13),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _MasteryStatPill extends StatelessWidget {
  const _MasteryStatPill({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $count',
        style: AppTextStyles.bodySmall(
          context,
        ).copyWith(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

enum _MasteryStatus { mastered, reviewing, weak, untouched }

_MasteryStatus _masteryStatus(KnowledgeConceptRecord concept) {
  if (concept.masteryScore <= 0 && concept.weaknessScore <= 0) {
    return _MasteryStatus.untouched;
  }
  if (concept.weaknessScore >= 70 || concept.masteryScore < 40) {
    return _MasteryStatus.weak;
  }
  if (concept.masteryScore >= 80) {
    return _MasteryStatus.mastered;
  }
  return _MasteryStatus.reviewing;
}

Color _masteryColor(_MasteryStatus status) {
  switch (status) {
    case _MasteryStatus.mastered:
      return AppColors.success;
    case _MasteryStatus.reviewing:
      return const Color(0xFFF59E0B);
    case _MasteryStatus.weak:
      return AppColors.error;
    case _MasteryStatus.untouched:
      return const Color(0xFF94A3B8);
  }
}

String _masteryLabel(_MasteryStatus status) {
  switch (status) {
    case _MasteryStatus.mastered:
      return '已掌握';
    case _MasteryStatus.reviewing:
      return '待巩固';
    case _MasteryStatus.weak:
      return '薄弱';
    case _MasteryStatus.untouched:
      return '未学习';
  }
}

class _GraphCanvasMetrics {
  const _GraphCanvasMetrics({required this.layerCount, required this.maxRows});

  final int layerCount;
  final int maxRows;

  static const double _nodeWidth = 92;
  static const double _nodeHeight = 92;
  static const double _sidePadding = 38;
  static const double _topPadding = 38;
  static const double _layerGap = 132;
  static const double _rowGap = 34;

  factory _GraphCanvasMetrics.fromGraph({
    required List<KnowledgeConceptWithDocument> concepts,
    required List<KnowledgeConceptLinkRecord> links,
  }) {
    if (concepts.isEmpty) {
      return const _GraphCanvasMetrics(layerCount: 1, maxRows: 1);
    }

    final layers = _buildRelationshipLayers(concepts, links);
    final maxRows = layers.fold<int>(
      1,
      (maxValue, layer) => math.max(maxValue, layer.length),
    );
    return _GraphCanvasMetrics(
      layerCount: math.max(1, layers.length),
      maxRows: maxRows,
    );
  }

  double widthFor(double viewportWidth) {
    final requiredWidth =
        _sidePadding * 2 + _nodeWidth + math.max(0, layerCount - 1) * _layerGap;
    return math.max(viewportWidth, requiredWidth + _sidePadding);
  }

  double heightFor(double viewportHeight) {
    final requiredHeight =
        _topPadding * 2 +
        maxRows * _nodeHeight +
        math.max(0, maxRows - 1) * _rowGap;
    return math.max(viewportHeight, requiredHeight + _topPadding);
  }

  static List<List<KnowledgeConceptWithDocument>> _buildRelationshipLayers(
    List<KnowledgeConceptWithDocument> concepts,
    List<KnowledgeConceptLinkRecord> links,
  ) {
    final byId = {for (final item in concepts) item.concept.id: item};
    final visibleIds = byId.keys.toSet();
    final outgoing = <int, List<int>>{};
    final incoming = <int, List<int>>{};

    for (final link in links) {
      if (!visibleIds.contains(link.fromConceptId) ||
          !visibleIds.contains(link.toConceptId)) {
        continue;
      }
      outgoing.putIfAbsent(link.fromConceptId, () => []).add(link.toConceptId);
      incoming.putIfAbsent(link.toConceptId, () => []).add(link.fromConceptId);
    }

    final rootId = _pickRootId(concepts, outgoing, incoming);
    final depthById = <int, int>{rootId: 0};
    final queue = <int>[rootId];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final depth = depthById[current] ?? 0;
      final nextIds = <int>{...?outgoing[current], ...?incoming[current]};
      for (final nextId in nextIds) {
        if (depthById.containsKey(nextId)) continue;
        depthById[nextId] = depth + 1;
        queue.add(nextId);
      }
    }

    var fallbackDepth = depthById.values.isEmpty
        ? 1
        : depthById.values.reduce(math.max) + 1;
    for (final item in concepts) {
      if (depthById.containsKey(item.concept.id)) continue;
      depthById[item.concept.id] = fallbackDepth;
      if ((depthById.length - 1) % 5 == 0) fallbackDepth++;
    }

    final grouped = <int, List<KnowledgeConceptWithDocument>>{};
    for (final item in concepts) {
      grouped.putIfAbsent(depthById[item.concept.id] ?? 0, () => []).add(item);
    }

    final orderedDepths = grouped.keys.toList()..sort();
    return orderedDepths
        .map((depth) => grouped[depth]!)
        .toList(growable: false);
  }

  static int _pickRootId(
    List<KnowledgeConceptWithDocument> concepts,
    Map<int, List<int>> outgoing,
    Map<int, List<int>> incoming,
  ) {
    final firstId = concepts.first.concept.id;
    if (outgoing.containsKey(firstId) || incoming.containsKey(firstId)) {
      return firstId;
    }
    var bestId = firstId;
    var bestDegree = -1;
    for (final item in concepts) {
      final id = item.concept.id;
      final degree = (outgoing[id]?.length ?? 0) + (incoming[id]?.length ?? 0);
      if (degree > bestDegree) {
        bestDegree = degree;
        bestId = id;
      }
    }
    return bestId;
  }
}

// ========== 图谱布局计算核心 ==========
class _GraphLayoutComputer {
  _GraphLayoutComputer({required this.concepts, required this.links});

  final List<KnowledgeConceptWithDocument> concepts;
  final List<KnowledgeConceptLinkRecord> links;

  List<_GraphNode> compute(Size size) {
    const nodeWidth = 92.0;
    const nodeHeight = 92.0;
    const sidePadding = 38.0;
    const topPadding = 38.0;
    const layerGap = 132.0;
    const rowGap = 34.0;

    final layers = _buildRelationshipLayers();
    final layerCount = math.max(1, layers.length);
    final availableWidth = math.max(1, size.width - sidePadding * 2);
    final computedLayerGap = layerCount <= 1
        ? 0.0
        : math.max(
            layerGap,
            (availableWidth - nodeWidth) / math.max(1, layerCount - 1),
          );
    final nodes = <_GraphNode>[];

    for (var layerIndex = 0; layerIndex < layers.length; layerIndex++) {
      final layer = layers[layerIndex];
      final columnHeight =
          layer.length * nodeHeight + math.max(0, layer.length - 1) * rowGap;
      final startY = math.max(topPadding, (size.height - columnHeight) / 2);
      final x = sidePadding + nodeWidth / 2 + layerIndex * computedLayerGap;

      for (var rowIndex = 0; rowIndex < layer.length; rowIndex++) {
        final item = layer[rowIndex];
        final y = startY + nodeHeight / 2 + rowIndex * (nodeHeight + rowGap);
        nodes.add(
          _GraphNode(
            item: item,
            rect: Rect.fromCenter(
              center: Offset(x, y),
              width: nodeWidth,
              height: nodeHeight,
            ),
          ),
        );
      }
    }
    return nodes;
  }

  List<List<KnowledgeConceptWithDocument>> _buildRelationshipLayers() {
    final byId = {for (final item in concepts) item.concept.id: item};
    final visibleIds = byId.keys.toSet();
    final outgoing = <int, List<int>>{};
    final incoming = <int, List<int>>{};

    for (final link in links) {
      if (!visibleIds.contains(link.fromConceptId) ||
          !visibleIds.contains(link.toConceptId)) {
        continue;
      }
      outgoing.putIfAbsent(link.fromConceptId, () => []).add(link.toConceptId);
      incoming.putIfAbsent(link.toConceptId, () => []).add(link.fromConceptId);
    }

    final rootId = _pickRootId(outgoing, incoming);
    final depthById = <int, int>{rootId: 0};
    final queue = <int>[rootId];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final depth = depthById[current] ?? 0;
      final nextIds = <int>{...?outgoing[current], ...?incoming[current]};
      for (final nextId in nextIds) {
        if (depthById.containsKey(nextId)) continue;
        depthById[nextId] = depth + 1;
        queue.add(nextId);
      }
    }

    var fallbackDepth = depthById.values.isEmpty
        ? 1
        : depthById.values.reduce(math.max) + 1;
    for (final item in concepts) {
      if (depthById.containsKey(item.concept.id)) continue;
      depthById[item.concept.id] = fallbackDepth;
      if ((depthById.length - 1) % 5 == 0) fallbackDepth++;
    }

    final grouped = <int, List<KnowledgeConceptWithDocument>>{};
    for (final item in concepts) {
      grouped.putIfAbsent(depthById[item.concept.id] ?? 0, () => []).add(item);
    }

    final orderedDepths = grouped.keys.toList()..sort();
    return orderedDepths
        .map((depth) {
          final layer = grouped[depth]!;
          layer.sort((a, b) {
            final aDegree =
                (outgoing[a.concept.id]?.length ?? 0) +
                (incoming[a.concept.id]?.length ?? 0);
            final bDegree =
                (outgoing[b.concept.id]?.length ?? 0) +
                (incoming[b.concept.id]?.length ?? 0);
            return bDegree.compareTo(aDegree);
          });
          return layer;
        })
        .toList(growable: false);
  }

  int _pickRootId(Map<int, List<int>> outgoing, Map<int, List<int>> incoming) {
    final firstId = concepts.first.concept.id;
    if (outgoing.containsKey(firstId) || incoming.containsKey(firstId)) {
      return firstId;
    }
    var bestId = firstId;
    var bestDegree = -1;
    for (final item in concepts) {
      final id = item.concept.id;
      final degree = (outgoing[id]?.length ?? 0) + (incoming[id]?.length ?? 0);
      if (degree > bestDegree) {
        bestDegree = degree;
        bestId = id;
      }
    }
    return bestId;
  }
}

class _KnowledgeGraphPainter extends CustomPainter {
  const _KnowledgeGraphPainter({required this.concepts, required this.links});

  final List<KnowledgeConceptWithDocument> concepts;
  final List<KnowledgeConceptLinkRecord> links;

  static List<_GraphNode> computeLayout(
    List<KnowledgeConceptWithDocument> concepts,
    List<KnowledgeConceptLinkRecord> links,
    Size size,
  ) {
    if (concepts.isEmpty) return [];
    return _GraphLayoutComputer(concepts: concepts, links: links).compute(size);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (concepts.isEmpty) return;
    final nodes = computeLayout(concepts, links, size);
    final nodeById = {for (final node in nodes) node.item.concept.id: node};
    final edgeLabels = <_GraphEdgeLabel>[];

    for (final link in links) {
      final from = nodeById[link.fromConceptId];
      final to = nodeById[link.toConceptId];
      if (from == null || to == null) continue;
      edgeLabels.add(_drawRelationEdge(canvas, from, to, link));
    }
  }

  // ---------------------------------------------------------------
  // 以下方法与 _GraphEdgePainter 共享，保持静态/无状态以便复用
  // ---------------------------------------------------------------

  @override
  bool shouldRepaint(covariant _KnowledgeGraphPainter oldDelegate) {
    return oldDelegate.concepts != concepts || oldDelegate.links != links;
  }

  static Color nodeColor(KnowledgeConceptRecord concept) {
    return _masteryColor(_masteryStatus(concept));
  }

  static Color relationColor(String relationLabel) {
    final text = relationLabel.trim();
    if (text.contains('易错') || text.contains('漏洞')) return AppColors.error;
    if (text.contains('前置') || text.contains('依赖')) {
      return const Color(0xFF7C3AED);
    }
    if (text.contains('包含') || text.contains('属于')) {
      return const Color(0xFF0F766E);
    }
    return const Color(0xFF475569);
  }

  static Offset edgePoint(Rect rect, Offset toward) {
    final center = rect.center;
    final dx = toward.dx - center.dx;
    final dy = toward.dy - center.dy;
    if (dx == 0 && dy == 0) return center;
    final angle = math.atan2(dy, dx);
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    if (rx == 0 || ry == 0) return center;
    final t =
        1 / math.sqrt((cosA * cosA) / (rx * rx) + (sinA * sinA) / (ry * ry));
    return center + Offset(t * cosA, t * sinA);
  }

  static void drawArrowHead(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
  ) {
    final direction = end - start;
    final len = direction.distance;
    if (len == 0) return;
    final unit = direction / len;
    final normal = Offset(-unit.dy, unit.dx);
    final tip = end;
    final base = end - unit * 14;
    final wing = unit * 6 + normal * 5;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(base.dx - wing.dx, base.dy - wing.dy)
        ..lineTo(base.dx + wing.dx, base.dy + wing.dy)
        ..close(),
      Paint()..color = color.withValues(alpha: 0.78),
    );
  }

  static Offset cubicPoint(
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
    double t,
  ) {
    final u = 1 - t;
    return p0 * (u * u * u) +
        p1 * (3 * u * u * t) +
        p2 * (3 * u * t * t) +
        p3 * (t * t * t);
  }

  static String shorten(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength - 1)}…';
  }

  // ---- Instance helpers delegating to static ----

  Color _relationColor(String label) => relationColor(label);
  Offset _edgePoint(Rect r, Offset t) => edgePoint(r, t);
  void _drawArrowHead(Canvas c, Offset s, Offset e, Color cl) =>
      drawArrowHead(c, s, e, cl);
  Offset _cubicPoint(Offset p0, Offset p1, Offset p2, Offset p3, double t) =>
      cubicPoint(p0, p1, p2, p3, t);

  _GraphEdgeLabel _drawRelationEdge(
    Canvas canvas,
    _GraphNode from,
    _GraphNode to,
    KnowledgeConceptLinkRecord link,
  ) {
    final color = _relationColor(link.relationLabel);
    final start = _edgePoint(from.rect, to.rect.center);
    final end = _edgePoint(to.rect, from.rect.center);
    final sameColumn = (start.dx - end.dx).abs() < 12;
    final controlOffset = sameColumn
        ? Offset(72, (end.dy - start.dy) * 0.18)
        : Offset(math.max(44, (end.dx - start.dx).abs() * 0.36), 0);
    final control1 = sameColumn
        ? start + controlOffset
        : Offset(start.dx + controlOffset.dx, start.dy);
    final control2 = sameColumn
        ? end + controlOffset
        : Offset(end.dx - controlOffset.dx, end.dy);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        end.dx,
        end.dy,
      );
    final paint = Paint()
      ..color = color.withValues(alpha: 0.78)
      ..strokeWidth = 1.9
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, paint);
    _drawArrowHead(canvas, control2, end, color);
    final center = _cubicPoint(start, control1, control2, end, 0.5);
    final nearStart = _cubicPoint(start, control1, control2, end, 0.36);
    final nearEnd = _cubicPoint(start, control1, control2, end, 0.64);
    final direction = end - start;
    final normal = direction.distance == 0
        ? const Offset(0, -1)
        : Offset(-direction.dy, direction.dx) / direction.distance;
    return _GraphEdgeLabel(
      text: link.relationLabel,
      centers: [
        center + normal * 18,
        center - normal * 18,
        nearStart + normal * 20,
        nearEnd - normal * 20,
        nearStart - normal * 20,
        nearEnd + normal * 20,
      ],
    );
  }
}

class _GraphNode {
  const _GraphNode({required this.item, required this.rect});

  final KnowledgeConceptWithDocument item;
  final Rect rect;
}

class _GraphEdgeLabel {
  const _GraphEdgeLabel({required this.text, required this.centers});

  final String text;
  final List<Offset> centers;
}

class _GraphLegend extends StatelessWidget {
  const _GraphLegend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.bodySmall(context).copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ========== 矢量图谱绘制器 ==========
class _GraphVectorPainter extends CustomPainter {
  _GraphVectorPainter({
    required this.nodes,
    required this.links,
    this.selectedNodeId,
    this.selectedLinkId,
    this.highlightedNodeIds = const {},
  });

  final List<_GraphNode> nodes;
  final List<KnowledgeConceptLinkRecord> links;
  final int? selectedNodeId;
  final int? selectedLinkId;
  final Set<int> highlightedNodeIds;

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    _drawBackgroundGrid(canvas, size);
    final nodeById = {for (final node in nodes) node.item.concept.id: node};
    final edgeLabels = <_GraphEdgeLabel>[];
    final isHighlightMode = selectedNodeId != null || selectedLinkId != null;

    for (final link in links) {
      final from = nodeById[link.fromConceptId];
      final to = nodeById[link.toConceptId];
      if (from == null || to == null) continue;
      final isHighlighted =
          isHighlightMode &&
          (link.fromConceptId == selectedNodeId ||
              link.toConceptId == selectedNodeId ||
              highlightedNodeIds.contains(link.fromConceptId) &&
                  highlightedNodeIds.contains(link.toConceptId));
      edgeLabels.add(
        _drawRelationEdge(
          canvas,
          from,
          to,
          link,
          isHighlighted || link.id == selectedLinkId,
        ),
      );
    }

    final occupiedRects = nodes
        .map((node) => node.rect.inflate(8))
        .toList(growable: true);
    for (final edgeLabel in edgeLabels) {
      _drawLabel(canvas, edgeLabel, occupiedRects);
    }
    for (final node in nodes) {
      _drawNode(canvas, node, isHighlightMode);
    }
  }

  void _drawBackgroundGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE2E8F0).withValues(alpha: 0.55)
      ..strokeWidth = 0.7;
    const gap = 48.0;
    for (var x = 0.0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  _GraphEdgeLabel _drawRelationEdge(
    Canvas canvas,
    _GraphNode from,
    _GraphNode to,
    KnowledgeConceptLinkRecord link,
    bool isHighlighted,
  ) {
    final color = _KnowledgeGraphPainter.relationColor(link.relationLabel);
    final start = _KnowledgeGraphPainter.edgePoint(from.rect, to.rect.center);
    final end = _KnowledgeGraphPainter.edgePoint(to.rect, from.rect.center);
    final sameColumn = (start.dx - end.dx).abs() < 12;
    final controlOffset = sameColumn
        ? Offset(72, (end.dy - start.dy) * 0.18)
        : Offset(math.max(44, (end.dx - start.dx).abs() * 0.36), 0);
    final control1 = sameColumn
        ? start + controlOffset
        : Offset(start.dx + controlOffset.dx, start.dy);
    final control2 = sameColumn
        ? end + controlOffset
        : Offset(end.dx - controlOffset.dx, end.dy);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        end.dx,
        end.dy,
      );

    final strokeWidth = isHighlighted ? 3.4 : 1.8;
    final alpha = isHighlighted ? 0.98 : 0.42;
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke,
    );
    _KnowledgeGraphPainter.drawArrowHead(canvas, control2, end, color);
    final center = _KnowledgeGraphPainter.cubicPoint(
      start,
      control1,
      control2,
      end,
      0.5,
    );
    final nearStart = _KnowledgeGraphPainter.cubicPoint(
      start,
      control1,
      control2,
      end,
      0.36,
    );
    final nearEnd = _KnowledgeGraphPainter.cubicPoint(
      start,
      control1,
      control2,
      end,
      0.64,
    );
    final direction = end - start;
    final normal = direction.distance == 0
        ? const Offset(0, -1)
        : Offset(-direction.dy, direction.dx) / direction.distance;
    return _GraphEdgeLabel(
      text: link.relationLabel,
      centers: [
        center + normal * 18,
        center - normal * 18,
        nearStart + normal * 20,
        nearEnd - normal * 20,
        nearStart - normal * 20,
        nearEnd + normal * 20,
      ],
    );
  }

  void _drawLabel(
    Canvas canvas,
    _GraphEdgeLabel label,
    List<Rect> occupiedRects,
  ) {
    final text = label.text.trim().isEmpty ? '关联' : label.text.trim();
    final textPainter = TextPainter(
      text: TextSpan(
        text: _KnowledgeGraphPainter.shorten(text, 14),
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 124);
    final chosenRect = _pickLabelRect(
      label.centers,
      Size(textPainter.width + 14, textPainter.height + 7),
      occupiedRects,
    );
    final rect = RRect.fromRectAndRadius(chosenRect, const Radius.circular(9));
    occupiedRects.add(chosenRect.inflate(5));
    canvas.drawRRect(
      rect,
      Paint()..color = Colors.white.withValues(alpha: 0.96),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    textPainter.paint(
      canvas,
      chosenRect.center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  void _drawNode(Canvas canvas, _GraphNode node, bool isHighlightMode) {
    final concept = node.item.concept;
    final color = _KnowledgeGraphPainter.nodeColor(concept);
    final isSelected = concept.id == selectedNodeId;
    final isHighlighted = highlightedNodeIds.contains(concept.id);
    final opacity = !isHighlightMode || isSelected || isHighlighted
        ? 1.0
        : 0.36;
    final center = node.rect.center;
    final radius = node.rect.width / 2 - 5;
    final score = concept.masteryScore.clamp(0, 100);

    canvas.drawCircle(
      center,
      radius + 9,
      Paint()..color = color.withValues(alpha: 0.08 * opacity),
    );
    canvas.drawCircle(
      center,
      radius + 3,
      Paint()..color = color.withValues(alpha: 0.13 * opacity),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 5 : (isHighlighted ? 3.5 : 2.4),
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 8),
      -math.pi / 2,
      math.pi * 2 * score / 100,
      false,
      Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5,
    );

    final titlePainter = TextPainter(
      text: TextSpan(
        text: _KnowledgeGraphPainter.shorten(concept.name, 12),
        style: TextStyle(
          color: color.withValues(alpha: opacity),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          height: 1.12,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: node.rect.width - 18);
    titlePainter.paint(
      canvas,
      center - Offset(titlePainter.width / 2, titlePainter.height / 2 + 6),
    );

    final scorePainter = TextPainter(
      text: TextSpan(
        text: '$score',
        style: TextStyle(
          color: Colors.white.withValues(alpha: opacity),
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final scoreRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, node.rect.bottom - 15),
        width: scorePainter.width + 14,
        height: scorePainter.height + 5,
      ),
      const Radius.circular(999),
    );
    canvas.drawRRect(
      scoreRect,
      Paint()..color = color.withValues(alpha: opacity),
    );
    scorePainter.paint(
      canvas,
      scoreRect.outerRect.center -
          Offset(scorePainter.width / 2, scorePainter.height / 2),
    );
  }

  Rect _pickLabelRect(
    List<Offset> centers,
    Size size,
    List<Rect> occupiedRects,
  ) {
    Rect rectFor(Offset center) =>
        Rect.fromCenter(center: center, width: size.width, height: size.height);
    for (final center in centers) {
      final rect = rectFor(center);
      if (!occupiedRects.any((occupied) => occupied.overlaps(rect))) {
        return rect;
      }
    }
    return rectFor(centers.first);
  }

  @override
  bool shouldRepaint(covariant _GraphVectorPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.links != links ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.selectedLinkId != selectedLinkId ||
        oldDelegate.highlightedNodeIds != highlightedNodeIds;
  }
}

// ========== 图谱透明交互热区 ==========
class _GraphNodeHitTarget extends StatelessWidget {
  const _GraphNodeHitTarget({required this.rect, required this.onTap});

  final Rect rect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GraphLinkHitTarget extends StatelessWidget {
  const _GraphLinkHitTarget({
    required this.link,
    required this.nodeById,
    required this.onTap,
  });

  final KnowledgeConceptLinkRecord link;
  final Map<int, _GraphNode> nodeById;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final from = nodeById[link.fromConceptId];
    final to = nodeById[link.toConceptId];
    if (from == null || to == null) {
      return const SizedBox.shrink();
    }
    final center = _GraphInteractionGeometry.edgeCenter(from.rect, to.rect);
    return Positioned(
      left: center.dx - 46,
      top: center.dy - 28,
      width: 92,
      height: 56,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GraphInteractionGeometry {
  const _GraphInteractionGeometry._();

  static Offset edgeCenter(Rect from, Rect to) {
    final start = _KnowledgeGraphPainter.edgePoint(from, to.center);
    final end = _KnowledgeGraphPainter.edgePoint(to, from.center);
    final sameColumn = (start.dx - end.dx).abs() < 12;
    final controlOffset = sameColumn
        ? Offset(72, (end.dy - start.dy) * 0.18)
        : Offset(math.max(44, (end.dx - start.dx).abs() * 0.36), 0);
    final control1 = sameColumn
        ? start + controlOffset
        : Offset(start.dx + controlOffset.dx, start.dy);
    final control2 = sameColumn
        ? end + controlOffset
        : Offset(end.dx - controlOffset.dx, end.dy);
    return _KnowledgeGraphPainter.cubicPoint(
      start,
      control1,
      control2,
      end,
      0.5,
    );
  }
}

// ========== 缩放按钮 ==========
class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.icon, required this.onTap, this.size = 22});

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(10),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          child: Icon(icon, size: size, color: const Color(0xFF334155)),
        ),
      ),
    );
  }
}

// ========== 迷你指标徽章 ==========
class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BaseTile extends StatelessWidget {
  const _BaseTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.onTap,
    required this.onMove,
    required this.onDelete,
    this.trailing,
  });
  final IconData icon;
  final String title, subtitle, body;
  final VoidCallback onTap, onDelete;
  final VoidCallback? onMove;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppColors.error, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 4,
                        softWrap: true,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (body.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          body,
                          maxLines: 6,
                          softWrap: true,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.35,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
                PopupMenuButton<String>(
                  tooltip: '鍐呭鎿嶄綔',
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: AppColors.textTertiary,
                  ),
                  onSelected: (value) {
                    if (value == 'move') {
                      onMove?.call();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    if (onMove != null)
                      const PopupMenuItem(
                        value: 'move',
                        child: Text('移动到其他知识库'),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('删除资料和结果'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ========== Common widgets ==========
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppShadows.cardSoftList,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.h3(
                    context,
                  ).copyWith(fontSize: 19, fontWeight: FontWeight.w900),
                ),
              ),
              trailing ?? const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _EmptyListHint extends StatelessWidget {
  const _EmptyListHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTextStyles.bodySmall(context),
      ),
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
  });
  final IconData icon;
  final String title, description;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => onPressed(),
              child: const Text('閲嶈瘯'),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== Data models ==========
class _KnowledgeData {
  const _KnowledgeData({
    required this.userId,
    required this.libraries,
    required this.selectedLibrary,
    required this.batches,
    required this.documents,
    required this.contents,
    required this.weakConcepts,
    required this.graphLinks,
    required this.favoriteKeys,
  });

  final int userId;
  final List<KnowledgeLibraryRecord> libraries;
  final KnowledgeLibraryRecord selectedLibrary;
  final List<DocumentBatchRecord> batches;
  final List<SourceDocumentRecord> documents;
  final List<GeneratedContentRecord> contents;
  final List<KnowledgeConceptWithDocument> weakConcepts;
  final List<KnowledgeConceptLinkRecord> graphLinks;
  final Set<String> favoriteKeys;

  int get totalCount =>
      batches.length + documents.length + contents.length + weakConcepts.length;
  int countByType(String type) => contentsOf(type).length;
  List<GeneratedContentRecord> contentsOf(String type) => contents
      .where((item) => item.contentType == type)
      .toList(growable: false);

  List<_ImportRecordGroup> get batchImportGroups {
    final documentsByBatch = <int, List<SourceDocumentRecord>>{};
    for (final document in documents) {
      final batchId = document.batchId;
      if (batchId == null) continue;
      documentsByBatch.putIfAbsent(batchId, () => []).add(document);
    }

    final groups = batches
        .map(
          (batch) => _ImportRecordGroup(
            key: 'batch:${batch.id}',
            title: batch.title,
            subtitle:
                '${batch.sourceTypeLabel} / ${batch.pageCount} 页 / ${batch.createdAtLabel}',
            icon: Icons.folder_copy_rounded,
            color: AppColors.primary,
            createdAt: batch.createdAt,
            batch: batch,
            documents: _sortDocuments(documentsByBatch[batch.id] ?? const []),
            itemCount: math.max(
              batch.pageCount,
              documentsByBatch[batch.id]?.length ?? 0,
            ),
          ),
        )
        .toList(growable: false);
    return _sortGroups(groups);
  }

  List<_ImportRecordGroup> get documentImportGroups {
    final groups = <_ImportRecordGroup>[
      ...batchImportGroups.map(
        (group) => group.copyWith(
          subtitle: '${group.subtitle} / ${group.documents.length} 页资料',
          icon: Icons.auto_stories_rounded,
          color: AppColors.secondaryBlue,
        ),
      ),
      ...documents
          .where((document) => document.batchId == null)
          .map(
            (document) => _ImportRecordGroup(
              key: 'document:${document.id}',
              title: document.title,
              subtitle:
                  '${document.sourceTypeLabel} / ${document.createdAtLabel} / OCR ${document.ocrStatusLabel}',
              icon: Icons.menu_book_rounded,
              color: AppColors.secondaryBlue,
              createdAt: document.createdAt,
              documents: [document],
              itemCount: 1,
            ),
          ),
    ];
    return _sortGroups(groups);
  }

  List<_ImportRecordGroup> contentImportGroupsOf(String type) {
    final typedContents = contentsOf(type);
    if (typedContents.isEmpty) return const <_ImportRecordGroup>[];

    final documentsById = {
      for (final document in documents) document.id: document,
    };
    final batchesById = {for (final batch in batches) batch.id: batch};
    final groupedContents = <String, List<GeneratedContentRecord>>{};

    for (final item in typedContents) {
      final document = documentsById[item.documentId];
      final key = document?.batchId == null
          ? 'document:${item.documentId}'
          : 'batch:${document!.batchId}';
      groupedContents.putIfAbsent(key, () => []).add(item);
    }

    final groups = groupedContents.entries
        .map((entry) {
          final items = entry.value
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final first = items.first;
          final document = documentsById[first.documentId];
          final batch = document?.batchId == null
              ? null
              : batchesById[document!.batchId];
          final groupDocuments = batch == null
              ? [?document]
              : _sortDocuments(
                  documents.where((item) => item.batchId == batch.id).toList(),
                );

          return _ImportRecordGroup(
            key: entry.key,
            title: batch?.title ?? document?.title ?? first.documentTitle,
            subtitle:
                '${batch?.sourceTypeLabel ?? document?.sourceTypeLabel ?? '资料'} / ${_formatImportTime(batch?.createdAt ?? document?.createdAt ?? first.createdAt)} / ${items.length} 条${first.contentLabel}',
            icon: _iconForContentType(type),
            color: _colorForContentType(type),
            createdAt:
                batch?.createdAt ?? document?.createdAt ?? first.createdAt,
            batch: batch,
            documents: groupDocuments,
            contents: items,
            itemCount: items.length,
          );
        })
        .toList(growable: false);

    return _sortGroups(groups);
  }

  static List<SourceDocumentRecord> _sortDocuments(
    List<SourceDocumentRecord> value,
  ) {
    return [...value]..sort((a, b) {
      final pageCompare = (a.pageNumber ?? 0).compareTo(b.pageNumber ?? 0);
      if (pageCompare != 0) return pageCompare;
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  static List<_ImportRecordGroup> _sortGroups(List<_ImportRecordGroup> groups) {
    return [...groups]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static String _formatImportTime(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  static IconData _iconForContentType(String type) {
    switch (type) {
      case _KnowledgeType.cards:
        return Icons.style_rounded;
      case _KnowledgeType.outlines:
        return Icons.list_alt_rounded;
      case _KnowledgeType.mindmaps:
        return Icons.account_tree_rounded;
      case _KnowledgeType.questions:
        return Icons.quiz_rounded;
      default:
        return Icons.auto_stories_rounded;
    }
  }

  static Color _colorForContentType(String type) {
    switch (type) {
      case _KnowledgeType.cards:
        return AppColors.success;
      case _KnowledgeType.outlines:
        return AppColors.accentOrange;
      case _KnowledgeType.mindmaps:
        return AppColors.secondaryPurple;
      case _KnowledgeType.questions:
        return AppColors.error;
      default:
        return AppColors.primary;
    }
  }
}

class _ImportRecordGroup {
  const _ImportRecordGroup({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.createdAt,
    required this.itemCount,
    this.batch,
    this.documents = const <SourceDocumentRecord>[],
    this.contents = const <GeneratedContentRecord>[],
  });

  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final DateTime createdAt;
  final int itemCount;
  final DocumentBatchRecord? batch;
  final List<SourceDocumentRecord> documents;
  final List<GeneratedContentRecord> contents;

  _ImportRecordGroup copyWith({
    String? subtitle,
    IconData? icon,
    Color? color,
  }) {
    return _ImportRecordGroup(
      key: key,
      title: title,
      subtitle: subtitle ?? this.subtitle,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      createdAt: createdAt,
      itemCount: itemCount,
      batch: batch,
      documents: documents,
      contents: contents,
    );
  }
}

class _KnowledgeType {
  const _KnowledgeType._();
  static const String documents = 'documents';
  static const String batches = 'batches';
  static const String cards = 'knowledge_cards';
  static const String outlines = 'review_outline';
  static const String mindmaps = 'mindmap_text';
  static const String questions = 'practice_questions';
  static const String graph = 'knowledge_graph';
}

class _KnowledgeTypeItem {
  const _KnowledgeTypeItem({
    required this.type,
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.foreground,
  });
  final String type, title;
  final int count;
  final IconData icon;
  final Color color;
  final Color foreground;
}
