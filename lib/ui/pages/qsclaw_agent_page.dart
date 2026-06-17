import 'package:flutter/material.dart';

import '../../agent/qsclaw_agent_service.dart';
import '../../database/auth_repository.dart';
import '../../database/models/user_profile.dart';
import '../theme/app_theme.dart';

// ========== QSClaw Agent Page ==========
// App-level agent surface backed by the QSClaw tool registry.

class QsClawAgentPage extends StatefulWidget {
  const QsClawAgentPage({this.authRepository, this.agentService, super.key});

  final AuthRepository? authRepository;
  final QsClawAgentService? agentService;

  @override
  State<QsClawAgentPage> createState() => _QsClawAgentPageState();
}

class _QsClawAgentPageState extends State<QsClawAgentPage> {
  late final AuthRepository _authRepository;
  late final QsClawAgentService _agentService;
  final TextEditingController _commandController = TextEditingController(
    text:
        '\u5e2e\u6211\u6574\u7406\u5173\u4e8e\u9ad8\u7b49\u6570\u5b66\u7684 PDF\uff0c\u5e76\u521b\u5efa\u6570\u5b66\u77e5\u8bc6\u5e93',
  );

  UserProfile? _user;
  QsClawRunResult? _result;
  String? _error;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _agentService = widget.agentService ?? QsClawAgentService();
    _loadUser();
  }

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    await _authRepository.ensureInitialized();
    final user = await _authRepository.getCurrentUserProfile();
    if (!mounted) return;
    setState(() {
      _user = user;
    });
  }

  Future<void> _runAgent() async {
    final user = _user;
    final command = _commandController.text.trim();
    if (user == null || command.isEmpty || _isRunning) {
      return;
    }

    setState(() {
      _isRunning = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await _agentService.runCommand(
        userId: user.id,
        command: command,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QSClaw')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const _HeroPanel(),
            const SizedBox(height: 14),
            _CommandPanel(
              controller: _commandController,
              isRunning: _isRunning,
              onRun: _runAgent,
            ),
            const SizedBox(height: 14),
            const _CapabilityPanel(),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _StatePanel(
                icon: Icons.error_outline_rounded,
                title: 'Run failed',
                body: _error!,
                color: AppColors.error,
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 14),
              _ResultPanel(result: _result!),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.psychology_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'QSClaw App Agent',
                  style: AppTextStyles.h2(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'QSClaw now runs through an app tool registry. It can plan a command, call registered app tools, and report each step. First tools cover library creation, document search, document move, and page navigation.',
            style: AppTextStyles.bodySmall(
              context,
            ).copyWith(color: AppColors.textSecondary, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _CommandPanel extends StatelessWidget {
  const _CommandPanel({
    required this.controller,
    required this.isRunning,
    required this.onRun,
  });

  final TextEditingController controller;
  final bool isRunning;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Command',
      child: Column(
        children: [
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              hintText:
                  'Example: organize my advanced math PDFs and create a math knowledge library',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.input),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isRunning ? null : onRun,
              icon: isRunning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(isRunning ? 'QSClaw is working' : 'Run QSClaw'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityPanel extends StatelessWidget {
  const _CapabilityPanel();

  @override
  Widget build(BuildContext context) {
    const items = [
      _CapabilityItem(
        'Tool registry',
        'Each app action is exposed as a named tool instead of fragile UI tapping.',
      ),
      _CapabilityItem(
        'Current tools',
        'Create library, search imported documents, move documents, and navigate to app pages.',
      ),
      _CapabilityItem(
        'Safety model',
        'Risky future tools such as delete, bulk overwrite, and external folder access should require user confirmation.',
      ),
    ];

    return _Panel(
      title: 'Agent capabilities',
      child: Column(
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${item.title}: ${item.body}',
                        style: AppTextStyles.bodySmall(context).copyWith(
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result});

  final QsClawRunResult result;

  @override
  Widget build(BuildContext context) {
    final noSources = result.status == QsClawRunStatus.waitingForSources;
    final libraryName = result.library?.name ?? 'No library action';
    return _Panel(
      title: noSources ? 'Library ready, waiting for sources' : 'Agent result',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResultRow(label: 'Topic', value: result.draft.topic),
          _ResultRow(label: 'Library', value: libraryName),
          if (result.navigationTarget != null)
            _ResultRow(label: 'Navigation', value: result.navigationTarget!),
          _ResultRow(label: 'Steps', value: '${result.executedSteps.length}'),
          _ResultRow(
            label: 'Matches',
            value: '${result.matchedDocuments.length}',
          ),
          if (result.executedSteps.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...result.executedSteps.map(
              (step) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bolt_rounded),
                title: Text(step.toolName),
                subtitle: Text(step.message),
              ),
            ),
          ],
          if (noSources)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'No matching imported documents were found. Share or import files into the app first, then run QSClaw again.',
              ),
            )
          else if (result.matchedDocuments.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...result.matchedDocuments.map(
              (document) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.picture_as_pdf_rounded),
                title: Text(document.title),
                subtitle: Text('Moved to $libraryName'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.cardSoftList,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.h3(context)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.h3(context)),
                const SizedBox(height: 4),
                Text(body, style: AppTextStyles.bodySmall(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: AppTextStyles.bodySmall(
                context,
              ).copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodySmall(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityItem {
  const _CapabilityItem(this.title, this.body);

  final String title;
  final String body;
}
