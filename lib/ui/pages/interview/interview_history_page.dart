import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../database/app_database.dart';
import '../../../database/interview_repository.dart';
import '../../../interview/interview_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/knowledge_components.dart';
import 'interview_chat_page.dart';
import 'interview_result_page.dart';

// ========== 面试历史 ==========
// 历史严格按知识库/记录范围过滤，不同知识库的成绩不会混在一起。

class InterviewHistorySheet extends StatefulWidget {
  const InterviewHistorySheet({
    required this.userId,
    required this.libraryId,
    this.recordId,
    this.database,
    this.preparationRoute,
    super.key,
  });

  final int userId;
  final int? libraryId;
  final int? recordId;
  final AppDatabase? database;
  final Route<dynamic>? preparationRoute;

  @override
  State<InterviewHistorySheet> createState() => _InterviewHistoryPageState();
}

class _InterviewHistoryPageState extends State<InterviewHistorySheet> {
  late Future<List<InterviewSession>> _future;

  InterviewRepository get _repo =>
      InterviewRepository(database: widget.database);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<InterviewSession>> _load() => _repo.listSessions(
    widget.userId,
    libraryId: widget.libraryId,
    recordId: widget.recordId,
  );

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _open(InterviewSession session) async {
    final finished =
        session.status == 'completed' || session.status == 'cancelled';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => finished
            ? InterviewResultPage(
                userId: widget.userId,
                sessionId: session.id,
                repository: _repo,
                database: widget.database,
                preparationRoute: widget.preparationRoute,
              )
            : InterviewChatPage(
                userId: widget.userId,
                sessionId: session.id,
                repository: _repo,
                database: widget.database,
                preparationRoute: widget.preparationRoute,
              ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _delete(InterviewSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这次面试'),
        content: const Text(
          '将删除该会话的问题、回答、录音与评分；'
          '原学习资料和其他面试不会受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteSession(widget.userId, session.id);
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: FutureBuilder<List<InterviewSession>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return KnowledgeEmptyState(
              title: '读取失败',
              message: '暂时无法读取面试记录',
              action: TextButton(onPressed: _refresh, child: const Text('重试')),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snapshot.data!;
          if (sessions.isEmpty) {
            return const KnowledgeEmptyState(
              title: '还没有面试记录',
              message: '完成一次 AI 面试后，成绩会保存在这里。',
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    title: Text(
                      session.scopeName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _subtitle(session),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _scoreLabel(session),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _statusLabel(session),
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    onTap: () => _open(session),
                    onLongPress: () => _delete(session),
                  ),
                );
              },
            ),
          );
        },
      ),
    ),
  );

  String _subtitle(InterviewSession session) {
    final mode = switch (session.mode) {
      'deep' => '深度面试',
      'quick' => '快速复习',
      _ => '基础问答',
    };
    final difficulty = switch (session.difficulty) {
      'easy' => '简单',
      'hard' => '困难',
      _ => '中等',
    };
    final started = session.startedAt.toLocal();
    final stamp =
        '${started.year}-'
        '${started.month.toString().padLeft(2, '0')}-'
        '${started.day.toString().padLeft(2, '0')} '
        '${started.hour.toString().padLeft(2, '0')}:'
        '${started.minute.toString().padLeft(2, '0')}';
    return '$mode · $difficulty · $stamp · '
        '已完成 ${session.completedQuestionCount}/${session.targetQuestionCount} 题';
  }

  String _statusLabel(InterviewSession session) => switch (session.status) {
    'completed' => '已完成',
    'cancelled' => '提前结束',
    'in_progress' => '未完成 · 点击继续',
    _ => '准备中',
  };

  String _scoreLabel(InterviewSession session) {
    final raw = session.reportJson;
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['overall_score'] != null) {
          return '${decoded['overall_score']}';
        }
      } catch (_) {
        // 报告损坏时显示占位，不臆造分数。
      }
    }
    return '—';
  }
}
