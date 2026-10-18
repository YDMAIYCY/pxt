import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../community/cloud_backend.dart';
import '../../../community/community_repository.dart';
import '../../../community/knowledge_community_bridge.dart';
import '../../../database/auth_repository.dart';
import '../../../database/knowledge_library_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/eclaw_chat_widgets.dart' show EClawRichText;
import 'community_widgets.dart';
import 'social_pages.dart';

class QuestionDetailPage extends StatefulWidget {
  const QuestionDetailPage({
    required this.questionId,
    this.repository,
    super.key,
  });
  final String questionId;
  final CommunityRepository? repository;
  @override
  State<QuestionDetailPage> createState() => _QuestionDetailPageState();
}

class _QuestionDetailPageState extends State<QuestionDetailPage> {
  late final _repo = widget.repository ?? CommunityRepository();
  final _reply = TextEditingController();
  late Future<Json> _future;
  List<Json> _answers = [];
  bool _bookmarked = false, _busy = false, _more = true;
  String _token = const Uuid().v4();
  ({String body, String token})? _pendingReply;
  String? _replyError;
  @override
  void initState() {
    super.initState();
    _future = _load()..ignore();
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
    setState(() {
      _future = _load()..ignore();
    });
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

  Future<void> _submitReply() async {
    if (_busy) return;
    final pending = _pendingReply ?? (body: _reply.text, token: _token);
    if (pending.body.trim().isEmpty) {
      communityMessage(context, '回答不能为空');
      return;
    }
    setState(() {
      _pendingReply = pending;
      _replyError = null;
    });
    await _action(() async {
      try {
        await _repo.answer(widget.questionId, pending.body, pending.token);
      } catch (e) {
        if (mounted) {
          setState(() => _replyError = '结果待确认，请重试确认\n${cloudError(e)}');
        }
        rethrow;
      }
      if (!mounted) return;
      setState(() {
        _reply.clear();
        _pendingReply = null;
        _token = const Uuid().v4();
      });
    }, message: '回答已发布');
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

  Widget _author(Json item, {Widget? trailing}) {
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title(context),
                ),
                const SizedBox(height: 1),
                Text(
                  communityTime(item['created_at']),
                  style: AppTextStyles.caption(context),
                ),
              ],
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
  }

