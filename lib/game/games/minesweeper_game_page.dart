import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';

class MinesweeperGamePage extends StatefulWidget {
  const MinesweeperGamePage({super.key});

  @override
  State<MinesweeperGamePage> createState() => _MinesweeperGamePageState();
}

class _MinesweeperGamePageState extends State<MinesweeperGamePage> {
  static const _stages = [
    {'name': '训练场', 'rows': 8, 'cols': 8, 'mines': 3},
    {'name': '进阶场', 'rows': 11, 'cols': 11, 'mines': 5},
  ];

  final _random = Random();
  late int _stageIndex;
  late int _rows, _cols, _mineTotal;
  late Set<int> _minePositions;
  late Map<int, int> _adjacentCounts;
  Set<int> _revealed = {};
  Set<int> _flagged = {};
  int _totalRestarts = 0;
  int _stageRestarts = 0;
  bool _firstClick = true;
  bool _finished = false;
  List<String> _completedStages = [];
  String _feedback = '点击格子翻开，长按标旗。标出所有雷即可通关。';

  @override
  void initState() {
    super.initState();
    _stageIndex = 0;
    _loadStage();
  }

  void _loadStage() {
    final config = _stages[_stageIndex];
    _rows = config['rows'] as int;
    _cols = config['cols'] as int;
    _mineTotal = config['mines'] as int;
    _firstClick = true;
    _stageRestarts = 0;
    _revealed = {};
    _flagged = {};
    _buildBoard();
  }

  void _buildBoard() {
    final totalCells = _rows * _cols;
    final allCells = List.generate(totalCells, (i) => i);
    final shuffled = allCells.toList()..shuffle(_random);
    _minePositions = shuffled.take(_mineTotal).toSet();
    _adjacentCounts = {};
    for (var i = 0; i < totalCells; i++) {
      if (_minePositions.contains(i)) continue;
      _adjacentCounts[i] = _neighbors(i).where((n) => _minePositions.contains(n)).length;
    }
  }

  int _toIndex(int row, int col) => row * _cols + col;
  int _row(int index) => index ~/ _cols;
  int _col(int index) => index % _cols;

  Iterable<int> _neighbors(int index) {
    final r = _row(index), c = _col(index);
    return [
      for (var dr = -1; dr <= 1; dr++)
        for (var dc = -1; dc <= 1; dc++)
          if (dr != 0 || dc != 0)
            if (r + dr >= 0 && r + dr < _rows && c + dc >= 0 && c + dc < _cols)
              _toIndex(r + dr, c + dc),
    ];
  }

