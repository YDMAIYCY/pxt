import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../community/cloud_backend.dart';
import '../../../community/community_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_kit.dart';
import 'community_widgets.dart';
import 'question_detail_page.dart';
import 'chat_page.dart';

class CommunityUserPage extends StatefulWidget {
  const CommunityUserPage({
    required this.userId,
    this.repository,
    super.key,
  });
  final String userId;
  final CommunityRepository? repository;
  @override
  State<CommunityUserPage> createState() => _CommunityUserPageState();
}

class _CommunityUserPageState extends State<CommunityUserPage> {
  late final _repo = widget.repository ?? CommunityRepository();
  late Future<Json> _future;
  List<Json> _questions = [], _answers = [];
  String _friend = 'none';
  bool _busy = false, _moreQuestions = true, _moreAnswers = true;
  @override
  void initState() {
    super.initState();
    _future = _load()..ignore();
  }

  Future<Json> _load() async {
    final p = await _repo.profile(widget.userId);
    _questions = await _repo.feed(author: widget.userId);
    _answers = await _repo.userAnswers(widget.userId);
    _friend = await _repo.friendStatus(widget.userId);
    _moreQuestions = _questions.length == 20;
    _moreAnswers = _answers.length == 20;
    return p;
  }

  void _reload() => setState(() {
    _future = _load()..ignore();
  });
  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _reload();
    } catch (e) {
      if (mounted) communityMessage(context, cloudError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chat() async {
    try {
      final id = await _repo.openConversation(widget.userId);
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatPage(conversationId: id)),
        );
      }
    } catch (e) {
      if (mounted) communityMessage(context, cloudError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: communityBackground,
    appBar: AppBar(
      title: const Text('同学主页'),
      actions: [
        if (_friend != 'self')
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) async {
              if (value == 'remove') {
                await _action(() => _repo.removeFriend(widget.userId));
              } else if (value == 'block') {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('屏蔽用户'),
                    content: const Text('屏蔽后将解除好友关系，并停止互相查看内容和私聊。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('屏蔽'),
                      ),
                    ],
                  ),
                );
                if (yes == true) {
                  await _action(() async {
                    await _repo.block(widget.userId);
                    if (context.mounted) Navigator.pop(context);
                  });
                }
              }
            },
            itemBuilder: (context) => [
              if (_friend == 'friend')
                const PopupMenuItem(value: 'remove', child: Text('删除好友')),
              const PopupMenuItem(value: 'block', child: Text('屏蔽用户')),
            ],
          ),
      ],
    ),
    body: CloudFutureView(
      future: _future,
      onRetry: _reload,
      builder: (p) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          // ---- 身份卡 ----
          AppCard.plain(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
            child: Column(
              children: [
                CommunityAvatar(profile: p, size: 76),
                const SizedBox(height: 12),
                Text(
                  p['nickname'] as String,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.h2(context),
                ),
                const SizedBox(height: 3),
                Text(
                  'ID：${p['public_id']}',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption(context),
                ),
                if ((p['bio'] as String? ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    p['bio'] as String,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall(context),
                  ),
                ],
                if (_friend != 'self') ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 46),
                    ),
                    onPressed: _busy || _friend == 'sent'
                        ? null
                        : _friend == 'friend'
                        ? _chat
                        : _friend == 'received'
                        ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const FriendsChatPage(initialIndex: 2),
                            ),
                          )
                        : () => _action(() => _repo.sendRequest(widget.userId)),
                    icon: Icon(
                      _friend == 'friend'
                          ? Icons.chat_bubble_outline_rounded
                          : _friend == 'received'
                          ? Icons.mark_email_unread_outlined
                          : Icons.person_add_alt_1_rounded,
                      size: 18,
                    ),
                    label: Text(
                      {
                            'friend': '发消息',
                            'sent': '已发送申请',
                            'received': '查看好友申请',
                            'none': '添加好友',
                          }[_friend] ??
                          '添加好友',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          // ---- 公开问题 ----
          AppSectionHeader(
            title: '公开问题',
            subtitle: _questions.isEmpty ? null : '最近 ${_questions.length} 条',
            accent: AppColors.primary,
          ),
          const SizedBox(height: 12),
          if (_questions.isEmpty)
            const AppEmptyState(
              compact: true,
              icon: Icons.forum_outlined,
              title: '还没有公开问题',
              description: '这位同学还没有发布过问题。',
            )
          else ...[
            for (final q in _questions)
              CommunityQuestionCard(
                question: q,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        QuestionDetailPage(questionId: q['id'] as String),
                  ),
                ),
                onProfile: () {},
              ),
            if (_moreQuestions)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          final rows = await _repo.feed(
                            author: widget.userId,
                            offset: _questions.length,
                          );
                          if (mounted) {
                            setState(() {
                              _questions.addAll(rows);
                              _moreQuestions = rows.length == 20;
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
                child: const Text('更多公开问题'),
              ),
          ],
          const SizedBox(height: AppSpacing.sectionGap),

          // ---- 公开回答 ----
          AppSectionHeader(
            title: '公开回答',
            subtitle: _answers.isEmpty ? null : '最近 ${_answers.length} 条',
            accent: AppColors.accentSky,
          ),
          const SizedBox(height: 12),
          if (_answers.isEmpty)
            const AppEmptyState(
              compact: true,
              icon: Icons.chat_bubble_outline_rounded,
              title: '还没有公开回答',
              description: '这位同学还没有回答过别人的问题。',
            )
          else ...[
            AppCard.outlined(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, a) in _answers.indexed) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        indent: 14,
                        color: AppColors.borderLight,
                      ),
                    AppListRow(
                      icon: Icons.subdirectory_arrow_right_rounded,
                      accent: AppColors.accentSky,
                      title:
                          (a['question'] as Map?)?['title'] as String? ?? '问题',
                      subtitle: a['body'] as String,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QuestionDetailPage(
                            questionId: a['question_id'] as String,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_moreAnswers)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          final rows = await _repo.userAnswers(
                            widget.userId,
                            offset: _answers.length,
                          );
                          if (mounted) {
                            setState(() {
                              _answers.addAll(rows);
                              _moreAnswers = rows.length == 20;
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
                child: const Text('更多公开回答'),
              ),
          ],
        ],
      ),
    ),
  );
}

