import 'package:flutter/material.dart';
import '../../agent/eclaw_context.dart';
import '../../database/app_database.dart';
import '../pages/ai_chat_page.dart';

class AskEClawButton extends StatelessWidget {
  const AskEClawButton({required this.scope, this.database, super.key});
  final EClawContext scope;
  final AppDatabase? database;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '问 EClaw',
    icon: const Icon(Icons.smart_toy_outlined),
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatPage(database: database, initialContext: scope),
      ),
    ),
  );
}
