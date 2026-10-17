import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/learning/study_activity_repository.dart';
import 'package:pxt1/learning/study_activity_tracker.dart';

class _RecordedActivity extends StudyActivityRepository {
  final intervals = <(int, DateTime, DateTime)>[];

  @override
  Future<void> recordUsage(int userId, DateTime from, DateTime to) async {
    intervals.add((userId, from, to));
  }
}

void main() {
  testWidgets(
    'periodic saves refresh listeners, pause stops ticks, dispose flushes',
    (tester) async {
      final repository = _RecordedActivity();
      var now = DateTime(2026, 10, 17, 10);
      final start = now;
      final tracker = StudyActivityTracker(
        repository: repository,
        now: () => now,
      );
      var refreshes = 0;
      tracker.addListener(() => refreshes++);
      await tracker.start(7);
      expect(repository.intervals, [(7, start, start)]);
      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(repository.intervals.last, (7, start, now));
      expect(refreshes, 2);
      await tracker.pause();
      final pausedCount = repository.intervals.length;
      now = now.add(const Duration(hours: 1));
      await tester.pump(const Duration(hours: 1));
      expect(repository.intervals.length, pausedCount);
      await tracker.resume();
      final resumedAt = now;
      now = now.add(const Duration(seconds: 10));
      final beforeDispose = refreshes;
      tracker.dispose();
      await tester.pump();
      expect(repository.intervals.last, (7, resumedAt, now));
      expect(refreshes, beforeDispose);
      await tester.pump(const Duration(minutes: 1));
      expect(repository.intervals.length, pausedCount + 2);
    },
  );
}
