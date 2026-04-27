import 'package:flutter/material.dart';

// ========== 新建知识库弹窗 ==========
// 让输入框控制器跟随弹窗自身生命周期释放，避免关闭动画期间提前 dispose。

class CreateKnowledgeLibraryDialog extends StatefulWidget {
  const CreateKnowledgeLibraryDialog({super.key});

  @override
  State<CreateKnowledgeLibraryDialog> createState() =>
      _CreateKnowledgeLibraryDialogState();
}

class _CreateKnowledgeLibraryDialogState
    extends State<CreateKnowledgeLibraryDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建知识库'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '知识库名称',
          hintText: '例如：高数、英语、考研政治',
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }
}
