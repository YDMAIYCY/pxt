import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../database/ai_generation_repository.dart';
import '../../../database/auth_repository.dart';
import '../../../database/document_batch_repository.dart';
import '../../../database/knowledge_graph_repository.dart';
import '../../../database/knowledge_library_repository.dart';
import '../../../database/models/ai_result_records.dart';
import '../../../database/models/document_batch_record.dart';
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
      limit: 80,
    );
    final graphLinks = await _knowledgeGraphRepository.fetchLinksByLibrary(
      userId: user.id,
      libraryId: selectedLibrary.id,
      limit: 300,
    );

    return _KnowledgeData(
      userId: user.id,
      libraries: libraries,
      selectedLibrary: selectedLibrary,
      batches: batches,
      documents: documents,
      contents: contents,
      weakConcepts: weakConcepts,
      graphLinks: graphLinks,
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
        count: data.batches.length,
        icon: Icons.folder_copy_rounded,
        color: const Color(0xFFF0FDFA),
        foreground: AppColors.primary,
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.documents,
        title: '讲义资料',
        count: data.documents.length,
        icon: Icons.menu_book_rounded,
        color: const Color(0xFFEFF6FF),
        foreground: AppColors.secondaryBlue,
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.cards,
        title: '知识卡片',
        count: data.countByType(_KnowledgeType.cards),
        icon: Icons.style_rounded,
        color: const Color(0xFFF0FDF4),
        foreground: AppColors.success,
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.outlines,
        title: '复习提纲',
        count: data.countByType(_KnowledgeType.outlines),
        icon: Icons.list_alt_rounded,
        color: const Color(0xFFFFF7ED),
        foreground: AppColors.accentOrange,
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.mindmaps,
        title: '思维导图文字',
        count: data.countByType(_KnowledgeType.mindmaps),
        icon: Icons.account_tree_rounded,
        color: const Color(0xFFF5F3FF),
        foreground: AppColors.secondaryPurple,
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.questions,
        title: '练习题',
        count: data.countByType(_KnowledgeType.questions),
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
      if (data.batches.isEmpty) {
        return const _EmptyListHint(text: '这个知识库还没有多页学习包。');
      }
      return Column(
        children: data.batches
            .map(
              (batch) => _ContentTile(
                title: batch.title,
                subtitle:
                    '${batch.sourceTypeLabel} / ${batch.pageCount} 页 / ${batch.createdAtLabel}',
                body: '点进学习包后可以逐页 OCR、生成 AI 结果和刷题。',
                onTap: () => _openBatch(batch.id),
                onMove: null,
                onDelete: () => _deleteBatch(data, batch.id),
              ),
            )
            .toList(growable: false),
      );
    }
    if (type == _KnowledgeType.documents) {
      if (data.documents.isEmpty) {
        return const _EmptyListHint(text: '这个知识库还没有讲义资料。');
      }
      return Column(
        children: data.documents
            .map(
              (document) => _DocumentTile(
                document: document,
                onTap: () => _openDocument(document.id),
                onMove: () => _moveDocument(data, document.id),
                onDelete: () => _deleteDocument(data, document.id),
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
        onOpenConcept: (item) {
          final documentId = item.concept.documentId;
          if (documentId == null) return;
          _openDocument(documentId);
        },
      );
    }

    final contents = data.contentsOf(type);
    if (contents.isEmpty) return const _EmptyListHint(text: '这个知识库的分类还没有真实结果。');
    return Column(
      children: contents
          .map(
            (item) => _ContentTile(
              title: item.title,
              subtitle: '${item.documentTitle} / ${item.contentLabel}',
              body: item.summary,
              onTap: () => _openDocument(item.documentId),
              onMove: () => _moveDocument(data, item.documentId),
              onDelete: () => _deleteDocument(data, item.documentId),
            ),
          )
          .toList(growable: false),
    );
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
  });
  final String title, subtitle, body;
  final VoidCallback onTap, onDelete;
  final VoidCallback? onMove;

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
class _KnowledgeGraphPanel extends StatelessWidget {
  const _KnowledgeGraphPanel({
    required this.concepts,
    required this.links,
    required this.onOpenConcept,
  });

  final List<KnowledgeConceptWithDocument> concepts;
  final List<KnowledgeConceptLinkRecord> links;
  final ValueChanged<KnowledgeConceptWithDocument> onOpenConcept;

