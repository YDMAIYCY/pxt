import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../community/cloud_backend.dart';
import '../../../community/community_repository.dart';
import '../../../community/knowledge_community_bridge.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/eclaw_chat_widgets.dart' show EClawRichText;
import 'community_widgets.dart';
import 'question_detail_page.dart';

class PublishQuestionPage extends StatefulWidget {
  const PublishQuestionPage({
    this.initialTitle = '',
    this.initialBody = '',
    this.documentId,
    this.repository,
    super.key,
  });
  final String initialTitle, initialBody;
  final int? documentId;
  final CommunityRepository? repository;
  @override
  State<PublishQuestionPage> createState() => _PublishQuestionPageState();
}

class _PublishQuestionPageState extends State<PublishQuestionPage> {
  late final _title = TextEditingController(text: widget.initialTitle),
      _body = TextEditingController(text: widget.initialBody);
  final _tags = TextEditingController();
  late final _repo = widget.repository ?? CommunityRepository();
  final _token = const Uuid().v4();
  ({
    String title,
    String body,
    List<String> tags,
    List<String> images,
    String token,
    int? source,
  })?
  _pending;
  final List<({XFile file, Uint8List bytes, String token})> _images = [];
  final Map<String, String> _uploaded = {};
  late int? _source = widget.documentId;
  bool _busy = false;
  bool get _locked => _busy || _pending != null;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_locked) return;
    try {
      if (_images.length >= 6) {
        communityMessage(context, '最多添加 6 张图片');
        return;
      }
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1800,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) {
        throw const CloudFailure('图片不能超过 8 MB');
      }
      if (mounted && !_locked) {
        setState(
          () =>
              _images.add((file: file, bytes: bytes, token: const Uuid().v4())),
        );
      }
    } catch (e) {
      if (mounted) communityMessage(context, cloudError(e));
    }
  }

  Future<void> _chooseCard() async {
    if (_locked) return;
    try {
      final cards = await KnowledgeCommunityBridge().shareableCards();
      if (!mounted || _locked) return;
      final card = await showModalBottomSheet<Map<String, Object?>>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: 440,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    '选择要引用的知识卡片',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text('仅复制选中的文字到草稿，发布前请检查并删除私人信息。'),
                ),
                Expanded(
                  child: cards.isEmpty
                      ? const Center(child: Text('还没有知识卡片'))
                      : ListView(
                          children: [
                            for (final c in cards)
                              ListTile(
                                title: Text(c['title'] as String),
                                subtitle: Text(
                                  c['content'] as String,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => Navigator.pop(ctx, c),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      );
      if (card != null && mounted && !_locked) {
        setState(() {
          _title.text = card['title'] as String;
          _body.text = card['content'] as String;
          _source = card['document_id'] as int;
        });
      }
    } catch (e) {
      if (mounted) communityMessage(context, cloudError(e));
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final title = _title.text.trim(), body = _body.text.trim();
    final tags = _tags.text
        .split(RegExp('[,，#]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (_pending == null &&
        (title.isEmpty ||
            body.isEmpty ||
            title.length > 160 ||
            body.length > 20000 ||
            tags.length > 8)) {
      setState(() => _error = '请填写标题和描述；标题最多 160 字，描述最多 20000 字，标签最多 8 个');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var pending = _pending;
      if (pending == null) {
        await _repo.identity.requireLinked();
        for (final image in _images) {
          _uploaded[image.token] ??= await _repo.upload(
            'community-images',
            image.bytes,
            image.file.name.split('.').last,
            token: image.token,
          );
        }
        if (!mounted) return;
        // From this point a failed response may still mean the write succeeded.
        pending = (
          title: title,
          body: body,
          tags: List<String>.unmodifiable(tags),
          images: List<String>.unmodifiable(
            _images.map((i) => _uploaded[i.token]!),
          ),
          token: _token,
          source: _source,
        );
        setState(() => _pending = pending);
      }
      final id = await _repo.publish(
        title: pending.title,
        body: pending.body,
        token: pending.token,
        tags: pending.tags,
        images: pending.images,
      );
      if (pending.source != null) {
        try {
          await KnowledgeCommunityBridge().linkPublishedQuestion(
            id,
            pending.source!,
          );
        } catch (_) {
          if (mounted) communityMessage(context, '发布成功，本地来源关联未完成');
        }
      }
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                QuestionDetailPage(questionId: id, repository: _repo),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = _pending == null
              ? cloudError(e)
              : '结果待确认，请重试确认\n${cloudError(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Hide the character counter until it is actually useful; a permanent
  /// "0/160" under the title is noise on an empty form.
  Widget? _counterWhenNearLimit(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) {
    if (maxLength == null || currentLength < maxLength * 0.8) return null;
    return Text(
      '$currentLength / $maxLength',
      style: AppTextStyles.caption(context),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: communityBackground,
    appBar: AppBar(
      title: const Text('发布问题'),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _title.text,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          EClawRichText(_body.text),
                          for (final i in _images)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Image.memory(i.bytes, height: 150),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
          child: const Text('预览'),
        ),
      ],
    ),
    bottomNavigationBar: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: communityBlue,
              minimumSize: const Size.fromHeight(52),
            ),
            child: Text(
              _busy
                  ? '正在上传并发布…'
                  : _pending != null
                  ? '重试确认'
                  : '发布问题',
            ),
          ),
        ),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        // ---- 问题内容 ----
        // One editor surface: the two fields are separated by a hairline, not
        // by two different containers, so the draft reads as a single document.
        AppCard.plain(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
                maxLength: 160,
                buildCounter: _counterWhenNearLimit,
                decoration: const InputDecoration(
                  labelText: '问题标题',
                  hintText: '一句话说清问题',
                  filled: false,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                enabled: !_locked,
              ),
              const Divider(height: 1, color: AppColors.borderLight),
              TextField(
                controller: _body,
                minLines: 5,
                maxLines: 18,
                maxLength: 20000,
                buildCounter: _counterWhenNearLimit,
                enabled: !_locked,
                decoration: const InputDecoration(
                  labelText: '问题描述',
                  hintText: '具体卡在哪一步？已经试过什么？',
                  filled: false,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ---- 标签 ----
        AppCard.plain(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: TextField(
            controller: _tags,
            enabled: !_locked,
            decoration: const InputDecoration(
              labelText: '知识标签',
              hintText: '用逗号分隔，例如 数据结构, 算法',
              filled: false,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ---- 补充材料 ----
        AppCard.outlined(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppSectionHeader(
                title: '补充材料',
                accent: AppColors.accentSky,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: _locked
                        ? null
                        : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_outlined, size: 18),
                    label: const Text('相册'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: _locked ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Text('拍照'),
                  ),
                  TextButton.icon(
                    onPressed: _locked ? null : _chooseCard,
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('引用知识卡片'),
                  ),
                ],
              ),
              if (_source != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '仅发布草稿文字，原文档仍保存在本地。',
                    style: AppTextStyles.caption(context),
                  ),
                ),
              if (_images.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final i in _images)
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                AppRadii.chipSmall,
                              ),
                              child: Image.memory(
                                i.bytes,
                                width: 95,
                                height: 95,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton(
                                tooltip: '移除图片',
                                onPressed: _locked
                                    ? null
                                    : () => setState(() => _images.remove(i)),
                                icon: const Icon(
                                  Icons.cancel,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: AppColors.tintOf(AppColors.error, 0.07),
                borderRadius: BorderRadius.circular(AppRadii.cardSmall),
                border: Border.all(
                  color: AppColors.tintOf(AppColors.error, 0.18),
                ),
              ),
              child: Text(
                _error!,
                style: AppTextStyles.bodySmall(
                  context,
                ).copyWith(color: AppColors.error),
              ),
            ),
          ),
        if (_error != null && !CloudBackend.instance.signedIn)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(
              onPressed: () async {
                await openAppAccount(context);
              },
              child: const Text('登录智学帮'),
            ),
          ),
        const SizedBox(height: 20),
      ],
    ),
  );
}
