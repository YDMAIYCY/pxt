import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import '../theme/app_theme.dart';

class MindmapEntry {
  const MindmapEntry(this.id, this.title, this.parent);
  final int id;
  final String title;
  final int? parent;
}

List<MindmapEntry> parseMindmap(String text) {
  final result = <MindmapEntry>[];
  final stack = <({int depth, int id})>[];
  for (final line in text.split('\n')) {
    final raw = line.replaceAll('\t', '  ');
    var title = raw.trim();
    if (title.isEmpty ||
        title.startsWith('```') ||
        title == 'mindmap' ||
        title.startsWith('graph ') ||
        title.startsWith('flowchart ')) {
      continue;
    }
    var depth = (raw.length - raw.trimLeft().length) ~/ 2;
    final heading = RegExp(r'^(#+)\s+').firstMatch(title);
    if (heading != null) depth = heading.group(1)!.length - 1;
    title = title.replaceFirst(RegExp(r'^(#+\s+|[-*+]\s+|[├└│─]+\s*)'), '');
    final root = RegExp(r'^root\(\((.*)\)\)$').firstMatch(title);
    if (root != null) title = root.group(1)!;
    if (title.isEmpty) continue;
    if (result.isNotEmpty && depth == 0) depth = 1;
    while (stack.isNotEmpty && stack.last.depth >= depth) {
      stack.removeLast();
    }
    final id = result.length;
    result.add(MindmapEntry(id, title, stack.lastOrNull?.id));
    stack.add((depth: depth, id: id));
  }
  return result;
}

class RecordMindmapView extends StatefulWidget {
  const RecordMindmapView({
    required this.text,
    required this.onSource,
    super.key,
  });
  final String text;
  final VoidCallback onSource;
  @override
  State<RecordMindmapView> createState() => _RecordMindmapViewState();
}

class _RecordMindmapViewState extends State<RecordMindmapView> {
  final _transform = TransformationController();
  final _collapsed = <int>{};
  Graph? _graph;
  String _search = '';
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = parseMindmap(widget.text);
    if (entries.isEmpty) return const Text('导图暂无节点，请编辑或重新生成。');
    final hidden = <int>{};
    for (final e in entries) {
      if (e.parent != null &&
          (_collapsed.contains(e.parent) || hidden.contains(e.parent))) {
        hidden.add(e.id);
      }
    }
    final visible = entries.where((e) => !hidden.contains(e.id)).toList();
    final graph = Graph()..isTree = true;
    _graph = graph;
    for (final e in visible) {
      graph.addNode(Node.Id(e.id));
    }
    for (final e in visible) {
      if (e.parent != null) graph.addEdge(Node.Id(e.parent), Node.Id(e.id));
    }
    final config = BuchheimWalkerConfiguration()
      ..siblingSeparation = 20
      ..levelSeparation = 40
      ..subtreeSeparation = 25
      ..orientation = BuchheimWalkerConfiguration.ORIENTATION_LEFT_RIGHT;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: '搜索并定位节点，点图中节点查看来源',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (text) => setState(() => _search = text.trim()),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _transform.value = Matrix4.identity(),
              child: const Text('回到起点'),
            ),
            TextButton(
              onPressed: () => setState(_collapsed.clear),
              child: const Text('展开全部'),
            ),
          ],
        ),
        if (_search.isNotEmpty)
          ...entries
              .where((e) => e.title.contains(_search))
              .take(10)
              .map(
                (e) => ListTile(
                  title: Text(e.title),
                  onTap: () {
                    setState(() {
                      _collapsed.clear();
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      final node = _graph!.nodes.firstWhere((n) => n.key?.value == e.id);
                      _transform.value = Matrix4.identity()
                        ..setTranslationRaw(
                          (MediaQuery.sizeOf(context).width - 72) / 2 -
                            node.position.dx - node.width / 2,
                          180 - node.position.dy - node.height / 2, 0);
                    });
                  },
                ),
              ),
        SizedBox(
          height: 360,
          child: ClipRect(
            child: InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(300),
              minScale: .15,
              maxScale: 3,
              child: GraphView(
                graph: graph,
                algorithm: BuchheimWalkerAlgorithm(
                  config,
                  TreeEdgeRenderer(config),
                ),
                paint: Paint()
                  ..color = AppColors.primaryLight
                  ..strokeWidth = 2,
                builder: (node) {
                  final entry = entries[node.key!.value as int];
                  final hasChildren = entries.any((e) => e.parent == entry.id);
                  return Container(
                    width: 160,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _search.isNotEmpty && entry.title.contains(_search)
                          ? AppColors.primaryLight
                          : AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: widget.onSource,
                          child: Text(entry.title),
                        ),
                        if (hasChildren)
                          IconButton(
                            tooltip: _collapsed.contains(entry.id)
                                ? '展开分支'
                                : '收起分支',
                            icon: Icon(
                              _collapsed.contains(entry.id)
                                  ? Icons.add
                                  : Icons.remove,
                            ),
                            onPressed: () => setState(() {
                              if (!_collapsed.add(entry.id)) {
                                _collapsed.remove(entry.id);
                              }
                            }),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
