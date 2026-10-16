import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../community/cloud_backend.dart';
import '../../../community/community_repository.dart';
import '../../../community/knowledge_community_bridge.dart';
import '../../widgets/eclaw_chat_widgets.dart' show EClawRichText;
import 'community_widgets.dart';
import 'question_detail_page.dart';

class PublishQuestionPage extends StatefulWidget {
  const PublishQuestionPage({
    this.initialTitle = '',
    this.initialBody = '',
    this.documentId,
    super.key,
  });
  final String initialTitle, initialBody;
  final int? documentId;
  @override
  State<PublishQuestionPage> createState() => _PublishQuestionPageState();
}

class _PublishQuestionPageState extends State<PublishQuestionPage> {
  late final _title = TextEditingController(text: widget.initialTitle),
      _body = TextEditingController(text: widget.initialBody);
  final _tags = TextEditingController(), _repo = CommunityRepository();
  final _token = const Uuid().v4();
  final List<({XFile file, Uint8List bytes, String token})> _images = [];
  final Map<String, String> _uploaded = {};
  late int? _source = widget.documentId;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
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
      if (mounted) {
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
    try {
      final cards = await KnowledgeCommunityBridge().shareableCards();
      if (!mounted) return;
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
      if (card != null && mounted) {
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
    if (title.isEmpty ||
        body.isEmpty ||
        title.length > 160 ||
        body.length > 20000 ||
        tags.length > 8) {
      setState(() => _error = '请填写标题和描述；标题最多 160 字，描述最多 20000 字，标签最多 8 个');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.identity.requireLinked();
      for (final image in _images) {
        _uploaded[image.token] ??= await _repo.upload(
          'community-images',
          image.bytes,
          image.file.name.split('.').last,
          token: image.token,
        );
      }
      final id = await _repo.publish(
        title: title,
        body: body,
        token: _token,
        tags: tags,
        images: _images.map((i) => _uploaded[i.token]!).toList(),
      );
      if (_source != null) {
        try {
          await KnowledgeCommunityBridge().linkPublishedQuestion(id, _source!);
        } catch (_) {
          if (mounted) communityMessage(context, '发布成功，本地来源关联未完成');
        }
      }
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => QuestionDetailPage(questionId: id)),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = cloudError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _title,
          maxLength: 160,
          decoration: const InputDecoration(
            labelText: '问题标题',
            hintText: '写清楚你想解决的问题',
          ),
          enabled: !_busy,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _body,
          minLines: 7,
          maxLines: 18,
          maxLength: 20000,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: '问题描述',
            hintText: '描述思路与困惑，可使用 Markdown、代码块和数学公式',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tags,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: '知识标签',
            hintText: '例如：高等数学，极限（最多 8 个）',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy ? null : () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_outlined),
              label: const Text('相册'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy ? null : () => _pick(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('拍照'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _chooseCard,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('引用知识卡片'),
            ),
          ],
        ),
        if (_source != null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '已引用本地资料。仅发布上方草稿文字，原文档及其他学习资料仍保存在本地。',
              style: TextStyle(color: Colors.blueGrey, fontSize: 12),
            ),
          ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final i in _images)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
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
                      onPressed: _busy
                          ? null
                          : () => setState(() => _images.remove(i)),
                      icon: const Icon(Icons.cancel, color: Colors.white),
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        if (_error != null && !CloudBackend.instance.signedIn)
          TextButton(
            onPressed: () async {
              await openAppAccount(context);
            },
            child: const Text('登录智学帮'),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: communityBlue,
            minimumSize: const Size.fromHeight(50),
          ),
          child: Text(_busy ? '正在上传并发布…' : '发布问题'),
        ),
      ],
    ),
  );
}
