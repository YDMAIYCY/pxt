import 'dart:io';
import 'package:flutter/material.dart';
import '../../database/app_database.dart';
import '../../database/auth_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/import_record.dart';
import '../../database/models/source_document_record.dart';
import '../../database/ocr_text_repository.dart';
import '../../database/source_document_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/knowledge_components.dart';
import 'ocr_result_page.dart';

class RecordSourcePage extends StatefulWidget {
  const RecordSourcePage({
    required this.record,
    this.initialDocumentId,
    this.database,
    super.key,
  });
  final ImportRecord record;
  final int? initialDocumentId;
  final AppDatabase? database;
  @override
  State<RecordSourcePage> createState() => _RecordSourcePageState();
}

class _RecordSourcePageState extends State<RecordSourcePage> {
  late final List<SourceDocumentRecord> _pages = widget.record.pages.isEmpty
      ? widget.record.sources
      : widget.record.pages;
  late int _index =
      _pages.indexWhere((p) => p.id == widget.initialDocumentId) < 0
      ? 0
      : _pages.indexWhere((p) => p.id == widget.initialDocumentId);
  Future<void> _ocr() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OcrResultPage(
          documentId: _pages[_index].id,
          authRepository: AuthRepository(database: widget.database),
          sourceDocumentRepository: SourceDocumentRepository(
            database: widget.database,
          ),
          ocrTextRepository: OcrTextRepository(database: widget.database),
          llmConfigRepository: LlmConfigRepository(database: widget.database),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final source = _pages[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('原始资料 · ${_index + 1}/${_pages.length}'),
        actions: [
          IconButton(
            tooltip: '识别、校对 OCR',
            onPressed: _ocr,
            icon: const Icon(Icons.edit_note),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Text(widget.record.title, style: AppTextStyles.h3(context)),
          const SizedBox(height: 10),
          SizedBox(
            height: 330,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColoredBox(
                color: const Color(0xFFECF3FF),
                child: InteractiveViewer(
                  minScale: .5,
                  maxScale: 5,
                  child: Image.file(
                    File(
                      source.sourceType == 'pdf_page' ||
                              source.sourceType == 'pdf_document'
                          ? source.imagePath
                          : source.originalFilePath ?? source.imagePath,
                    ),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Text('原文件不可用，请检查资料文件是否仍在本机。')),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _pages.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: i == _index ? AppColors.primary : Colors.transparent,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: SourceThumbnail(
                  source: _pages[i],
                  width: 56,
                  height: 78,
                  onTap: () => setState(() => _index = i),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  '第 ${_index + 1} 页 OCR 文本',
                  style: AppTextStyles.h3(context),
                ),
              ),
              TextButton(onPressed: _ocr, child: const Text('识别 / 校对')),
            ],
          ),
          FutureBuilder(
            future: OcrTextRepository(
              database: widget.database,
            ).getByDocumentId(source.id),
            builder: (context, snapshot) => SelectableText(
              snapshot.hasError
                  ? '读取失败：${snapshot.error}'
                  : snapshot.connectionState != ConnectionState.done
                  ? '正在读取…'
                  : snapshot.data?.effectiveText ?? '这页尚未识别，点击“识别 / 校对”开始。',
              style: AppTextStyles.body(context),
            ),
          ),
        ],
      ),
    );
  }
}
