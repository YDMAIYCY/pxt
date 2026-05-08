import 'dart:math';

import 'package:flutter/material.dart';

class MathGamePage extends StatefulWidget {
  const MathGamePage({super.key});

  @override
  State<MathGamePage> createState() => _MathGamePageState();
}

class _MathGamePageState extends State<MathGamePage> {
  final _random = Random();
  late List<Map<String, dynamic>> _questions;
  int _index = 0;
  int _correct = 0;
  bool _finished = false;
  String _feedback = '';
  String? _selectedOption;

  static const _totalQuestions = 8;

  @override
  void initState() {
    super.initState();
    _questions = _buildQuestions();
  }

  List<Map<String, dynamic>> _buildQuestions() {
    final bank = <Map<String, dynamic>>[];

    // 加减混合
    var a = 18 + _random.nextInt(18), b = 12 + _random.nextInt(13), c = 6 + _random.nextInt(9);
    var answer = a + b - c;
    bank.add({'prompt': '直接计算：$a + $b - $c = ？', 'answer': answer, 'options': _numericOptions(answer, preferred: [answer + 3, answer - 4, a + c])});

    // 先乘后减
    a = 6 + _random.nextInt(4); b = 4 + _random.nextInt(5); c = 8 + _random.nextInt(11);
    answer = a * b - c;
    bank.add({'prompt': '先乘后减：$a × $b - $c = ？', 'answer': answer, 'options': _numericOptions(answer, preferred: [a * b, answer + b, answer - a])});

    // 带括号乘法
    a = 8 + _random.nextInt(11); b = 6 + _random.nextInt(7); c = 2 + _random.nextInt(3);
    answer = (a + b) * c;
    bank.add({'prompt': '带括号计算：（$a + $b）× $c = ？', 'answer': answer, 'options': _numericOptions(answer, preferred: [a + b * c, answer - c, answer + a])});

    // 分配律
    a = 5 + _random.nextInt(5); b = 8 + _random.nextInt(7); c = 2 + _random.nextInt(4);
    answer = a * (b - c);
    bank.add({'prompt': '再算括号里的差：$a × （$b - $c）= ？', 'answer': answer, 'options': _numericOptions(answer, preferred: [a * b - c, a * (b + c), answer - a])});

    // 先除后加
    final divisor = 3 + _random.nextInt(6);
    final quotient = 6 + _random.nextInt(7);
    final extra = 8 + _random.nextInt(11);
    answer = quotient + extra;
    bank.add({'prompt': '先除后加：${divisor * quotient} ÷ $divisor + $extra = ？', 'answer': answer, 'options': _numericOptions(answer, preferred: [quotient * extra, quotient, answer + divisor])});

    // 带括号除法
    final div2 = 2 + _random.nextInt(4);
    final target = 8 + _random.nextInt(7);
    final addA = 10 + _random.nextInt(15);
    answer = target;
    bank.add({'prompt': '带括号计算：（$addA + ${div2 * target - addA}）÷ $div2 = ？', 'answer': answer, 'options': _numericOptions(answer, min: 1, preferred: [target + div2, target - 2, addA ~/ div2])});

    // 填空 +
    answer = 12 + _random.nextInt(15);
    b = 8 + _random.nextInt(11);
    c = answer + b;
    bank.add({'prompt': '填空：□ + $b = $c，□ 应该填几？', 'answer': answer, 'options': _numericOptions(answer, preferred: [c - 1, b, answer + 5])});

    // 填空 ×
    answer = 4 + _random.nextInt(9);
    final factor = 5 + _random.nextInt(5);
    final result = answer * factor;
    bank.add({'prompt': '填空：□ × $factor = $result，□ 应该填几？', 'answer': answer, 'options': _numericOptions(answer, min: 1, preferred: [factor, answer + 2, result - factor])});

    // 周长
    final length = 6 + _random.nextInt(7);
    final width = 4 + _random.nextInt(6);
    answer = 2 * (length + width);
    bank.add({'prompt': '一个长方形长 $length 米、宽 $width 米，它的周长是多少米？', 'answer': answer, 'options': _numericOptions(answer, preferred: [length * width, length + width, answer + 4])});

    // 买笔
    final perBox = 8 + _random.nextInt(8);
    final boxes = 3 + _random.nextInt(3);
    final bonus = 3 + _random.nextInt(6);
    answer = perBox * boxes + bonus;
    bank.add({'prompt': '一盒彩笔有 $perBox 支，买 $boxes 盒后又奖励 $bonus 支，一共有多少支？', 'answer': answer, 'options': _numericOptions(answer, preferred: [perBox * boxes, perBox + boxes + bonus, answer - bonus])});

    // 书本
    final total = 28 + _random.nextInt(21);
    final give = 7 + _random.nextInt(9);
    final buy = 4 + _random.nextInt(7);
    answer = total - give + buy;
    bank.add({'prompt': '小明原来有 $total 本书，借给同学 $give 本，又新买了 $buy 本，现在有多少本？', 'answer': answer, 'options': _numericOptions(answer, preferred: [total - give, total + buy, answer - 2])});

    // 分苹果
    final each = 5 + _random.nextInt(5);
    final students = 4 + _random.nextInt(4);
    answer = each;
    final eachTotal = each * students;
    bank.add({'prompt': '把 $eachTotal 个苹果平均分给 $students 个同学，每人能分到多少个？', 'answer': answer, 'options': _numericOptions(answer, min: 1, preferred: [students, eachTotal - students, answer + 3])});

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
      if (candidate >= min && candidate != answer && !options.contains(candidate)) {
        options.add(candidate);
      }
    }
    options.shuffle(_random);
    return options.take(4).toList();
  }

  String get _currentPrompt => _questions[_index]['prompt'] as String;
  List<int> get _currentOptions => List<int>.from(_questions[_index]['options'] as List);
  int get _currentAnswer => _questions[_index]['answer'] as int;

  void _selectOption(int option) {
    if (_finished || _selectedOption != null) return;
    setState(() {
      _selectedOption = '$option';
      if (option == _currentAnswer) {
        _correct++;
        _feedback = '答对了！';
      } else {
        _feedback = '答错了，正确答案是 $_currentAnswer。';
      }
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _selectedOption = null;
        _feedback = '';
        _index++;
        if (_index >= _totalQuestions) _finished = true;
      });
    });
  }

  int get _score => (_correct / _totalQuestions * 100).round();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('口算达人'),
        backgroundColor: const Color(0xFF0EA5E9),
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
              if (!_finished) ...[
                LinearProgressIndicator(
                  value: _index / _totalQuestions,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0EA5E9)),
                ),
                const SizedBox(height: 8),
                Text('题目进度：${_index + 1}/$_totalQuestions', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: _finished ? _buildFinished() : _buildQuestion(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestion() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: const Color(0xFFF0F9FF), borderRadius: BorderRadius.circular(16)),
          child: Text(_currentPrompt, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF0B1324), height: 1.5), textAlign: TextAlign.center),
        ),
        const SizedBox(height: 16),
        if (_feedback.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _feedback.contains('对') ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_feedback, style: TextStyle(color: _feedback.contains('对') ? const Color(0xFF065F46) : const Color(0xFF991B1B), fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 20),
        ...List.generate(4, (i) {
          final option = _currentOptions[i];
          final isSelected = _selectedOption == '$option';
          final isCorrect = option == _currentAnswer;
          Color bgColor;
          if (_selectedOption == null) {
            bgColor = i.isEven ? const Color(0xFF10B981) : const Color(0xFF0EA5E9);
          } else if (isSelected) {
            bgColor = isCorrect ? const Color(0xFF10B981) : const Color(0xFFEF4444);
          } else if (isCorrect && _selectedOption != null) {
            bgColor = const Color(0xFF10B981);
          } else {
            bgColor = const Color(0xFFCBD5E1);
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              width: double.infinity,
              child: Material(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: _selectedOption == null ? () => _selectOption(option) : null,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    alignment: Alignment.center,
                    child: Text('$option', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _selectedOption != null && !isSelected && !isCorrect ? const Color(0xFF64748B) : Colors.white)),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFinished() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.emoji_events_rounded, size: 56, color: Color(0xFFF59E0B)),
        const SizedBox(height: 12),
        Text('完成！答对 $_correct / $_totalQuestions 题', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0B1324))),
        const SizedBox(height: 8),
        Text('本关得分：$_score', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF0EA5E9))),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: () {
          setState(() { _index = 0; _correct = 0; _finished = false; _feedback = ''; _selectedOption = null; _questions = _buildQuestions(); });
        }, icon: const Icon(Icons.refresh_rounded), label: const Text('再来一次')),
      ],
    );
  }
}