class FriendsChatPage extends StatefulWidget {
  const FriendsChatPage({
    this.initialIndex = 0,
    this.repository,
    super.key,
  });
  final int initialIndex;
  final CommunityRepository? repository;
  @override
  State<FriendsChatPage> createState() => _FriendsChatPageState();
}

class _FriendsChatPageState extends State<FriendsChatPage>
    with WidgetsBindingObserver {
  late final _repo = widget.repository ?? CommunityRepository();
  late Future<Json> _future;
  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _load()..ignore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    final ch = _channel;
    if (ch != null) _repo.client.removeChannel(ch);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<Json> _load() async {
    await _repo.identity.requireLinked();
    try {
    _channel ??= _repo.client
          .channel('friends-${_repo.uid}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'recipient_id',
              value: _repo.uid,
            ),
            callback: (_) => _scheduleReload(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'friend_requests',
            callback: (_) => _scheduleReload(),
          )
          .subscribe((status, error) {
            if (status == RealtimeSubscribeStatus.subscribed) _scheduleReload();
          });
    } catch (_) {
      // Realtime is an enhancement, not a dependency: if the channel
      // cannot be created, the page still shows what it already fetched.
    }
    return {
      'friends': await _repo.friends(),
      'requests': await _repo.requests(),
      'inbox': await _repo.inbox(),
    };
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _reload();
    });
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _future = _load()..ignore();
      });
    }
  }

  Future<void> _chat(String user) async {
    try {
      final id = await _repo.openConversation(user);
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatPage(conversationId: id)),
        );
        _reload();
      }
    } catch (e) {
      if (mounted) communityMessage(context, cloudError(e));
    }
  }

  Future<void> _respond(String id, bool yes) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _repo.respond(id, yes);
      _reload();
    } catch (e) {
      if (mounted) communityMessage(context, cloudError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _list(List<Widget> children) => RefreshIndicator(
    onRefresh: () async {
      _reload();
      try {
        await _future;
      } catch (_) {}
    },
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: children.isEmpty
          ? const [
              AppEmptyState(
                icon: Icons.forum_outlined,
                title: '暂无内容',
                description: '去社区回答几个问题，就容易遇到同学了。',
              ),
            ]
          : children,
    ),
  );
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    initialIndex: widget.initialIndex,
    child: Scaffold(
      backgroundColor: communityBackground,
      appBar: AppBar(
        title: const Text('好友与聊天'),
        actions: [
          IconButton(
            tooltip: '搜索用户',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UserSearchPage()),
              );
              _reload();
            },
            icon: const Icon(Icons.person_add_alt_outlined),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: '好友'),
            Tab(text: '私聊'),
            Tab(text: '好友申请'),
          ],
        ),
      ),
      body: CloudFutureView(
        future: _future,
        onRetry: _reload,
        builder: (data) => TabBarView(
          children: [
            _list([
              if ((data['friends'] as List).isEmpty)
                const AppEmptyState(
                  icon: Icons.people_outline_rounded,
                  title: '还没有好友',
                  description: '搜索昵称或公开 ID，把一起学习的同学加进来。',
                )
              else
                AppCard.outlined(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, p)
                          in (data['friends'] as List)
                              .cast<Json>()
                              .indexed) ...[
                        if (i > 0)
                          const Divider(
                            height: 1,
                            indent: 66,
                            color: AppColors.borderLight,
                          ),
                        AppListRow(
                          leading: CommunityAvatar(profile: p),
                          title: p['nickname'] as String,
                          subtitle: 'ID：${p['public_id']}',
                          trailing: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          onTap: () => _chat(p['id'] as String),
                        ),
                      ],
                    ],
                  ),
                ),
            ]),
            _list([
              if ((data['inbox'] as List).isEmpty)
                const AppEmptyState(
                  icon: Icons.mark_chat_unread_outlined,
                  title: '还没有私聊',
                  description: '在好友列表里点开一个同学，就能开始对话。',
                )
              else
                AppCard.outlined(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, c)
                          in (data['inbox'] as List).cast<Json>().indexed) ...[
                        if (i > 0)
                          const Divider(
                            height: 1,
                            indent: 66,
                            color: AppColors.borderLight,
                          ),
                        _InboxRow(
                          conversation: c,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatPage(
                                  conversationId: c['id'] as String,
                                ),
                              ),
                            );
                            _reload();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
            ]),
            _list([
              for (final r in (data['requests'] as List).cast<Json>())
                Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        ListTile(
                          leading: CommunityAvatar(
                            profile: Json.from(
                              (r['sender_id'] == _repo.uid
                                      ? r['recipient']
                                      : r['sender'])
                                  as Map,
                            ),
                          ),
                          title: Text(
                            ((r['sender_id'] == _repo.uid
                                        ? r['recipient']
                                        : r['sender'])
                                    as Map)['nickname']
                                as String,
                          ),
                          subtitle: Text(
                            '${r['sender_id'] == _repo.uid ? '已发出' : '收到申请'} · ${{'pending': '待处理', 'accepted': '已同意', 'rejected': '已拒绝', 'cancelled': '已取消'}[r['status']]}',
                          ),
                        ),
                        if (r['status'] == 'pending' &&
                            r['recipient_id'] == _repo.uid)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _respond(r['id'] as String, false),
                                child: const Text('拒绝'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 44),
                                ),
                                onPressed: _busy
                                    ? null
                                    : () => _respond(r['id'] as String, true),
                                child: const Text('同意'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            ]),
          ],
        ),
      ),
    ),
  );
}

