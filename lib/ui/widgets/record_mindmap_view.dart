import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'mindmap_layout.dart';

export 'mindmap_layout.dart' show MindmapEntry, parseMindmap;

const _branchColors = <Color>[
  Color(0xFF2563EB),
  Color(0xFFF07928),
  Color(0xFF159D83),
  Color(0xFF8B5CF6),
  Color(0xFFDB458B),
  Color(0xFF0891B2),
  Color(0xFFB58A08),
  Color(0xFFDB5555),
];

class RecordMindmapView extends StatefulWidget {
  const RecordMindmapView({
    required this.text,
    required this.onSource,
    this.query,
    this.fullscreen = false,
    super.key,
  });
  final String text;
  final VoidCallback onSource;
  final String? query;
  final bool fullscreen;
  @override
  State<RecordMindmapView> createState() => _RecordMindmapViewState();
}

class _RecordMindmapViewState extends State<RecordMindmapView> {
  final _transform = TransformationController();
  final _collapsed = <int>{};
  late final _searchController = TextEditingController(
    text: widget.query ?? '',
  );
  late List<MindmapEntry> _entries = parseMindmap(widget.text);
  late String _search = widget.query?.trim() ?? '';
  Size? _viewport;
  MindmapLayout? _layout;
  bool _needsFit = true;
  int _matchIndex = 0;

