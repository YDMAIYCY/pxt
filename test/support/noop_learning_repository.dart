import 'package:pxt1/database/learning_repository.dart';

class NoopLearningRepository extends LearningRepository {
  @override
  Future<void> recordQuestionAttempt(
    int userId,
    int questionId,
    bool correct,
    String answer, {
    int? conceptId,
    String origin = 'practice',
    String? prompt,
    String? feedback,
    int? score,
  }) async {}
}
