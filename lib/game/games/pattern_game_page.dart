import 'dart:math';

import 'package:flutter/material.dart';

class PatternGamePage extends StatefulWidget {
  const PatternGamePage({super.key});

  @override
  State<PatternGamePage> createState() => _PatternGamePageState();
}

class _PatternGamePageState extends State<PatternGamePage> {
  final _random = Random();
  late List<Map<String, dynamic>> _questions;
  int _questionIndex = 0;
  int _correct = 0;
  bool _finished = false;
  String _feedback = '';
  String? _selectedOption;

  static const _totalQuestions = 5;

  @override
  void initState() {
    super.initState();
    _questions = _buildQuestions();
  }

  List<Map<String, dynamic>> _buildQuestions() {
    final bank = <Map<String, dynamic>>[];

    final start = 4 + _random.nextInt(7);
    final step = [3, 4, 5, 6][_random.nextInt(4)];
    final seq = List.generate(5, (i) => start + step * i);
    bank.add({
      'prompt': '观察等差规律：${seq.join("，")}，？',
      'answer': start + step * 5,
      'options': _numericOptions(start + step * 5, preferred: [start + step * 6, start + step * 4, start + step * 7]),
    });

    final mulStart = 2 + _random.nextInt(3);
    final mul = [2, 3][_random.nextInt(2)];
    final mulSeq = List.generate(5, (i) => mulStart * pow(mul, i).toInt());
    final mulAnswer = mulStart * pow(mul, 5).toInt();
    bank.add({
      'prompt': '观察倍数规律：${mulSeq.join("，")}，？',
      'answer': mulAnswer,
      'options': _numericOptions(mulAnswer, min: 1, preferred: [mulAnswer * mul, mulAnswer ~/ mul, mulAnswer + mul * 3]),
    });

    final diffStart = 1 + _random.nextInt(4);
    final diff = 2 + _random.nextInt(3);
    final growth = 1 + _random.nextInt(2);
    final diffSeq = <int>[diffStart];
    var currentDiff = diff;
    while (diffSeq.length < 6) { diffSeq.add(diffSeq.last + currentDiff); currentDiff += growth; }
    final diffAnswer = diffSeq.last;
    bank.add({
      'prompt': '差值在悄悄变大：${diffSeq.sublist(0, 5).join("，")}，？',
      'answer': diffAnswer,
      'options': _numericOptions(diffAnswer, preferred: [diffAnswer + growth, diffAnswer - growth - 1, diffAnswer - currentDiff]),
    });

    final fibA = 1 + _random.nextInt(3); final fibB = 2 + _random.nextInt(3);
    final fibSeq = <int>[fibA, fibB];
    while (fibSeq.length < 6) { fibSeq.add(fibSeq[fibSeq.length - 1] + fibSeq[fibSeq.length - 2]); }
    bank.add({
      'prompt': '后一个数等于前两个数之和：${fibSeq.sublist(0, 5).join("，")}，？',
      'answer': fibSeq.last,
      'options': _numericOptions(fibSeq.last, preferred: [fibSeq.last + fibSeq[2], fibSeq.last - fibSeq[1], fibSeq[fibSeq.length - 2] + fibSeq[fibSeq.length - 3]]),
    });

    bank.add({'prompt': '观察平方数规律：1，4，9，16，25，？', 'answer': 36, 'options': [30, 36, 42, 49]});
    bank.add({'prompt': '每次多加 1 个单位：1，3，6，10，15，？', 'answer': 21, 'options': [18, 20, 21, 28]});

    final oddStart = 2 + _random.nextInt(4); final evenStart = 8 + _random.nextInt(5);
    final oddStep = [2, 3][_random.nextInt(2)]; final evenStep = [3, 4][_random.nextInt(2)];
    final oddEvenSeq = <int>[];
    var ov = oddStart, ev = evenStart;
    for (var i = 0; i < 6; i++) {
      oddEvenSeq.add(i % 2 == 0 ? ov : ev);
      if (i % 2 == 0) { ov += oddStep; } else { ev += evenStep; }
    }
    bank.add({
      'prompt': '奇数位和偶数位各自成规律：${oddEvenSeq.join("，")}，？',
      'answer': ov,
      'options': _numericOptions(ov, preferred: [ov + 1, oddEvenSeq.last + oddStep, ov - oddStep]),
    });

    bank.add({'prompt': '循环规律是哪个：春，夏，秋，冬，春，？', 'answer': '夏', 'options': ['夏', '秋', '冬', '春']});
    bank.add({'prompt': '按方向顺时针变化：东，南，西，北，东，？', 'answer': '南', 'options': ['南', '西', '北', '东']});
    bank.add({'prompt': '颜色循环规律：红，蓝，黄，绿，红，蓝，？', 'answer': '黄', 'options': ['黄', '绿', '红', '蓝']});
    bank.add({'prompt': '观察质数规律：2，3，5，7，11，？', 'answer': 13, 'options': [13, 15, 17, 19]});

    bank.shuffle(_random);
    return bank.take(_totalQuestions).toList();
  }

