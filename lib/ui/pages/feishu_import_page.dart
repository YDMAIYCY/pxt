import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../database/app_database.dart';
import '../../feishu/feishu_client.dart';
import '../../feishu/feishu_controller.dart';
import '../../feishu/feishu_selection.dart';
import '../theme/app_theme.dart';
import '../widgets/feishu_logo.dart';
import 'feishu_import_confirm_page.dart';
import 'feishu_job_page.dart';

class FeishuImportPage extends StatefulWidget {
  const FeishuImportPage({
    required this.userId,
    this.database,
    this.client,
    this.initialFolder,
    this.returnAfterConnection = false,
    super.key,
  });
  final int userId;
  final AppDatabase? database;
  final FeishuClient? client;
  final String? initialFolder;
  final bool returnAfterConnection;
  @override
  State<FeishuImportPage> createState() => _FeishuImportPageState();
}

class _FeishuImportPageState extends State<FeishuImportPage>
    with WidgetsBindingObserver {
  late final controller = widget.client == null
      ? FeishuController.forUser(widget.userId, database: widget.database)
      : FeishuController(
          userId: widget.userId,
          database: widget.database,
          client: widget.client,
        );
  final selection = FeishuSelection();
  final roots = <String, List<String>>{'drive': [], 'wiki': []};
  final cursors = <String, String?>{};
  final more = <String, bool>{};
  String tab = 'drive', query = '', message = '连接飞书账号后选择真实资料。';
  bool foldersOnly = false, busy = false, checking = false;
  Timer? poll;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    selection.addListener(_changed);
    controller.addListener(_changed);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await controller.initialize();
      if (controller.client.hasSession) await _check();
    } catch (error) {
      if (mounted) setState(() => message = '初始化失败：$error');
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    poll?.cancel();
    selection.removeListener(_changed);
    selection.dispose();
    controller.removeListener(_changed);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        controller.client.hasSession &&
        !controller.connected) {
      unawaited(_check());
    }
  }

  Future<void> _action(Future<void> Function() fn) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await fn();
    } catch (error) {
      if (error is FeishuException && error.statusCode == 401) {
        await controller.expire();
      }
      if (mounted) setState(() => message = '$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _connect() => _action(() async {
    poll?.cancel();
    final url = await controller.client.connect();
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw StateError('无法打开授权浏览器');
    }
    if (mounted) setState(() => message = '请在浏览器同意授权，看到成功提示后返回 App。');
    poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  });
  Future<void> _check() async {
    if (checking) return;
    checking = true;
    try {
      await controller.checkConnection();
      if (!mounted) return;
      if (controller.connected) {
        poll?.cancel();
        if (widget.returnAfterConnection) {
          Navigator.pop(context);
          return;
        }
        message = '已连接真实飞书账号';
        if (roots[tab]!.isEmpty) await _load();
      } else if (controller.connection?['status'] == 'failed') {
        poll?.cancel();
        message = '${controller.connection?['error']}';
      }
      _changed();
    } catch (error) {
      poll?.cancel();
      if (mounted) setState(() => message = '$error');
    } finally {
      checking = false;
    }
  }

  Future<void> _load({FeishuResource? node, bool next = false}) async {
    if (node?.loadState == 'loading') return;
    if (!controller.connected) return;
    final group = node == null
        ? tab
        : node.kind == 'wiki' || node.spaceId.isNotEmpty
        ? 'wiki'
        : 'drive';
    final bucket = node?.key ?? group;
    if (node != null) {
      node.loadState = 'loading';
      node.error = null;
    }
    _changed();
    try {
      final result = await controller.client.request(
        'GET',
        '/resources',
        query: {
          'kind': group,
          if (node != null) 'parent_key': node.key,
          if (node != null && node.kind != 'wiki') 'parent_id': node.id,
          if (node?.kind == 'wiki') 'space_id': node!.id,
          if (node != null && node.kind != 'wiki' && node.spaceId.isNotEmpty)
            'space_id': node.spaceId,
          if (next && cursors[bucket] != null) 'page_token': cursors[bucket]!,
        },
      );
      final items = (result['items'] as List).cast<Map<String, dynamic>>();
      selection.add(items.map(FeishuResource.new).toList());
      await controller.repository.cache(widget.userId, items);
      final destination = node?.children ?? roots[group]!;
      if (!next) destination.clear();
      for (final item in items) {
        if (!destination.contains(item['key'])) {
          destination.add(item['key'] as String);
        }
      }
      cursors[bucket] = result['page_token'] as String?;
      more[bucket] = result['has_more'] == true;
      if (node != null) {
        node.loadState = 'loaded';
        node.accessible = true;
        node.hasMore = more[bucket]!;
      }
    } catch (error) {
      if (node != null) {
        node.loadState = 'failed';
        node.error = '$error';
        node.accessible =
            !(error is FeishuException &&
                [403, 404].contains(error.statusCode));
      } else {
        message = '$error';
      }
      if (error is FeishuException && error.statusCode == 401) {
        await controller.expire();
      }
    }
    if (node != null) {
      try {
        await controller.repository.cache(widget.userId, [
          {
            ...node.data,
            'load_state': node.loadState,
            'accessible': node.accessible,
            'has_more': node.hasMore,
            'error': node.error,
          },
        ]);
      } catch (error) {
        message = '资源缓存失败：$error';
      }
    }
    _changed();
  }

  Future<void> _expand(FeishuResource node) async {
    if (!node.hasChildren) return;
    node.expanded = !node.expanded;
    _changed();
    if (node.expanded && !{'loaded', 'loading'}.contains(node.loadState)) {
      await _load(node: node);
    }
  }

  Future<void> _openUrl() async {
    final field = TextEditingController(text: widget.initialFolder ?? '');
    final input = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开分享文件夹'),
        content: TextField(
          controller: field,
          decoration: const InputDecoration(hintText: '文件夹 URL / Token'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('打开'),
          ),
        ],
      ),
    );
    field.dispose();
    if (input == null) return;
    await _action(() async {
      final uri = Uri.tryParse(input.trim());
      final parts = uri?.pathSegments.where((p) => p.isNotEmpty).toList() ?? [];
      final id = uri?.hasScheme == true
          ? (uri!.scheme == 'https' &&
                    uri.host.endsWith('.feishu.cn') &&
                    parts.length == 3 &&
                    parts[0] == 'drive' &&
                    parts[1] == 'folder'
                ? parts.last
                : '')
          : input.trim();
      if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(id)) {
        throw StateError('请输入有效飞书文件夹 URL');
      }
      final meta = await controller.client.request('GET', '/folders/$id');
      final node = FeishuResource({
        'key': 'folder:$id',
        'id': id,
        'name': meta['name'],
        'kind': 'folder',
        'account_id': controller.connection!['account_id'],
        'has_children': true,
        'supported': true,
      });
      selection.add([node]);
      if (!roots['drive']!.contains(node.key)) {
        roots['drive']!.insert(0, node.key);
      }
      tab = 'drive';
      node.expanded = true;
      await _load(node: node);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F8FF),
    appBar: AppBar(title: const Text('选择飞书资料'), centerTitle: true),
    bottomNavigationBar: SafeArea(
      child: Container(
        color: Colors.white,
        // The outer Scaffold already supplies the floating dock inset via MediaQuery.
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '已选择 ${selection.rules.length} 项',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '文档数量将在确认前扫描',
                    style: AppTextStyles.caption(context),
                  ),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: AppTextStyles.label(
                  context,
                ).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              onPressed:
                  busy || selection.rules.isEmpty || !controller.connected
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FeishuImportConfirmPage(
                            controller: controller,
                            roots: selection.roots,
                          ),
                        ),
                      );
                      _changed();
                    },
              child: const Text('下一步：确认导入'),
            ),
          ],
        ),
      ),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const FeishuLogo(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  controller.connected ? '已连接飞书账号' : '尚未连接飞书账号',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: InputDecoration(
              hintText: '搜索',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const Text(
          '搜索范围：当前账号已加载节点，未加载目录不参与',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        Row(
          children: [
            for (final filter in const [
              ('drive', '云文档'),
              ('folders', '文件夹'),
              ('wiki', '知识空间'),
            ])
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    setState(() {
                      tab = filter.$1 == 'wiki' ? 'wiki' : 'drive';
                      foldersOnly = filter.$1 == 'folders';
                    });
                    if (roots[tab]!.isEmpty) await _action(() => _load());
                  },
                  child: Text(
                    filter.$2,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color:
                          (tab == 'wiki'
                              ? filter.$1 == 'wiki'
                              : foldersOnly
                              ? filter.$1 == 'folders'
                              : filter.$1 == 'drive')
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            children: [
              Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              if (!controller.connected) ...[
                FilledButton(
                  onPressed: busy ? null : _connect,
                  child: const Text('连接我的飞书账号'),
                ),
                if (controller.client.hasSession)
                  TextButton(
                    onPressed: _check,
                    child: const Text('我已授权，检查连接状态'),
                  ),
              ] else ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: busy || controller.running
                        ? null
                        : () => _action(() async {
                            poll?.cancel();
                            final revoked = await controller.disconnect();
                            selection.clear();
                            for (final list in roots.values) {
                              list.clear();
                            }
                            cursors.clear();
                            more.clear();
                            message = revoked
                                ? '已断开连接，可重新授权其他账号'
                                : '已清除本机连接；服务不可达，服务端短期会话会在到期后失效';
                          }),
                    child: const Text('断开连接'),
                  ),
                ),
                if (tab == 'drive')
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: busy ? null : _openUrl,
                      child: const Text('打开分享文件夹'),
                    ),
                  ),
                if (query.isNotEmpty)
                  for (final node in selection.nodes.values.where(
                    (n) =>
                        n.name.toLowerCase().contains(query.toLowerCase()) &&
                        (tab == 'wiki'
                            ? n.kind == 'wiki' || n.spaceId.isNotEmpty
                            : n.spaceId.isEmpty &&
                                  (!foldersOnly || n.kind == 'folder')),
                  ))
                    _row(node, 0, search: true)
                else
                  for (final key in roots[tab]!)
                    _tree(selection.nodes[key]!, 0),
                if (more[tab] == true)
                  TextButton(
                    onPressed: () => _action(() => _load(next: true)),
                    child: const Text('加载更多'),
                  ),
                if (roots[tab]!.isEmpty)
                  TextButton(
                    onPressed: () => _action(() => _load()),
                    child: const Text('暂无资源，重试加载'),
                  ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FeishuJobPage(controller: controller),
                    ),
                  ),
                  child: const Text('导入任务 / 恢复进度'),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
  Widget _tree(FeishuResource node, int depth) =>
      foldersOnly && tab == 'drive' && node.kind != 'folder'
      ? const SizedBox.shrink()
      : Column(
          children: [
            _row(node, depth),
            if (node.expanded) ...[
              if (node.loadState == 'loading') const LinearProgressIndicator(),
              if (node.error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Text(
                        node.error!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.error,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _load(node: node),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              for (final key in node.children)
                _tree(selection.nodes[key]!, depth + 1),
              if (node.hasMore)
                TextButton(
                  onPressed: () => _load(node: node, next: true),
                  child: const Text('加载更多子节点'),
                ),
            ],
          ],
        );
  Widget _row(FeishuResource node, int depth, {bool search = false}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: EdgeInsets.only(left: (depth * 14.0).clamp(0, 56)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Checkbox(
              value: selection.state(node.key),
              tristate: true,
              onChanged: !node.selectable || !node.accessible || busy
                  ? null
                  : (_) => selection.toggle(
                      node.key,
                      selection.state(node.key) != true,
                    ),
            ),
            Icon(
              node.hasChildren
                  ? Icons.folder_rounded
                  : Icons.description_rounded,
              color: const Color(0xFF83A9F5),
              size: 25,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: search ? null : () => _expand(node),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        !node.accessible
                            ? '无权读取'
                            : !node.selectable
                            ? '${node.kind} · 暂不支持导入'
                            : node.kind == 'folder'
                            ? '文件夹 · 包含下级文档'
                            : node.kind == 'wiki'
                            ? '知识空间'
                            : '新版云文档',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (node.hasChildren && !search)
              IconButton(
                onPressed: () => _expand(node),
                icon: Icon(
                  node.expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                ),
              ),
          ],
        ),
      );
}
