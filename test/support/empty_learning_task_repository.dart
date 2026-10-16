import 'package:pxt1/learning/learning_task_repository.dart';

class EmptyLearningTaskRepository extends LearningTaskRepository {
  @override
  Future<LearningDashboard> dashboard(int userId) async => const LearningDashboard(
    tasks: [], recommendations: [], pendingPractice: 0,
    overduePractice: 0, wrongQuestions: 0, inProgress: 0,
  );

  @override
  Future<List<PracticeBacklog>> practiceBacklog(
    int userId, {
    int limit = 3,
    int maxQuestionsPerDocument = 20,
  }) async => const [];
}
