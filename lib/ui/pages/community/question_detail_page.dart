import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../community/cloud_backend.dart';
import '../../../community/community_repository.dart';
import '../../../community/knowledge_community_bridge.dart';
import '../../../database/auth_repository.dart';
import '../../../database/knowledge_library_repository.dart';
import '../../widgets/eclaw_chat_widgets.dart' show EClawRichText;
import 'community_widgets.dart';
import 'social_pages.dart';

class QuestionDetailPage extends StatefulWidget {
  const QuestionDetailPage({required this.questionId, super.key});
  final String questionId;
  @override
  State<QuestionDetailPage> createState() => _QuestionDetailPageState();
}

class _QuestionDetailPageState extends State<QuestionDetailPage> {
  final _repo = CommunityRepository(), _reply = TextEditingController();
  late Future<Json> _future;
  List<Json> _answers = [];
  bool _bookmarked = false, _busy = false, _more = true;
  String _token = const Uuid().v4();
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<Json> _load() async {
    final q = await _repo.question(widget.questionId);
    final answers = await _repo.answers(widget.questionId);
    final b = await _repo.bookmarked(widget.questionId);
    _answers = answers;
    _more = answers.length == 20;
    _bookmarked = b;
    return q;
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    try {
      await _future;
    } catch (_) {}
  }

