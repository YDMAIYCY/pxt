import 'package:flutter/foundation.dart';

/// A revision of committed learning data, using the app's existing notifier model.
class LearningEvents {
  LearningEvents._();
  static final changed = ValueNotifier<int>(0);
  static void notify() => changed.value++;
}
