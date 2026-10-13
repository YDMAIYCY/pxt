import 'dart:io';
import 'package:flutter/material.dart';
import '../../database/models/source_document_record.dart';
import '../theme/app_theme.dart';

class KnowledgeSearchField extends StatelessWidget {
  const KnowledgeSearchField({
    required this.hint,
    required this.onChanged,
    super.key,
  });
  final String hint;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => TextField(
    onChanged: onChanged,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      prefixIcon: const Icon(
        Icons.search_rounded,
        color: AppColors.textSecondary,
      ),
      filled: true,
      fillColor: Colors.white.withValues(alpha: .95),
      contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class KnowledgeEmptyState extends StatelessWidget {
  const KnowledgeEmptyState({
    required this.title,
    required this.message,
    this.action,
    super.key,
  });
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
    child: Column(
      children: [
        const Icon(
          Icons.auto_stories_outlined,
          size: 46,
          color: AppColors.primaryLight,
        ),
        const SizedBox(height: 14),
        Text(title, style: AppTextStyles.h3(context)),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall(context),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class SourceThumbnail extends StatelessWidget {
  const SourceThumbnail({
    required this.source,
    this.onTap,
    this.width = 70,
    this.height = 90,
    super.key,
  });
  final SourceDocumentRecord source;
  final VoidCallback? onTap;
  final double width, height;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '原始资料 ${source.pageNumber ?? 1}',
    button: true,
    child: Material(
      color: const Color(0xFFE9F1FB),
      borderRadius: BorderRadius.circular(9),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: source.sourceType == 'pdf_document'
              ? const Icon(
                  Icons.picture_as_pdf_outlined,
                  color: AppColors.primary,
                )
              : Image.file(
                  File(source.imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.textTertiary,
                  ),
                ),
        ),
      ),
    ),
  );
}

Future<String?> knowledgeTextPrompt(
  BuildContext context,
  String title, {
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 80,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  // Dispose after the closing route animation releases the TextField.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return result;
}

Future<bool> knowledgeConfirmDelete(
  BuildContext context,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(message),
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
    ) ??
    false;
