import 'package:flutter/material.dart';

import '../../../community/cloud_backend.dart';
import '../../../community/community_repository.dart';
import '../../../database/auth_repository.dart';
import '../home_page.dart';
import '../login_page.dart';

const communityBlue = Color(0xFF2870F5);
const communityBackground = Color(0xFFF4F7FC);

void communityMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));

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
          padding: const EdgeInsets.all(28),
          children: [
            const SizedBox(height: 40),
            const Icon(
              Icons.cloud_off_outlined,
              size: 44,
              color: Colors.blueGrey,
            ),
            const SizedBox(height: 16),
            Text(cloudError(s.error!), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () async {
                if (!CloudBackend.instance.configured &&
                    CloudBackend.instance.failure != null) {
                  await CloudBackend.instance.initialize();
                }
                onRetry();
              },
              child: const Text('重新加载'),
            ),
            if (!CloudBackend.instance.signedIn)
              TextButton(
                onPressed: () async {
                  if (await openAppAccount(context)) onRetry();
                },
                child: const Text('登录智学帮'),
              ),
          ],
        );
      }
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
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
              backgroundColor: const Color(0xFFE5EEFF),
              foregroundColor: communityBlue,
              child: Text(
                (profile['nickname'] as String? ?? '同学').characters.first,
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
    final n = (question['answer_count'] as num?)?.toInt() ?? 0;
    final resolved = question['accepted_answer_id'] != null;
    final state = resolved
        ? '已解决'
        : n == 0
        ? '待解答'
        : '讨论中';
    final images = (question['image_paths'] as List? ?? []);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(18),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              communityTime(question['created_at']),
                              style: const TextStyle(
                                color: Colors.blueGrey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: resolved
                            ? const Color(0xFFE9FAF2)
                            : const Color(0xFFFFF0F2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        state,
                        style: TextStyle(
                          color: resolved
                              ? const Color(0xFF12A777)
                              : const Color(0xFFE85670),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  question['title'] as String,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF12213A),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  question['body'] as String,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Color(0xFF7D889B),
                  ),
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
                if ((question['tags'] as List? ?? []).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final tag in question['tags'] as List)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDF4FF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              tag.toString(),
                              style: const TextStyle(
                                color: communityBlue,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline,
                      size: 19,
                      color: Colors.blueGrey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$n 个回答',
                      style: const TextStyle(color: Colors.blueGrey),
                    ),
                    const SizedBox(width: 22),
                    Icon(
                      question['bookmarked'] == true
                          ? Icons.star
                          : Icons.star_border,
                      size: 21,
                      color: Colors.blueGrey,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${question['bookmark_count'] ?? 0} 人收藏',
                      style: const TextStyle(color: Colors.blueGrey),
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
