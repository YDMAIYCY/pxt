import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../../database/auth_repository.dart';
import '../../database/models/ocr_text_record.dart';
import '../../database/models/source_document_record.dart';
import '../../database/ocr_text_repository.dart';
import '../../database/source_document_repository.dart';
import '../../pipeline/ocr_pipeline_service.dart';

class OcrResultPage extends StatefulWidget {
  const OcrResultPage({
    required this.documentId,
    this.authRepository,
    this.sourceDocumentRepository,
    this.ocrTextRepository,
    this.ocrPipelineService,
    super.key,
  });

  final int documentId;
  final AuthRepository? authRepository;
  final SourceDocumentRepository? sourceDocumentRepository;
  final OcrTextRepository? ocrTextRepository;
  final OcrPipelineService? ocrPipelineService;

  @override
  State<OcrResultPage> createState() => _OcrResultPageState();
}

class _OcrResultPageState extends State<OcrResultPage> {
  late final AuthRepository _authRepository;
  late final SourceDocumentRepository _sourceDocumentRepository;
  late final OcrTextRepository _ocrTextRepository;
  late final OcrPipelineService _ocrPipelineService;

  late Future<_OcrPageData> _pageFuture;

  final TextEditingController _rawTextController = TextEditingController();
  final TextEditingController _cleanTextController = TextEditingController();

