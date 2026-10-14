import 'package:flutter/material.dart';

import '../../database/models/graph_records.dart';
import '../../graph/graph_style.dart';
import '../../graph/graph_vocabulary.dart';
import '../theme/app_theme.dart';

// ========== 知识点详情 BottomSheet ==========
// 主页保持简洁，详情用临时 BottomSheet 呈现，不做常驻卡片。
// 所有内容都来自真实图谱数据；缺失的入口明确说明不可用，不伪装成已开放。

enum GraphNodeSheetAction {
  openSource,
  openKnowledgeCard,
  focusNeighbors,
  startAiInterview,
  confirmMerge,
  openRelation,
}

class GraphNodeSheetResult {
  const GraphNodeSheetResult({
    required this.action,
    this.importRecordId,
    this.documentId,
    this.neighborNodeId,
    this.mergeIntoNodeId,
    this.edgeId,
  });

  final GraphNodeSheetAction action;
  final int? importRecordId;
  final int? documentId;
  final int? neighborNodeId;
  final int? mergeIntoNodeId;
  final int? edgeId;
}

Future<GraphNodeSheetResult?> showGraphNodeDetailSheet(
  BuildContext context, {
  required GraphNodeDetail detail,
  required Map<int, Color> libraryColors,
  List<GraphNodeRecord> mergeCandidates = const <GraphNodeRecord>[],
  bool aiInterviewAvailable = false,
}) {
  return showModalBottomSheet<GraphNodeSheetResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GraphNodeDetailSheet(
      detail: detail,
      libraryColors: libraryColors,
      mergeCandidates: mergeCandidates,
      aiInterviewAvailable: aiInterviewAvailable,
    ),
  );
}

class _GraphNodeDetailSheet extends StatelessWidget {
  const _GraphNodeDetailSheet({
    required this.detail,
    required this.libraryColors,
    required this.mergeCandidates,
    required this.aiInterviewAvailable,
  });

  final GraphNodeDetail detail;
  final Map<int, Color> libraryColors;
  final List<GraphNodeRecord> mergeCandidates;
  final bool aiInterviewAvailable;