/// One notification row: kind icon, actor + action, time. Unread rows get a
/// tinted surface plus a dot — an unread item should be findable at a glance
/// in a long list, which a 6px Badge dot alone was not.
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification, required this.onTap});

  final Json notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final unread = n['read_at'] == null;
    final kind = n['kind'];
    final (icon, accent) = switch (kind) {
      'answer' => (Icons.forum_rounded, AppColors.accentSky),
      'comment' => (Icons.chat_bubble_rounded, AppColors.accentSky),
      'accepted' => (Icons.check_circle_rounded, AppColors.success),
      'friend_request' => (Icons.person_add_alt_1_rounded, AppColors.accentViolet),
      'friend_accepted' => (Icons.people_alt_rounded, AppColors.accentViolet),
      'message' => (Icons.mail_rounded, AppColors.accentMint),
      _ => (Icons.notifications_rounded, AppColors.primary),
    };
    final action =
        {
          'answer': '回答了你的问题',
          'comment': '回复了你的讨论',
          'accepted': '采纳了你的回答',
          'friend_request': '申请添加你为好友',
          'friend_accepted': '同意了好友申请',
          'message': '发来了私信',
        }[kind] ??
        '发来一条学习消息';

    return Material(
      color: unread ? AppColors.tintOf(AppColors.primary, 0.05) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.tintOf(accent, 0.13),
                  borderRadius: BorderRadius.circular(AppRadii.chipSmall),
                  border: Border.all(color: AppColors.tintOf(accent, 0.18)),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${(n['actor'] as Map?)?['nickname'] ?? '同学'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: action),
                        ],
                      ),
                      style: AppTextStyles.bodySmall(
                        context,
                      ).copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      communityTime(n['created_at']),
                      style: AppTextStyles.caption(context),
                    ),
                  ],
                ),
              ),
              if (unread) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One conversation row: avatar, name, last-message preview, time, unread count.
class _InboxRow extends StatelessWidget {
  const _InboxRow({required this.conversation, required this.onTap});