  /// Owner-only and destructive actions live in an overflow so they never sit
  /// shoulder to shoulder with the primary "收藏 / 存入知识库" pair.
  Widget _moreMenu({
    required List<PopupMenuEntry<String>> items,
    required void Function(String) onSelected,
  }) => PopupMenuButton<String>(
    tooltip: '更多操作',
    icon: const Icon(
      Icons.more_horiz_rounded,
      color: AppColors.textSecondary,
    ),
    onSelected: onSelected,
    itemBuilder: (_) => items,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: communityBackground,
    appBar: AppBar(title: const Text('问题详情')),
    body: CloudFutureView(
      future: _future,
      onRetry: () => _refresh(),
      builder: (q) {
        final resolved = q['accepted_answer_id'] != null;
        final isOwner = q['author_id'] == _repo.uid;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              // ---- 问题 ----
              AppCard.plain(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _author(
                      q,
                      trailing: AppTag(
                        label: resolved ? '已解决' : '待解答',
                        accent: resolved
                            ? AppColors.success
                            : AppColors.accentAmber,
                        icon: resolved
                            ? Icons.check_circle_rounded
                            : Icons.pending_outlined,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      q['title'] as String,
                      style: AppTextStyles.h2(context).copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
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
                    if ((q['tags'] as List).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final tag in q['tags'] as List)
                              AppTag(
                                label: tag.toString(),
                                accent: AppColors.primary,
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: AppColors.borderLight),
                    Row(
                      children: [
                        _ActionChip(
                          icon: _bookmarked
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          label: _bookmarked ? '已收藏' : '收藏',
                          active: _bookmarked,
                          onTap: _busy
                              ? null
                              : () => _action(
                                  () => _repo.bookmark(
                                    widget.questionId,
                                    !_bookmarked,
                                  ),
                                ),
                        ),
                        _ActionChip(
                          icon: Icons.library_add_outlined,
                          label: '存入知识库',
                          onTap: _busy ? null : () => _save(q, null),
                        ),
                        const Spacer(),
                        _moreMenu(
                          items: [
                            if (isOwner) ...[
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('编辑'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('删除'),
                              ),
                            ] else
                              const PopupMenuItem(
                                value: 'report',
                                child: Text('举报'),
                              ),
                          ],
                          onSelected: (value) async {
                            if (value == 'edit') {
                              await _edit('community_questions', q);
                            } else if (value == 'delete') {
                              if (await confirmCommunityDelete(context)) {
                                await _action(() async {
                                  await _repo.deleteContent(
                                    'community_questions',
                                    widget.questionId,
                                  );
                                  if (context.mounted) Navigator.pop(context);
                                });
                              }
                            } else {
                              await _report('question', widget.questionId);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ---- 回答 ----
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 20, 2, 12),
                child: AppSectionHeader(
                  title: '回答与讨论',
                  subtitle: resolved
                      ? '已解决 · 采纳的回答排在最前'
                      : _answers.isEmpty
                      ? null
                      : '共 ${_answers.length} 条',
                  accent: resolved ? AppColors.success : AppColors.accentSky,
                ),
              ),
              if (_answers.isEmpty)
                const AppEmptyState(
                  compact: true,
                  icon: Icons.forum_outlined,
                  title: '还没有回答',
                  description: '分享一下你的思路，也许正好能解开这个卡点。',
                ),
              for (final a
                  in [..._answers]..sort(
                    (a, b) => (a['id'] == q['accepted_answer_id']
                        ? -1
                        : b['id'] == q['accepted_answer_id']
                        ? 1
                        : 0),
                  ))
                _answerCard(q, a, isOwner: isOwner),
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

              // ---- 写回答 ----
              AppCard.plain(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppSectionHeader(
                      title: '写下你的回答',
                      accent: AppColors.accentSky,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reply,
                      minLines: 3,
                      maxLines: 10,
                      maxLength: 30000,
                      enabled: !_busy && _pendingReply == null,
                      decoration: const InputDecoration(
                        labelText: '写下你的回答',
                        hintText: '写回答',
                      ),
                    ),
                    if (_replyError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _replyError!,
                          style: AppTextStyles.bodySmall(
                            context,
                          ).copyWith(color: AppColors.error),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: _busy ? null : _submitReply,
                        child: Text(
                          _busy
                              ? '提交中…'
                              : _pendingReply != null
                              ? '重试确认'
                              : '发布回答',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _answerCard(Json q, Json a, {required bool isOwner}) {
    final accepted = q['accepted_answer_id'] == a['id'];
    final mine = a['author_id'] == _repo.uid;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        decoration: BoxDecoration(
          color: accepted
              ? AppColors.tintOf(AppColors.success, 0.04)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
            color: accepted ? AppColors.success : AppColors.borderLight,
            width: accepted ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _author(
              a,
              trailing: accepted
                  ? const AppTag(
                      label: '已采纳',
                      accent: AppColors.success,
                      icon: Icons.check_circle_rounded,
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            EClawRichText(a['body'] as String),
            Row(
              children: [
                _ActionChip(
                  icon: Icons.library_add_outlined,
                  label: '存入知识库',
                  onTap: _busy ? null : () => _save(q, a),
                ),
                if (isOwner)
                  _ActionChip(
                    icon: accepted
                        ? Icons.undo_rounded
                        : Icons.verified_outlined,
                    label: accepted ? '取消采纳' : '采纳',
                    active: accepted,
                    onTap: _busy
                        ? null
                        : () => _action(
                            () => _repo.accept(
                              widget.questionId,
                              accepted ? null : a['id'] as String,
                            ),
                          ),
                  ),
                const Spacer(),
                _moreMenu(
                  items: [
                    if (mine) ...[
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                      const PopupMenuItem(value: 'delete', child: Text('删除')),
                    ] else
                      const PopupMenuItem(value: 'report', child: Text('举报')),
                  ],
                  onSelected: (value) async {
                    if (value == 'edit') {
                      await _edit('community_answers', a);
                    } else if (value == 'delete') {
                      if (await confirmCommunityDelete(context)) {
                        await _action(
                          () => _repo.deleteContent(
                            'community_answers',
                            a['id'] as String,
                          ),
                        );
                      }
                    } else {
                      await _report('answer', a['id'] as String);
                    }
                  },
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
    );
  }
}

/// A compact footer action: icon + label, tinted when active. Replaces five
/// loose `TextButton`s that had no grouping and no visual hierarchy.
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = active ? AppColors.accentAmber : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.chipSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTextStyles.label(
                context,
              ).copyWith(color: accent, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
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
