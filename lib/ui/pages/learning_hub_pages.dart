import 'package:flutter/material.dart';

import '../../database/auth_repository.dart';
import '../../database/source_document_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/source_document_record.dart';
import '../../generator/learning_resource_service.dart';
import '../theme/app_theme.dart';
import 'ai_chat_page.dart';
import 'ai_interview_page.dart';
import 'practice_review_page.dart';
import 'qsclaw_agent_page.dart';
import 'tabs/focus_tab_page.dart';
import 'tabs/tasks_tab_page.dart';
import 'learning_workspace_page.dart';
import 'library_practice_page.dart';

Future<void> openLearningPage(
  BuildContext context,
  Widget page, {
  VoidCallback? onChanged,
}) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  onChanged?.call();
}

class PracticeTabPage extends StatelessWidget {
  const PracticeTabPage({this.onDataChanged, super.key});
  final VoidCallback? onDataChanged;
  @override
  Widget build(BuildContext context) =>
      const LibraryPracticePage(embedded: true);
}

class CompanionTabPage extends StatelessWidget {
  const CompanionTabPage({super.key});
  @override
  Widget build(BuildContext context) => _Hub(
    title: 'AI 学伴',
    subtitle: '答疑、解释与反向讲解，围绕自己的资料学习。',
    items: [
      _HubItem(
        'AI 答疑',
        '结合本地资料回答问题',
        Icons.chat_bubble_outline_rounded,
        () => openLearningPage(context, const AiChatPage()),
      ),
      _HubItem(
        '深度讲解',
        '选择知识包，理解原理和应用',
        Icons.auto_awesome_rounded,
        () => openLearningPage(
          context,
          const _PackPicker(resourceType: 'deep_explanation'),
        ),
      ),
      _HubItem(
        '费曼学习',
        '用自己的话讲解，AI 检查遗漏',
        Icons.school_rounded,
        () => openLearningPage(context, const _PackPicker(feynman: true)),
      ),
      _HubItem(
        'QSClaw',
        '使用已有的资料整理和学习工具',
        Icons.smart_toy_rounded,
        () => openLearningPage(context, const QsClawAgentPage()),
      ),
    ],
  );
}

class FocusSessionPage extends StatelessWidget {
  const FocusSessionPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('专注与学习计划')),
    body: const FocusTabPage(),
  );
}

class LearningPlansPage extends StatelessWidget {
  const LearningPlansPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('计划与待办')),
    body: const TasksTabPage(),
  );
}

class _PackPicker extends StatefulWidget {
  const _PackPicker({
    this.resourceType = 'application_questions',
    this.feynman = false,
  });
  final String resourceType;
  final bool feynman;
  @override
  State<_PackPicker> createState() => _PackPickerState();
}

class _PackPickerState extends State<_PackPicker> {
  late final _future = _load();
  Future<List<Widget>> _load() async {
    final user = await AuthRepository().getCurrentUserProfile();
    if (user == null) throw StateError('请先登录');
    final docs = await SourceDocumentRepository().fetchAllSourceDocuments(
      userId: user.id,
      limit: 300,
    );
    return docs
        .map(
          (d) => ListTile(
            leading: const Icon(Icons.auto_stories_rounded),
            title: Text(d.title),
            subtitle: Text(d.ocrStatusLabel),
            onTap: () => openLearningPage(
              context,
              widget.feynman
                  ? AiInterviewPage(documentId: d.id, feynman: true)
                  : widget.resourceType == 'application_questions'
                  ? _ExamSetupPage(document: d)
                  : LearningWorkspacePage(
                      documentId: d.id,
                      initialType: widget.resourceType,
                    ),
            ),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('选择知识包')),
    body: FutureBuilder<List<Widget>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('先拍照或导入一份资料'));
        }
        return ListView(children: snapshot.data!);
      },
    ),
  );
}

class _ExamSetupPage extends StatefulWidget {
  const _ExamSetupPage({required this.document});
  final SourceDocumentRecord document;
  @override
  State<_ExamSetupPage> createState() => _ExamSetupPageState();
}

class _ExamSetupPageState extends State<_ExamSetupPage> {
  int _count = 5;
  String _difficulty = '基础理解';
  bool _busy = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('智能组卷')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(widget.document.title, style: AppTextStyles.h2(context)),
        const SizedBox(height: 20),
        DropdownButtonFormField<int>(
          initialValue: _count,
          decoration: const InputDecoration(labelText: '题量'),
          items: [5, 10, 20]
              .map((c) => DropdownMenuItem(value: c, child: Text('$c 道')))
              .toList(),
          onChanged: _busy ? null : (value) => setState(() => _count = value!),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _difficulty,
          decoration: const InputDecoration(labelText: '难度'),
          items: [
            '基础理解',
            '综合应用',
            '深入思考',
          ].map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
          onChanged: _busy
              ? null
              : (value) => setState(() => _difficulty = value!),
        ),
        const SizedBox(height: 20),
        if (_busy) const LinearProgressIndicator(),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    final config = await LlmConfigRepository().getByUserId(
                      widget.document.userId,
                    );
                    if (config?.isConfigured != true) {
                      throw StateError('请先在“我的”配置 AI 模型');
                    }
                    final ids = await LearningResourceService().createExam(
                      widget.document,
                      config!,
                      count: _count,
                      difficulty: _difficulty,
                    );
                    if (context.mounted) {
                      await openLearningPage(
                        context,
                        PracticeReviewPage(
                          documentId: widget.document.id,
                          questionIds: ids,
                        ),
                      );
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$error')));
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: const Text('生成并开始练习'),
        ),
        TextButton(
          onPressed: () => openLearningPage(
            context,
            LearningWorkspacePage(documentId: widget.document.id),
          ),
          child: const Text('先查看或解析资料'),
        ),
      ],
    ),
  );
}

class _Hub extends StatelessWidget {
  const _Hub({
    required this.title,
    required this.subtitle,
    required this.items,
  });
  final String title;
  final String subtitle;
  final List<_HubItem> items;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 108),
    children: [
      Text(title, style: AppTextStyles.h1(context)),
      const SizedBox(height: 8),
      Text(subtitle, style: AppTextStyles.bodySmall(context)),
      const SizedBox(height: 20),
      ...items.map(
        (item) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Icon(item.icon, color: AppColors.primary),
            title: Text(item.title),
            subtitle: Text(item.subtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: item.onTap,
          ),
        ),
      ),
    ],
  );
}

class _HubItem {
  const _HubItem(this.title, this.subtitle, this.icon, this.onTap);
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}