  void _ensureSafeFirstClick(int index) {
    if (_revealed.isNotEmpty || _flagged.isNotEmpty || !_minePositions.contains(index)) return;
    while (_minePositions.contains(index)) {
      _buildBoard();
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _revealCell(int index) {
    if (_finished || _flagged.contains(index) || _revealed.contains(index)) return;

    if (_firstClick) {
      _firstClick = false;
      _ensureSafeFirstClick(index);
    }

    if (_minePositions.contains(index)) {
      _totalRestarts++;
      _stageRestarts++;
      _firstClick = true;
      _revealed = {};
      _flagged = {};
      _buildBoard();
      _feedback = '踩到雷了，本阶段已重新开始。';
      _rebuild();
      return;
    }

    final queue = Queue<int>();
    final seen = <int>{index};
    queue.add(index);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (_revealed.contains(current) || _flagged.contains(current) || _minePositions.contains(current)) continue;
      _revealed.add(current);
      if ((_adjacentCounts[current] ?? 0) == 0) {
        for (final nxt in _neighbors(current)) {
          if (!seen.contains(nxt) && !_flagged.contains(nxt)) {
            seen.add(nxt);
            queue.add(nxt);
          }
        }
      }
    }

    final count = _adjacentCounts[index] ?? 0;
    _feedback = count == 0 ? '安全区，继续排查。' : '这个格子周围有 $count 个雷。';
    _rebuild();
  }

  void _toggleFlag(int index) {
    if (_finished || _revealed.contains(index)) return;

    if (_flagged.contains(index)) {
      _flagged.remove(index);
      _feedback = '已取消标旗，${_flagged.length}/$_mineTotal';
      _rebuild();
      return;
    }

    if (_flagged.length >= _mineTotal) {
      _feedback = '旗子数量已用满！';
      _rebuild();
      return;
    }

    _flagged.add(index);
    _feedback = '已标旗 ${_flagged.length}/$_mineTotal';

    if (_flagged.length == _mineTotal && _flagged.every((f) => _minePositions.contains(f))) {
      final completedName = _stages[_stageIndex]['name'] as String;
      _completedStages.add(completedName);
      if (_stageIndex < _stages.length - 1) {
        _stageIndex++;
        _loadStage();
        _feedback = '$completedName 已完成，进入${_stages[_stageIndex]['name']}。';
      } else {
        _finished = true;
        _feedback = '全部扫雷图完成！';
      }
    } else if (_flagged.length == _mineTotal) {
      _feedback = '旗子数量已用满，但还没有全部找对。';
    }
    _rebuild();
  }

  int get _remainingSafe => _rows * _cols - _mineTotal - _revealed.length;

  int get _score {
    final s = 100 - _totalRestarts * 8;
    return s.clamp(55, 100);
  }

  static const _numberColors = {
    1: Color(0xFF2563EB), 2: Color(0xFF16A34A), 3: Color(0xFFDC2626),
    4: Color(0xFF7C3AED), 5: Color(0xFFEA580C), 6: Color(0xFF0D9488),
    7: Color(0xFF1E293B), 8: Color(0xFF64748B),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('扫雷挑战'),
        backgroundColor: const Color(0xFFEF4444),
        foregroundColor: Colors.white,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('得分: $_score', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoPanel(),
              const SizedBox(height: 12),
              _buildGridWidget(),
              if (_finished) _buildFinished(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            _buildBadge('阶段 ${_stageIndex + 1}/${_stages.length}', const Color(0xFFEF4444)),
            _buildBadge(_stages[_stageIndex]['name'] as String, const Color(0xFFF59E0B)),
            _buildBadge('雷: $_mineTotal', const Color(0xFF6366F1)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 4, children: [
            Text('旗: ${_flagged.length}/$_mineTotal', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            Text('重开: $_stageRestarts', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            Text('剩余: $_remainingSafe', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF2563EB))),
          ]),
          const SizedBox(height: 6),
          Text(_feedback, style: TextStyle(color: _finished ? const Color(0xFF16A34A) : const Color(0xFFEA580C), fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildGridWidget() {
    final mediaQuery = MediaQuery.of(context);
    final availableWidth = mediaQuery.size.width -
        mediaQuery.padding.horizontal - 32;
    const gridPadding = 10.0;
    const gap = 2.0;
    final cellWidth = (availableWidth - gridPadding * 2 -
            gap * (_cols - 1)) /
        _cols;
    final cellTotal = min(42.0, max(0.0, cellWidth.floorToDouble()));
    return Center(
      child: Container(
        padding: const EdgeInsets.all(gridPadding),
        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(16)),
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: List.generate(_rows * _cols, (i) {
            final revealed = _revealed.contains(i);
            final flagged = _flagged.contains(i);
            return GestureDetector(
              onTap: _finished ? null : () => _revealCell(i),
              onLongPress: _finished ? null : () => _toggleFlag(i),
              child: Container(
                width: cellTotal,
                height: cellTotal,
                decoration: BoxDecoration(
                  color: revealed ? const Color(0xFFF8FAFC) : (flagged ? const Color(0xFFF59E0B) : const Color(0xFF3B82F6)),
                  borderRadius: BorderRadius.circular(6),
                  border: revealed ? Border.all(color: const Color(0xFFCBD5E1)) : null,
                ),
                child: Center(
                  child: revealed
                      ? (_adjacentCounts[i] != null && _adjacentCounts[i]! > 0
                          ? Text('${_adjacentCounts[i]}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _numberColors[_adjacentCounts[i]]))
                          : const SizedBox.shrink())
                      : flagged
                          ? const Text('旗', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))
                          : null,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildFinished() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Center(
        child: Column(children: [
          const Icon(Icons.emoji_events_rounded, size: 56, color: Color(0xFFF59E0B)),
          const SizedBox(height: 12),
          const Text('扫雷全部完成！', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('共重开 $_totalRestarts 次', style: const TextStyle(fontSize: 16, color: Color(0xFF64748B))),
          Text('本关得分：$_score', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFFEF4444))),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: () => setState(() { _stageIndex = 0; _completedStages = []; _totalRestarts = 0; _finished = false; _loadStage(); }),
              icon: const Icon(Icons.refresh_rounded), label: const Text('再来一次')),
        ]),
      ),
    );
  }
}