  List<int> _numericOptions(int answer, {int min = 0, List<int>? preferred}) {
    final options = <int>[answer];
    for (final v in preferred ?? <int>[]) {
      if (v >= min && v != answer && !options.contains(v)) options.add(v);
    }
    final deltas = [-18, -12, -9, -7, -5, -4, -3, 3, 4, 5, 7, 9, 12, 18];
    while (options.length < 4) {
      final delta = deltas[_random.nextInt(deltas.length)];
      final candidate = answer + delta;
      if (candidate >= min && candidate != answer && !options.contains(candidate)) options.add(candidate);
    }
    options.shuffle(_random);
    return options.take(4).toList();
  }

  dynamic get _currentAnswer => _questions[_questionIndex]['answer'];
  List<dynamic> get _currentOptions {
    final raw = _questions[_questionIndex]['options'];
    if (raw is List) return raw;
    return [];
  }

  void _selectOption(dynamic option) {
    if (_finished || _selectedOption != null) return;
    final correct = option == _currentAnswer;
    setState(() {
      _selectedOption = option.toString();
      if (correct) {
        _correct++;
        _feedback = '回答正确！';
      } else {
        _feedback = '回答错误，正确答案是 $_currentAnswer。';
      }
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() {
        _selectedOption = null; _feedback = '';
        _questionIndex++;
        if (_questionIndex >= _totalQuestions) _finished = true;
      });
    });
  }

  int get _score => _correct * 20;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('找规律'),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        actions: [
          Center(child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text('得分: $_score', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          )),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            if (!_finished) ...[
              LinearProgressIndicator(value: _questionIndex / _totalQuestions, backgroundColor: const Color(0xFFE2E8F0), valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1))),
              const SizedBox(height: 8),
              Text('题目进度：${_questionIndex + 1}/$_totalQuestions', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 24),
            Expanded(child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
              child: _finished ? _buildFinished() : _buildQuestion(),
            )),
          ]),
        ),
      ),
    );
  }

  Widget _buildQuestion() {
    final options = _currentOptions;
    return SingleChildScrollView(
      child: Column(children: [
        Container(
          width: double.infinity, padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(14)),
          child: Text(_questions[_questionIndex]['prompt'] as String, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF0B1324), height: 1.5), textAlign: TextAlign.center),
        ),
        const SizedBox(height: 16),
        if (_feedback.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: _feedback.contains('正确') ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(12)),
            child: Text(_feedback, style: TextStyle(color: _feedback.contains('正确') ? const Color(0xFF065F46) : const Color(0xFF991B1B), fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        const SizedBox(height: 20),
        ...List.generate(options.length, (i) {
          final option = options[i];
          final isSelected = _selectedOption == option.toString();
          final correctAnswer = option == _currentAnswer;
          final clicked = _selectedOption != null;
          Color bg;
          if (!clicked) { bg = i.isEven ? const Color(0xFF6366F1) : const Color(0xFF8B5CF6); }
          else if (isSelected) { bg = correctAnswer ? const Color(0xFF10B981) : const Color(0xFFEF4444); }
          else if (correctAnswer) { bg = const Color(0xFF10B981); }
          else { bg = const Color(0xFFCBD5E1); }

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: clicked ? null : () => _selectOption(option),
              child: Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
                child: Text('$option', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: (!clicked || isSelected || correctAnswer) ? Colors.white : const Color(0xFF64748B))),
              ),
            ),
          );
        }),
      ]),
    );
  }

  Widget _buildFinished() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.emoji_events_rounded, size: 56, color: Color(0xFFF59E0B)),
        const SizedBox(height: 12),
        Text('完成！答对 $_correct / $_totalQuestions 题', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0B1324))),
        const SizedBox(height: 8),
        Text('本关得分：$_score', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF6366F1))),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: () => setState(() { _questionIndex = 0; _correct = 0; _finished = false; _feedback = ''; _selectedOption = null; _questions = _buildQuestions(); }), icon: const Icon(Icons.refresh_rounded), label: const Text('再来一次')),
      ]),
    );
  }
}
