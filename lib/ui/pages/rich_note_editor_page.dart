import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

class RichNoteEditorPage extends StatefulWidget {
  const RichNoteEditorPage({required this.content, super.key});
  final String content;
  @override
  State<RichNoteEditorPage> createState() => _RichNoteEditorPageState();
}

class _RichNoteEditorPageState extends State<RichNoteEditorPage> {
  late final quill.QuillController _controller;
  @override
  void initState() {
    super.initState();
    dynamic decoded;
    try {
      decoded = jsonDecode(widget.content);
    } catch (_) {}
    final text = decoded is Map
        ? (decoded['content'] ?? decoded['outline_text'] ?? '').toString()
        : widget.content;
    _controller = quill.QuillController(
      document: decoded is Map && decoded['delta'] is List
          ? quill.Document.fromJson(decoded['delta'] as List)
          : quill.Document.fromJson([
              {'insert': '$text\n'},
            ]),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('编辑学习笔记'),
      actions: [
        TextButton(
          onPressed: () {
            final text = _controller.document.toPlainText().trim();
            if (text.isEmpty) return;
            Navigator.pop(
              context,
              jsonEncode({
                'content': text,
                'delta': _controller.document.toDelta().toJson(),
              }),
            );
          },
          child: const Text('保存'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          quill.QuillSimpleToolbar(
            controller: _controller,
            config: const quill.QuillSimpleToolbarConfig(
              showFontFamily: false,
              showFontSize: false,
              showSearchButton: false,
              showLink: false,
            ),
          ),
          Expanded(
            child: quill.QuillEditor.basic(
              controller: _controller,
              config: const quill.QuillEditorConfig(
                padding: EdgeInsets.all(20),
                placeholder: '写下你的理解…',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
