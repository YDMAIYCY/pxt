import 'package:flutter/material.dart';

import '../../../database/ai_generation_repository.dart';
import '../../../database/auth_repository.dart';
import '../../../database/document_batch_repository.dart';
import '../../../database/knowledge_library_repository.dart';
import '../../../database/models/ai_result_records.dart';
import '../../../database/models/document_batch_record.dart';
import '../../../database/models/knowledge_library_record.dart';
import '../../../database/models/source_document_record.dart';
import '../../../database/source_document_repository.dart';
import '../../widgets/create_knowledge_library_dialog.dart';
import '../document_batch_detail_page.dart';
import '../document_detail_page.dart';

// ========== 知识库 Tab ==========
// 按用户选择的知识库读取资料、卡片、提纲、导图、复习题和错题讲解。

class KnowledgeTabPage extends StatefulWidget {
  const KnowledgeTabPage({
    this.authRepository,
    this.sourceDocumentRepository,
    this.aiGenerationRepository,
    this.documentBatchRepository,
    this.knowledgeLibraryRepository,
    super.key,
  });

  final AuthRepository? authRepository;
  final SourceDocumentRepository? sourceDocumentRepository;
  final AiGenerationRepository? aiGenerationRepository;
  final DocumentBatchRepository? documentBatchRepository;
  final KnowledgeLibraryRepository? knowledgeLibraryRepository;

  @override
  State<KnowledgeTabPage> createState() => _KnowledgeTabPageState();
}

