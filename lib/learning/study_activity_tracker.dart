import 'dart:async';

import 'package:flutter/foundation.dart';

import 'study_activity_repository.dart';

/// One tracker for the signed-in shell, including pages pushed above its tabs.
class StudyActivityTracker extends ChangeNotifier {
  StudyActivityTracker({
    StudyActivityRepository? repository,
    DateTime Function()? now,
  }) : _repository = repository ?? StudyActivityRepository(),
       _now = now ?? DateTime.now;

  final StudyActivityRepository _repository;
  final DateTime Function() _now;
  int? _userId;
  DateTime? _since;
  Timer? _timer;
  Future<void> _writes = Future.value();
  bool _disposed = false;

  Future<void> start(int userId) async {
    await pause();
    if (_disposed) return;
    _userId = userId;
    await resume();
  }

  Future<void> resume() {
    if (_disposed || _userId == null || _since != null) return _writes;
    _since = _now();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
    return flush();
  }

  Future<void> flush() {
    final userId = _userId;
    final from = _since;
    if (userId == null || from == null) return _writes;
    final to = _now();
    // Retain subsecond time for the next tick.
    final end = from.add(Duration(seconds: to.difference(from).inSeconds));
    _since = end;
    _writes = _writes.then((_) async {
      try {
        await _repository.recordUsage(userId, from, end);
        if (!_disposed) notifyListeners();
      } catch (error) {
        debugPrint('保存使用时长失败：$error');
      }
    });
    return _writes;
  }

  Future<void> pause() {
    _timer?.cancel();
    _timer = null;
    final pending = flush();
    _since = null;
    return pending;
  }

  @override
  void dispose() {
    pause();
    _disposed = true;
    super.dispose();
  }
}
