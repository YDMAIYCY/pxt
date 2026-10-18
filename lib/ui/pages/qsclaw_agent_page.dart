import 'package:flutter/material.dart';

import '../../agent/qsclaw_agent_service.dart';
import '../../database/auth_repository.dart';
import 'ai_chat_page.dart';

// ========== QSClaw Agent Page ==========
// Keeps the old route name while QSClaw and AI Chat share one conversation UI.
class QsClawAgentPage extends StatelessWidget {
  const QsClawAgentPage({this.authRepository, this.agentService, super.key});

  final AuthRepository? authRepository;
  final QsClawAgentService? agentService;

  @override
  Widget build(BuildContext context) {
    return AiChatPage(
      authRepository: authRepository,
      qsClawAgentService: agentService,
    );
  }
}
