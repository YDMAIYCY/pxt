import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../community/cloud_backend.dart';
import '../../../community/community_repository.dart';
import 'community_widgets.dart';
import 'question_detail_page.dart';
import 'chat_page.dart';

class CommunityUserPage extends StatefulWidget {
  const CommunityUserPage({required this.userId, super.key});
  final String userId;
  @override
  State<CommunityUserPage> createState() => _CommunityUserPageState();
}

class _CommunityUserPageState extends State<CommunityUserPage> {
  final _repo = CommunityRepository();
  late Future<Json> _future;
  List<Json> _questions = [], _answers = [];
  String _friend = 'none';
  bool _busy = false, _moreQuestions = true, _moreAnswers = true;
  @override
  void initState() {
    super.initState();
    _future = _load();
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

  void _reload() => setState(() => _future = _load());
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
    appBar: AppBar(title: const Text('同学主页')),
    body: CloudFutureView(
      future: _future,
      onRetry: _reload,
      builder: (p) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: CommunityAvatar(profile: p, size: 80)),
          const SizedBox(height: 12),
          Text(
            p['nickname'] as String,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(
            'ID：${p['public_id']}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 10),
          Text(p['bio'] as String, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (_friend != 'self')
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
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
                  child: Text(
                    {
                          'friend': '发消息',
                          'sent': '已发送申请',
                          'received': '查看好友申请',
                          'none': '添加好友',
                        }[_friend] ??
                        '添加好友',
                  ),
                ),
                if (_friend == 'friend')
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: _busy
                        ? null
                        : () =>
                              _action(() => _repo.removeFriend(widget.userId)),
                    child: const Text('删除好友'),
                  ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
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
                        },
                  child: const Text('屏蔽用户'),
                ),
              ],
            ),
          const SizedBox(height: 24),
          const Text(
            '公开问题',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
          ),
          const SizedBox(height: 12),
          if (_questions.isEmpty)
            const Text('暂无公开问题', style: TextStyle(color: Colors.blueGrey)),
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
          const SizedBox(height: 20),
          const Text(
            '公开回答',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
          ),
          if (_answers.isEmpty)
            const Text('暂无公开回答', style: TextStyle(color: Colors.blueGrey)),
          for (final a in _answers)
            Card(
              color: Colors.white,
              child: ListTile(
                title: Text(
                  (a['question'] as Map?)?['title'] as String? ?? '问题',
                ),
                subtitle: Text(
                  a['body'] as String,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuestionDetailPage(
                      questionId: a['question_id'] as String,
                    ),
                  ),
                ),
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
      ),
    ),
  );
}

class FriendsChatPage extends StatefulWidget {
  const FriendsChatPage({this.initialIndex = 0, super.key});
  final int initialIndex;
  @override
  State<FriendsChatPage> createState() => _FriendsChatPageState();
}

class _FriendsChatPageState extends State<FriendsChatPage>
    with WidgetsBindingObserver {
  final _repo = CommunityRepository();
  late Future<Json> _future;
  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _load();
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
    if (mounted) setState(() => _future = _load());
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
          ? [
              const Padding(
                padding: EdgeInsets.all(45),
                child: Center(
                  child: Text(
                    '暂无内容，去社区认识新同学吧',
                    style: TextStyle(color: Colors.blueGrey),
                  ),
                ),
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
              for (final p in (data['friends'] as List).cast<Json>())
                Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: CommunityAvatar(
                      profile: p,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CommunityUserPage(userId: p['id'] as String),
                        ),
                      ),
                    ),
                    title: Text(p['nickname'] as String),
                    subtitle: Text('ID：${p['public_id']}'),
                    trailing: const Icon(
                      Icons.chat_bubble_outline,
                      color: communityBlue,
                    ),
                    onTap: () => _chat(p['id'] as String),
                  ),
                ),
            ]),
            _list([
              for (final c in (data['inbox'] as List).cast<Json>())
                Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: CommunityAvatar(
                      profile: Json.from(c['profile'] as Map),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            (c['profile'] as Map)['nickname'] as String,
                          ),
                        ),
                        Text(
                          communityTime((c['latest'] as Map?)?['created_at']),
                          style: const TextStyle(
                            color: Colors.blueGrey,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      (c['latest'] as Map?)?['kind'] == 'image'
                          ? '[图片]'
                          : (c['latest'] as Map?)?['body'] as String? ??
                                '开始交流吧',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: (c['unread'] as num) > 0
                        ? Badge(label: Text('${c['unread']}'))
                        : null,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ChatPage(conversationId: c['id'] as String),
                        ),
                      );
                      _reload();
                    },
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