  @override
  Widget build(BuildContext context) {
    final node = detail.node;
    final media = MediaQuery.of(context);
    final accent = _accent();

    final prerequisites = detail.neighbors
        .where(
          (item) =>
              GraphRelationTypes.normalize(item.edge.relationType) ==
                  GraphRelationTypes.prerequisite ||
              GraphRelationTypes.normalize(item.edge.relationType) ==
                  GraphRelationTypes.dependsOn,
        )
        .toList(growable: false);
    final applications = detail.neighbors
        .where(
          (item) =>
              GraphRelationTypes.normalize(item.edge.relationType) ==
              GraphRelationTypes.appliedTo,
        )
        .toList(growable: false);
    final others = detail.neighbors
        .where(
          (item) =>
              !prerequisites.contains(item) && !applications.contains(item),
        )
        .toList(growable: false);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.82),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Color.lerp(accent, Colors.white, 0.85),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withValues(alpha: 0.4)),
                  ),
                  child: Icon(Icons.hub_rounded, color: accent, size: 22),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.displayName.isEmpty
                            ? node.canonicalName
                            : node.displayName,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          _Chip(label: node.entityType, color: accent),
                          if (detail.libraryNames.length > 1) ...[
                            const SizedBox(width: 6),
                            _Chip(
                              label: '跨 ${detail.libraryNames.length} 库共享',
                              color: AppColors.secondaryPurple,
                            ),
                          ],
                          if (node.status == GraphNodeStatus.pendingReview) ...[
                            const SizedBox(width: 6),
                            const _Chip(
                              label: '待核对',
                              color: AppColors.warning,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (node.aliases.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                '同义说法：${node.aliases.join('、')}',
                style: AppTextStyles.caption(context),
              ),
            ],
            if (node.description != null && node.description!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                node.description!,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: Color(0xFF475569),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _SectionTitle(title: '来源知识库'),
            const SizedBox(height: 8),
            if (detail.libraryNames.isEmpty)
              Text('暂无可追溯的来源库。', style: AppTextStyles.bodySmall(context))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: detail.libraryNames
                    .map(
                      (name) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Color.lerp(accent, Colors.white, 0.9),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            const SizedBox(height: 18),
            _SectionTitle(title: '来源记录'),
            const SizedBox(height: 4),
            if (detail.sources.isEmpty)
              Text('这条知识点还没有关联记录。', style: AppTextStyles.bodySmall(context))
            else
              ...detail.sources.take(8).map(
                (source) => _SourceTile(
                  source: source,
                  onTap: () => Navigator.of(context).pop(
                    GraphNodeSheetResult(
                      action: GraphNodeSheetAction.openSource,
                      importRecordId: source.source.importRecordId,
                      documentId: source.source.sourceDocumentId,
                    ),
                  ),
                ),
              ),
            if (prerequisites.isNotEmpty) ...[
              const SizedBox(height: 14),
              _SectionTitle(title: '前置知识'),
              ...prerequisites.map(
                (item) => _NeighborTile(
                  item: item,
                  onTap: () => Navigator.of(context).pop(
                    GraphNodeSheetResult(
                      action: GraphNodeSheetAction.focusNeighbors,
                      neighborNodeId: item.node.id,
                      edgeId: item.edge.id,
                    ),
                  ),
                ),
              ),
            ],
            if (applications.isNotEmpty) ...[
              const SizedBox(height: 14),
              _SectionTitle(title: '应用方向'),
              ...applications.map(
                (item) => _NeighborTile(
                  item: item,
                  onTap: () => Navigator.of(context).pop(
                    GraphNodeSheetResult(
                      action: GraphNodeSheetAction.focusNeighbors,
                      neighborNodeId: item.node.id,
                      edgeId: item.edge.id,
                    ),
                  ),
                ),
              ),
            ],
            if (others.isNotEmpty) ...[
              const SizedBox(height: 14),
              _SectionTitle(title: '关联知识点（${others.length}）'),
              ...others.take(12).map(
                (item) => _NeighborTile(
                  item: item,
                  onTap: () => Navigator.of(context).pop(
                    GraphNodeSheetResult(
                      action: GraphNodeSheetAction.focusNeighbors,
                      neighborNodeId: item.node.id,
                      edgeId: item.edge.id,
                    ),
                  ),
                ),
              ),
            ],
            if (mergeCandidates.isNotEmpty) ...[
              const SizedBox(height: 18),
              _SectionTitle(title: '可能的同一概念'),
              const SizedBox(height: 4),
              Text(
                '名称相同但类型不同，不会自动合并。确认后才会归并为一个实体。',
                style: AppTextStyles.caption(context),
              ),
              const SizedBox(height: 6),
              ...mergeCandidates.map(
                (candidate) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.call_merge_rounded, size: 20),
                  title: Text('${candidate.displayName}（${candidate.entityType}）'),
                  trailing: TextButton(
                    onPressed: () => Navigator.of(context).pop(
                      GraphNodeSheetResult(
                        action: GraphNodeSheetAction.confirmMerge,
                        mergeIntoNodeId: candidate.id,
                      ),
                    ),
                    child: const Text('合并'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            _SectionTitle(title: '可执行操作'),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: detail.sources.isEmpty
                    ? null
                    : () {
                        final source = detail.sources.first;
                        Navigator.of(context).pop(
                          GraphNodeSheetResult(
                            action: GraphNodeSheetAction.openSource,
                            importRecordId: source.source.importRecordId,
                            documentId: source.source.sourceDocumentId,
                          ),
                        );
                      },
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('查看来源'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: detail.sources.isEmpty
                    ? null
                    : () {
                        final source = detail.sources.first;
                        Navigator.of(context).pop(
                          GraphNodeSheetResult(
                            action: GraphNodeSheetAction.openKnowledgeCard,
                            importRecordId: source.source.importRecordId,
                            documentId: source.source.sourceDocumentId,
                          ),
                        );
                      },
                icon: const Icon(Icons.style_rounded, size: 18),
                label: const Text('查看知识卡片'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: detail.neighbors.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(
                        const GraphNodeSheetResult(
                          action: GraphNodeSheetAction.focusNeighbors,
                        ),
                      ),
                icon: const Icon(Icons.hub_outlined, size: 18),
                label: Text('查看关联知识（${detail.neighbors.length}）'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: aiInterviewAvailable
                    ? () => Navigator.of(context).pop(
                        const GraphNodeSheetResult(
                          action: GraphNodeSheetAction.startAiInterview,
                        ),
                      )
                    : () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('AI 面试入口尚未在应用内开放，暂不能从这里发起。'),
                        ),
                      ),
                icon: Icon(
                  aiInterviewAvailable
                      ? Icons.record_voice_over_rounded
                      : Icons.lock_outline_rounded,
                  size: 18,
                ),
                label: Text(
                  aiInterviewAvailable ? '基于该知识点发起 AI 面试' : 'AI 面试（暂未开放）',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _accent() {
    for (final source in detail.sources) {
      final libraryId = source.source.knowledgeBaseId;
      if (libraryId != null) {
        final color = libraryColors[libraryId];
        if (color != null) return color;
      }
    }
    return const Color(0xFF5B90FF);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 3,
        height: 14,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      const SizedBox(width: 7),
      Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
      ),
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    ),
  );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source, required this.onTap});

  final GraphNodeSourceView source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = source.recordTitle.isNotEmpty
        ? source.recordTitle
        : (source.documentTitle.isNotEmpty ? source.documentTitle : '来源资料');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.description_outlined, size: 20),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (source.libraryName.isNotEmpty) source.libraryName,
          if (source.source.evidenceText != null)
            '证据：${_short(source.source.evidenceText!)}',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption(context),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }

  static String _short(String text) =>
      text.length <= 42 ? text : '${text.substring(0, 42)}…';
}

class _NeighborTile extends StatelessWidget {
  const _NeighborTile({required this.item, required this.onTap});

  final GraphNodeNeighborView item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final relation = GraphRelationTypes.normalize(item.edge.relationType);
    final color = GraphPalette.relationColor(relation);
    final arrow = item.isOutgoing ? '→' : '←';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        GraphPalette.relationDashed(relation)
            ? Icons.trending_flat_rounded
            : Icons.trending_up_rounded,
        size: 20,
        color: color,
      ),
      title: Text(
        '$arrow ${item.node.displayName.isEmpty ? item.node.canonicalName : item.node.displayName}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '$relation · 置信度 ${(item.edge.confidence * 100).round()}%'
        '${item.edge.origin == GraphEdgeOrigin.crossLibrary ? ' · 跨库' : ''}',
        style: AppTextStyles.caption(context),
      ),
      trailing: const Icon(Icons.my_location_rounded, size: 16),
      onTap: onTap,
    );
  }
}
