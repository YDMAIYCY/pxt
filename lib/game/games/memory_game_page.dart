import 'dart:math';

import 'package:flutter/material.dart';

class MemoryGamePage extends StatefulWidget {
  const MemoryGamePage({super.key});

  @override
  State<MemoryGamePage> createState() => _MemoryGamePageState();
}

class _MemoryGamePageState extends State<MemoryGamePage> {
  late List<int> _cards;
  late List<bool> _revealed;
  late List<bool> _matched;
  int? _first;
  int _moves = 0;
  bool _finished = false;
  bool _locked = false;

  static const _colors = [
    Color(0xFFFF6666), Color(0xFF66B2FF), Color(0xFF66CC99), Color(0xFFFFB347),
    Color(0xFFBA68C8), Color(0xFFFF8C94), Color(0xFF81C784), Color(0xFFFFD666),
  ];

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    final random = Random();
    final values = [...List.generate(8, (i) => i + 1), ...List.generate(8, (i) => i + 1)];
    values.shuffle(random);
    _cards = values;
    _revealed = List.filled(16, false);
    _matched = List.filled(16, false);
    _first = null;
    _moves = 0;
    _finished = false;
    _locked = false;
  }

  void _tapCard(int index) {
    if (_locked || _finished || _revealed[index] || _matched[index]) return;

    setState(() {
      _revealed[index] = true;
      if (_first == null) {
        _first = index;
      } else if (index != _first) {
        _moves++;
        if (_cards[_first!] == _cards[index]) {
          _matched[_first!] = true;
          _matched[index] = true;
          _first = null;
          if (_matched.every((m) => m)) _finished = true;
        } else {
          _locked = true;
          final prevFirst = _first;
          _first = null;
          Future.delayed(const Duration(milliseconds: 700), () {
            if (!mounted) return;
            setState(() {
              _revealed[prevFirst!] = false;
              _revealed[index] = false;
              _locked = false;
            });
          });
        }
      }
    });
  }

  int get _score {
    final s = 100 - (_moves - 8).clamp(0, 100) * 8;
    return s.clamp(40, 100);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('记忆卡片'),
        backgroundColor: const Color(0xFF8B5CF6),
        foregroundColor: Colors.white,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('步数: $_moves', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(14)),
                child: const Text('翻开两张卡片，找到所有相同数字的配对。', style: TextStyle(color: Color(0xFF6D28D9), fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _finished ? _buildFinished() : _buildGrid(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return LayoutBuilder(builder: (context, constraints) {
      final size = (constraints.maxWidth - 24) / 4;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(16, (i) {
          final revealed = _revealed[i] || _matched[i];
          return GestureDetector(
            onTap: () => _tapCard(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: revealed ? _colors[(_cards[i] - 1) % _colors.length] : const Color(0xFF5B21B6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: revealed
                    ? Text('${_cards[i]}', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white))
                    : const Text('?', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white70)),
              ),
            ),
          );
        }),
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
          const Text('全部配对完成！', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0B1324))),
          const SizedBox(height: 8),
          Text('共用了 $_moves 步', style: const TextStyle(fontSize: 16, color: Color(0xFF64748B))),
          Text('本关得分：$_score', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF8B5CF6))),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => setState(() => _reset()),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('再来一次'),
          ),
        ],
      ),
    );
  }
}
