import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'feishu_logo.dart';

Future<String?> showKnowledgeAddSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF7FAFF),
      builder: (context) => const _AddSheet(),
    );

class _AddSheet extends StatefulWidget {
  const _AddSheet();
  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  String? _choice;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('添加知识库', style: AppTextStyles.h2(context)),
          const SizedBox(height: 6),
          const Text(
            '选择一种方式，让知识更容易整理和学习',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          for (final option in const [
            ('feishu', '从飞书导入', '同步云文档，自动构建 AI 知识库', Icons.cloud_outlined),
            (
              'local',
              '从本地文件导入',
              '图片、PDF、Word、PPT 等学习资料',
              Icons.description_outlined,
            ),
            ('manual', '手动创建知识库', '自定义名称、简介和封面', Icons.add),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: _choice == option.$1
                        ? AppColors.primary
                        : const Color(0xFFDDE8FF),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: option.$1 == 'feishu'
                        ? const FeishuLogo(size: 28)
                        : Icon(option.$4, color: AppColors.primary),
                  ),
                  title: Text(
                    option.$2,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    option.$3,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => setState(() => _choice = option.$1),
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _choice == null
                  ? null
                  : () => Navigator.pop(context, _choice),
              child: const Text('继续'),
            ),
          ),
        ],
      ),
    ),
  );
}
