import 'dart:math';

import 'package:flutter/material.dart';

class SlidePuzzleGamePage extends StatefulWidget {
  const SlidePuzzleGamePage({super.key});

  @override
  State<SlidePuzzleGamePage> createState() => _SlidePuzzleGamePageState();
}

class _SlidePuzzleGamePageState extends State<SlidePuzzleGamePage> {
  static const _stageSizes = [3, 4];
  final _random = Random();

  late int _stageIndex;
  late int _size;
  late List<int> _goal;
  late List<int> _tiles;
  int _totalMoves = 0;
  int _stageMoves = 0;
  bool _finished = false;
  List<int> _completedStages = [];
  String _feedback = '点击与空白格相邻的数字块移动。';

  @override
  void initState() {
    super.initState();
    _stageIndex = 0;
    _setupStage();
  }

  void _setupStage() {
    _size = _stageSizes[_stageIndex];
    _goal = [...List.generate(_size * _size - 1, (i) => i + 1), 0];
    _tiles = _shuffleSolvable();
    _stageMoves = 0;
  }

  List<int> _shuffleSolvable() {
    while (true) {
      final candidate = List<int>.from(_goal);
      candidate.shuffle(_random);
      if (_listEquals(candidate, _goal)) continue;
      var misplaced = 0;
      for (var i = 0; i < candidate.length; i++) {
        if (candidate[i] != 0 && candidate[i] != _goal[i]) misplaced++;
      }
      if (misplaced >= _size + 3 && _isSolvable(candidate)) return candidate;
    }
  }

  bool _isSolvable(List<int> nums) {
    final arr = nums.where((x) => x != 0).toList();
    var inv = 0;
    for (var i = 0; i < arr.length; i++) {
      for (var j = i + 1; j < arr.length; j++) {
        if (arr[i] > arr[j]) inv++;
      }
    }
    if (_size % 2 == 1) return inv % 2 == 0;
    final blankRowFromBottom = _size - (nums.indexOf(0) ~/ _size);
    if (blankRowFromBottom % 2 == 0) return inv % 2 == 1;
    return inv % 2 == 0;
  }

  bool _listEquals(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) { if (a[i] != b[i]) return false; }
    return true;
  }

  bool _isAdjacent(int a, int b) {
    final ra = a ~/ _size, ca = a % _size;
    final rb = b ~/ _size, cb = b % _size;
    return (ra - rb).abs() + (ca - cb).abs() == 1;
  }

  void _tapTile(int index) {
    if (_finished || _tiles[index] == 0) return;
    final zero = _tiles.indexOf(0);
    if (_isAdjacent(index, zero)) {
      setState(() {
        final tmp = _tiles[index];
        _tiles[index] = _tiles[zero];
        _tiles[zero] = tmp;
        _stageMoves++;
        _totalMoves++;
        if (_listEquals(_tiles, _goal)) _completeStage();
      });
    }
  }

  void _completeStage() {
    _completedStages.add(_size);
    if (_stageIndex < _stageSizes.length - 1) {
      final finishedSize = _size;
      _stageIndex++;
      _setupStage();
      _feedback = '$finishedSize×$finishedSize 完成，进入 ${_stageSizes[_stageIndex]}×${_stageSizes[_stageIndex]}。';
    } else {
      _finished = true;
      _feedback = '华容道全部通关！';
    }
  }

  int get _score {
    final penalty = _totalMoves > 140 ? (_totalMoves - 140) ~/ 2 : 0;
    return (100 - penalty).clamp(45, 100);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('数字华容道'),
        backgroundColor: const Color(0xFFF59E0B),
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
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildInfo(),
              const SizedBox(height: 20),
              _finished ? _buildFinished() : _buildPuzzle(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _stageSizes.map((s) {
              final completed = _completedStages.contains(s);
              final active = s == _size && !_finished;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: completed ? const Color(0xFF10B981) : (active ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$s×$s', style: TextStyle(color: (completed || active) ? Colors.white : const Color(0xFF64748B), fontWeight: FontWeight.w700)),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text('本阶段: $_stageMoves 步 | 总计: $_totalMoves 步', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(_feedback, style: TextStyle(color: _finished ? const Color(0xFF16A34A) : const Color(0xFFB45309), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildPuzzle() {
    const gap = 6.0;
    return LayoutBuilder(builder: (context, constraints) {
      final preferredTileSize = _size == 3 ? 100.0 : 76.0;
      final fittedTileSize = (constraints.maxWidth - (_size - 1) * gap) / _size;
      final tileSize = min(preferredTileSize, max(0.0, fittedTileSize));
      final gridWidth = _size * tileSize + (_size - 1) * gap;
      return Center(
        child: SizedBox(
          width: gridWidth,
          height: gridWidth,
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: List.generate(_tiles.length, (i) {
              final value = _tiles[i];
              return GestureDetector(
                onTap: () => _tapTile(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: tileSize,
                  height: tileSize,
                  decoration: BoxDecoration(
                    color: value == 0 ? const Color(0xFFE2E8F0) : (value % 2 == 1 ? const Color(0xFFF59E0B) : const Color(0xFF7C3AED)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: value != 0
                      ? Center(child: Text('$value', style: TextStyle(fontSize: _size == 3 ? 36 : 28, fontWeight: FontWeight.w900, color: Colors.white)))
                      : null,
                ),
              );
            }),
          ),
        ),
      );
    });
  }

  Widget _buildFinished() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_rounded, size: 56, color: Color(0xFFF59E0B)),
          const SizedBox(height: 12),
          const Text('华容道全部通关！', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('共移动 $_totalMoves 次', style: const TextStyle(fontSize: 16, color: Color(0xFF64748B))),
          Text('本关得分：$_score', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFFF59E0B))),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => setState(() { _stageIndex = 0; _completedStages = []; _totalMoves = 0; _finished = false; _feedback = '点击与空白格相邻的数字块移动。'; _setupStage(); }),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('再来一次'),
          ),
        ],
      ),
    );
  }
}
