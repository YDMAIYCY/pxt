import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../agent/eclaw_task.dart';
import '../../database/models/ai_chat_records.dart';
import '../../database/models/knowledge_context_source.dart';
import '../theme/app_theme.dart';

const eclawBlue = Color(0xFF2870F5);

// EClaw keeps its own navy ink so the assistant reads as its own surface, while
// every container below still comes from the shared radius/spacing tokens.
const _eclawInk = Color(0xFF132D53);
const _eclawMuted = Color(0xFF69809D);

class EClawAvatar extends StatelessWidget {
  const EClawAvatar({this.size = 34, super.key});
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size / 3),
    child: Image.asset(
      'assets/images/eclaw_robot_avatar.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          Icon(Icons.smart_toy_rounded, size: size, color: eclawBlue),
    ),
  );
}

class EClawWelcome extends StatelessWidget {
  const EClawWelcome({required this.onPrompt, super.key});
  final ValueChanged<String> onPrompt;

  /// name / one-line payoff / icon / accent / the prompt actually sent.
  static const _capabilities = <(String, String, IconData, Color, String)>[
    ('整理资料', '把 PDF 归档到知识库', Icons.folder_copy_outlined, AppColors.accentSky,
     '帮我整理关于【主题】的 PDF 到【名称】知识库'),
    ('生成练习', '按知识库出题', Icons.edit_note_rounded, AppColors.accentMint,
     '帮我根据当前知识库生成 10 道练习题'),
    ('分析错题', '看掌握与薄弱点', Icons.bar_chart_rounded, AppColors.accentFlame,
     '帮我分析当前范围的错题和知识掌握情况'),
    ('学习规划', '安排一段复习', Icons.calendar_month_outlined, AppColors.accentViolet,
     '帮我根据当前知识库安排一小时复习'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontal = 20.0;
        const gap = 12.0;
        final cardWidth =
            (constraints.maxWidth - horizontal * 2 - gap) / 2;
        // Centre the block when there is room, still scroll on short screens.
        final minHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight - 56
            : 0.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(horizontal, 28, horizontal, 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _badge()),
                const SizedBox(height: 24),
                Text(
                  '有什么可以帮你？',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.h1(context).copyWith(color: _eclawInk),
                ),
                const SizedBox(height: 10),
                Text(
                  '可以直接提问，也可以选一件事让我开始。',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall(
                    context,
                  ).copyWith(color: _eclawMuted, height: 1.6),
                ),
                const SizedBox(height: 26),
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final item in _capabilities)
                      SizedBox(
                        width: cardWidth,
                        child: _CapabilityCard(
                          title: item.$1,
                          hint: item.$2,
                          icon: item.$3,
                          accent: item.$4,
                          onTap: () => onPrompt(item.$5),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The brand anchor for an otherwise empty chat: the mascot sitting in a soft
  /// blue halo, which gives the page a focal point instead of a bare image.
  Widget _badge() => Container(
    width: 132,
    height: 132,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          eclawBlue.withValues(alpha: 0.18),
          AppColors.accentViolet.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.6),
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: eclawBlue.withValues(alpha: 0.16),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: const EClawAvatar(size: 88),
  );
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({
    required this.title,
    required this.hint,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String hint;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.tile),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.tintOf(accent, 0.14),
                  borderRadius: BorderRadius.circular(AppRadii.iconBox),
                ),
                child: Icon(icon, size: 19, color: accent),
              ),
              const SizedBox(height: 10),
              Text(title, style: AppTextStyles.title(context)),
              const SizedBox(height: 2),
              Text(
                hint,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EClawRichText extends StatelessWidget {
  const EClawRichText(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    // Render TeX locally. No WebView, network images or document HTML execution.
    final math = RegExp(
      r'\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)|(?<!\\)\$([^\n$]+?)\$',
    );
    final children = <Widget>[];
    var start = 0;
    void markdown(String data) {
      if (data.trim().isEmpty) return;
      children.add(
        MarkdownBody(
          data: data,
          selectable: true,
          imageBuilder: (_, _, _) => const Text('[图片]'),
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(
              fontSize: 14,
              height: 1.65,
              color: Color(0xFF263D59),
            ),
            code: const TextStyle(fontSize: 13, color: Color(0xFF205BBA)),
          ),
        ),
      );
    }

    for (final match in math.allMatches(text)) {
      markdown(text.substring(start, match.start));
      final tex =
          match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4)!;
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              tex,
              textStyle: const TextStyle(fontSize: 16),
              onErrorFallback: (_) => SelectableText(tex),
            ),
          ),
        ),
      );
      start = match.end;
    }
    markdown(text.substring(start));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class EClawMessageBubble extends StatelessWidget {
  const EClawMessageBubble({
    required this.message,
    required this.citations,
    required this.onSource,
    this.taskCard,
    super.key,
  });
  final AiChatMessageRecord message;
  final List<KnowledgeContextSource> citations;
  final ValueChanged<KnowledgeContextSource> onSource;
  final Widget? taskCard;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: message.isUser
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        if (!message.isUser) ...[const EClawAvatar(), const SizedBox(width: 8)],
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.sizeOf(context).width *
                  (message.isUser ? .80 : .84),
            ),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: message.isUser ? eclawBlue : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: message.isUser
                  ? null
                  : Border.all(color: const Color(0xFFE6EDF8)),
            ),
            child: message.isUser
                ? Text(
                    message.content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (taskCard != null)
                        taskCard!
                      else
                        EClawRichText(
                          message.content.replaceAll('QSClaw', 'EClaw'),
                        ),
                      if (citations.isNotEmpty) ...[
                        const Divider(height: 24),
                        const Text(
                          '参考资料',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7C8DA5),
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (var i = 0; i < citations.length; i++)
                          Material(
                            color: const Color(0xFFF1F6FF),
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              onTap: () => onSource(citations[i]),
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.description_outlined,
                                      size: 19,
                                      color: eclawBlue,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '[${i + 1}] ${citations[i].documentTitle}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            '${citations[i].location} · ${citations[i].sourceLabel}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF69809D),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    ),
  );
}

