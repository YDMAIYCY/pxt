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
  const CommunityUserPage({required this.userId, this.repository, super.key});
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

  VoidCallback? get _primaryAction => switch (_friend) {
    'friend' => _chat,
    'received' => () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FriendsChatPage(initialIndex: 2),
      ),
    ),
    'sent' => null,
    _ => () => _action(() => _repo.sendRequest(widget.userId)),
  };

  Future<void> _block() async {
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
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('屏蔽'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await _action(() async {
        await _repo.block(widget.userId);
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> _loadMoreQuestions() async {
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
      if (mounted) communityMessage(context, cloudError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadMoreAnswers() async {
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
      if (mounted) communityMessage(context, cloudError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
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
                await _block();
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
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          _ProfileHeader(
            profile: p,
            friend: _friend,
            busy: _busy,
            questionCount: _questions.length,
            answerCount: _answers.length,
            onPrimary: _primaryAction,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                    Center(
                      child: TextButton(
                        onPressed: _busy ? null : _loadMoreQuestions,
                        child: const Text('更多公开问题'),
                      ),
                    ),
                ],
                const SizedBox(height: AppSpacing.sectionGap),
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
                                (a['question'] as Map?)?['title'] as String? ??
                                '问题',
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
                    Center(
                      child: TextButton(
                        onPressed: _busy ? null : _loadMoreAnswers,
                        child: const Text('更多公开回答'),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// The identity block of a classmate page.
///
/// A centred white card made every profile look like a placeholder business
/// card. This one borrows the language of a social profile: a tinted cover with
/// oversized ring marks, the avatar breaking out of it, then left-aligned
/// identity, counts and one action.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.friend,
    required this.busy,
    required this.questionCount,
    required this.answerCount,
    required this.onPrimary,
  });

  final Json profile;
  final String friend;
  final bool busy;
  final int questionCount;
  final int answerCount;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    final bio = (profile['bio'] as String? ?? '').trim();
    final self = friend == 'self';
    final label = {
          'friend': '发消息',
          'sent': '已发送申请',
          'received': '查看好友申请',
          'none': '添加好友',
        }[friend] ??
        '添加好友';
    final icon = friend == 'friend'
        ? Icons.chat_bubble_rounded
        : friend == 'received'
        ? Icons.mark_email_unread_rounded
        : Icons.person_add_alt_1_rounded;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.tintOf(AppColors.primary, 0.15),
            AppColors.tintOf(AppColors.accentViolet, 0.07),
            communityBackground,
          ],
          stops: const [0, 0.58, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -52,
            top: -64,
            child: IgnorePointer(
              child: Container(
                width: 176,
                height: 176,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.surface.withValues(alpha: 0.6),
                    width: 22,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 104,
            top: 30,
            child: IgnorePointer(
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.22),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surface,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.ink.withValues(alpha: 0.10),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: CommunityAvatar(profile: profile, size: 72),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile['nickname'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.h1(
                                context,
                              ).copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'ID ${profile['public_id']}',
                              style: AppTextStyles.caption(
                                context,
                              ).copyWith(letterSpacing: 0.2),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _ProfileStat(count: questionCount, label: '问题'),
                                const SizedBox(width: 16),
                                _ProfileStat(count: answerCount, label: '回答'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    bio,
                    style: AppTextStyles.bodySmall(
                      context,
                    ).copyWith(height: 1.55),
                  ),
                ],
                if (!self) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 46),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.button),
                      ),
                    ),
                    onPressed: busy ? null : onPrimary,
                    icon: Icon(icon, size: 18),
                    label: Text(label),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.count, required this.label});
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(
        '$count',
        style: AppTextStyles.label(
          context,
        ).copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
      ),
      const SizedBox(width: 3),
      Text(label, style: AppTextStyles.caption(context)),
    ],
  );
}

class FriendsChatPage extends StatefulWidget {
  const FriendsChatPage({this.initialIndex = 0, this.repository, super.key});
  final int initialIndex;
  final CommunityRepository? repository;
  @override
  State<FriendsChatPage> createState() => _FriendsChatPageState();
}

class _FriendsChatPageState extends State<FriendsChatPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final _repo = widget.repository ?? CommunityRepository();
  late final TabController _tabs;
  late Future<Json> _future;
  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialIndex,
    )..addListener(_onTabChanged);
    _future = _load()..ignore();
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging && mounted) setState(() {});
    if (_tabs.indexIsChanging && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
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
            if (status == RealtimeSubscribeStatus.subscribed) {
              _scheduleReload();
            }
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

  Future<void> _openSearch() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UserSearchPage()),
    );
    _reload();
  }

  Future<void> _openProfile(String userId) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CommunityUserPage(userId: userId, repository: _repo),
    ),
  );

  Widget _list(List<Widget> children) => RefreshIndicator(
    onRefresh: () async {
      _reload();
      try {
        await _future;
      } catch (_) {}
    },
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: children,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: communityBackground,
    appBar: AppBar(
      title: const Text('好友与聊天'),
      actions: [
        IconButton(
          tooltip: '添加好友',
          onPressed: _openSearch,
          icon: const Icon(Icons.person_add_alt_1_rounded),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: AppSegmented<int>(
            value: _tabs.index,
            onChanged: (index) => _tabs.animateTo(index),
            options: const [
              AppSegmentedOption(0, '好友'),
              AppSegmentedOption(1, '私聊'),
              AppSegmentedOption(2, '好友申请'),
            ],
          ),
        ),
      ),
    ),
    body: CloudFutureView(
      future: _future,
      onRetry: _reload,
      builder: (data) => TabBarView(
        controller: _tabs,
        children: [
          _list([
            if ((data['friends'] as List).isEmpty)
              AppEmptyState(
                icon: Icons.people_outline_rounded,
                title: '还没有好友',
                description: '搜索同学，发一条好友申请开始交流。',
                actionLabel: '添加好友',
                onAction: _openSearch,
              )
            else
              AppCard.outlined(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, p)
                        in (data['friends'] as List).cast<Json>().indexed) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          indent: 70,
                          color: AppColors.borderLight,
                        ),
                      _FriendRow(
                        profile: p,
                        onOpenProfile: () => _openProfile(p['id'] as String),
                        onChat: () => _chat(p['id'] as String),
                      ),
                    ],
                  ],
                ),
              ),
          ]),
          _list([
            if ((data['inbox'] as List).isEmpty)
              AppEmptyState(
                icon: Icons.forum_outlined,
                title: '还没有私聊',
                description: '在好友列表里点对话框就能开始一次对话。',
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
                          indent: 70,
                          color: AppColors.borderLight,
                        ),
                      _InboxRow(
                        conversation: c,
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
                    ],
                  ],
                ),
              ),
          ]),
          _list([
            if ((data['requests'] as List).isEmpty)
              AppEmptyState(
                icon: Icons.mark_email_unread_outlined,
                title: '没有好友申请',
                description: '对方同意后，申请会移入好友列表。',
              )
            else
              AppCard.outlined(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, r)
                        in (data['requests'] as List).cast<Json>().indexed) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          indent: 70,
                          color: AppColors.borderLight,
                        ),
                      _RequestRow(
                        request: r,
                        uid: _repo.uid,
                        busy: _busy,
                        onRespond: (yes) =>
                            _respond(r['id'] as String, yes),
                      ),
                    ],
                  ],
                ),
              ),
          ]),
        ],
      ),
    ),
  );
}