class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key});
  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final _query = TextEditingController(), _repo = CommunityRepository();
  Future<List<Json>>? _future;
  List<Json> _items = [];
  bool _more = false, _busy = false;
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    setState(
      () => _future = _repo.searchUsers(_query.text).then((rows) {
        _items = rows;
        _more = rows.length == 20;
        return rows;
      }),
    );
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
            onSubmitted: (_) => _search(),
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
                                  setState(() => _busy = true);
                                  try {
                                    final rows = await _repo.searchUsers(
                                      _query.text,
                                      offset: _items.length,
                                    );
                                    if (mounted) {
                                      setState(() {
                                        _items.addAll(rows);
                                        _more = rows.length == 20;
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
  const LearningNotificationsPage({super.key});
  @override
  State<LearningNotificationsPage> createState() =>
      _LearningNotificationsPageState();
}

class _LearningNotificationsPageState extends State<LearningNotificationsPage>
    with WidgetsBindingObserver {
  final _repo = CommunityRepository();
  late Future<List<Json>> _future;
  List<Json> _items = [];
  RealtimeChannel? _channel;
  bool _more = true, _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_channel != null) _repo.client.removeChannel(_channel!);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _reload();
  }

  Future<List<Json>> _load() async {
    final rows = await _repo.notifications();
    _items = rows;
    _more = rows.length == 30;
    _channel ??= _repo.client
        .channel('learning-notifications-${_repo.uid}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: _repo.uid,
          ),
          callback: (_) {
            if (mounted) _reload();
          },
        )
        .subscribe();
    return rows;
  }

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  Future<void> _open(Json n) async {
    try {
      await _repo.readNotification(n['id'] as String);
      if (!mounted) return;
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
      if (mounted) _reload();
    } catch (e) {
      if (mounted) communityMessage(context, cloudError(e));
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
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text(
                '这里显示应用内通知。后台系统推送尚未配置。',
                style: TextStyle(color: Colors.blueGrey, fontSize: 12),
              ),
            ),
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: Text('暂时没有学习消息')),
              ),
            for (final n in _items)
              Card(
                color: Colors.white,
                child: ListTile(
                  leading: Badge(
                    isLabelVisible: n['read_at'] == null,
                    child: CommunityAvatar(
                      profile: Json.from(n['actor'] as Map? ?? {}),
                    ),
                  ),
                  title: Text(
                    '${(n['actor'] as Map?)?['nickname'] ?? '同学'}${{'answer': '回答了你的问题', 'comment': '回复了你的讨论', 'accepted': '采纳了你的回答', 'friend_request': '申请添加你为好友', 'friend_accepted': '同意了好友申请', 'message': '发来了私信'}[n['kind']] ?? '发来一条学习消息'}',
                  ),
                  subtitle: Text(communityTime(n['created_at'])),
                  onTap: () => _open(n),
                ),
              ),
            if (_more)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          final rows = await _repo.notifications(
                            offset: _items.length,
                          );
                          if (mounted) {
                            setState(() {
                              _items.addAll(rows);
                              _more = rows.length == 30;
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
                child: const Text('加载更多消息'),
              ),
          ],
        ),
      ),
    ),
  );
}
