import '../database/agent_task_repository.dart';
import 'eclaw_task.dart';
import 'eclaw_tool_registry.dart';
import 'eclaw_context.dart';
import 'dart:async';

class AgentTaskExecutor {
  AgentTaskExecutor({required this.registry, required this.repository});
  final EClawToolRegistry registry;
  final AgentTaskRepository repository;
  static final Set<String> _active = {};
  static final StreamController<String> _updates =
      StreamController<String>.broadcast();
  static Stream<String> get updates => _updates.stream;
  String key(AgentTask task) =>
      '${identityHashCode(registry.database)}:${task.userId}:${task.id}';

  /// On reopening a session, running mutating steps are never blindly repeated.
  Future<AgentTask> recover(AgentTask task) async {
    if (task.status != 'running' || _active.contains(key(task))) return task;
    for (final step in task.steps.where(
      (s) => s.status == AgentStepStatus.running,
    )) {
      step.status = AgentStepStatus.failed;
      step.error = registry.get(step.tool).replaySafe
          ? '执行中断，可以重试；已完成步骤会跳过。'
          : '执行中断，结果可能已保存。请检查对应业务页面，避免重复生成。';
    }
    task.status = task.cancelRequested ? 'cancelled' : 'failed';
    await repository.save(task);
    return task;
  }

  Future<void> run(
    AgentTask task, {
    bool confirm = false,
    void Function()? onChanged,
  }) async {
    final taskKey = key(task);
    if (task.isTerminal || !_active.add(taskKey)) return;
    try {
      if (!await repository.claim(task.userId, task.id)) return;
      task.status = 'running';
      for (var index = 0; index < task.steps.length; index++) {
        final step = task.steps[index];
        if (step.status == AgentStepStatus.completed) continue;
        final fresh = await repository.get(task.userId, task.id);
        if (fresh == null || fresh.cancelRequested) {
          task.cancelRequested = true;
          task.status = 'cancelled';
          for (final pending in task.steps.where(
            (s) => s.status != AgentStepStatus.completed,
          )) {
            pending.status = AgentStepStatus.cancelled;
          }
          await repository.save(task);
          onChanged?.call();
          return;
        }
        final tool = registry.get(step.tool);
        if (step.status == AgentStepStatus.failed &&
            !tool.replaySafe &&
            step.error?.contains('执行中断') == true) {
          task.status = 'failed';
          await repository.save(task);
          return;
        }
        try {
          final args = step.args.map(
            (key, value) => MapEntry(key, _resolve(value, task, index)),
          );
          tool.validate(args);
          final collectionStart =
              step.tool == 'create_knowledge_library' &&
              task.steps
                  .skip(index + 1)
                  .any((s) => s.tool == 'move_document_to_library');
          if ((tool.requiresConfirmation || collectionStart) &&
              !step.confirmed) {
            if (confirm && step.status == AgentStepStatus.waitingConfirmation) {
              step.confirmed = true;
              confirm = false;
              if (collectionStart) {
                for (final move
                    in task.steps
                        .skip(index + 1)
                        .where(
                          (s) =>
                              s.tool == 'move_document_to_library' &&
                              s.args['libraryId'] == '@$index.libraryId',
                        )) {
                  move.confirmed = true;
                }
              }
            } else {
              step.status = AgentStepStatus.waitingConfirmation;
              task.status = 'waiting_confirmation';
              await repository.save(task);
              onChanged?.call();
              return;
            }
          }
          // A collection that found nothing must not create an empty target.
          if (step.tool == 'create_knowledge_library' &&
              task.steps
                  .take(index)
                  .any(
                    (s) =>
                        s.tool == 'search_documents' &&
                        (s.result['recordIds'] as List?)?.isEmpty == true,
                  )) {
            throw StateError('没有匹配资料，未创建知识库或移动数据');
          }
          step.status = AgentStepStatus.running;
          step.error = null;
          await repository.save(task);
          onChanged?.call();
          final moved = task.steps
              .take(index)
              .where(
                (s) =>
                    s.tool == 'move_document_to_library' &&
                    s.status == AgentStepStatus.completed,
              )
              .lastOrNull;
          final executionContext = moved == null
              ? task.context
              : EClawContext(
                  knowledgeBaseId: moved.result['libraryId'] as int,
                  importRecordId: task.context.importRecordId,
                  documentId: task.context.documentId,
                );
          step.result = await registry.run(
            step.tool,
            EClawToolCall(
              userId: task.userId,
              context: executionContext,
              args: args,
              operationKey: 'eclaw:${task.userId}:${task.id}:$index',
            ),
            confirmed: step.confirmed,
          );
          step.status = AgentStepStatus.completed;
          await repository.save(task);
          onChanged?.call();
        } catch (error) {
          final uncertain =
              !tool.replaySafe &&
              (step.status == AgentStepStatus.running ||
                  step.status == AgentStepStatus.completed) &&
              !'$error'.contains('API Key');
          step.status = AgentStepStatus.failed;
          step.error = uncertain
              ? '执行中断，结果可能已保存，请先检查业务页面，避免重复生成。错误：$error'
              : '$error';
          task.status = 'failed';
          await repository.save(task);
          onChanged?.call();
          return;
        }
      }
      task.status = 'completed';
      await repository.save(task);
      onChanged?.call();
    } finally {
      _active.remove(taskKey);
      _updates.add(taskKey);
    }
  }

  Map<String, dynamic> resolvedArgs(AgentTask task, AgentTaskStep step) => step
      .args
      .map((k, v) => MapEntry(k, _resolve(v, task, task.steps.indexOf(step))));
  Object? _resolve(Object? value, AgentTask task, int index) {
    if (value is! String || !value.startsWith('@')) return value;
    final match = RegExp(r'^@(\d+)\.([a-zA-Z][a-zA-Z0-9]*)$').firstMatch(value);
    if (match == null) throw ArgumentError('无效的步骤引用：$value');
    final previous = int.parse(match.group(1)!);
    if (previous >= index ||
        task.steps[previous].status != AgentStepStatus.completed) {
      throw StateError('前置步骤尚未完成');
    }
    final result = task.steps[previous].result[match.group(2)];
    if (result == null) throw StateError('前置步骤没有返回所需参数');
    return result;
  }
}
