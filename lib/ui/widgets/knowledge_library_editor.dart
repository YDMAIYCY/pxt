import 'package:flutter/material.dart';
import '../../database/knowledge_library_repository.dart';
import '../../database/models/knowledge_library_record.dart';
import '../theme/app_theme.dart';
import 'knowledge_book_cover.dart';

Future<KnowledgeLibraryRecord?> showKnowledgeLibraryEditor(
  BuildContext context, {
  required int userId,
  required KnowledgeLibraryRepository repository,
  KnowledgeLibraryRecord? library,
}) => showModalBottomSheet<KnowledgeLibraryRecord>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: const Color(0xFFF6F9FF),
  builder: (_) =>
      _LibraryEditor(userId: userId, repository: repository, library: library),
);

class _LibraryEditor extends StatefulWidget {
  const _LibraryEditor({
    required this.userId,
    required this.repository,
    this.library,
  });
  final int userId;
  final KnowledgeLibraryRepository repository;
  final KnowledgeLibraryRecord? library;
  @override
  State<_LibraryEditor> createState() => _LibraryEditorState();
}

class _LibraryEditorState extends State<_LibraryEditor> {
  late final _name = TextEditingController(text: widget.library?.name ?? '');
  late final _description = TextEditingController(
    text: widget.library?.description ?? '',
  );
  late String _theme = widget.library?.coverTheme ?? 'math';
  late int _color = widget.library?.coverColor ?? bookColors.first;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final library = widget.library;
      final result = library == null
          ? await widget.repository.createLibrary(
              userId: widget.userId,
              name: _name.text,
              description: _description.text,
              coverTheme: _theme,
              coverColor: _color,
            )
          : await widget.repository.updateLibrary(
              userId: widget.userId,
              libraryId: library.id,
              name: _name.text,
              description: _description.text,
              coverTheme: _theme,
              coverColor: _color,
            );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        4,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.library == null ? '添加知识库' : '编辑知识库',
            style: AppTextStyles.h2(context),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 80,
                child: KnowledgeBookCover(
                  title: _name.text.isEmpty ? '我的知识库' : _name.text,
                  theme: _theme,
                  color: _color,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  children: [
                    TextField(
                      controller: _name,
                      maxLength: 40,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: '知识库名称'),
                    ),
                    TextField(
                      controller: _description,
                      maxLength: 120,
                      decoration: const InputDecoration(labelText: '简介（可选）'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('封面图案'),
          Wrap(
            spacing: 6,
            children: bookThemes.entries
                .map(
                  (e) => ChoiceChip(
                    label: Text(e.value),
                    selected: _theme == e.key,
                    onSelected: (_) => setState(() => _theme = e.key),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          const Text('封面颜色'),
          const SizedBox(height: 8),
          Row(
            children: bookColors
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Semantics(
                      label: '封面颜色 $c',
                      selected: _color == c,
                      child: InkWell(
                        onTap: () => setState(() => _color = c),
                        borderRadius: BorderRadius.circular(24),
                        child: CircleAvatar(
                          radius: 17,
                          backgroundColor: Color(c),
                          child: _color == c
                              ? const Icon(
                                  Icons.check,
                                  size: 19,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? '正在保存…'
                    : widget.library == null
                    ? '创建知识库'
                    : '保存修改',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
