import 'dart:math';

import 'package:flutter/material.dart';

class Game2048Page extends StatefulWidget {
  const Game2048Page({super.key});

  @override
  State<Game2048Page> createState() => _Game2048PageState();
}

class _Game2048PageState extends State<Game2048Page> {
  static const _n = 4;
  final _rng = Random();

  List<List<int>> _grid = List.generate(_n, (_) => List.filled(_n, 0));
  int _score = 0;
  bool _over = false;

  static const _bg = {
    0:    Color(0xFFCDC1B4), 2: Color(0xFFEEE4DA), 4: Color(0xFFEDE0C8),
    8:    Color(0xFFF2B179), 16: Color(0xFFF59563), 32: Color(0xFFF67C5F),
    64:   Color(0xFFF65E3B), 128: Color(0xFFEDCF72), 256: Color(0xFFEDCC61),
    512:  Color(0xFFEDC850), 1024: Color(0xFFEDC53F), 2048: Color(0xFFEDC22E),
  };
  static const _fg = {
    2: Color(0xFF776E65), 4: Color(0xFF776E65), 8: Colors.white,
    16: Colors.white, 32: Colors.white, 64: Colors.white, 128: Colors.white,
    256: Colors.white, 512: Colors.white, 1024: Colors.white, 2048: Colors.white,
  };
  Color _cbg(int v) => _bg[v] ?? const Color(0xFF3C3A32);
  Color _cfg(int v) => _fg[v] ?? Colors.white;
  double _fs(int v) => v < 100 ? 28 : v < 1000 ? 24 : v < 10000 ? 18 : 14;

  @override
  void initState() {
    super.initState();
    _add(); _add();
  }

  void _add() {
    final empty = <int>[];
    for (var i = 0; i < _n * _n; i++) {
      if (_grid[i ~/ _n][i % _n] == 0) empty.add(i);
    }
    if (empty.isEmpty) return;
    final idx = empty[_rng.nextInt(empty.length)];
    _grid[idx ~/ _n][idx % _n] = _rng.nextDouble() < 0.9 ? 2 : 4;
  }

  bool _alive() {
    for (var r = 0; r < _n; r++) {
      for (var c = 0; c < _n; c++) {
        if (_grid[r][c] == 0) return true;
        if (c < _n - 1 && _grid[r][c] == _grid[r][c + 1]) return true;
        if (r < _n - 1 && _grid[r][c] == _grid[r + 1][c]) return true;
      }
    }
    return false;
  }

  List<int> _merge(List<int> row) {
    final f = row.where((v) => v != 0).toList();
    final m = <int>[];
    var i = 0;
    while (i < f.length) {
      if (i + 1 < f.length && f[i] == f[i + 1]) { m.add(f[i] * 2); _score += f[i] * 2; i += 2; }
      else { m.add(f[i]); i++; }
    }
    while (m.length < _n) { m.add(0); }
    return m;
  }

  void _swipe(Direction d) {
    if (_over) return;
    final old = _grid.map((r) => List<int>.from(r)).toList();
    switch (d) {
      case Direction.left:
        for (var r = 0; r < _n; r++) { _grid[r] = _merge(_grid[r]); }
      case Direction.right:
        for (var r = 0; r < _n; r++) { _grid[r] = _merge(_grid[r].reversed.toList()).reversed.toList(); }
      case Direction.up:
        for (var c = 0; c < _n; c++) {
          final col = _merge([for (var r = 0; r < _n; r++) _grid[r][c]]);
          for (var r = 0; r < _n; r++) { _grid[r][c] = col[r]; }
        }
      case Direction.down:
        for (var c = 0; c < _n; c++) {
          final col = _merge([for (var r = _n - 1; r >= 0; r--) _grid[r][c]]);
          for (var r = 0; r < _n; r++) { _grid[_n - 1 - r][c] = col[r]; }
        }
    }
    var moved = false;
    for (var r = 0; r < _n; r++) {
      for (var c = 0; c < _n; c++) { if (_grid[r][c] != old[r][c]) moved = true; }
    }
    if (moved) { _add(); if (!_alive()) _over = true; setState(() {}); }
  }

  @override
  Widget build(BuildContext context) {
    final gap = 6.0;
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8EF),
      appBar: AppBar(
        title: const Text('2048'),
        backgroundColor: const Color(0xFFEC4899),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('得分: $_score', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          ),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (d) {
          if (d.primaryVelocity == null) return;
          if (d.primaryVelocity! < -30) _swipe(Direction.left);
          if (d.primaryVelocity! > 30) _swipe(Direction.right);
        },
        onVerticalDragEnd: (d) {
          if (d.primaryVelocity == null) return;
          if (d.primaryVelocity! < -30) _swipe(Direction.up);
          if (d.primaryVelocity! > 30) _swipe(Direction.down);
        },
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [
                  const Expanded(child: Text('滑动合并数字', maxLines: 2, softWrap: true,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF776E65)))),
                  const SizedBox(width: 12),
                  FilledButton.tonal(
                      style: FilledButton.styleFrom(minimumSize: const Size(88, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 16)),
                      onPressed: () => setState(() { _grid = List.generate(_n, (_) => List.filled(_n, 0)); _score = 0; _over = false; _add(); _add(); }),
                      child: const Text('新游戏')),
                ]),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final boardWidth = min(420.0, constraints.maxWidth);
                    final size = max(0.0, (boardWidth - gap * (_n + 2)) / _n);
                    return Center(
                      child: Container(
                        padding: EdgeInsets.all(gap),
                        decoration: BoxDecoration(color: const Color(0xFFBBADA0), borderRadius: BorderRadius.circular(12)),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          for (var r = 0; r < _n; r++)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              for (var c = 0; c < _n; c++)
                                Container(
                                  width: size, height: size,
                                  margin: EdgeInsets.all(gap / 2),
                                  decoration: BoxDecoration(
                                    color: _cbg(_grid[r][c]),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: _grid[r][c] > 0
                                      ? FittedBox(child: Text('${_grid[r][c]}', style: TextStyle(fontSize: _fs(_grid[r][c]), fontWeight: FontWeight.w800, color: _cfg(_grid[r][c]))))
                                      : null,
                                ),
                            ]),
                        ]),
                      ),
                    );
                  },
                ),
                if (_over) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: const Color(0xFFEEE4DA).withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('游戏结束', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF776E65))),
                      const SizedBox(height: 8),
                      Text('得分: $_score', style: const TextStyle(fontSize: 18, color: Color(0xFF776E65))),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: () => setState(() { _grid = List.generate(_n, (_) => List.filled(_n, 0)); _score = 0; _over = false; _add(); _add(); }), child: const Text('重新开始')),
                    ]),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

enum Direction { left, right, up, down }