class _KnowledgeTabPageState extends State<KnowledgeTabPage> {
  late final AuthRepository _authRepository;
  late final SourceDocumentRepository _sourceDocumentRepository;
  late final AiGenerationRepository _aiGenerationRepository;
  late final DocumentBatchRepository _documentBatchRepository;
  late final KnowledgeLibraryRepository _knowledgeLibraryRepository;
  late Future<_KnowledgeData> _future;
  String _selectedType = _KnowledgeType.documents;
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
    _knowledgeLibraryRepository =
        widget.knowledgeLibraryRepository ?? KnowledgeLibraryRepository();
    _future = _loadData();
  }

  Future<_KnowledgeData> _loadData() async {
    await _authRepository.ensureInitialized();
    final user = await _authRepository.getCurrentUserProfile();
    if (user == null) {
      throw StateError('登录状态已失效');
    }

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
    final wrongQuestions = await _aiGenerationRepository
        .fetchPracticeQuestionsByUser(
          userId: user.id,
          libraryId: selectedLibrary.id,
          reviewStatus: PracticeQuestionReviewStatus.wrong,
          limit: 300,
        );

    return _KnowledgeData(
      userId: user.id,
      libraries: libraries,
      selectedLibrary: selectedLibrary,
      batches: batches,
      documents: documents,
      contents: contents,
      wrongQuestions: wrongQuestions,
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
    final future = _loadData();
    setState(() {
      _future = future;
    });
    await future;
  }

  void _selectLibrary(int libraryId) {
    setState(() {
      _selectedLibraryId = libraryId;
      _future = _loadData();
    });
  }

  Future<void> _openDocument(int documentId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentDetailPage(documentId: documentId),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _openBatch(int batchId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentBatchDetailPage(batchId: batchId),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _createLibrary(int userId) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const CreateKnowledgeLibraryDialog(),
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }

    try {
      final library = await _knowledgeLibraryRepository.createLibrary(
        userId: userId,
        name: name,
      );
      _selectedLibraryId = library.id;
      if (mounted) {
        _showMessage('已创建知识库：${library.name}');
        await _refresh();
      }
    } catch (error) {
      if (mounted) {
        _showMessage('创建知识库失败：$error');
      }
    }
  }

  Future<void> _deleteCurrentLibrary(_KnowledgeData data) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('删除“${data.selectedLibrary.name}”？'),
          content: Text(
            '会同时删除这个知识库下的 ${data.documents.length} 份资料，以及相关 OCR 文本、AI 结果、复习题和错题记录。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              child: const Text('确认删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    try {
      await _knowledgeLibraryRepository.deleteLibraryAndContents(
        userId: data.userId,
        libraryId: data.selectedLibrary.id,
      );
      _selectedLibraryId = null;
      if (mounted) {
        _showMessage('知识库已删除');
        await _refresh();
      }
    } catch (error) {
      if (mounted) {
        _showMessage('删除知识库失败：$error');
      }
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
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '移动到哪个知识库',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF0B1324),
                    fontWeight: FontWeight.w800,
                  ),
                ),
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
        );
      },
    );
    if (targetId == null) {
      return;
    }

    try {
      await _sourceDocumentRepository.moveDocumentToLibrary(
        userId: data.userId,
        documentId: documentId,
        libraryId: targetId,
      );
      if (mounted) {
        _showMessage('已移动到目标知识库');
        await _refresh();
      }
    } catch (error) {
      if (mounted) {
        _showMessage('移动失败：$error');
      }
    }
  }

  Future<void> _deleteDocument(_KnowledgeData data, int documentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除这份资料？'),
          content: const Text('会同时删除它的 OCR 文本、AI 结果、复习题和错题记录。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    try {
      await _sourceDocumentRepository.deleteDocument(
        userId: data.userId,
        documentId: documentId,
      );
      if (mounted) {
        _showMessage('资料已删除');
        await _refresh();
      }
    } catch (error) {
      if (mounted) {
        _showMessage('删除失败：$error');
      }
    }
  }

  Future<void> _deleteBatch(_KnowledgeData data, int batchId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除这个学习包？'),
          content: const Text('会同时删除学习包下全部页资料、OCR 文本、AI 结果、复习题和错题记录。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    try {
      await _documentBatchRepository.deleteBatch(
        userId: data.userId,
        batchId: batchId,
      );
      if (mounted) {
        _showMessage('学习包已删除');
        await _refresh();
      }
    } catch (error) {
      if (mounted) {
        _showMessage('删除学习包失败：$error');
      }
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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
                        onSelected: (type) {
                          setState(() {
                            _selectedType = type;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      _buildSelectedList(data),
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
        color: const Color(0xFFECFEFF),
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.documents,
        title: '讲义资料',
        count: data.documents.length,
        icon: Icons.menu_book_rounded,
        color: const Color(0xFFE0F2FE),
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.cards,
        title: '知识卡片',
        count: data.countByType(_KnowledgeType.cards),
        icon: Icons.style_rounded,
        color: const Color(0xFFF0FDF4),
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.outlines,
        title: '复习提纲',
        count: data.countByType(_KnowledgeType.outlines),
        icon: Icons.list_alt_rounded,
        color: const Color(0xFFFFF7ED),
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.mindmaps,
        title: '思维导图文字',
        count: data.countByType(_KnowledgeType.mindmaps),
        icon: Icons.account_tree_rounded,
        color: const Color(0xFFF5F3FF),
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.questions,
        title: '复习题',
        count: data.countByType(_KnowledgeType.questions),
        icon: Icons.quiz_rounded,
        color: const Color(0xFFFDF2F8),
      ),
      _KnowledgeTypeItem(
        type: _KnowledgeType.wrongQuestions,
        title: '错题讲解',
        count: data.wrongQuestions.length,
        icon: Icons.report_problem_rounded,
        color: const Color(0xFFFEF2F2),
      ),
    ];
  }

  Widget _buildSelectedList(_KnowledgeData data) {
    if (_selectedType == _KnowledgeType.batches) {
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

    if (_selectedType == _KnowledgeType.documents) {
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

    if (_selectedType == _KnowledgeType.wrongQuestions) {
      if (data.wrongQuestions.isEmpty) {
        return const _EmptyListHint(text: '这个知识库暂无待处理错题。');
      }
      return Column(
        children: data.wrongQuestions
            .map(
              (item) => _ContentTile(
                title: item.question.questionText,
                subtitle:
                    '${item.documentTitle} / 错 ${item.question.wrongCount} 次',
                body:
                    item.question.analysisText ??
                    item.question.answerText ??
                    '',
                onTap: () => _openDocument(item.question.documentId),
                onMove: () => _moveDocument(data, item.question.documentId),
                onDelete: () => _deleteDocument(data, item.question.documentId),
              ),
            )
            .toList(growable: false),
      );
    }

    final contents = data.contentsOf(_selectedType);
    if (contents.isEmpty) {
      return const _EmptyListHint(text: '这个知识库的分类还没有真实结果。');
    }

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

class _Header extends StatelessWidget {
  const _Header({required this.data});

  final _KnowledgeData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFECFEFF), Color(0xFFEEF2FF)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.collections_bookmark_rounded,
              color: Color(0xFF0C4A6E),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.selectedLibrary.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0B1324),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '当前知识库共 ${data.totalCount} 条资料与生成结果',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
          IconButton(
            tooltip: '新建知识库',
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            tooltip: '删除当前知识库',
            onPressed: onDeleteSelected,
            color: const Color(0xFFDC2626),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: libraries
              .map(
                (library) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${library.name} · ${library.documentCount}'),
                    selected: library.id == selectedLibrary.id,
                    onSelected: (_) => onSelected(library.id),
                  ),
                ),
              )
              .toList(growable: false),
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
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: item.color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? const Color(0xFF0C4A6E) : Colors.white,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(item.icon, color: const Color(0xFF0C4A6E)),
              const SizedBox(height: 8),
              Text(
                item.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF0B1324),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${item.count} 条',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF475569),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.onTap,
    required this.onMove,
    required this.onDelete,
  });

  final SourceDocumentRecord document;
  final VoidCallback onTap;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return _BaseTile(
      icon: Icons.description_rounded,
      title: document.title,
      subtitle: '${document.sourceTypeLabel} / ${document.createdAtLabel}',
      body:
          'OCR：${document.ocrStatusLabel} / AI：${document.aiDone ? '已生成' : '待生成'}',
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

  final String title;
  final String subtitle;
  final String body;
  final VoidCallback onTap;
  final VoidCallback? onMove;
  final VoidCallback onDelete;

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
  final String title;
  final String subtitle;
  final String body;
  final VoidCallback onTap;
  final VoidCallback? onMove;
  final VoidCallback onDelete;

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
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: const Color(0xFF0C4A6E)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF0B1324),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
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
                                color: const Color(0xFF475569),
                                height: 1.35,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '内容操作',
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: Color(0xFF94A3B8),
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

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0B1324),
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF64748B),
          fontWeight: FontWeight.w600,
        ),
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
  final String title;
  final String description;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFF64748B)),
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
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: () => onPressed(), child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _KnowledgeData {
  const _KnowledgeData({
    required this.userId,
    required this.libraries,
    required this.selectedLibrary,
    required this.batches,
    required this.documents,
    required this.contents,
    required this.wrongQuestions,
  });

  final int userId;
  final List<KnowledgeLibraryRecord> libraries;
  final KnowledgeLibraryRecord selectedLibrary;
  final List<DocumentBatchRecord> batches;
  final List<SourceDocumentRecord> documents;
  final List<GeneratedContentRecord> contents;
  final List<PracticeQuestionWithDocument> wrongQuestions;

  int get totalCount =>
      batches.length +
      documents.length +
      contents.length +
      wrongQuestions.length;

  int countByType(String type) => contentsOf(type).length;

  List<GeneratedContentRecord> contentsOf(String type) {
    return contents
        .where((item) => item.contentType == type)
        .toList(growable: false);
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
  static const String wrongQuestions = 'wrong_questions';
}

class _KnowledgeTypeItem {
  const _KnowledgeTypeItem({
    required this.type,
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
  });

  final String type;
  final String title;
  final int count;
  final IconData icon;
  final Color color;
}