class EClawTaskCard extends StatelessWidget {
  const EClawTaskCard({
    required this.task,
    required this.busy,
    required this.preview,
    required this.onConfirm,
    required this.onCancel,
    required this.onRetry,
    required this.onOpen,
    required this.onUndo,
    super.key,
  });
  final AgentTask task;
  final bool busy;
  final String preview;
  final VoidCallback onConfirm, onCancel, onRetry;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final ValueChanged<String> onUndo;
  @override
  Widget build(BuildContext context) {
    final completed = task.steps
        .where((s) => s.status == AgentStepStatus.completed)
        .length;
    final current = task.steps
        .where(
          (s) =>
              s.status != AgentStepStatus.completed &&
              s.status != AgentStepStatus.cancelled,
        )
        .firstOrNull;
    final title = switch (task.status) {
      'waiting_confirmation' => '请确认操作',
      'completed' => '任务已完成',
      'failed' => '任务未完成',
      'cancelled' => '已取消',
      _ => '正在处理',
    };
    final outcomes = task.steps
        .where((s) => s.status == AgentStepStatus.completed)
        .toList();
    final result = outcomes
        .where((s) => s.result['destination'] != null)
        .lastOrNull
        ?.result;
    final move = outcomes.where((s) => s.result['undoKey'] != null).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              task.status == 'completed'
                  ? Icons.check_circle_outline
                  : Icons.auto_awesome_outlined,
              size: 18,
              color: eclawBlue,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '$completed/${task.steps.length}',
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: completed / task.steps.length,
          minHeight: 3,
          color: eclawBlue,
          backgroundColor: const Color(0xFFEDF3FE),
        ),
        const SizedBox(height: 10),
        if (current != null)
          Text(current.label, style: const TextStyle(fontSize: 13)),
        if (task.waitingStep != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              preview,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        if (current?.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              current!.error!,
              style: const TextStyle(fontSize: 13, color: Color(0xFFB34F42)),
            ),
          ),
        for (final step in outcomes.where(
          (s) =>
              task.steps.length == 1 ||
              !const {
                'search_documents',
                'get_learning_state',
                'create_knowledge_library',
                'prepare_learning_plan',
              }.contains(s.tool),
        ))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: EClawRichText('${step.result['message'] ?? step.label}'),
          ),
        for (final step in outcomes.where(
          (s) => s.tool == 'search_documents' && task.steps.length == 1,
        ))
          for (final document in (step.result['documents'] as List? ?? []).take(
            8,
          ))
            TextButton.icon(
              onPressed: () => onOpen({
                'destination': 'source',
                ...Map<String, dynamic>.from(document as Map),
              }),
              icon: const Icon(Icons.description_outlined, size: 16),
              label: Text(
                '${document['title']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        if (task.cancelRequested && task.status == 'running')
          const Text('当前步骤结束后停止，已经保存的结果会保留。', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (task.waitingStep != null)
              FilledButton(
                onPressed: busy ? null : onConfirm,
                style: FilledButton.styleFrom(backgroundColor: eclawBlue),
                child: Text(
                  task.waitingStep!.tool.contains('library') ? '确认整理' : '确认执行',
                ),
              ),
            if (!task.isTerminal)
              TextButton(
                onPressed: task.cancelRequested ? null : onCancel,
                child: const Text('取消'),
              ),
            if (task.status == 'failed')
              OutlinedButton(
                onPressed: busy ? null : onRetry,
                child: const Text('重试未完成步骤'),
              ),
            if (result != null)
              OutlinedButton(
                onPressed: () => onOpen(result),
                child: Text(_label('${result['destination']}')),
              ),
            if (move != null && task.status != 'running')
              TextButton(
                onPressed: busy
                    ? null
                    : () => onUndo(move.result['undoKey'] as String),
                child: const Text('撤销整理'),
              ),
          ],
        ),
      ],
    );
  }

  String _label(String target) => switch (target) {
    'practice' => '去练习',
    'graph' => '打开图谱',
    'focus' => '查看学习任务',
    'tasks' => '查看任务中心',
    'concept' => '查看知识点',
    'source' => '查看资料',
    'wrong' => '查看错题',
    'interview' => '准备面试',
    'interview_history' => '查看面试报告',
    _ => '查看知识库',
  };
}
