import 'package:flutter/material.dart';
import '../../../community/cloud_backend.dart';
import '../../../community/community_repository.dart';
import '../../../database/models/user_profile.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_kit.dart';
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
  Widget build(BuildContext context) {
    final signedIn = CloudBackend.instance.signedIn;
    final accountId = widget.profile.username.startsWith('cloud_')
        ? _publicId ?? '暂不可用'
        : widget.profile.username;
    return Scaffold(
      appBar: AppBar(title: const Text('账号与安全')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          AppCard.plain(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSectionHeader(
                  title: '账号信息',
                  accent: AppColors.primary,
                ),
                const SizedBox(height: 4),
                _InfoRow(label: '账号 ID', value: accountId),
                _InfoRow(label: '昵称', value: widget.profile.primaryName),
                _InfoRow(
                  label: '性别 / 年龄',
                  value:
                      '${widget.profile.gender} / ${widget.profile.age ?? '未设置'}',
                ),
                _InfoRow(
                  label: '最近登录',
                  value:
                      widget.profile.lastLoginAt?.toLocal().toString() ??
                      '暂无记录',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard.plain(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSectionHeader(
                  title: '登录邮箱',
                  accent: AppColors.accentSky,
                ),
                const SizedBox(height: 10),
                Text(
                  signedIn
                      ? '邮箱：${CloudBackend.instance.client?.auth.currentUser?.email ?? '已验证'}'
                      : '请登录智学帮，原有学习资料已保留',
                  style: AppTextStyles.bodySmall(context),
                ),
                if (!signedIn) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () async {
                      if (await openAppAccount(context)) await _load();
                    },
                    child: const Text('登录智学帮'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard.outlined(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSectionHeader(
                  title: '隐私设置',
                  accent: AppColors.success,
                ),
                const SizedBox(height: 12),
                const _PrivacyRow(
                  icon: Icons.lock_outline_rounded,
                  title: '个人知识库默认私有',
                  body: '原始资料、OCR、飞书内容、练习、学习任务和专注记录保存在本地。仅主动发布的文字和图片进入社区。',
                ),
                const SizedBox(height: 12),
                const _PrivacyRow(
                  icon: Icons.image_outlined,
                  title: '公开资料与私聊附件',
                  body: '头像、昵称和签名用于社区展示。私聊图片仅限合法好友会话成员读取。已签发图片链接有效期为 2 分钟。',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard.outlined(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSectionHeader(
                  title: '已屏蔽用户',
                  accent: AppColors.accentRose,
                ),
                const SizedBox(height: 6),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: TextButton(
                      onPressed: _load,
                      child: Text('$_error，点击重试'),
                    ),
                  ),
                if (_blocks.isEmpty && _error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      '暂无屏蔽记录',
                      style: AppTextStyles.bodySmall(context),
                    ),
                  ),
                for (final block in _blocks)
                  AppListRow(
                    dense: true,
                    icon: Icons.block_rounded,
                    accent: AppColors.accentRose,
                    title:
                        (block['blocked_nickname'] as String?)?.trim().isNotEmpty ==
                            true
                        ? block['blocked_nickname'] as String
                        : '已屏蔽用户',
                    subtitle: '屏蔽于 ${communityTime(block['created_at'])}',
                    trailing: TextButton(
                      onPressed: () async {
                        try {
                          await _repo.unblock(block['blocked_id'] as String);
                          await _load();
                        } catch (e) {
                          if (context.mounted) {
                            communityMessage(context, cloudError(e));
                          }
                        }
                      },
                      child: const Text('解除屏蔽'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Label on the left, value right-aligned in ink: a read-only info row, which
/// reads as data rather than as a tappable setting.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: AppTextStyles.labelSmall(
              context,
            ).copyWith(color: AppColors.textTertiary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTextStyles.bodySmall(
              context,
            ).copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _PrivacyRow extends StatelessWidget {
  const _PrivacyRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.tintOf(AppColors.success, 0.12),
          borderRadius: BorderRadius.circular(AppRadii.chipSmall),
          border: Border.all(color: AppColors.tintOf(AppColors.success, 0.18)),
        ),
        child: Icon(icon, size: 18, color: AppColors.success),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.title(context)),
            const SizedBox(height: 3),
            Text(body, style: AppTextStyles.caption(context)),
          ],
        ),
      ),
    ],
  );
}
