import 'package:flutter/material.dart';

import '../../../community/cloud_backend.dart';
import '../../../community/community_repository.dart';
import '../../../database/auth_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_kit.dart';
import '../home_page.dart';
import '../login_page.dart';

// The community carried its own near-duplicate blue (#2870F5) and off-white
// (#F4F7FC). Folded into the shared ramp so every module reads as one product.
const communityBlue = AppColors.primary;
const communityBackground = AppColors.background;

void communityMessage(BuildContext context, String message) =>
    showAppToast(context, message);

Future<bool> openAppAccount(BuildContext context) async {
  final previous = await AuthRepository().getCurrentUserProfile();
  if (!context.mounted) return false;
  final success =
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const LoginPage(returnResult: true)),
      ) ==
      true;
  if (!success || !context.mounted) return false;
  final current = await AuthRepository().getCurrentUserProfile();
  if (!context.mounted) return false;
  if (previous?.id != current?.id) {
    // Switching accounts recreates tabs so no cached personal records survive.
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(HomePage.routeName, (_) => false);
    return false;
  }
  return true;
}

Future<String?> communityPrompt(
  BuildContext context,
  String title, {
  String initial = '',
  int maxLength = 4000,
}) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 2,
        maxLines: 7,
        maxLength: maxLength,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(ctx, controller.text.trim());
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
  // Disposal after the dialog's closing animation avoids a disposed controller in flight.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return value;
}

Future<bool> confirmCommunityDelete(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除自己的内容'),
        content: const Text('删除后将无法恢复，确定删除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    ) ==
    true;

class CloudFutureView<T> extends StatelessWidget {
  const CloudFutureView({
    required this.future,
    required this.onRetry,
    required this.builder,
    super.key,
  });
  final Future<T> future;
  final VoidCallback onRetry;
  final Widget Function(T) builder;
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, s) {
      if (s.hasError) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            AppErrorState(
              title: cloudError(s.error!),
              description: '云端社区暂时不可用，可以稍后重试。',
              icon: Icons.cloud_off_outlined,
              retryLabel: '重新加载',
              onRetry: () async {
                if (!CloudBackend.instance.configured &&
                    CloudBackend.instance.failure != null) {
                  await CloudBackend.instance.initialize();
                }
                onRetry();
              },
            ),
            if (!CloudBackend.instance.signedIn)
              Center(
                child: TextButton(
                  onPressed: () async {
                    if (await openAppAccount(context)) onRetry();
                  },
                  child: const Text('登录智学帮'),
                ),
              ),
          ],
        );
      }
      if (!s.hasData) return const AppSkeletonList(items: 4, height: 96);
      return builder(s.data as T);
    },
  );
}

String communityTime(dynamic value) {
  final time = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  return '${time.month}月${time.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class CommunityImage extends StatefulWidget {
  const CommunityImage({
    required this.path,
    this.bucket = 'community-images',
    this.height = 150,
    this.width,
    super.key,
  });
  final String path, bucket;
  final double height;
  final double? width;
  @override
  State<CommunityImage> createState() => _CommunityImageState();
}

class _CommunityImageState extends State<CommunityImage> {
  late Future<String> _url;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CommunityImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.bucket != widget.bucket) _load();
  }

  void _load() {
    _url = CommunityRepository().imageUrl(widget.bucket, widget.path);
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      height: widget.height,
      width: widget.width,
      child: FutureBuilder<String>(
        future: _url,
        builder: (_, s) {
          final retry = IconButton(
            tooltip: '重新加载图片',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_load),
          );
          if (s.hasError) return retry;
          if (!s.hasData) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          return Image.network(
            s.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => retry,
            loadingBuilder: (_, child, p) => p == null
                ? child
                : const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
          );
        },
      ),
    ),
  );
}

class CommunityAvatar extends StatelessWidget {
  const CommunityAvatar({
    required this.profile,
    this.size = 42,
    this.onTap,
    super.key,
  });
  final Json profile;
  final double size;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(size),
    child: ClipOval(
      child: profile['avatar_path'] != null
          ? CommunityImage(
              path: profile['avatar_path'] as String,
              bucket: 'profile-images',
              height: size,
              width: size,
            )
          : CircleAvatar(
              radius: size / 2,
              backgroundColor: AppColors.tintOf(AppColors.primary, 0.14),
              foregroundColor: communityBlue,
              child: Text(
                (profile['nickname'] as String? ?? '同学').characters.first,
                style: AppTextStyles.title(context).copyWith(
                  color: communityBlue,
                  fontSize: size * 0.4,
                ),
              ),
            ),
    ),
  );
}

class CommunityQuestionCard extends StatelessWidget {
  const CommunityQuestionCard({
    required this.question,
    required this.onTap,
    required this.onProfile,
    super.key,
  });
  final Json question;
  final VoidCallback onTap, onProfile;

  @override
  Widget build(BuildContext context) {
    final p = Json.from(question['profile'] as Map? ?? {});
    final answers = (question['answer_count'] as num?)?.toInt() ?? 0;
    final resolved = question['accepted_answer_id'] != null;
    // Status carries its own accent instead of a flat tint, so "已解决 / 待解答 /
    // 讨论中" is readable at a glance in a long feed.
    final (stateLabel, stateAccent, stateIcon) = resolved
        ? ('已解决', AppColors.success, Icons.check_circle_rounded)
        : answers == 0
        ? ('待解答', AppColors.accentAmber, Icons.pending_outlined)
        : ('讨论中', AppColors.accentSky, Icons.forum_rounded);
    final images = question['image_paths'] as List? ?? const [];
    final tags = question['tags'] as List? ?? const [];
    final bookmarkCount = question['bookmark_count'] ?? 0;
    final bookmarked = question['bookmarked'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.borderLight),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CommunityAvatar(profile: p, onTap: onProfile),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: onProfile,
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
                              communityTime(question['created_at']),
                              style: AppTextStyles.caption(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppTag(
                      label: stateLabel,
                      accent: stateAccent,
                      icon: stateIcon,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  question['title'] as String,
                  style: AppTextStyles.h3(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700, height: 1.45),
                ),
                const SizedBox(height: 6),
                Text(
                  question['body'] as String,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall(context),
                ),
                if (images.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: CommunityImage(
                      path: images.first as String,
                      width: 220,
                      height: 110,
                    ),
                  ),
                if (tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final tag in tags)
                          AppTag(
                            label: tag.toString(),
                            accent: AppColors.primary,
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: AppColors.borderLight),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$answers 个回答',
                      style: AppTextStyles.labelSmall(
                        context,
                      ).copyWith(color: AppColors.textTertiary),
                    ),
                    const SizedBox(width: 18),
                    Icon(
                      bookmarked ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 17,
                      color: bookmarked
                          ? AppColors.accentAmber
                          : AppColors.textTertiary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$bookmarkCount 人收藏',
                      style: AppTextStyles.labelSmall(
                        context,
                      ).copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
