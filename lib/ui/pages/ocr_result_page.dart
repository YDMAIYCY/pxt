import 'package:flutter/material.dart';

import '../../database/auth_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/ocr_text_record.dart';
import '../../database/models/source_document_record.dart';
import '../../database/ocr_text_repository.dart';
import '../../database/source_document_repository.dart';
import '../../llm/minimax_client.dart';
import '../../ocr/ocr_text_quality_evaluator.dart';
import '../../ocr/ocr_text_repair_service.dart';
import '../../pipeline/ocr_pipeline_service.dart';
import '../theme/app_theme.dart';
import 'image_crop_selection_page.dart';

class OcrResultPage extends StatefulWidget {
  const OcrResultPage({
    required this.documentId,
    this.authRepository,
    this.sourceDocumentRepository,
    this.ocrTextRepository,
    this.llmConfigRepository,
    this.ocrPipelineService,
    this.ocrTextRepairService,
    super.key,
  });

  final int documentId;
  final AuthRepository? authRepository;
  final SourceDocumentRepository? sourceDocumentRepository;
  final OcrTextRepository? ocrTextRepository;
  final LlmConfigRepository? llmConfigRepository;
  final OcrPipelineService? ocrPipelineService;
  final OcrTextRepairService? ocrTextRepairService;

  @override
  State<OcrResultPage> createState() => _OcrResultPageState();
}

class _OcrResultPageState extends State<OcrResultPage> {
  late final AuthRepository _authRepository;
  late final SourceDocumentRepository _sourceDocumentRepository;
  late final OcrTextRepository _ocrTextRepository;
  late final LlmConfigRepository _llmConfigRepository;
  late final OcrPipelineService _ocrPipelineService;

  late Future<_OcrPageData> _pageFuture;

  final TextEditingController _rawTextController = TextEditingController();
  final TextEditingController _cleanTextController = TextEditingController();
  final TextEditingController _finalTextController = TextEditingController();

