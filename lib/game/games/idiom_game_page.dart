import 'dart:math';

import 'package:flutter/material.dart';

class IdiomGamePage extends StatefulWidget {
  const IdiomGamePage({super.key});

  @override
  State<IdiomGamePage> createState() => _IdiomGamePageState();
}

class _IdiomGamePageState extends State<IdiomGamePage> {
  final _random = Random();

  static const _puzzleBank = [
    {'clue': '形容说话做事坚决果断，毫不犹豫', 'answer': '斩钉截铁', 'decoys': '剪叮接决刀锋快烈雷明山河'},
    {'clue': '比喻忍辱负重，刻苦自励，等待时机', 'answer': '卧薪尝胆', 'decoys': '坐柴品苦志勇寒热兵马风云'},
    {'clue': '形容条理十分分明，整齐不乱', 'answer': '井井有条', 'decoys': '木木成章清楚顺序分层丝路'},
    {'clue': '比喻事情真相完全显露出来', 'answer': '水落石出', 'decoys': '山高云起波沉火现真假迷踪'},
    {'clue': '比喻做事之前心里已经有完整打算', 'answer': '胸有成竹', 'decoys': '心怀妙策文墨画梅松兰风骨'},
  ];

  static const _gridSize = 6;
  static const _totalQuestions = 5;

  late List<Map<String, String>> _puzzles;
  int _questionIndex = 0;
  int _correct = 0;
  int _mistakes = 0;
  bool _finished = false;
  String _feedback = '根据释义，在字阵中按相邻路径找出完整成语。';

  late String _clue;
  late String _answer;
  late List<String> _answerChars;
  late List<List<String>> _board;
  late List<(int, int)> _selectedCells;

  @override
  void initState() {
    super.initState();
    _puzzles = List<Map<String, String>>.from(_puzzleBank)..shuffle(_random);
    _loadQuestion();
  }

  void _loadQuestion() {
    final current = _puzzles[_questionIndex];
    _clue = current['clue']!;
    _answer = current['answer']!;
    _answerChars = _answer.split('');
    _selectedCells = [];
    _buildGrid(current['decoys']!);
  }

  void _buildGrid(String decoys) {
    while (true) {
      final path = _generatePath();
      if (path == null) continue;
      final fillerPool = (decoys + _answer).split('');
      _board = List.generate(_gridSize, (r) => List.generate(_gridSize, (c) => fillerPool[_random.nextInt(fillerPool.length)]));
      for (var i = 0; i < _answerChars.length; i++) {
        final (r, c) = path[i];
        _board[r][c] = _answerChars[i];
      }
      break;
    }
  }