  SourceDocumentRecord? _document;
  bool _isRecognizing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _sourceDocumentRepository =
        widget.sourceDocumentRepository ?? SourceDocumentRepository();
    _ocrTextRepository = widget.ocrTextRepository ?? OcrTextRepository();
    _ocrPipelineService = widget.ocrPipelineService ?? OcrPipelineService();
    _pageFuture = _loadPageData();
  }

  @override
  void dispose() {
    _rawTextController.dispose();
    _cleanTextController.dispose();
    super.dispose();
  }

  Future<_OcrPageData> _loadPageData() async {
    await _authRepository.ensureInitialized();
    final currentUser = await _authRepository.getCurrentUserProfile();
    if (currentUser == null) {
      throw StateError('登录状态已失效，请重新登录');
    }

    final document = await _sourceDocumentRepository.getSourceDocumentById(
      userId: currentUser.id,
      documentId: widget.documentId,
    );
    if (document == null) {
      throw StateError('资料不存在或无权访问');
    }

    final ocrRecord = await _ocrTextRepository.getByDocumentId(
      widget.documentId,
    );

    _document = document;
    _rawTextController.text = ocrRecord?.rawText ?? '';
    _cleanTextController.text = ocrRecord?.cleanText ?? '';

    return _OcrPageData(document: document, ocrRecord: ocrRecord);
  }

  Future<void> _reloadPageData() async {
    final future = _loadPageData();
    setState(() {
      _pageFuture = future;
    });
    await future;
  }

  Future<void> _runOcr() async {
    if (_isRecognizing) {
      return;
    }

    final document = _document;
    if (document == null) {
      _showMessage('当前资料未加载完成，请稍后再试');
      return;
    }

    setState(() {
      _isRecognizing = true;
    });

    final result = await _ocrPipelineService.runForDocument(document: document);

    if (!mounted) {
      return;
    }

    _showMessage(result.message);

    try {
      await _reloadPageData();
    } catch (_) {
      if (mounted) {
        _showMessage('OCR 执行完成，但页面刷新失败，请手动下拉重试');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRecognizing = false;
        });
      }
    }
  }

  Future<void> _saveEditedText() async {
    if (_isSaving) {
      return;
    }

    final document = _document;
    if (document == null) {
      _showMessage('当前资料未加载完成，请稍后再试');
      return;
    }

    final rawText = _rawTextController.text.trim();
    final cleanText = _cleanTextController.text.trim();

    if (rawText.isEmpty && cleanText.isEmpty) {
      _showMessage('识别文本不能为空，请先识别或手动输入');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _ocrTextRepository.upsertOcrText(
        documentId: document.id,
        rawText: rawText.isEmpty ? cleanText : rawText,
        cleanText: cleanText.isEmpty ? rawText : cleanText,
      );

      if (!mounted) {
        return;
      }

      _showMessage('OCR 文本已保存到数据库');
      await _reloadPageData();
    } catch (error) {
      if (mounted) {
        _showMessage('保存失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('OCR 结果'),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
      ),
      body: FutureBuilder<_OcrPageData>(
        future: _pageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _OcrStatePanel(
              icon: Icons.error_outline_rounded,
              title: 'OCR 页面加载失败',
              description: '请稍后重试，或返回资料详情重新进入。',
              actionLabel: '重新加载',
              onPressed: _reloadPageData,
            );
          }

          final data = snapshot.data!;
          final style = _ocrStyleOf(data.document.ocrStatus);
          final isBusy = _isRecognizing || _isSaving;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: style.background,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            data.document.ocrStatusLabel,
                            style: TextStyle(
                              color: style.foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (_isRecognizing)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      data.document.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data.document.ocrErrorMessage?.trim().isNotEmpty == true
                          ? '失败原因：${data.document.ocrErrorMessage}'
                          : '支持识别后重试；你也可以直接手动编辑文本并保存。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: isBusy ? null : _runOcr,
                            icon: Icon(
                              data.document.ocrStatus ==
                                      SourceDocumentOcrStatus.success
                                  ? Icons.refresh_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            label: Text(
                              data.document.ocrStatus ==
                                      SourceDocumentOcrStatus.success
                                  ? '重试 OCR'
                                  : '开始 OCR',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isBusy ? null : _saveEditedText,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded),
                            label: const Text('保存修改'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _TextEditorCard(
                title: '原始识别文本',
                hintText: '点击“开始 OCR”后会展示原始文本；你也可手动输入。',
                controller: _rawTextController,
              ),
              const SizedBox(height: 14),
              _TextEditorCard(
                title: '清洗后文本',
                hintText: '建议保留结构清晰的可读版本，作为后续 AI 生成输入。',
                controller: _cleanTextController,
              ),
              if (data.ocrRecord == null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    '当前尚无 OCR 入库记录。完成识别或保存后，这里会进入数据库并同步首页状态。',
                    style: TextStyle(
                      color: Color(0xFF854D0E),
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TextEditorCard extends StatelessWidget {
  const _TextEditorCard({
    required this.title,
    required this.hintText,
    required this.controller,
  });

  final String title;
  final String hintText;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            keyboardType: TextInputType.multiline,
            minLines: 8,
            maxLines: null,
            decoration: InputDecoration(
              hintText: hintText,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              filled: true,
              fillColor: AppColors.background,
            ),
          ),
        ],
      ),
    );
  }
}

class _OcrStatePanel extends StatelessWidget {
  const _OcrStatePanel({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => onPressed(),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _OcrPageData {
  const _OcrPageData({required this.document, required this.ocrRecord});

  final SourceDocumentRecord document;
  final OcrTextRecord? ocrRecord;
}

class _OcrStatusStyle {
  const _OcrStatusStyle({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

_OcrStatusStyle _ocrStyleOf(String status) {
  switch (status) {
    case SourceDocumentOcrStatus.processing:
      return const _OcrStatusStyle(
        background: AppColors.primarySoft,
        foreground: AppColors.primary,
      );
    case SourceDocumentOcrStatus.success:
      return const _OcrStatusStyle(
        background: Color(0xFFDCFCE7),
        foreground: Color(0xFF166534),
      );
    case SourceDocumentOcrStatus.failed:
      return const _OcrStatusStyle(
        background: Color(0xFFFEF2F2),
        foreground: Color(0xFFB91C1C),
      );
    case SourceDocumentOcrStatus.pending:
    default:
      return const _OcrStatusStyle(
        background: Color(0xFFFFEDD5),
        foreground: Color(0xFF9A3412),
      );
  }
}
