import 'package:flutter/material.dart';
import '../../../community/cloud_backend.dart';
import '../../../community/community_repository.dart';
import '../../../database/models/user_profile.dart';
import 'community_widgets.dart';

class AccountSecurityPage extends StatefulWidget {
  const AccountSecurityPage({required this.profile, super.key});
  final UserProfile profile;
  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  final _repo = CommunityRepository();
  String? _publicId;
  List<Json> _blocks = [];
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      List<Json> blocks = [];
      String? publicId;
      if (CloudBackend.instance.signedIn) {
        await _repo.identity.requireLinked();
        publicId = (await _repo.profile(_repo.uid))['public_id'] as String?;
        blocks = await _repo.blocks();
      }
      if (mounted) {
        setState(() {
          _publicId = publicId;
          _blocks = blocks;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = cloudError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('账号与安全')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ListTile(
          title: const Text('账号 ID'),
          subtitle: Text(
            widget.profile.username.startsWith('cloud_')
                ? _publicId ?? '暂不可用'
                : widget.profile.username,
          ),
        ),
        ListTile(
          title: const Text('昵称'),
          subtitle: Text(widget.profile.primaryName),
        ),
        ListTile(
          title: const Text('性别 / 年龄'),
          subtitle: Text(
            '${widget.profile.gender} / ${widget.profile.age ?? '未设置'}',
          ),
        ),
        ListTile(
          title: const Text('最近登录'),
          subtitle: Text(
            widget.profile.lastLoginAt?.toLocal().toString() ?? '暂无记录',
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(
            Icons.account_circle_outlined,
            color: communityBlue,
          ),
          title: const Text('登录邮箱'),
          subtitle: Text(
            CloudBackend.instance.signedIn
                ? '邮箱：${CloudBackend.instance.client?.auth.currentUser?.email ?? '已验证'}'
                : '请登录智学帮，原有学习资料已保留',
          ),
        ),
        if (!CloudBackend.instance.signedIn)
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () async {
              if (await openAppAccount(context)) await _load();
            },
            child: const Text('登录智学帮'),
          ),
        const SizedBox(height: 20),
        const Text(
          '隐私设置',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('个人知识库默认私有'),
          subtitle: Text('原始资料、OCR、飞书内容、练习、学习任务和专注记录保存在本地。仅主动发布的文字和图片进入社区。'),
        ),
        const ListTile(
          leading: Icon(Icons.image_outlined),
          title: Text('公开资料与私聊附件'),
          subtitle: Text('头像、昵称和签名用于社区展示。私聊图片仅限合法好友会话成员读取。已签发图片链接有效期为 2 分钟。'),
        ),
        const SizedBox(height: 12),
        const Text(
          '已屏蔽用户',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        if (_error != null)
          TextButton(onPressed: _load, child: Text('$_error，点击重试')),
        if (_blocks.isEmpty && _error == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text('暂无屏蔽记录', style: TextStyle(color: Colors.blueGrey)),
          ),
        for (final block in _blocks)
          ListTile(
            title: Text(
              (block['blocked_nickname'] as String?)?.trim().isNotEmpty == true
                  ? block['blocked_nickname'] as String
                  : '已屏蔽用户',
            ),
            subtitle: Text('屏蔽于 ${communityTime(block['created_at'])}'),
            trailing: TextButton(
              onPressed: () async {
                try {
                  await _repo.unblock(block['blocked_id'] as String);
                  await _load();
                } catch (e) {
                  if (context.mounted) communityMessage(context, cloudError(e));
                }
              },
              child: const Text('解除屏蔽'),
            ),
          ),
      ],
    ),
  );
}