  Future<void> _action(
    Future<void> Function() action, {
    String? message,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        if (message != null) communityMessage(context, message);
        await _refresh();
      }
    } catch (e) {
      if (mounted) communityMessage(context, cloudError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _user(Json p) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CommunityUserPage(userId: p['id'] as String),
    ),
  );
  Future<void> _save(Json q, Json? answer) async {
    try {
      final user = await AuthRepository().getCurrentUserProfile();
      if (user == null) throw const CloudFailure('请先登录');
      final libraries = await KnowledgeLibraryRepository().fetchLibraries(
        user.id,
      );
      if (!mounted) return;
      final library = await showModalBottomSheet<int>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('保存到我的知识库')),
              for (final l in libraries)
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(l.name),
                  onTap: () => Navigator.pop(ctx, l.id),
                ),
            ],
          ),
        ),
      );
      if (library == null) return;
      await KnowledgeCommunityBridge().saveToLibrary(
        question: q,
        answer: answer,
        libraryId: library,
      );
      var synced = true;
      try {
        await _repo.saveReference(q['id'] as String, answer?['id'] as String?);
      } catch (_) {
        synced = false;
      }
      if (mounted) {
        communityMessage(
          context,
          synced ? '已保存到个人知识库，并保留社区来源链接' : '已保存到本地知识库；云端引用同步失败，可再次保存重试',
        );
      }
    } catch (e) {
      if (mounted) communityMessage(context, cloudError(e));
    }
  }

  Future<void> _report(String type, String id) async {
    final reason = await communityPrompt(context, '举报原因', maxLength: 1000);
    if (reason != null) {
      await _action(() => _repo.report(type, id, reason), message: '举报已提交');
    }
  }

  Future<void> _edit(String table, Json item) async {
    String? title;
    if (table == 'community_questions') {
      title = await communityPrompt(
        context,
        '修改问题标题',
        initial: item['title'] as String,
        maxLength: 160,
      );
      if (title == null) return;
    }
    if (!mounted) return;
    final text = await communityPrompt(
      context,
      '修改内容',
      initial: item['body'] as String,
      maxLength: table == 'community_questions' ? 20000 : 30000,
    );
    if (text != null) {
      await _action(
        () =>
            _repo.editContent(table, item['id'] as String, text, title: title),
        message: '已更新',
      );
    }
  }

  Widget _author(Json item) {
    final p = Json.from(item['profile'] as Map? ?? {});
    return Row(
      children: [
        CommunityAvatar(profile: p, onTap: () => _user(p)),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: () => _user(p),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p['nickname'] as String? ?? '同学',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  communityTime(item['created_at']),
                  style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: communityBackground,
    appBar: AppBar(title: const Text('问题详情')),
    body: CloudFutureView(
      future: _future,
      onRetry: () => _refresh(),
      builder: (q) => RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _author(q),
                  const SizedBox(height: 16),
                  Text(
                    q['title'] as String,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  EClawRichText(q['body'] as String),
                  for (final path in q['image_paths'] as List)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: CommunityImage(
                        path: path as String,
                        height: 210,
                        width: double.infinity,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final tag in q['tags'] as List)
                        Chip(
                          label: Text(
                            tag.toString(),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _action(
                                () => _repo.bookmark(
                                  widget.questionId,
                                  !_bookmarked,
                                ),
                              ),
                        icon: Icon(
                          _bookmarked ? Icons.star : Icons.star_border,
                        ),
                        label: Text(_bookmarked ? '已收藏' : '收藏'),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : () => _save(q, null),
                        icon: const Icon(Icons.library_add_outlined),
                        label: const Text('存入知识库'),
                      ),
                      if (q['author_id'] == _repo.uid) ...[
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit('community_questions', q),
                          child: const Text('编辑'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (await confirmCommunityDelete(context)) {
                                    await _action(() async {
                                      await _repo.deleteContent(
                                        'community_questions',
                                        widget.questionId,
                                      );
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    });
                                  }
                                },
                          child: const Text('删除'),
                        ),
                      ] else
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _report('question', widget.questionId),
                          child: const Text('举报'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                q['accepted_answer_id'] == null ? '回答与讨论' : '已解决 · 已采纳的回答会突出显示',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_answers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  '还没有回答，分享你的思路吧',
                  style: TextStyle(color: Colors.blueGrey),
                ),
              ),
            for (final a
                in [..._answers]..sort(
                  (a, b) => (a['id'] == q['accepted_answer_id']
                      ? -1
                      : b['id'] == q['accepted_answer_id']
                      ? 1
                      : 0),
                ))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  decoration: BoxDecoration(
                    border: q['accepted_answer_id'] == a['id']
                        ? Border.all(color: const Color(0xFF24BB8D), width: 2)
                        : null,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (q['accepted_answer_id'] == a['id'])
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              '✓ 已采纳',
                              style: TextStyle(
                                color: Color(0xFF12A777),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        _author(a),
                        const SizedBox(height: 12),
                        EClawRichText(a['body'] as String),
                        const SizedBox(height: 8),
                        Wrap(
                          children: [
                            TextButton(
                              onPressed: _busy ? null : () => _save(q, a),
                              child: const Text('存入知识库'),
                            ),
                            if (q['author_id'] == _repo.uid)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _action(
                                        () => _repo.accept(
                                          widget.questionId,
                                          q['accepted_answer_id'] == a['id']
                                              ? null
                                              : a['id'] as String,
                                        ),
                                      ),
                                child: Text(
                                  q['accepted_answer_id'] == a['id']
                                      ? '取消采纳'
                                      : '采纳',
                                ),
                              ),
                            if (a['author_id'] == _repo.uid) ...[
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _edit('community_answers', a),
                                child: const Text('编辑'),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        if (await confirmCommunityDelete(
                                          context,
                                        )) {
                                          await _action(
                                            () => _repo.deleteContent(
                                              'community_answers',
                                              a['id'] as String,
                                            ),
                                          );
                                        }
                                      },
                                child: const Text('删除'),
                              ),
                            ] else
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () =>
                                          _report('answer', a['id'] as String),
                                child: const Text('举报'),
                              ),
                          ],
                        ),
                        AnswerComments(
                          key: ValueKey('${a['id']}:${q['updated_at']}'),
                          answerId: a['id'] as String,
                          repository: _repo,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_more)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          final more = await _repo.answers(
                            widget.questionId,
                            offset: _answers.length,
                          );
                          if (mounted) {
                            setState(() {
                              _answers.addAll(more);
                              _more = more.length == 20;
                            });
                          }
                        } catch (e) {
                          if (context.mounted) {
                            communityMessage(context, cloudError(e));
                          }
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: const Text('加载更多回答'),
              ),
            _card(
              Column(
                children: [
                  TextField(
                    controller: _reply,
                    minLines: 3,
                    maxLines: 10,
                    maxLength: 30000,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: '写下你的回答',
                      hintText: '支持 Markdown、代码块和数学公式',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: _busy
                          ? null
                          : () {
                              if (_reply.text.trim().isEmpty) {
                                communityMessage(context, '回答不能为空');
                                return;
                              }
                              _action(() async {
                                await _repo.answer(
                                  widget.questionId,
                                  _reply.text,
                                  _token,
                                );
                                _reply.clear();
                                _token = const Uuid().v4();
                              }, message: '回答已发布');
                            },
                      child: Text(_busy ? '提交中…' : '发布回答'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

class AnswerComments extends StatefulWidget {
  const AnswerComments({
    required this.answerId,
    required this.repository,
    super.key,
  });
  final String answerId;
  final CommunityRepository repository;
  @override
  State<AnswerComments> createState() => _AnswerCommentsState();
}

class _AnswerCommentsState extends State<AnswerComments> {
  List<Json> _comments = [];
  bool _opened = false, _busy = false, _more = true;
  String? _error;
  String? _pendingText, _pendingParent;
  String _token = const Uuid().v4();
  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() {
      _opened = true;
      _busy = true;
      _error = null;
    });
    try {
      final rows = await widget.repository.comments(
        widget.answerId,
        offset: more ? _comments.length : 0,
      );
      if (mounted) {
        setState(() {
          if (!more) _comments = [];
          _comments.addAll(rows);
          _more = rows.length == 20;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = cloudError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reply({Json? parent}) async {
    final text = await communityPrompt(
      context,
      parent == null ? '评论回答' : '回复评论',
      maxLength: 4000,
    );
    if (text == null) return;
    _pendingText = text;
    _pendingParent = parent?['id'] as String?;
    _token = const Uuid().v4();
    await _send();
  }

  Future<void> _send() async {
    if (_busy || _pendingText == null) return;
    setState(() => _busy = true);
    try {
      await widget.repository.comment(
        widget.answerId,
        _pendingText!,
        _token,
        parent: _pendingParent,
      );
      _pendingText = null;
      _pendingParent = null;
    } catch (e) {
      if (mounted) communityMessage(context, cloudError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && _pendingText == null) await _load();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Divider(height: 16),
      Row(
        children: [
          TextButton.icon(
            onPressed: _busy
                ? null
                : () => _opened ? setState(() => _opened = false) : _load(),
            icon: const Icon(Icons.forum_outlined, size: 18),
            label: Text(_opened ? '收起评论' : '查看评论'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _reply(),
            child: const Text('写评论'),
          ),
        ],
      ),
      if (_opened) ...[
        for (final c in _comments)
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${(c['profile'] as Map?)?['nickname'] ?? '同学'}${c['parent_id'] == null ? '' : ' · 回复评论'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  c['body'] as String,
                  style: const TextStyle(fontSize: 13, height: 1.6),
                ),
                Row(
                  children: [
                    Text(
                      communityTime(c['created_at']),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.blueGrey,
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _reply(parent: c),
                      child: const Text('回复'),
                    ),
                    if (c['author_id'] == widget.repository.uid)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                if (await confirmCommunityDelete(context)) {
                                  try {
                                    await widget.repository.deleteContent(
                                      'community_comments',
                                      c['id'] as String,
                                    );
                                    await _load();
                                  } catch (e) {
                                    if (context.mounted) {
                                      communityMessage(context, cloudError(e));
                                    }
                                  }
                                }
                              },
                        child: const Text('删除'),
                      ),
                    if (c['author_id'] != widget.repository.uid)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final reason = await communityPrompt(
                                  context,
                                  '举报评论',
                                  maxLength: 1000,
                                );
                                if (reason == null) return;
                                try {
                                  await widget.repository.report(
                                    'comment',
                                    c['id'] as String,
                                    reason,
                                  );
                                  if (context.mounted) {
                                    communityMessage(context, '举报已提交');
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    communityMessage(context, cloudError(e));
                                  }
                                }
                              },
                        child: const Text('举报'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (_comments.isEmpty && !_busy && _error == null)
          const Text(
            '暂无评论',
            style: TextStyle(color: Colors.blueGrey, fontSize: 12),
          ),
        if (_error != null)
          TextButton(onPressed: () => _load(), child: Text('$_error，点击重试')),
        if (_more && _comments.isNotEmpty)
          TextButton(
            onPressed: _busy ? null : () => _load(more: true),
            child: const Text('更多评论'),
          ),
      ],
      if (_pendingText != null)
        TextButton(
          onPressed: _busy ? null : _send,
          child: const Text('评论发送失败，点击重试'),
        ),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
    ],
  );
}
