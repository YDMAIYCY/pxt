import 'eclaw_context.dart';

enum AgentStepStatus {
  pending,
  running,
  waitingConfirmation,
  completed,
  failed,
  cancelled,
}

class AgentTaskStep {
  AgentTaskStep({
    required this.tool,
    required this.label,
    this.args = const {},
    this.status = AgentStepStatus.pending,
    this.result = const {},
    this.error,
    this.confirmed = false,
  });
  final String tool, label;
  final Map<String, dynamic> args;
  AgentStepStatus status;
  Map<String, dynamic> result;
  String? error;
  bool confirmed;
  Map<String, Object?> toJson() => {
    'tool': tool,
    'label': label,
    'args': args,
    'status': status == AgentStepStatus.waitingConfirmation
        ? 'waiting_confirmation'
        : status.name,
    'result': result,
    'error': error,
    'confirmed': confirmed,
  };
  factory AgentTaskStep.fromJson(Map<String, dynamic> json) => AgentTaskStep(
    tool: json['tool'] as String,
    label: json['label'] as String,
    args: Map<String, dynamic>.from(json['args'] as Map),
    status: json['status'] == 'waiting_confirmation'
        ? AgentStepStatus.waitingConfirmation
        : AgentStepStatus.values.byName(json['status'] as String),
    result: Map<String, dynamic>.from(json['result'] as Map),
    error: json['error'] as String?,
    confirmed: json['confirmed'] == true,
  );
}

class AgentTask {
  AgentTask({
    required this.id,
    required this.userId,
    required this.sessionId,
    required this.command,
    required this.context,
    required this.steps,
    this.status = 'pending',
    this.cancelRequested = false,
  });
  final int id, userId, sessionId;
  final String command;
  final EClawContext context;
  final List<AgentTaskStep> steps;
  String status;
  bool cancelRequested;
  bool get isTerminal => status == 'completed' || status == 'cancelled';
  AgentTaskStep? get waitingStep => steps
      .where((s) => s.status == AgentStepStatus.waitingConfirmation)
      .firstOrNull;
}
