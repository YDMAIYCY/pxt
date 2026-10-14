import 'package:flutter/material.dart';

import '../../database/models/knowledge_library_record.dart';
import '../theme/app_theme.dart';

// ========== 添加知识库弹窗 ==========
// 支持多选、搜索、全选、清空与确认；已选中的知识库有明确标记。
// 选择结果只影响可视化范围，不会写入知识实体网络。

Future<List<int>?> showGraphLibraryPicker(
  BuildContext context, {
  required List<KnowledgeLibraryRecord> libraries,
  required List<int> selectedIds,
  Map<int, int> nodeCounts = const <int, int>{},
}) {
  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GraphLibraryPickerSheet(
      libraries: libraries,
      selectedIds: selectedIds,
      nodeCounts: nodeCounts,
    ),
  );
}

class _GraphLibraryPickerSheet extends StatefulWidget {
  const _GraphLibraryPickerSheet({
    required this.libraries,
    required this.selectedIds,
    required this.nodeCounts,
  });

  final List<KnowledgeLibraryRecord> libraries;
  final List<int> selectedIds;
  final Map<int, int> nodeCounts;

  @override
  State<_GraphLibraryPickerSheet> createState() =>
      _GraphLibraryPickerSheetState();
}

class _GraphLibraryPickerSheetState extends State<_GraphLibraryPickerSheet> {
  late final Set<int> _selected = widget.selectedIds.toSet();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final filtered = widget.libraries
        .where(
          (library) =>
              _query.isEmpty ||
              library.name.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList(growable: false);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('选择知识库', style: AppTextStyles.h2(context)),
                  ),
                  Text(
                    '已选 ${_selected.length} 本',
                    style: AppTextStyles.bodySmall(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: const InputDecoration(
                  hintText: '搜索知识库',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(
                      () => _selected.addAll(
                        widget.libraries.map((library) => library.id),
                      ),
                    ),
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text('全选'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(_selected.clear),
                    icon: const Icon(Icons.clear_all_rounded, size: 18),
                    label: const Text('清空'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的知识库',
                        style: AppTextStyles.bodySmall(context),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final library = filtered[index];
                        final checked = _selected.contains(library.id);
                        final nodeCount =
                            widget.nodeCounts[library.id] ?? 0;
                        final accent = Color(library.coverColor);
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              _selected.add(library.id);
                            } else {
                              _selected.remove(library.id);
                            }
                          }),
                          secondary: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Color.lerp(accent, Colors.white, 0.82),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Icon(
                              Icons.menu_book_rounded,
                              size: 18,
                              color: accent,
                            ),
                          ),
                          title: Text(
                            library.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            nodeCount > 0
                                ? '${library.documentCount} 份资料 · $nodeCount 个知识点'
                                : '${library.documentCount} 份资料 · 尚未建图谱',
                            style: AppTextStyles.caption(context),
                          ),
                          controlAffinity: ListTileControlAffinity.trailing,
                          activeColor: AppColors.primary,
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_selected.toList()..sort()),
                    child: Text(
                      _selected.isEmpty ? '不选择，返回空状态' : '确认选择（${_selected.length}）',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