  final Json conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final latest = conversation['latest'] as Map?;
    final unread = (conversation['unread'] as num?)?.toInt() ?? 0;
    final preview = latest?['kind'] == 'image'
        ? '[图片]'
        : (latest?['body'] as String?)?.trim().isNotEmpty == true
        ? latest!['body'] as String
        : '开始交流吧';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              CommunityAvatar(
                profile: Json.from(conversation['profile'] as Map? ?? {}),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${(conversation['profile'] as Map)['nickname']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.title(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          communityTime(latest?['created_at']),
                          style: AppTextStyles.caption(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall(context),
                          ),
                        ),
                        if (unread > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(AppRadii.chip),
                            ),
                            child: Text(
                              '$unread',
                              style: AppTextStyles.labelSmall(context).copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UserSearchPage extends StatefulWidget {
  const UserSearchPage({this.repository, super.key});
  final CommunityRepository? repository;
  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final _query = TextEditingController();
  late final _repo = widget.repository ?? CommunityRepository();
  Timer? _debounce;
  int _searchVersion = 0;
  String _searchTerm = '';
  Future<List<Json>>? _future;
  List<Json> _items = [];
  bool _more = false, _busy = false;
  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _search() {
    _debounce?.cancel();
    final term = _query.text.trim();
    final version = ++_searchVersion;
    _searchTerm = term;
    _busy = false;
    _items = [];
    _more = false;
    if (term.isEmpty) {
      setState(() => _future = null);
      return;
    }
    setState(() {
      _future = _repo.searchUsers(term).then((rows) {
        if (mounted && version == _searchVersion) {
          _items = rows;
          _more = rows.length == 20;
        }
        return rows;
      });
    });
  }

  void _queryChanged(String value) {
    _debounce?.cancel();
    ++_searchVersion;
    setState(() {
      _future = null;
      _items = [];
      _more = false;
      _busy = false;
    });
    if (value.trim().isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 350), _search);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('搜索用户')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _query,
            onChanged: _queryChanged,
            onSubmitted: (_) => _search(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '昵称或公开用户 ID',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: '搜索用户',
                onPressed: _search,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
        ),
        Expanded(
          child: _future == null
              ? const Center(child: Text('输入昵称或公开 ID 搜索同学'))
              : CloudFutureView(
                  key: ValueKey(_searchVersion),
                  future: _future!,
                  onRetry: _search,
                  builder: (_) => ListView(
                    children: [
                      if (_items.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: Text('没有找到用户'),
                          ),
                        ),
                      for (final p in _items)
                        ListTile(
                          leading: CommunityAvatar(profile: p),
                          title: Text(p['nickname'] as String),
                          subtitle: Text('ID：${p['public_id']}'),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CommunityUserPage(userId: p['id'] as String),
                            ),
                          ),
                        ),
                      if (_more)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final version = _searchVersion;
                                  final term = _searchTerm;
                                  setState(() => _busy = true);
                                  try {
                                    final rows = await _repo.searchUsers(
                                      term,
                                      offset: _items.length,
                                    );
                                    if (mounted && version == _searchVersion) {
                                      setState(() {
                                        _items.addAll(rows);
                                        _more = rows.length == 20;
                                      });
                                    }
                                  } catch (e) {
                                    if (context.mounted &&
                                        version == _searchVersion) {
                                      communityMessage(context, cloudError(e));
                                    }
                                  } finally {
                                    if (mounted && version == _searchVersion) {
                                      setState(() => _busy = false);
                                    }
                                  }
                                },
                          child: const Text('加载更多'),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );
}

class LearningNotificationsPage extends StatefulWidget {
  const LearningNotificationsPage({
    this.repository,
    this.authChanges,
    super.key,
  });
  final CommunityRepository? repository;
  final Listenable? authChanges;
  @override
  State<LearningNotificationsPage> createState() =>
      _LearningNotificationsPageState();
}

class _LearningNotificationsPageState extends State<LearningNotificationsPage>
    with WidgetsBindingObserver {
  late final CommunityRepository _repo;
  late final Listenable _authChanges;
  late Future<List<Json>> _future;
  List<Json> _items = [];
  RealtimeChannel? _channel;
  String? _authUuid;
  int _generation = 0, _loadGeneration = 0;
  bool _more = true, _busy = false;
  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? CommunityRepository();
    _authChanges = widget.authChanges ?? CloudBackend.instance;
    _authUuid = _currentUuid;
    WidgetsBinding.instance.addObserver(this);
    _authChanges.addListener(_authChanged);
    _future = _load()..ignore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authChanges.removeListener(_authChanged);
    _generation++;
    _stopListening();
    super.dispose();
  }

  String? get _currentUuid {
    try {
      return _repo.uid;
    } on CloudFailure {
      return null;
    }
  }

  bool _isCurrent(int generation, String? uuid) =>
      mounted &&
      generation == _generation &&
      uuid == _authUuid &&
      uuid == _currentUuid;

  void _stopListening() {
    final channel = _channel;
    _channel = null;
    if (channel != null) _repo.client.removeChannel(channel);
  }

  void _authChanged() {
    if (!mounted || _currentUuid == _authUuid) return;
    _generation++;
    _authUuid = _currentUuid;
    _stopListening();
    _items = [];
    _more = false;
    _busy = false;
    _reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _reload();
  }

  Future<List<Json>> _load() async {
    final generation = _generation, uuid = _authUuid;
    final request = ++_loadGeneration;
    _busy = false;
    try {
      if (uuid == null) throw const CloudFailure('请先登录智学帮');
      final rows = await _repo.notifications();
      if (!_isCurrent(generation, uuid) || request != _loadGeneration) {
        return [];
      }
      _items = rows;
      _more = rows.length == 30;
      try {
    _channel ??= _repo.client
            .channel('learning-notifications-$uuid')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'notifications',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'recipient_id',
                value: uuid,
              ),
              callback: (_) {
                if (_isCurrent(generation, uuid)) _reload();
              },
            )
            .subscribe();
      } catch (_) {
        // Realtime is an enhancement, not a dependency: if the channel
        // cannot be created, the page still shows what it already fetched.
      }
      return rows;
    } catch (e) {
      if (!_isCurrent(generation, uuid) || request != _loadGeneration) {
        return [];
      }
      if (e is AuthException || e is PostgrestException && e.code == '42501') {
        _generation++;
        _stopListening();
        _items = [];
        _more = false;
      }
      rethrow;
    }
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _future = _load()..ignore();
      });
    }
  }

  Future<void> _open(Json n) async {
    final generation = _generation, uuid = _authUuid;
    if (uuid == null || !_isCurrent(generation, uuid)) return;
    try {
      await _repo.readNotification(n['id'] as String);
      if (!mounted || !_isCurrent(generation, uuid)) return;
      if (n['question_id'] != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                QuestionDetailPage(questionId: n['question_id'] as String),
          ),
        );
      } else if (n['conversation_id'] != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ChatPage(conversationId: n['conversation_id'] as String),
          ),
        );
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const FriendsChatPage(initialIndex: 2),
          ),
        );
      }
      if (_isCurrent(generation, uuid)) _reload();
    } catch (e) {
      if (mounted && _isCurrent(generation, uuid)) {
        communityMessage(context, cloudError(e));
      }
    }
  }

  Future<void> _loadMore() async {
    final generation = _generation, uuid = _authUuid;
    final request = _loadGeneration;
    if (_busy || !_more || uuid == null || !_isCurrent(generation, uuid)) {
      return;
    }
    setState(() => _busy = true);
    try {
      final rows = await _repo.notifications(offset: _items.length);
      if (!_isCurrent(generation, uuid) || request != _loadGeneration) return;
      setState(() {
        _items.addAll(rows);
        _more = rows.length == 30;
      });
    } catch (e) {
      if (mounted &&
          _isCurrent(generation, uuid) &&
          request == _loadGeneration) {
        communityMessage(context, cloudError(e));
      }
    } finally {
      if (_isCurrent(generation, uuid) && request == _loadGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: communityBackground,
    appBar: AppBar(title: const Text('学习消息')),
    body: CloudFutureView(
      future: _future,
      onRetry: _reload,
      builder: (_) => RefreshIndicator(
        onRefresh: () async {
          _reload();
          try {
            await _future;
          } catch (_) {}
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            Row(
              children: [
                const Icon(
                  Icons.notifications_active_outlined,
                  size: 15,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '这里显示应用内通知，后台系统推送尚未配置。',
                    style: AppTextStyles.labelSmall(
                      context,
                    ).copyWith(color: AppColors.textTertiary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_items.isEmpty)
              const AppEmptyState(
                icon: Icons.notifications_none_rounded,
                title: '暂时没有学习消息',
                description: '有人回答你的问题、申请好友或私信你时，会出现在这里。',
              )
            else
              AppCard.outlined(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          indent: 64,
                          color: AppColors.borderLight,
                        ),
                      _NotificationRow(
                        notification: _items[i],
                        onTap: () => _open(_items[i]),
                      ),
                    ],
                  ],
                ),
              ),
            if (_more)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton(
                  onPressed: _busy ? null : _loadMore,
                  child: const Text('加载更多消息'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
