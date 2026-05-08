import 'package:flutter/material.dart';

import '../../database/auth_repository.dart';
import '../../database/document_batch_repository.dart';
import '../../database/models/document_batch_record.dart';
import '../../database/models/source_document_record.dart';
import 'document_detail_page.dart';

// ========== 学习包详情页 ==========
// 展示 PDF / 多图批量导入形成的学习包，并提供每一页资料的处理入口。

class DocumentBatchDetailPage extends StatefulWidget {
  const DocumentBatchDetailPage({
    required this.batchId,
    this.authRepository,
    this.documentBatchRepository,
    super.key,
  });

  final int batchId;
  final AuthRepository? authRepository;
  final DocumentBatchRepository? documentBatchRepository;

  @override
  State<DocumentBatchDetailPage> createState() =>
      _DocumentBatchDetailPageState();
}

class _DocumentBatchDetailPageState extends State<DocumentBatchDetailPage> {
  late final AuthRepository _authRepository;
  late final DocumentBatchRepository _documentBatchRepository;
  late Future<DocumentBatchWithPages> _future;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _documentBatchRepository =
        widget.documentBatchRepository ?? DocumentBatchRepository();
    _future = _loadData();
  }

  Future<DocumentBatchWithPages> _loadData() async {
    await _authRepository.ensureInitialized();
    final user = await _authRepository.getCurrentUserProfile();
    if (user == null) {
      throw StateError('登录状态已失效');
    }

    final batch = await _documentBatchRepository.getBatchWithPages(
      userId: user.id,
      batchId: widget.batchId,
    );
    if (batch == null) {
      throw StateError('学习包不存在或无权访问');
    }
    return batch;
  }

  Future<void> _refresh() async {
    final future = _loadData();
    setState(() {
      _future = future;
    });
    await future;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('学习包详情'),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF0B1324),
      ),
      body: FutureBuilder<DocumentBatchWithPages>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _StatePanel(
              icon: Icons.error_outline_rounded,
              title: '学习包加载失败',
              description: '请稍后重试。',
              onPressed: _refresh,
            );
          }

          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _BatchHeader(batch: data.batch),
                const SizedBox(height: 14),
                _PageList(pages: data.pages, onOpenDocument: _openDocument),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BatchHeader extends StatelessWidget {
  const _BatchHeader({required this.batch});

  final DocumentBatchRecord batch;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFECFEFF), Color(0xFFFFF7ED)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.folder_copy_rounded,
              color: Color(0xFF0C4A6E),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  batch.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF0B1324),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${batch.sourceTypeLabel} / ${batch.pageCount} 页 / ${batch.createdAtLabel}',
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

class _PageList extends StatelessWidget {
  const _PageList({required this.pages, required this.onOpenDocument});

  final List<SourceDocumentRecord> pages;
  final Future<void> Function(int documentId) onOpenDocument;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '页资料',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF0B1324),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (pages.isEmpty)
            Text(
              '这个学习包暂时没有页资料。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ...pages.map(
              (page) =>
                  _PageTile(page: page, onTap: () => onOpenDocument(page.id)),
            ),
        ],
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({required this.page, required this.onTap});

  final SourceDocumentRecord page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${page.pageNumber ?? 1}',
                    style: const TextStyle(
                      color: Color(0xFF0C4A6E),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        page.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF0B1324),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'OCR ${page.ocrStatusLabel} / AI ${page.aiDone ? '已生成' : '待生成'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
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
            FilledButton(
              onPressed: () => onPressed(),
              child: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }
}