  @override
  Widget build(BuildContext context) {
    final visibleConcepts = concepts.take(28).toList(growable: false);
    final visibleConceptIds = visibleConcepts
        .map((item) => item.concept.id)
        .toSet();
    final visibleLinks = links
        .where(
          (link) =>
              visibleConceptIds.contains(link.fromConceptId) &&
              visibleConceptIds.contains(link.toConceptId),
        )
        .take(80)
        .toList(growable: false);
    final rootConcept = visibleConcepts.first.concept;

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
                          '主干：${rootConcept.name} · ${visibleConcepts.length} 个知识点 · ${visibleLinks.length} 条关系',
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
              SizedBox(
                height: 360,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                    child: InteractiveViewer(
                      minScale: 0.75,
                      maxScale: 2.2,
                      boundaryMargin: const EdgeInsets.all(120),
                      child: CustomPaint(
                        painter: _KnowledgeGraphPainter(
                          concepts: visibleConcepts,
                          links: visibleLinks,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _GraphLegend(label: '薄弱高', color: AppColors.error),
                  _GraphLegend(label: '待巩固', color: AppColors.info),
                  _GraphLegend(label: '已掌握', color: AppColors.success),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '主干知识点',
          style: AppTextStyles.h3(
            context,
          ).copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        ...visibleConcepts
            .take(12)
            .map(
              (item) =>
                  _ConceptTile(item: item, onTap: () => onOpenConcept(item)),
            ),
      ],
    );
  }
}

class _KnowledgeGraphPainter extends CustomPainter {
  const _KnowledgeGraphPainter({required this.concepts, required this.links});

  final List<KnowledgeConceptWithDocument> concepts;
  final List<KnowledgeConceptLinkRecord> links;

  @override
  void paint(Canvas canvas, Size size) {
    if (concepts.isEmpty) return;
    final nodes = _layoutNodes(size);
    final nodeById = {for (final node in nodes) node.item.concept.id: node};
    final edgePaint = Paint()
      ..color = const Color(0xFF94A3B8).withValues(alpha: 0.72)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final link in links) {
      final from = nodeById[link.fromConceptId];
      final to = nodeById[link.toConceptId];
      if (from == null || to == null) continue;
      canvas.drawLine(from.center, to.center, edgePaint);
      final middle = Offset(
        (from.center.dx + to.center.dx) / 2,
        (from.center.dy + to.center.dy) / 2,
      );
      _drawLabel(canvas, middle, link.relationLabel);
    }

    for (final node in nodes) {
      final concept = node.item.concept;
      final color = _nodeColor(concept);
      final shadowPaint = Paint()
        ..color = color.withValues(alpha: 0.16)
        ..style = PaintingStyle.fill;
      final fillPaint = Paint()
        ..color = color.withValues(alpha: 0.94)
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(node.center, node.radius + 6, shadowPaint);
      canvas.drawCircle(node.center, node.radius, fillPaint);
      canvas.drawCircle(node.center, node.radius, borderPaint);
      _drawNodeText(canvas, node);
    }
  }

  List<_GraphNode> _layoutNodes(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final nodes = <_GraphNode>[];
    nodes.add(
      _GraphNode(
        item: concepts.first,
        center: center,
        radius: _nodeRadius(concepts.first.concept, isRoot: true),
      ),
    );
    if (concepts.length == 1) return nodes;

    final firstRing = math.min(10, concepts.length - 1);
    final secondRing = concepts.length - 1 - firstRing;
    final safeRadius = math.min(size.width, size.height) / 2;
    final firstRingRadius = safeRadius * 0.5;
    final secondRingRadius = safeRadius * 0.78;

    for (var i = 1; i < concepts.length; i++) {
      final inSecondRing = i > firstRing;
      final ringIndex = inSecondRing ? i - firstRing - 1 : i - 1;
      final ringCount = inSecondRing ? secondRing : firstRing;
      final angle =
          (-math.pi / 2) + (2 * math.pi * ringIndex / math.max(1, ringCount));
      final radius = inSecondRing ? secondRingRadius : firstRingRadius;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      nodes.add(
        _GraphNode(
          item: concepts[i],
          center: point,
          radius: _nodeRadius(concepts[i].concept),
        ),
      );
    }
    return nodes;
  }

  double _nodeRadius(KnowledgeConceptRecord concept, {bool isRoot = false}) {
    if (isRoot) return 38;
    return 24 + math.min(10, concept.weaknessScore / 10);
  }

  Color _nodeColor(KnowledgeConceptRecord concept) {
    if (concept.weaknessScore >= 70) return AppColors.error;
    if (concept.masteryScore >= 70) return AppColors.success;
    return AppColors.info;
  }

  void _drawNodeText(Canvas canvas, _GraphNode node) {
    final name = node.item.concept.name;
    final label = name.length > 8 ? '${name.substring(0, 8)}…' : name;
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1.05,
        ),
      ),
      maxLines: 2,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: node.radius * 1.65);
    textPainter.paint(
      canvas,
      node.center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  void _drawLabel(Canvas canvas, Offset center, String label) {
    final text = label.trim().isEmpty ? '关联' : label.trim();
    final textPainter = TextPainter(
      text: TextSpan(
        text: text.length > 7 ? '${text.substring(0, 7)}…' : text,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 72);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: textPainter.width + 12,
        height: textPainter.height + 6,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = Colors.white.withValues(alpha: 0.86),
    );
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _KnowledgeGraphPainter oldDelegate) {
    return oldDelegate.concepts != concepts || oldDelegate.links != links;
  }
}

class _GraphNode {
  const _GraphNode({
    required this.item,
    required this.center,
    required this.radius,
  });

  final KnowledgeConceptWithDocument item;
  final Offset center;
  final double radius;
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

class _BaseTile extends StatelessWidget {
  const _BaseTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.onTap,
    required this.onMove,
    required this.onDelete,
  });
  final IconData icon;
  final String title, subtitle, body;
  final VoidCallback onTap, onDelete;
  final VoidCallback? onMove;

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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
  });

  final int userId;
  final List<KnowledgeLibraryRecord> libraries;
  final KnowledgeLibraryRecord selectedLibrary;
  final List<DocumentBatchRecord> batches;
  final List<SourceDocumentRecord> documents;
  final List<GeneratedContentRecord> contents;
  final List<KnowledgeConceptWithDocument> weakConcepts;
  final List<KnowledgeConceptLinkRecord> graphLinks;

  int get totalCount =>
      batches.length + documents.length + contents.length + weakConcepts.length;
  int countByType(String type) => contentsOf(type).length;
  List<GeneratedContentRecord> contentsOf(String type) => contents
      .where((item) => item.contentType == type)
      .toList(growable: false);
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