/// A friend row: tapping the row starts a chat, tapping the avatar opens the
/// profile. The explicit chat bubble on the right makes the primary action
/// visible instead of hiding it behind "tap the row".
class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.profile,
    required this.onOpenProfile,
    required this.onChat,
  });

  final Json profile;
  final VoidCallback onOpenProfile;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onChat,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            InkResponse(
              onTap: onOpenProfile,
              radius: 28,
              child: CommunityAvatar(profile: profile, size: 46),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile['nickname'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.title(context),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'ID ${profile['public_id']}',
                    style: AppTextStyles.caption(context),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.tintOf(AppColors.primary, 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.forum_outlined,
                size: 17,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// One friend request. Incoming pending requests get inline accept/reject;
/// everything else collapses into a single status tag, so the list stops
/// looking like a form.
class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.uid,
    required this.busy,
    required this.onRespond,
  });

  final Json request;
  final String uid;
  final bool busy;
  final ValueChanged<bool> onRespond;

  @override
  Widget build(BuildContext context) {
    final outgoing = request['sender_id'] == uid;
    final other = (outgoing ? request['recipient'] : request['sender']) as Map;
    final status = request['status'] as String? ?? 'pending';
    final pendingIncoming = status == 'pending' && !outgoing;
    final (label, accent) = switch (status) {
      'accepted' => ('已是好友', AppColors.success),
      'rejected' => ('已拒绝', AppColors.textQuiet),
      'cancelled' => ('已取消', AppColors.textQuiet),
      _ => (outgoing ? '等待对方处理' : '想加你为好友', AppColors.accentAmber),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          CommunityAvatar(profile: Json.from(other), size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  other['nickname'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title(context),
                ),
                const SizedBox(height: 4),
                Text(label, style: AppTextStyles.caption(context)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (pendingIncoming) ...[
            _MiniAction(
              label: '拒绝',
              onTap: busy ? null : () => onRespond(false),
            ),
            const SizedBox(width: 8),
            _MiniAction(
              label: '同意',
              primary: true,
              onTap: busy ? null : () => onRespond(true),
            ),
          ] else
            AppTag(label: label, accent: accent),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.label,
    this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadii.chip),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: primary ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.chip),
          border: primary ? null : Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelSmall(context).copyWith(
            color: primary ? AppColors.textOnPrimary : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
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
      'friend_request' => (
        Icons.person_add_alt_1_rounded,
        AppColors.accentViolet,
      ),
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
      color: unread
          ? AppColors.tintOf(AppColors.primary, 0.05)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            if (unread)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 3, color: AppColors.primary),
              ),
            Padding(
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
                            text:
                                '${(n['actor'] as Map?)?['nickname'] ?? '同学'}',
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
          ],
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
                              borderRadius: BorderRadius.circular(
                                AppRadii.chip,
                              ),
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
              hintText: '昵称 / ID',
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
                          leading: Tooltip(
                            message: '查看主页',
                            child: InkResponse(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CommunityUserPage(
                                    userId: p['id'] as String,
                                  ),
                                ),
                              ),
                              child: CommunityAvatar(profile: p, size: 46),
                            ),
                          ),
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

  Widget _group(String title, int unread, List<Json> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
        child: Row(
          children: [
            Text(
              title,
              style: AppTextStyles.label(context).copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 8),
            if (unread > 0)
              AppTag(label: '$unread 条未读', accent: AppColors.primary)
            else
              Text('${rows.length} 条', style: AppTextStyles.caption(context)),
          ],
        ),
      ),
      AppCard.outlined(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                const Divider(
                  height: 1,
                  indent: 64,
                  color: AppColors.borderLight,
                ),
              _NotificationRow(
                notification: rows[i],
                onTap: () => _open(rows[i]),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.sectionGap),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: communityBackground,
    appBar: AppBar(title: const Text('学习消息')),
    body: CloudFutureView(
      future: _future,
      onRetry: _reload,
      builder: (_) {
        final today = <Json>[];
        final earlier = <Json>[];
        final now = DateTime.now();
        for (final item in _items) {
          final at = DateTime.tryParse(
            item['created_at']?.toString() ?? '',
          )?.toLocal();
          if (at != null && DateUtils.isSameDay(at, now)) {
            today.add(item);
          } else {
            earlier.add(item);
          }
        }
        int unreadOf(List<Json> rows) =>
            rows.where((n) => n['read_at'] == null).length;
        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            try {
              await _future;
            } catch (_) {}
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              if (_items.isEmpty)
                const AppEmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: '暂时没有学习消息',
                  description: '有人回答、采纳或私信你时，会出现在这里。',
                )
              else ...[
                if (today.isNotEmpty) _group('今天', unreadOf(today), today),
                if (earlier.isNotEmpty)
                  _group('更早', unreadOf(earlier), earlier),
              ],
              if (_more)
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : _loadMore,
                    child: const Text('加载更多消息'),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
