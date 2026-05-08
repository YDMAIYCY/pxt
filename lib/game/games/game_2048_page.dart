import 'dart:math';

import 'package:flutter/material.dart';

class Game2048Page extends StatefulWidget {
  const Game2048Page({super.key});

  @override
  State<Game2048Page> createState() => _Game2048PageState();
}

class _Game2048PageState extends State<Game2048Page> {
  static const _size = 4;
  final _random = Random();

  late List<List<int>> _grid;
  int _score = 0;
  bool _gameOver = false;
  bool _won = false;

  static const _bgColors = {
    0: Color(0xFFCDC1B4),
    2: Color(0xFFEEE4DA),
    4: Color(0xFFEDE0C8),
    8: Color(0xFFF2B179),
    16: Color(0xFFF59563),
    32: Color(0xFFF67C5F),
    64: Color(0xFFF65E3B),
    128: Color(0xFFEDCF72),
    256: Color(0xFFEDCC61),
    512: Color(0xFFEDC850),
    1024: Color(0xFFEDC53F),
    2048: Color(0xFFEDC22E),
  };

  static const _textColors = {
    0: Color(0xFFCDC1B4),
    2: Color(0xFF776E65),
    4: Color(0xFF776E65),
    8: Colors.white,
    16: Colors.white,
    32: Colors.white,
    64: Colors.white,
    128: Colors.white,
    256: Colors.white,
    512: Colors.white,
    1024: Colors.white,
    2048: Colors.white,
  };

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _grid = List.generate(_size, (_) => List.filled(_size, 0));
    _score = 0;
    _gameOver = false;
    _won = false;
    _spawnTile();
    _spawnTile();
  }

  void _spawnTile() {
    final empty = <(int, int)>[];
    for (var r = 0; r < _size; r++) {
      for (var c = 0; c < _size; c++) {
        if (_grid[r][c] == 0) empty.add((r, c));
      }
    }
    if (empty.isEmpty) return;
    final (r, c) = empty[_random.nextInt(empty.length)];
    _grid[r][c] = _random.nextDouble() < 0.9 ? 2 : 4;
  }

  bool _canMove() {
    for (var r = 0; r < _size; r++) {
      for (var c = 0; c < _size; c++) {
        if (_grid[r][c] == 0) return true;
        if (_grid[r][c] == 2048 && !_won) {
          _won = true;
        }
        if (c < _size - 1 && _grid[r][c] == _grid[r][c + 1]) return true;
        if (r < _size - 1 && _grid[r][c] == _grid[r + 1][c]) return true;
      }
    }
    return false;
  }

  List<int> _slideLine(List<int> line) {
    final filtered = line.where((v) => v != 0).toList();
    final merged = <int>[];
    var i = 0;
    while (i < filtered.length) {
      if (i + 1 < filtered.length && filtered[i] == filtered[i + 1]) {
        merged.add(filtered[i] * 2);
        _score += filtered[i] * 2;
        i += 2;
      } else {
        merged.add(filtered[i]);
        i++;
      }
    }
    while (merged.length < _size) {
      merged.add(0);
    }
    return merged;
  }

  void _move(Direction dir) {
    if (_gameOver) return;

    final oldGrid = _grid.map((row) => List<int>.from(row)).toList();
    final oldScore = _score;

    switch (dir) {
      case Direction.left:
        for (var r = 0; r < _size; r++) {
          _grid[r] = _slideLine(_grid[r]);
        }
      case Direction.right:
        for (var r = 0; r < _size; r++) {
          _grid[r] = _slideLine(_grid[r].reversed.toList()).reversed.toList();
        }
      case Direction.up:
        for (var c = 0; c < _size; c++) {
          final col = _slideLine(List.generate(_size, (r) => _grid[r][c]));
          for (var r = 0; r < _size; r++) {
            _grid[r][c] = col[r];
          }
        }
      case Direction.down:
        for (var c = 0; c < _size; c++) {
          final col = _slideLine(List.generate(_size, (r) => _grid[_size - 1 - r][c]));
          for (var r = 0; r < _size; r++) {
            _grid[_size - 1 - r][c] = col[r];
          }
        }
    }

    var moved = false;
    for (var r = 0; r < _size; r++) {
      for (var c = 0; c < _size; c++) {
        if (_grid[r][c] != oldGrid[r][c]) moved = true;
      }
    }

    if (moved) {
      _spawnTile();
      if (!_canMove()) _gameOver = true;
      setState(() {});
    } else {
      _score = oldScore;
    }
  }

  Color _tileBg(int value) => _bgColors[value] ?? const Color(0xFF3C3A32);
  Color _tileTextColor(int value) => _textColors[value] ?? Colors.white;
  double _tileFontSize(int value) {
    if (value < 100) return 28;
    if (value < 1000) return 24;
    return 18;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8EF),
      appBar: AppBar(
        title: const Text('2048'),
        backgroundColor: const Color(0xFFEC4899),
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
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -30) {
            _move(Direction.left);
          } else if (details.primaryVelocity! > 30) {
            _move(Direction.right);
          }
        },
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -30) {
            _move(Direction.up);
          } else if (details.primaryVelocity! > 30) {
            _move(Direction.down);
          }
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('滑动合并数字', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF776E65))),
                    FilledButton.tonal(
                      onPressed: () => setState(() => _reset()),
                      child: const Text('新游戏'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: const Color(0xFFBBADA0), borderRadius: BorderRadius.circular(12)),
                      child: Stack(
                        children: [
                          Column(
                            children: List.generate(_size, (r) {
                              return Expanded(
                                child: Row(
                                  children: List.generate(_size, (c) {
                                    final value = _grid[r][c];
                                    return Expanded(
                                      child: Container(
                                        margin: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(color: _tileBg(value), borderRadius: BorderRadius.circular(8)),
                                        child: Center(
                                          child: value > 0
                                              ? Text('$value', style: TextStyle(fontSize: _tileFontSize(value), fontWeight: FontWeight.w800, color: _tileTextColor(value)))
                                              : null,
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              );
                            }),
                          ),
                          if (_gameOver)
                            Container(
                              decoration: BoxDecoration(color: const Color(0xFFEEE4DA).withValues(alpha: 0.73), borderRadius: BorderRadius.circular(8)),
                              child: const Center(
                                child: Text('游戏结束', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF776E65))),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum Direction { left, right, up, down }