  @override
  void didUpdateWidget(covariant RecordMindmapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _entries = parseMindmap(widget.text);
      _collapsed.clear();
      _matchIndex = 0;
      _needsFit = true;
    }
    if (widget.query != oldWidget.query) _changeSearch(widget.query ?? '');
  }

  @override
  void dispose() {
    _transform.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<MindmapEntry> get _matches => _search.isEmpty
      ? []
      : _entries
            .where(
              (entry) =>
                  entry.title.toLowerCase().contains(_search.toLowerCase()),
            )
            .toList();

  void _changeSearch(String value) {
    setState(() {
      _search = value.trim();
      _matchIndex = 0;
      // Search reveals matching descendants without discarding any branches.
      if (_search.isNotEmpty) _collapsed.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _matches.isNotEmpty) _locate(_matches.first.id);
    });
  }

  void _fit({bool readable = false}) {
    final layout = _layout, viewport = _viewport;
    if (layout == null || viewport == null || layout.bounds.isEmpty) return;
    final overviewScale = math
        .min(
          viewport.width / layout.size.width,
          viewport.height / layout.size.height,
        )
        .clamp(0.08, 1.0);
    final scale = readable ? math.max(0.65, overviewScale) : overviewScale;
    final center = readable && scale > overviewScale
        ? layout.bounds[_entries.first.id]!.center
        : layout.size.center(Offset.zero);
    _transform.value = Matrix4.identity()
      ..setTranslationRaw(
        viewport.width / 2 - center.dx * scale,
        viewport.height / 2 - center.dy * scale,
        0,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _locate(int id) {
    final rect = _layout?.bounds[id], viewport = _viewport;
    if (rect == null || viewport == null) return;
    final scale = math
        .min(1.15, (viewport.width - 24) / rect.width)
        .clamp(0.3, 1.15);
    _transform.value = Matrix4.identity()
      ..setTranslationRaw(
        viewport.width / 2 - rect.center.dx * scale,
        viewport.height / 2 - rect.center.dy * scale,
        0,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _nextMatch(int step) {
    final matches = _matches;
    if (matches.isEmpty) return;
    setState(() => _matchIndex = (_matchIndex + step) % matches.length);
    _locate(matches[_matchIndex].id);
  }

  void _zoom(double factor) {
    final viewport = _viewport;
    if (viewport == null) return;
    final current = _transform.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(0.08, 4.0);
    final ratio = target / current;
    final center = viewport.center(Offset.zero);
    final origin = _transform.value.getTranslation();
    _transform.value = Matrix4.identity()
      ..setTranslationRaw(
        center.dx + (origin.x - center.dx) * ratio,
        center.dy + (origin.y - center.dy) * ratio,
        0,
      )
      ..scaleByDouble(target, target, 1, 1);
  }

  Future<void> _openFullscreen() async {
    if (widget.fullscreen) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (fullscreenContext) => Scaffold(
          appBar: AppBar(
            title: const Text('思维导图'),
            actions: [
              IconButton(
                tooltip: '查看原始资料',
                icon: const Icon(Icons.source_outlined),
                onPressed: () {
                  Navigator.of(fullscreenContext).pop();
                  widget.onSource();
                },
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: RecordMindmapView(
                text: widget.text,
                onSource: widget.onSource,
                query: _search,
                fullscreen: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _nodeStyle(BuildContext context, int id) => TextStyle(
    fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
    fontSize: id == 0 ? 17 : 14,
    fontWeight: id == 0 || _entries[id].parent == 0
        ? FontWeight.w700
        : FontWeight.w500,
    height: 1.4,
    letterSpacing: 0,
  );

  MindmapLayout _measure(BuildContext context) {
    final sizes = <int, Size>{};
    final parents = _entries.map((entry) => entry.parent).toSet();
    for (final entry in _entries) {
      final style = _nodeStyle(context, entry.id);
      final toggle = parents.contains(entry.id) ? 26.0 : 0.0;
      final painter = TextPainter(
        text: TextSpan(text: entry.title, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      );
      painter.layout();
      final width = (painter.width + 32 + toggle).clamp(
        128.0,
        entry.id == 0 ? 224.0 : 208.0,
      );
      painter.layout(maxWidth: width - 32 - toggle);
      sizes[entry.id] = Size(
        width,
        math.max(48, math.max(painter.height, toggle == 0 ? 0 : 24) + 28),
      );
      painter.dispose();
    }
    return MindmapLayout(
      entries: _entries,
      nodeSizes: sizes,
      collapsed: _collapsed,
    );
  }

  List<TextSpan> _highlightedTitle(String title, Color foreground) {
    final query = _search.toLowerCase();
    if (query.isEmpty) return [TextSpan(text: title)];
    final result = <TextSpan>[];
    final lower = title.toLowerCase();
    var cursor = 0;
    var found = lower.indexOf(query);
    while (found >= 0) {
      if (found > cursor) {
        result.add(TextSpan(text: title.substring(cursor, found)));
      }
      result.add(
        TextSpan(
          text: title.substring(found, found + query.length),
          style: const TextStyle(
            backgroundColor: Color(0xFFFFD86B),
            color: Color(0xFF633D00),
          ),
        ),
      );
      cursor = found + query.length;
      found = lower.indexOf(query, cursor);
    }
    result.add(
      TextSpan(
        text: title.substring(cursor),
        style: TextStyle(color: foreground),
      ),
    );
    return result;
  }

  Widget _node(BuildContext context, MindmapEntry entry, MindmapLayout layout) {
    final root = entry.id == 0;
    final primary = entry.parent == 0;
    final color = root
        ? const Color(0xFF293F75)
        : _branchColors[layout.branches[entry.id]! % _branchColors.length];
    final match =
        _search.isNotEmpty &&
        entry.title.toLowerCase().contains(_search.toLowerCase());
    final foreground = root || primary ? Colors.white : const Color(0xFF26344C);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('mindmap-node-${entry.id}'),
        borderRadius: BorderRadius.circular(root ? 18 : 12),
        onTap: widget.fullscreen ? null : _openFullscreen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: root || primary
                ? color
                : Color.lerp(color, Colors.white, 0.90),
            borderRadius: BorderRadius.circular(root ? 18 : 12),
            border: Border.all(
              color: match
                  ? const Color(0xFFF2A900)
                  : color.withValues(alpha: root || primary ? 1 : 0.35),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: _nodeStyle(
                      context,
                      entry.id,
                    ).copyWith(color: foreground),
                    children: _highlightedTitle(entry.title, foreground),
                  ),
                ),
              ),
              if (layout.hasChildren(entry.id))
                SizedBox(
                  width: 26,
                  child: IconButton(
                    tooltip: _collapsed.contains(entry.id) ? '展开分支' : '收起分支',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    iconSize: 18,
                    color: foreground,
                    icon: Icon(
                      _collapsed.contains(entry.id) ? Icons.add : Icons.remove,
                    ),
                    onPressed: () => setState(() {
                      if (!_collapsed.add(entry.id)) {
                        _collapsed.remove(entry.id);
                      }
                      _needsFit = true;
                    }),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _canvas() => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = Size(constraints.maxWidth, constraints.maxHeight);
      if (_viewport != viewport) {
        _viewport = viewport;
        _needsFit = true;
      }
      final layout = _measure(context);
      _layout = layout;
      if (_needsFit) {
        _needsFit = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_matches.isNotEmpty) {
            _locate(_matches[_matchIndex % _matches.length].id);
          } else {
            _fit(readable: widget.fullscreen);
          }
        });
      }
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE3E9F4)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: GestureDetector(
            onTap: widget.fullscreen ? null : _openFullscreen,
            child: InteractiveViewer(
              key: ValueKey(
                widget.fullscreen
                    ? 'mindmap-fullscreen-canvas'
                    : 'mindmap-preview-canvas',
              ),
              transformationController: _transform,
              constrained: false,
              alignment: Alignment.topLeft,
              boundaryMargin: const EdgeInsets.all(800),
              minScale: 0.08,
              maxScale: 4,
              child: SizedBox(
                width: layout.size.width,
                height: layout.size.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: _MindmapEdges(layout)),
                    ),
                    for (final entry in _entries)
                      if (layout.bounds[entry.id] case final rect?)
                        Positioned.fromRect(
                          rect: rect,
                          child: _node(context, entry, layout),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) return const Text('导图暂无节点，请编辑或重新生成。');
    final matches = _matches;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.query == null || widget.fullscreen) ...[
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: '搜索导图节点，直接在图中标色',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _changeSearch,
          ),
          const SizedBox(height: 6),
        ],
        Wrap(
          spacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed: _fit,
              icon: const Icon(Icons.center_focus_strong, size: 18),
              label: const Text('查看全图'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _collapsed.clear();
                _needsFit = true;
              }),
              child: const Text('展开全部'),
            ),
            if (!widget.fullscreen)
              TextButton.icon(
                onPressed: _openFullscreen,
                icon: const Icon(Icons.fullscreen, size: 20),
                label: const Text('全屏'),
              ),
            if (widget.fullscreen) ...[
              IconButton(
                tooltip: '放大导图',
                onPressed: () => _zoom(1.3),
                icon: const Icon(Icons.add_circle_outline),
              ),
              IconButton(
                tooltip: '缩小导图',
                onPressed: () => _zoom(1 / 1.3),
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
            if (_search.isNotEmpty) ...[
              Text(
                matches.isEmpty
                    ? '未找到匹配节点'
                    : '${_matchIndex + 1}/${matches.length} 处匹配',
              ),
              if (matches.isNotEmpty) ...[
                IconButton(
                  tooltip: '上一处匹配',
                  onPressed: () => _nextMatch(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: '下一处匹配',
                  onPressed: () => _nextMatch(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ],
          ],
        ),
        if (widget.fullscreen)
          Expanded(child: _canvas())
        else
          SizedBox(height: 340, child: _canvas()),
        const SizedBox(height: 6),
        Text(
          widget.fullscreen ? '双指缩放，拖动查看各分支' : '点击导图全屏查看 · 双指缩放，拖动浏览',
          style: AppTextStyles.caption(context),
        ),
      ],
    );
  }
}

class _MindmapEdges extends CustomPainter {
  _MindmapEdges(this.layout);
  final MindmapLayout layout;
  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in layout.entries) {
      final rect = layout.bounds[entry.id],
          parent = layout.bounds[entry.parent];
      if (rect == null || parent == null) continue;
      final right = layout.rightSide[entry.id]!;
      final from = Offset(right ? parent.right : parent.left, parent.center.dy);
      final to = Offset(right ? rect.left : rect.right, rect.center.dy);
      final middle = (from.dx + to.dx) / 2;
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..cubicTo(middle, from.dy, middle, to.dy, to.dx, to.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color =
              _branchColors[layout.branches[entry.id]! % _branchColors.length]
                  .withValues(alpha: 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = entry.parent == 0 ? 3 : 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MindmapEdges oldDelegate) =>
      oldDelegate.layout != layout;
}
