import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../community/cloud_backend.dart';
import '../../../community/community_repository.dart';
import '../../../community/chat_outbox_repository.dart';
import 'community_widgets.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({required this.conversationId, super.key});
  final String conversationId;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final _repo = CommunityRepository(),
      _outbox = ChatOutboxRepository(),
      _text = TextEditingController();
  late Future<bool> _future;
  RealtimeChannel? _channel;
  Timer? _poll;
  List<Json> _messages = [], _pending = [];
  final Set<String> _failed = {};
  bool _queuing = false;
  bool _sending = false,
      _paging = false,
      _more = true,
      _syncing = false,
      _foreground = true;
  String _status = '正在连接…', _title = '私聊';
  String? _syncError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _start();
    CloudBackend.instance.addListener(_authChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CloudBackend.instance.removeListener(_authChanged);
    _poll?.cancel();
    if (_channel != null) _repo.client.removeChannel(_channel!);
    _text.dispose();
    super.dispose();
  }

  void _authChanged() {
    if (!mounted) return;
    if (!CloudBackend.instance.signedIn) {
      _poll?.cancel();
      if (_channel != null) _repo.client.removeChannel(_channel!);
      setState(() {
        _messages = [];
        _pending = [];
        _syncError = '云端会话已过期，请返回账号与安全重新登录';
      });
    }
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
    await _repo.identity.requireLinked();
    final inbox = await _repo.inbox();
    final info = inbox
        .where((i) => i['id'] == widget.conversationId)
        .firstOrNull;
    if (info == null) throw const CloudFailure('会话不存在，或好友关系已变化');
    _title = (info['profile'] as Map)['nickname'] as String;
    _messages = await _repo.messages(widget.conversationId);
    _more = _messages.length == 30;
    _pending = await _outbox.pending(widget.conversationId);
    _channel ??= _repo.client
        .channel('chat-${widget.conversationId}-${_repo.uid}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (_) => _sync(),
        )
        .subscribe((status, error) {
          if (!mounted) return;
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
    // Also reconcile while foregrounded if the socket silently drops an event.
    _poll ??= Timer.periodic(const Duration(seconds: 20), (_) {
      if (_foreground && mounted && ModalRoute.of(context)?.isCurrent == true) {
        _sync();
      }
    });
    await _markRead();
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _markRead() async {
    if (_messages.isNotEmpty &&
        mounted &&
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
    if (_syncing || !mounted) return;
    _syncing = true;
    try {
      // Catch up every missing page, even after a long offline interval.
      final previous = _messages.firstOrNull?['id'];
      Json? cursor;
      var found = previous == null;
      while (true) {
        final incoming = await _repo.messages(
          widget.conversationId,
          before: cursor,
        );
        if (!mounted) return;
        if (incoming.any((m) => m['id'] == previous)) found = true;
        setState(() {
          if (_messages.isEmpty && incoming.length == 30) _more = true;
          _merge(incoming);
        });
        if (found || incoming.length < 30) break;
        cursor = incoming.last;
      }
      await _markRead();
      if (mounted) {
        setState(() {
          _status = '已同步';
          _syncError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '连接暂不可用';
          _syncError = cloudError(e);
        });
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> _history() async {
    if (_paging || !_more || _messages.isEmpty) return;
    setState(() => _paging = true);
    try {
      final rows = await _repo.messages(
        widget.conversationId,
        before: _messages.last,
      );
      if (mounted) {
        setState(() {
          _merge(rows);
          _more = rows.length == 30;
        });
      }
    } catch (e) {
      if (mounted) communityMessage(context, cloudError(e));
    } finally {
      if (mounted) setState(() => _paging = false);
    }
  }

  Future<void> _queue({ImageSource? image}) async {
    if (_queuing || _sending) return;
    setState(() => _queuing = true);
    try {
      if (image != null) {
        final file = await ImagePicker().pickImage(
          source: image,
          maxWidth: 1800,
          imageQuality: 85,
        );
        if (file == null) return;
        final bytes = await file.readAsBytes();
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
        _text.clear();
      }
      final pending = await _outbox.pending(widget.conversationId);
      if (mounted) setState(() => _pending = pending);
      await _deliver();
    } catch (e) {
      if (mounted) communityMessage(context, cloudError(e));
    } finally {
      if (mounted) setState(() => _queuing = false);
    }
  }

  Future<void> _deliver() async {
    if (_sending || !mounted) return;
    setState(() => _sending = true);
    try {
      final pending = await _outbox.pending(widget.conversationId);
      if (mounted) setState(() => _pending = pending);
      for (final item in pending) {
        if (!mounted) return;
        try {
          await _outbox.deliver(item);
          _failed.remove(item['token']);
        } catch (e) {
          _failed.add(item['token'] as String);
          if (mounted) setState(() => _syncError = cloudError(e));
        }
      }
      final remaining = await _outbox.pending(widget.conversationId);
      if (mounted) setState(() => _pending = remaining);
      await _sync();
    } catch (e) {
      if (mounted) setState(() => _syncError = cloudError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _bubble(Json item, {bool pending = false}) {
    final mine = pending || item['sender_id'] == _repo.uid;
    final token = item['token'] as String?;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .78,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFFE3EDFF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
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
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            const SizedBox(height: 6),
            Text(
              communityTime(item['created_at']),
              style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
            ),
            if (pending)
              TextButton(
                onPressed: _sending ? null : _deliver,
                child: Text(
                  _sending
                      ? '发送中…'
                      : _failed.contains(token)
                      ? '发送失败，点击重试'
                      : '等待发送，点击重试',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            if (!pending && mine)
              const Text(
                '已发送',
                style: TextStyle(fontSize: 10, color: Colors.blueGrey),
              ),
          ],
        ),
      ),
    );
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
          onPressed: () {
            _sync();
            _deliver();
          },
          icon: const Icon(Icons.sync),
        ),
      ],
    ),
    body: CloudFutureView<bool>(
      future: _future,
      onRetry: () => setState(() => _future = _start()),
      builder: (_) => Column(
        children: [
          if (_syncError != null)
            MaterialBanner(
              content: Text(_syncError!),
              actions: [
                TextButton(
                  onPressed: () {
                    _sync();
                    _deliver();
                  },
                  child: const Text('重试'),
                ),
              ],
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
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
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