  List<(int, int)>? _generatePath() {
    const directions = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)];
    for (var attempt = 0; attempt < 200; attempt++) {
      final start = (_random.nextInt(_gridSize), _random.nextInt(_gridSize));
      final path = <(int, int)>[start];
      final used = <(int, int)>{start};
      while (path.length < _answerChars.length) {
        final (r, c) = path.last;
        final candidates = <(int, int)>[];
        for (final (dr, dc) in directions) {
          final nr = r + dr, nc = c + dc;
          if (nr >= 0 && nr < _gridSize && nc >= 0 && nc < _gridSize && !used.contains((nr, nc))) {
            candidates.add((nr, nc));
          }
        }
        if (candidates.isEmpty) break;
        final next = candidates[_random.nextInt(candidates.length)];
        path.add(next);
        used.add(next);
      }
      if (path.length == _answerChars.length) return path;
    }
    return null;
  }

  bool _isAdjacent((int, int) a, (int, int) b) => (a.$1 - b.$1).abs() <= 1 && (a.$2 - b.$2).abs() <= 1;

  String get _selectedText => _selectedCells.map((c) => _board[c.$1][c.$2]).join();

  void _tapCell(int row, int col) {
    if (_finished) return;
    final cell = (row, col);
    if (_selectedCells.contains(cell)) return;

    final expectedIndex = _selectedCells.length;
    final chosenChar = _board[row][col];
    final expectedChar = _answerChars[expectedIndex];

    if (expectedIndex > 0 && !_isAdjacent(_selectedCells.last, cell)) {
      setState(() { _selectedCells = []; _mistakes++; _feedback = '所选字必须和上一个字相邻，路径已清空。'; });
      return;
    }
    if (chosenChar != expectedChar) {
      setState(() { _selectedCells = []; _mistakes++; _feedback = '点到了"$chosenChar"，路径已清空。'; });
      return;
    }

    _selectedCells.add(cell);
    if (_selectedCells.length == _answerChars.length) {
      _correct++;
      _questionIndex++;
      if (_questionIndex >= _totalQuestions) {
        _finished = true;
        setState(() => _feedback = '五道成语寻踪全部完成！');
      } else {
        setState(() => _feedback = '找对了：$_answer，继续下一题。');
        _loadQuestion();
      }
    } else {
      setState(() => _feedback = '已找到 ${_selectedCells.length}/${_answerChars.length} 个字。');
    }
  }

  int get _score {
    final base = (_correct / _totalQuestions * 100).round();
    return (base - _mistakes * 5 + 8).clamp(30, 100);
  }

  double _cellSize(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final available = mediaQuery.size.width - mediaQuery.padding.horizontal -
        32 - 16 - _gridSize * 4;
    return min(56.0, max(0.0, available / _gridSize));
  }

  @override
  Widget build(BuildContext context) {
    final cellSize = _cellSize(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('成语寻踪'),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        actions: [
          Center(child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text('得分: $_score', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          )),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!_finished) ...[
              LinearProgressIndicator(value: _questionIndex / _totalQuestions, backgroundColor: const Color(0xFFE2E8F0), valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981))),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('题目：${_questionIndex + 1}/$_totalQuestions', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                Text('失误：$_mistakes', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
              ]),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFA7F3D0))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('线索', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF065F46))),
                const SizedBox(height: 4),
                Text(_finished ? '五道题都完成了！' : _clue, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0B1324))),
                Text('目标：${_answerChars.length} 字成语', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF10B981))),
              child: Column(children: [
                const Text('当前路径', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                Text(_selectedCells.isEmpty ? '尚未开始' : _selectedText.split('').join('  '),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _selectedCells.isEmpty ? const Color(0xFF94A3B8) : const Color(0xFF0B1324))),
              ]),
            ),
            const SizedBox(height: 12),
            if (!_finished) Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(16)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_gridSize, (r) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(_gridSize, (c) {
                        final selected = _selectedCells.contains((r, c));
                        return GestureDetector(
                          onTap: () => _tapCell(r, c),
                          child: Container(
                            width: cellSize, height: cellSize,
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: selected ? const Color(0xFF10B981) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: selected ? const Color(0xFF059669) : const Color(0xFFE2E8F0), width: 1.5),
                            ),
                            child: Center(child: Text(_board[r][c],
                                style: TextStyle(fontSize: cellSize * 0.38, fontWeight: FontWeight.w700, color: selected ? Colors.white : const Color(0xFF0B1324)))),
                          ),
                        );
                      }),
                    );
                  }),
                ),
              ),
            ),
            if (!_finished) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() { _selectedCells = []; _feedback = '当前路径已手动清空。'; }),
                  icon: const Icon(Icons.clear_rounded, color: Color(0xFFEF4444)),
                  label: const Text('清空当前路径', style: TextStyle(color: Color(0xFFEF4444))),
                ),
              ),
            ],
            if (_feedback.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_feedback, textAlign: TextAlign.center,
                    style: TextStyle(color: _feedback.contains('找对') || _finished ? const Color(0xFF16A34A) : const Color(0xFFEA580C), fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            if (_finished) Center(
              child: Column(children: [
                const Icon(Icons.emoji_events_rounded, size: 56, color: Color(0xFFF59E0B)),
                const SizedBox(height: 12),
                Text('完成！答对 $_correct / $_totalQuestions 题', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                Text('累计失误 $_mistakes 次', style: const TextStyle(fontSize: 16, color: Color(0xFF64748B))),
                Text('本关得分：$_score', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF10B981))),
                const SizedBox(height: 20),
                FilledButton.icon(onPressed: () => setState(() { _questionIndex = 0; _correct = 0; _mistakes = 0; _finished = false; _feedback = '根据释义，在字阵中按相邻路径找出完整成语。'; _puzzles = List<Map<String, String>>.from(_puzzleBank)..shuffle(_random); _loadQuestion(); }),
                    icon: const Icon(Icons.refresh_rounded), label: const Text('再来一次')),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
