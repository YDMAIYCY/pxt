import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../community/cloud_backend.dart';
import '../../../community/community_repository.dart';
import '../../../community/chat_outbox_repository.dart';
import 'community_widgets.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    required this.conversationId,
    this.repository,
    this.outbox,
    this.authChanges,
    super.key,
  });
  final String conversationId;
  final CommunityRepository? repository;
  final ChatOutboxRepository? outbox;
  final Listenable? authChanges;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  late final CommunityRepository _repo;
  late final ChatOutboxRepository _outbox;
  late final Listenable _authChanges;
  final _text = TextEditingController();
  late Future<bool> _future;
  RealtimeChannel? _channel;
  Timer? _poll;
  List<Json> _messages = [], _pending = [];
  final Map<String, String> _sendErrors = {};
  int _generation = 0;
  String? _authUuid;
  bool _ready = false;
  bool _queuing = false;
  bool _sending = false,
      _paging = false,
      _more = true,
      _syncing = false,
      _foreground = true;
  String _status = '正在连接…', _title = '私聊';
  String? _syncError;
  Json? _peerProfile;
  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? CommunityRepository();
    _outbox = widget.outbox ?? ChatOutboxRepository(community: _repo);
    _authChanges = widget.authChanges ?? CloudBackend.instance;
    WidgetsBinding.instance.addObserver(this);
    _authChanges.addListener(_authChanged);
    _future = _start()..ignore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authChanges.removeListener(_authChanged);
    _generation++;
    _stopListening();
    _text.dispose();
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
    _poll?.cancel();
    _poll = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) _repo.client.removeChannel(channel);
  }

  void _clear() {
    _ready = false;
    _messages = [];
    _pending = [];
    _sendErrors.clear();
    _text.clear();
    _sending = _queuing = _paging = _syncing = false;
    _more = false;
    _title = '私聊';
    _syncError = null;
  }

  void _authChanged() {
    if (!mounted || _currentUuid == _authUuid) return;
    setState(() {
      _future = _start()..ignore();
    });
  }

  bool _accessError(Object error) =>
      error is AuthException ||
      error is PostgrestException &&
          (error.code == '42501' || error.code == 'PGRST301');

  void _loseAccess(String message) {
    _generation++;
    _stopListening();
    setState(() {
      _clear();
      _status = '会话不可用';
      _syncError = message;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _sync();
      _deliver();
    }
  }

  Future<bool> _start() async {
    final generation = ++_generation;
    final uuid = _authUuid = _currentUuid;
    _stopListening();
    _clear();
    _status = '正在连接…';
    try {
      if (uuid == null) {
        throw const CloudFailure('云端会话已过期，请返回账号与安全重新登录');
      }
      final linked = await _repo.identity.requireLinked();
      if (!_isCurrent(generation, uuid)) return false;
      if (linked != uuid) throw const CloudFailure('登录状态需要更新，请重新登录智学帮');
      final inbox = await _repo.inbox();
      if (!_isCurrent(generation, uuid)) return false;
      final info = inbox
          .where((i) => i['id'] == widget.conversationId)
          .firstOrNull;
      if (info == null) throw const CloudFailure('会话不存在，或好友关系已变化');
      final messages = await _repo.messages(widget.conversationId);
      if (!_isCurrent(generation, uuid)) return false;
      final pending = await _outbox.pending(widget.conversationId);
      if (!_isCurrent(generation, uuid)) return false;
      _peerProfile = Json.from(info['profile'] as Map);
      _title = _peerProfile!['nickname'] as String;
      _messages = messages;
      _more = messages.length == 30;
      _pending = pending;
      _ready = true;
      try {
        _channel ??= _repo.client
            .channel('chat-${widget.conversationId}-$uuid')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'chat_messages',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'conversation_id',
                value: widget.conversationId,
              ),
              callback: (_) {
                if (_isCurrent(generation, uuid)) _sync();
              },
            )
            .subscribe((status, error) {
              if (!_isCurrent(generation, uuid)) return;
              setState(
                () => _status = status == RealtimeSubscribeStatus.subscribed
                    ? '已连接'
                    : status == RealtimeSubscribeStatus.channelError ||
                          status == RealtimeSubscribeStatus.timedOut
                    ? '连接中断，正在重连…'
                    : '正在连接…',
              );
              if (status == RealtimeSubscribeStatus.subscribed) {
                _sync();
                _deliver();
              }
            });
      } catch (_) {
        // Realtime is an enhancement, not a dependency: if the channel
        // cannot be created, the page still shows what it already fetched.
      }
      // Also reconcile while foregrounded if the socket silently drops an event.
      _poll ??= Timer.periodic(const Duration(seconds: 20), (_) {
        if (_isCurrent(generation, uuid) &&
            _foreground &&
            ModalRoute.of(context)?.isCurrent == true) {
          _sync();
        }
      });
      await _markRead(generation, uuid);
      if (!_isCurrent(generation, uuid)) return false;
      setState(() {});
      return true;
    } catch (e) {
      if (!_isCurrent(generation, uuid)) return false;
      _generation++;
      _stopListening();
      _clear();
      rethrow;
    }
  }

  Future<void> _markRead(int generation, String? uuid) async {
    if (_isCurrent(generation, uuid) &&
        _messages.isNotEmpty &&
        _foreground &&
        ModalRoute.of(context)?.isCurrent == true) {
      await _repo.markRead(
        widget.conversationId,
        _messages.first['id'] as String,
      );
    }
  }

  void _merge(List<Json> incoming) {
    final all = {
      for (final m in [..._messages, ...incoming]) m['id'] as String: m,
    };
    _messages = all.values.toList()
      ..sort((a, b) {
        final date = (b['created_at'] as String).compareTo(
          a['created_at'] as String,
        );
        return date == 0
            ? (b['id'] as String).compareTo(a['id'] as String)
            : date;
      });
  }

  Future<void> _sync() async {
    final generation = _generation, uuid = _authUuid;
    if (!_ready || _syncing || !_isCurrent(generation, uuid)) return;
    _syncing = true;
    try {
      // RLS may return an empty message list after friendship/access is revoked.
      final inbox = await _repo.inbox();
      if (!_isCurrent(generation, uuid)) return;
      if (!inbox.any((i) => i['id'] == widget.conversationId)) {
        _loseAccess('会话不存在，或好友关系已变化');
        return;
      }
      // Catch up every missing page, even after a long offline interval.
      final previous = _messages.firstOrNull?['id'];
      Json? cursor;
      var found = previous == null;
      while (true) {
        final incoming = await _repo.messages(
          widget.conversationId,
          before: cursor,
        );
        if (!_isCurrent(generation, uuid)) return;
        if (incoming.any((m) => m['id'] == previous)) found = true;
        setState(() {
          if (_messages.isEmpty && incoming.length == 30) _more = true;
          _merge(incoming);
        });
        if (found || incoming.length < 30) break;
        cursor = incoming.last;
      }
      await _markRead(generation, uuid);
      if (_isCurrent(generation, uuid)) {
        setState(() {
          _status = '已同步';
          _syncError = null;
        });
      }
    } catch (e) {
      if (_isCurrent(generation, uuid)) {
        if (_accessError(e)) {
          _loseAccess(cloudError(e));
          return;
        }
        setState(() {
          _status = '连接暂不可用';
          _syncError = cloudError(e);
        });
      }
    } finally {
      if (_isCurrent(generation, uuid)) _syncing = false;
    }
  }

  Future<void> _history() async {
    final generation = _generation, uuid = _authUuid;
    if (!_ready ||
        !_isCurrent(generation, uuid) ||
        _paging ||
        !_more ||
        _messages.isEmpty) {
      return;
    }
    setState(() => _paging = true);
    try {
      final rows = await _repo.messages(
        widget.conversationId,
        before: _messages.last,
      );
      if (_isCurrent(generation, uuid)) {
        setState(() {
          _merge(rows);
          _more = rows.length == 30;
        });
      }
    } catch (e) {
      if (_isCurrent(generation, uuid)) {
        if (_accessError(e)) {
          _loseAccess(cloudError(e));
        } else if (mounted) {
          communityMessage(context, cloudError(e));
        }
      }
    } finally {
      if (_isCurrent(generation, uuid)) setState(() => _paging = false);
    }
  }

  Future<void> _queue({ImageSource? image}) async {
    final generation = _generation, uuid = _authUuid;
    if (!_ready || !_isCurrent(generation, uuid) || _queuing || _sending) {
      return;
    }
    setState(() => _queuing = true);
    try {
      if (image != null) {
        final file = await ImagePicker().pickImage(
          source: image,
          maxWidth: 1800,
          imageQuality: 85,
        );
        if (!_isCurrent(generation, uuid) || file == null) return;
        final bytes = await file.readAsBytes();
        if (!_isCurrent(generation, uuid)) return;
        final ext = file.name.split('.').last.toLowerCase();
        if (bytes.length > 8 * 1024 * 1024 ||
            !['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
          throw const CloudFailure('请选择小于 8 MB 的 JPG、PNG 或 WebP 图片');
        }
        await _outbox.enqueue(
          widget.conversationId,
          '',
          image: bytes,
          extension: ext,
        );
      } else {
        final body = _text.text.trim();
        if (body.isEmpty) return;
        if (body.length > 8000) throw const CloudFailure('每条消息最多 8000 字');
        await _outbox.enqueue(widget.conversationId, body);
        if (!_isCurrent(generation, uuid)) return;
        _text.clear();
      }
      if (!_isCurrent(generation, uuid)) return;
      final pending = await _outbox.pending(widget.conversationId);
      if (!_isCurrent(generation, uuid)) return;
      setState(() => _pending = pending);
      await _deliver();
    } catch (e) {
      if (_isCurrent(generation, uuid)) {
        if (_accessError(e)) {
          _loseAccess(cloudError(e));
        } else if (mounted) {
          communityMessage(context, cloudError(e));
        }
      }
    } finally {
      if (_isCurrent(generation, uuid)) setState(() => _queuing = false);
    }
  }

  Future<void> _deliver() async {
    final generation = _generation, uuid = _authUuid;
    if (!_ready || _sending || !_isCurrent(generation, uuid)) return;
    setState(() => _sending = true);
    try {
      final pending = await _outbox.pending(widget.conversationId);
      if (!_isCurrent(generation, uuid)) return;
      setState(() => _pending = pending);
      for (final item in pending) {
        if (!_isCurrent(generation, uuid)) return;
        final token = item['token'] as String;
        try {
          await _outbox.deliver(item);
          if (!_isCurrent(generation, uuid)) return;
          setState(() => _sendErrors.remove(token));
        } catch (e) {
          if (!_isCurrent(generation, uuid)) return;
          if (_accessError(e)) {
            _loseAccess(cloudError(e));
            return;
          }
          setState(() => _sendErrors[token] = cloudError(e));
        }
      }
      final remaining = await _outbox.pending(widget.conversationId);
      if (!_isCurrent(generation, uuid)) return;
      setState(() => _pending = remaining);
      await _sync();
    } catch (e) {
      if (_isCurrent(generation, uuid)) {
        if (_accessError(e)) {
          _loseAccess(cloudError(e));
        } else {
          setState(() => _syncError = cloudError(e));
        }
      }
    } finally {
      if (_isCurrent(generation, uuid)) setState(() => _sending = false);
    }
  }

  Widget _bubble(Json item, {bool pending = false}) {
    final mine = pending || item['sender_id'] == _authUuid;
    final token = item['token'] as String?;
    return Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!mine)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 8),
            child: CommunityAvatar(
              profile: _peerProfile ?? {'nickname': _title},
              size: 32,
            ),
          ),
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * .72,
            ),
            margin: const EdgeInsets.fromLTRB(8, 6, 12, 6),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: mine ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(mine ? 18 : 5),
                topRight: Radius.circular(mine ? 5 : 18),
                bottomLeft: const Radius.circular(18),
                bottomRight: const Radius.circular(18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item['image_path'] != null)
                  CommunityImage(
                    path: item['image_path'] as String,
                    bucket: 'chat-images',
                    height: 180,
                    width: 220,
                  )
                else if (pending && item['image_bytes'] != null)
                  Image.memory(
                    item['image_bytes'],
                    height: 140,
                    width: 180,
                    fit: BoxFit.cover,
                  ),
                if ((item['body'] as String).isNotEmpty)
                  SelectableText(
                    item['body'] as String,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.55,
                      color: mine ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  communityTime(item['created_at']),
                  style: TextStyle(
                    fontSize: 10,
                    color: mine
                        ? const Color(0xFFD7E3FF)
                        : AppColors.textTertiary,
                  ),
                ),
                if (pending)
                  TextButton(
                    onPressed: _sending ? null : _deliver,
                    child: Text(
                      _sending
                          ? '发送中…'
                          : _sendErrors.containsKey(token)
                          ? '发送失败，点击重试'
                          : '等待发送，点击重试',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                if (pending && _sendErrors.containsKey(token))
                  Text(
                    _sendErrors[token]!,
                    style: const TextStyle(fontSize: 11, color: Colors.red),
                  ),
                if (!pending && mine)
                  Text(
                    '已发送',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFD7E3FF),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _retry() {
    if (!_ready) {
      setState(() {
        _future = _start()..ignore();
      });
      return;
    }
    _sync();
    _deliver();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: communityBackground,
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_title),
          Text(
            _status,
            style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '重新同步',
          onPressed: _retry,
          icon: const Icon(Icons.sync),
        ),
      ],
    ),
    body: CloudFutureView<bool>(
      future: _future,
      onRetry: () => setState(() {
        _future = _start()..ignore();
      }),
      builder: (_) => Column(
        children: [
          if (_syncError != null)
            MaterialBanner(
              content: Text(_syncError!),
              actions: [TextButton(onPressed: _retry, child: const Text('重试'))],
            ),
          Expanded(
            child: ListView(
              reverse: true,
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                for (final p in _pending.reversed)
                  if (!_messages.any((m) => m['client_token'] == p['token']))
                    _bubble(p, pending: true),
                for (final m in _messages) _bubble(m),
                if (_more)
                  TextButton(
                    onPressed: _paging ? null : _history,
                    child: Text(_paging ? '正在加载…' : '查看更早消息'),
                  ),
                if (_messages.isEmpty && _pending.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: Text(
                        '从一句问候开始吧',
                        style: TextStyle(color: Colors.blueGrey),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.borderLight)),
              ),
              padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PopupMenuButton<ImageSource>(
                    enabled: !_queuing && !_sending,
                    tooltip: '发送图片',
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: communityBlue,
                    ),
                    onSelected: (source) => _queue(image: source),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: ImageSource.gallery,
                        child: Text('从相册选择'),
                      ),
                      PopupMenuItem(
                        value: ImageSource.camera,
                        child: Text('拍照'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: '发送消息',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _queue(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: _queuing || _sending ? null : () => _queue(),
                    child: const Text('发送'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