  SourceDocumentRecord? _document;
  bool _isRecognizing = false;
  bool _isSaving = false;
  bool _isRepairing = false;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _sourceDocumentRepository =
        widget.sourceDocumentRepository ?? SourceDocumentRepository();
    _ocrTextRepository = widget.ocrTextRepository ?? OcrTextRepository();
    _llmConfigRepository = widget.llmConfigRepository ?? LlmConfigRepository();
    _ocrPipelineService = widget.ocrPipelineService ?? OcrPipelineService();
    _pageFuture = _loadPageData();
  }

  @override
  void dispose() {
    _rawTextController.dispose();
    _cleanTextController.dispose();
    _finalTextController.dispose();
    super.dispose();
  }

  Future<_OcrPageData> _loadPageData() async {
    await _authRepository.ensureInitialized();
    final currentUser = await _authRepository.getCurrentUserProfile();
    if (currentUser == null) {
      throw StateError('?????????????');
    }

    final document = await _sourceDocumentRepository.getSourceDocumentById(
      userId: currentUser.id,
      documentId: widget.documentId,
    );
    if (document == null) {
      throw StateError('??????????');
    }

    final ocrRecord = await _ocrTextRepository.getByDocumentId(
      widget.documentId,
    );

    _document = document;
    _rawTextController.text = ocrRecord?.rawText ?? '';
    _cleanTextController.text = ocrRecord?.cleanText ?? '';
    _finalTextController.text = ocrRecord?.finalText ?? '';

    return _OcrPageData(document: document, ocrRecord: ocrRecord);
  }

  Future<void> _reloadPageData() async {
    final future = _loadPageData();
    setState(() {
      _pageFuture = future;
    });
    await future;
  }

  Future<void> _runOcr({String? imagePathOverride}) async {
    if (_isRecognizing) {
      return;
    }

    final document = _document;
    if (document == null) {
      _showMessage('???????????????');
      return;
    }

    setState(() {
      _isRecognizing = true;
    });

    final result = await _ocrPipelineService.runForDocument(
      document: document,
      imagePathOverride: imagePathOverride,
    );

    if (!mounted) {
      return;
    }

    _showMessage(result.message);

    try {
      await _reloadPageData();
    } catch (_) {
      if (mounted) {
        _showMessage('OCR ????????????????????');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRecognizing = false;
        });
      }
    }
  }

  Future<void> _cropAndRunOcr() async {
    if (_isRecognizing || _isSaving || _isRepairing) {
      return;
    }

    final document = _document;
    if (document == null) {
      _showMessage('???????????????');
      return;
    }

    final croppedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ImageCropSelectionPage(imagePath: document.imagePath),
      ),
    );
    if (!mounted || croppedPath == null || croppedPath.trim().isEmpty) {
      return;
    }

    try {
      await _sourceDocumentRepository.updateDocumentImagePath(
        userId: document.userId,
        documentId: document.id,
        imagePath: croppedPath,
      );
      await _runOcr(imagePathOverride: croppedPath);
    } catch (error) {
      if (mounted) {
        _showMessage('?????????$error');
      }
    }
  }

  Future<void> _saveEditedText() async {
    if (_isSaving) {
      return;
    }

    final document = _document;
    if (document == null) {
      _showMessage('???????????????');
      return;
    }

    final rawText = _rawTextController.text.trim();
    final cleanText = _cleanTextController.text.trim();
    final finalText = _finalTextController.text.trim();

    if (rawText.isEmpty && cleanText.isEmpty && finalText.isEmpty) {
      _showMessage('??????????????AI ???????');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final rawForSave = rawText.isEmpty
          ? (cleanText.isEmpty ? finalText : cleanText)
          : rawText;
      final cleanForSave = cleanText.isEmpty
          ? (rawText.isEmpty ? finalText : rawText)
          : cleanText;
      final quality = OcrTextQualityEvaluator.evaluate(
        rawText: rawForSave,
        cleanText: cleanForSave,
      );
      final hasFinalText = finalText.isNotEmpty;
      final needsReview = !hasFinalText && !quality.isUsableForAutomation;

      await _ocrTextRepository.upsertOcrText(
        documentId: document.id,
        rawText: rawForSave,
        cleanText: cleanForSave,
        finalText: hasFinalText ? finalText : null,
        quality: quality,
        ocrStatus: needsReview
            ? SourceDocumentOcrStatus.needsReview
            : SourceDocumentOcrStatus.success,
        ocrErrorMessage: needsReview
            ? 'OCR ???????????AI ????? finalText'
            : null,
      );

      if (!mounted) {
        return;
      }

      _showMessage(needsReview ? '??????? OCR ?????????' : 'OCR ?????????');
      await _reloadPageData();
    } catch (error) {
      if (mounted) {
        _showMessage('?????$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _confirmFinalText() async {
    final document = _document;
    if (document == null) {
      _showMessage('???????????????');
      return;
    }

    final finalText = _resolveFinalTextCandidate();
    if (finalText.isEmpty) {
      _showMessage('finalText ??????? AI ?????????');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _ocrTextRepository.saveFinalText(
        documentId: document.id,
        finalText: finalText,
      );
      if (!mounted) return;
      _finalTextController.text = finalText;
      _showMessage('finalText ?????????? AI ????????');
      await _reloadPageData();
    } catch (error) {
      if (mounted) {
        _showMessage('?? finalText ???$error');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _repairWithAi() async {
    if (_isRepairing) {
      return;
    }

    final document = _document;
    if (document == null) {
      _showMessage('???????????????');
      return;
    }

    final rawText = _rawTextController.text.trim();
    final cleanText = _cleanTextController.text.trim();
    if (rawText.isEmpty && cleanText.isEmpty) {
      _showMessage('?? OCR ????? rawText/cleanText???? AI ??');
      return;
    }

    final currentUser = await _authRepository.getCurrentUserProfile();
    if (!mounted) return;
    if (currentUser == null) {
      _showMessage('?????????????');
      return;
    }
    final llmConfig = await _llmConfigRepository.getByUserId(currentUser.id);
    if (!mounted) return;
    if (llmConfig == null || !llmConfig.isConfigured) {
      _showMessage('?????????? AI ??? API Key');
      return;
    }

    setState(() => _isRepairing = true);
    try {
      final repairService =
          widget.ocrTextRepairService ??
          OcrTextRepairService(client: MiniMaxClient.fromConfig(llmConfig));
      final repaired = await repairService.repair(
        rawText: rawText,
        cleanText: cleanText,
      );
      await _ocrTextRepository.saveFinalText(
        documentId: document.id,
        finalText: repaired.finalText,
      );
      if (!mounted) return;
      _finalTextController.text = repaired.finalText;
      _showMessage(
        repaired.summary.isEmpty
            ? 'AI ????????? finalText'
            : 'AI ?????${repaired.summary}',
      );
      await _reloadPageData();
    } catch (error) {
      if (mounted) {
        _showMessage('AI ?????$error');
      }
    } finally {
      if (mounted) setState(() => _isRepairing = false);
    }
  }

  String _resolveFinalTextCandidate() {
    final finalText = _finalTextController.text.trim();
    if (finalText.isNotEmpty) return finalText;
    final cleanText = _cleanTextController.text.trim();
    if (cleanText.isNotEmpty) return cleanText;
    return _rawTextController.text.trim();
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
        title: const Text('OCR ??'),
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
              title: 'OCR ??????',
              description: '??????????????????',
              actionLabel: '????',
              onPressed: _reloadPageData,
            );
          }

          final data = snapshot.data!;
          final style = _ocrStyleOf(data.document.ocrStatus);
          final isBusy = _isRecognizing || _isSaving || _isRepairing;

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
                        if (isBusy)
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
                          ? '???${data.document.ocrErrorMessage}'
                          : '?????????? OCR???????????? AI ???? AI ??????? finalText?',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _OcrActionButtons(
                      isBusy: isBusy,
                      isSaving: _isSaving,
                      isRepairing: _isRepairing,
                      isRecognizing: _isRecognizing,
                      hasSuccess:
                          data.document.ocrStatus ==
                          SourceDocumentOcrStatus.success,
                      onRunOcr: () => _runOcr(),
                      onCropAndRunOcr: _cropAndRunOcr,
                      onRepairWithAi: _repairWithAi,
                      onSaveEditedText: _saveEditedText,
                      onConfirmFinalText: _confirmFinalText,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _QualityPanel(record: data.ocrRecord),
              const SizedBox(height: 16),
              _TextEditorCard(
                title: '?????? rawText',
                hintText: '????? OCR??????????????????',
                controller: _rawTextController,
              ),
              const SizedBox(height: 14),
              _TextEditorCard(
                title: '????? cleanText',
                hintText: '??????????????????????? AI ???',
                controller: _cleanTextController,
              ),
              const SizedBox(height: 14),
              _TextEditorCard(
                title: '???? finalText',
                hintText: 'AI ?????????????????? AI ??????????',
                controller: _finalTextController,
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
                    '???? OCR ??????????????????????????????',
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

class _OcrActionButtons extends StatelessWidget {
  const _OcrActionButtons({
    required this.isBusy,
    required this.isSaving,
    required this.isRepairing,
    required this.isRecognizing,
    required this.hasSuccess,
    required this.onRunOcr,
    required this.onCropAndRunOcr,
    required this.onRepairWithAi,
    required this.onSaveEditedText,
    required this.onConfirmFinalText,
  });

  final bool isBusy;
  final bool isSaving;
  final bool isRepairing;
  final bool isRecognizing;
  final bool hasSuccess;
  final VoidCallback onRunOcr;
  final VoidCallback onCropAndRunOcr;
  final VoidCallback onRepairWithAi;
  final VoidCallback onSaveEditedText;
  final VoidCallback onConfirmFinalText;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: isBusy ? null : onRunOcr,
                icon: Icon(
                  hasSuccess ? Icons.refresh_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(hasSuccess ? '?? OCR' : '?? OCR'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isBusy ? null : onCropAndRunOcr,
                icon: const Icon(Icons.crop_rounded),
                label: const Text('????'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isBusy ? null : onRepairWithAi,
                icon: isRepairing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high_rounded),
                label: const Text('AI ??'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isBusy ? null : onSaveEditedText,
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text('????'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: isBusy ? null : onConfirmFinalText,
            icon: const Icon(Icons.verified_rounded),
            label: const Text('?? finalText??????? AI ??'),
          ),
        ),
      ],
    );
  }
}

class _QualityPanel extends StatelessWidget {
  const _QualityPanel({required this.record});

  final OcrTextRecord? record;

  @override
  Widget build(BuildContext context) {
    final qualityScore = record?.qualityScore;
    final qualityLevel = record?.qualityLevel?.trim();
    final isLow = record?.isLowQuality ?? false;
    final reasons = record?.qualityReasons ?? const <String>[];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLow ? const Color(0xFFFFF7ED) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isLow ? const Color(0xFFF59E0B) : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLow ? Icons.warning_amber_rounded : Icons.fact_check_rounded,
                color: isLow ? const Color(0xFF9A3412) : AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'OCR ????',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            qualityScore == null
                ? '??????? OCR ????????????'
                : '?? $qualityScore / 100 ? ${_qualityLevelLabel(qualityLevel)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isLow ? const Color(0xFF9A3412) : AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
          if (isLow) ...[
            const SizedBox(height: 6),
            Text(
              '??????????? AI ???????????????? AI ??/???? finalText?',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF9A3412),
                height: 1.45,
              ),
            ),
          ],
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: reasons
                  .map(
                    (reason) => _QualityChip(text: _qualityReasonLabel(reason)),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
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
    case SourceDocumentOcrStatus.needsReview:
      return const _OcrStatusStyle(
        background: Color(0xFFFFF7ED),
        foreground: Color(0xFF9A3412),
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

String _qualityLevelLabel(String? level) {
  switch (level) {
    case 'high':
      return '???';
    case 'medium':
      return '????';
    case 'low':
      return '???';
    default:
      return '???';
  }
}

String _qualityReasonLabel(String reason) {
  switch (reason) {
    case 'ui_noise':
      return '??????';
    case 'ineffective_cleaning':
      return '???????';
    case 'too_short':
      return '????';
    case 'too_many_symbols':
      return '??????';
    case 'low_chinese_ratio':
      return '??????';
    case 'suspicious_structure':
      return '????';
    default:
      return reason;
  }
}
