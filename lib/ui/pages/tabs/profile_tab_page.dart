import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../common/app_assets.dart';
import '../../../common/profile_image_store.dart';
import '../../../database/ai_generation_repository.dart';
import '../../../database/auth_repository.dart';
import '../../../database/llm_config_repository.dart';
import '../../../database/models/ai_result_records.dart';
import '../../../database/models/llm_provider_config.dart';
import '../../../database/models/user_profile.dart';
import '../login_page.dart';

// ========== 参数配置 ==========
// 这里集中放“我的”页用到的预设项和常量。
const List<String> _genderOptions = ['保密', '女生', '男生'];

const List<_AvatarPreset> _avatarPresets = [
  _AvatarPreset(
    id: ProfilePresetIds.avatarSky,
    label: '雾蓝',
    icon: Icons.wb_cloudy_rounded,
    gradientColors: [Color(0xFF38BDF8), Color(0xFF1D4ED8)],
    foregroundColor: Colors.white,
  ),
  _AvatarPreset(
    id: ProfilePresetIds.avatarSunset,
    label: '落日',
    icon: Icons.wb_sunny_rounded,
    gradientColors: [Color(0xFFFB7185), Color(0xFFF97316)],
    foregroundColor: Colors.white,
  ),
  _AvatarPreset(
    id: ProfilePresetIds.avatarForest,
    label: '松林',
    icon: Icons.park_rounded,
    gradientColors: [Color(0xFF34D399), Color(0xFF166534)],
    foregroundColor: Colors.white,
  ),
  _AvatarPreset(
    id: ProfilePresetIds.avatarViolet,
    label: '紫雾',
    icon: Icons.auto_awesome_rounded,
    gradientColors: [Color(0xFFA78BFA), Color(0xFF6D28D9)],
    foregroundColor: Colors.white,
  ),
  _AvatarPreset(
    id: ProfilePresetIds.avatarLogo,
    label: 'Logo',
    icon: Icons.auto_stories_rounded,
    gradientColors: [Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
    foregroundColor: Color(0xFF0C4A6E),
    useLogoAsset: true,
  ),
];

const List<_BackgroundPreset> _backgroundPresets = [
  _BackgroundPreset(
    id: ProfilePresetIds.backgroundAurora,
    label: '头图',
    imageAsset: 'assets/images/3.png',
    gradientColors: [Color(0xFF111827), Color(0xFF1D4ED8), Color(0xFF38BDF8)],
    overlayOpacity: 0.34,
  ),
  _BackgroundPreset(
    id: ProfilePresetIds.backgroundCosmos,
    label: '夜色',
    gradientColors: [Color(0xFF0F172A), Color(0xFF1D4ED8), Color(0xFF7C3AED)],
    overlayOpacity: 0.38,
  ),
  _BackgroundPreset(
    id: ProfilePresetIds.backgroundMist,
    label: '薄雾',
    gradientColors: [Color(0xFF1E293B), Color(0xFF475569), Color(0xFF94A3B8)],
    overlayOpacity: 0.18,
  ),
  _BackgroundPreset(
    id: ProfilePresetIds.backgroundSunrise,
    label: '晨曦',
    gradientColors: [Color(0xFF7C2D12), Color(0xFFEA580C), Color(0xFFFBBF24)],
    overlayOpacity: 0.2,
  ),
];

// ========== 页面入口 ==========
// 个人中心主页面，承载展示和交互。
class ProfileTabPage extends StatefulWidget {
  const ProfileTabPage({super.key});

  @override
  State<ProfileTabPage> createState() => _ProfileTabPageState();
}

class _ProfileTabPageState extends State<ProfileTabPage> {
  final AuthRepository _authRepository = AuthRepository();
  final LlmConfigRepository _llmConfigRepository = LlmConfigRepository();
  final AiGenerationRepository _aiGenerationRepository =
      AiGenerationRepository();
  final ProfileImageStore _imageStore = ProfileImageStore();

  UserProfile? _profile;
  LlmProviderConfig? _llmConfig;
  StudyOverviewStats? _studyStats;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // ========== 数据读取 ==========
  // 这里放用户资料加载逻辑。
  Future<void> _loadProfile() async {
    try {
      await _authRepository.ensureInitialized();
      final currentProfile = await _authRepository.getCurrentUserProfile();
      final llmConfig = currentProfile == null
          ? null
          : await _llmConfigRepository.getByUserId(currentProfile.id);
      final studyStats = currentProfile == null
          ? null
          : await _aiGenerationRepository.fetchStudyOverviewStats(
              currentProfile.id,
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _profile = currentProfile;
        _llmConfig = llmConfig;
        _studyStats = studyStats;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      _showMessage('加载资料失败：$error');
    }
  }

  // ========== 数据保存 ==========
  // 这里放资料更新与持久化逻辑。
  Future<bool> _saveProfile(
    UserProfile profile, {
    required String successMessage,
  }) async {
    setState(() {
      _isSaving = true;
    });

    try {
      final savedProfile = await _authRepository.saveUserProfile(profile);

      if (!mounted) {
        return false;
      }

      setState(() {
        _profile = savedProfile;
      });
      _showMessage(successMessage);
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      _showMessage('保存失败：$error');
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ========== 交互逻辑 ==========
  // 这里放页面按钮行为、弹窗与跳转。
  Future<void> _editProfile() async {
    final profile = _profile;
    if (profile == null) {
      return;
    }

    final result = await Navigator.of(context).push<_ProfileEditDraft>(
      MaterialPageRoute(
        builder: (_) =>
            _EditProfilePage(profile: profile, genderOptions: _genderOptions),
      ),
    );

    if (result == null) {
      return;
    }

    await _saveProfile(
      profile.copyWith(
        displayName: result.displayName,
        bio: result.bio,
        gender: result.gender,
        age: result.age,
      ),
      successMessage: '资料已更新',
    );
  }

  Future<void> _showAvatarActions() async {
    final profile = _profile;
    if (profile == null) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ActionListSheet(
          title: '设置头像',
          description: '支持从本地相册选择，也可以恢复默认或切换预设头像。',
          actions: [
            _ActionItem(
              icon: Icons.photo_library_rounded,
              title: '从相册选择',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAvatarFromGallery();
              },
            ),
            _ActionItem(
              icon: Icons.style_rounded,
              title: '选择预设头像',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAvatarStyle();
              },
            ),
            _ActionItem(
              icon: Icons.restart_alt_rounded,
              title: '恢复默认头像',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _resetAvatarToDefault();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showBackgroundActions() async {
    final profile = _profile;
    if (profile == null) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ActionListSheet(
          title: '设置背景',
          description: '支持从本地相册选择背景图，也可切换预设背景。',
          actions: [
            _ActionItem(
              icon: Icons.photo_size_select_actual_rounded,
              title: '从相册选择',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickBackgroundFromGallery();
              },
            ),
            _ActionItem(
              icon: Icons.palette_rounded,
              title: '选择预设背景',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickBackgroundStyle();
              },
            ),
            _ActionItem(
              icon: Icons.restart_alt_rounded,
              title: '恢复默认背景',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _resetBackgroundToDefault();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showProfileMoreActions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ActionListSheet(
          title: '个人信息设置',
          description: '统一管理姓名、简介、头像、背景、性别和年龄等资料。',
          actions: [
            _ActionItem(
              icon: Icons.edit_note_rounded,
              title: '编辑个人资料',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _editProfile();
              },
            ),
            _ActionItem(
              icon: Icons.photo_filter_rounded,
              title: '设置头像',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showAvatarActions();
              },
            ),
            _ActionItem(
              icon: Icons.wallpaper_rounded,
              title: '设置背景',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showBackgroundActions();
              },
            ),
            _ActionItem(
              icon: Icons.info_outline_rounded,
              title: '账号信息',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showAccountInfo();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _editLlmConfig() async {
    final profile = _profile;
    if (profile == null) {
      return;
    }

    final currentConfig =
        _llmConfig ?? LlmProviderConfig.emptyForUser(profile.id);
    final result = await Navigator.of(context).push<LlmProviderConfig>(
      MaterialPageRoute(
        builder: (_) => _EditLlmConfigPage(config: currentConfig),
      ),
    );

    if (result == null) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final saved = await _llmConfigRepository.save(result);
      final profile = _profile;
      final latestStats = profile == null
          ? null
          : await _aiGenerationRepository.fetchStudyOverviewStats(profile.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _llmConfig = saved;
        _studyStats = latestStats;
      });
      _showMessage('AI 大模型配置已保存');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('保存 AI 配置失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _pickAvatarFromGallery() async {
    final profile = _profile;
    if (profile == null) {
      return;
    }

    final imagePath = await _imageStore.pickAndPersist(ProfileImageKind.avatar);
    if (imagePath == null) {
      return;
    }

    final oldPath = profile.avatarImagePath;
    final saved = await _saveProfile(
      profile.copyWith(avatarImagePath: imagePath),
      successMessage: '头像已更新',
    );

    if (saved) {
      await _imageStore.deleteIfManaged(oldPath);
    } else {
      await _imageStore.deleteIfManaged(imagePath);
    }
  }

  Future<void> _pickBackgroundFromGallery() async {
    final profile = _profile;
    if (profile == null) {
      return;
    }

    final imagePath = await _imageStore.pickAndPersist(
      ProfileImageKind.background,
    );
    if (imagePath == null) {
      return;
    }

    final oldPath = profile.backgroundImagePath;
    final saved = await _saveProfile(
      profile.copyWith(backgroundImagePath: imagePath),
      successMessage: '背景已更新',
    );

    if (saved) {
      await _imageStore.deleteIfManaged(oldPath);
    } else {
      await _imageStore.deleteIfManaged(imagePath);
    }
  }

  Future<void> _pickAvatarStyle() async {
    final profile = _profile;
    if (profile == null) {
      return;
    }

    final selectedAvatar = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _AvatarPickerSheet(
        currentAvatarId: profile.avatarStyle,
        presets: _avatarPresets,
        previewBuilder: (preset, size) => _AvatarView(
          profile: profile.copyWith(
            avatarStyle: preset.id,
            avatarImagePath: null,
          ),
          size: size,
        ),
      ),
    );

    if (selectedAvatar == null) {
      return;
    }

    final oldPath = profile.avatarImagePath;
    final saved = await _saveProfile(
      profile.copyWith(avatarStyle: selectedAvatar, avatarImagePath: null),
      successMessage: '头像样式已更新',
    );

    if (saved) {
      await _imageStore.deleteIfManaged(oldPath);
    }
  }

  Future<void> _pickBackgroundStyle() async {
    final profile = _profile;
    if (profile == null) {
      return;
    }

    final selectedBackground = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _BackgroundPickerSheet(
        currentBackgroundId: profile.backgroundStyle,
        presets: _backgroundPresets,
      ),
    );

    if (selectedBackground == null) {
      return;
    }

    final oldPath = profile.backgroundImagePath;
    final saved = await _saveProfile(
      profile.copyWith(
        backgroundStyle: selectedBackground,
        backgroundImagePath: null,
      ),
      successMessage: '背景样式已更新',
    );

    if (saved) {
      await _imageStore.deleteIfManaged(oldPath);
    }
  }

  Future<void> _resetAvatarToDefault() async {
    final profile = _profile;
    if (profile == null) {
      return;
    }

    final oldPath = profile.avatarImagePath;
    final saved = await _saveProfile(
      profile.copyWith(
        avatarStyle: ProfilePresetIds.defaultAvatarStyle,
        avatarImagePath: null,
      ),
      successMessage: '已恢复默认头像',
    );

    if (saved) {
      await _imageStore.deleteIfManaged(oldPath);
    }
  }

  Future<void> _resetBackgroundToDefault() async {
    final profile = _profile;
    if (profile == null) {
      return;
    }

    final oldPath = profile.backgroundImagePath;
    final saved = await _saveProfile(
      profile.copyWith(
        backgroundStyle: ProfilePresetIds.defaultBackgroundStyle,
        backgroundImagePath: null,
      ),
      successMessage: '已恢复默认背景',
    );

    if (saved) {
      await _imageStore.deleteIfManaged(oldPath);
    }
  }

  Future<void> _showAccountInfo() async {
    final profile = _profile;
    if (profile == null) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _AccountInfoSheet(profile: profile),
    );
  }

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确认退出当前账号吗？退出后将返回登录页。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );

    if (shouldLogout != true) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _authRepository.logoutCurrentUser();

      if (!mounted) {
        return;
      }

      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(LoginPage.routeName, (route) => false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('退出失败：$error');
      setState(() {
        _isSaving = false;
      });
    }
  }

  // ========== 视图构建 ==========
  // 这里放页面结构与样式组件拼装。
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final profile = _profile;
    if (profile == null) {
      return _ProfileUnavailableState(onRetry: _loadProfile);
    }

    return Stack(
      children: [
        IgnorePointer(
          ignoring: _isSaving,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 100),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeroHeader(context, profile),
                      Transform.translate(
                        offset: const Offset(0, -28),
                        child: _buildSettingsSection(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isSaving)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildHeroSection(BuildContext context, UserProfile profile) {
    final backgroundPreset = _backgroundPresetFor(profile.backgroundStyle);
    final textTheme = Theme.of(context).textTheme;
    final genderIcon = profile.gender == '男生'
        ? Icons.male_rounded
        : profile.gender == '女生'
        ? Icons.female_rounded
        : Icons.shield_outlined;
    final ageLabel = profile.age == null ? '年龄未设置' : '${profile.age} 岁';

    return SizedBox(
      height: 438,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _BackgroundPreview(
            preset: backgroundPreset,
            backgroundImagePath: profile.backgroundImagePath,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.35, 1],
                colors: [
                  Colors.black.withValues(alpha: 0.10),
                  Colors.black.withValues(alpha: 0.24),
                  Colors.black.withValues(alpha: 0.68),
                ],
              ),
            ),
          ),
          Positioned(
            left: 18,
            top: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: Text(
                '我的',
                style: textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Positioned(
            right: 18,
            top: 16,
            child: _HeaderIconButton(
              icon: Icons.wallpaper_rounded,
              tooltip: '设置背景',
              onTap: _showBackgroundActions,
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _AvatarView(profile: profile, size: 96),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: _HeaderIconButton(
                            icon: Icons.camera_alt_rounded,
                            tooltip: '设置头像',
                            size: 30,
                            onTap: _showAvatarActions,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  profile.primaryName,
                                  style: textTheme.headlineMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    height: 1.05,
                                  ),
                                ),
                                _MetaChip(
                                  icon: genderIcon,
                                  label: profile.gender,
                                ),
                                _MetaChip(
                                  icon: Icons.cake_rounded,
                                  label: ageLabel,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '账号 ID: ${profile.username}',
                              style: textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Text(
                    profile.bio,
                    style: textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.96),
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '个人资料、头像和账号信息可从右上角三个点进入。',
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context, UserProfile profile) {
    final backgroundPreset = _backgroundPresetFor(profile.backgroundStyle);
    final textTheme = Theme.of(context).textTheme;
    final genderIcon = profile.gender == '男生'
        ? Icons.male_rounded
        : profile.gender == '女生'
        ? Icons.female_rounded
        : Icons.shield_outlined;
    final ageLabel = profile.age == null ? '年龄未设置' : '${profile.age} 岁';

    return SizedBox(
      height: 438,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _BackgroundPreview(
            preset: backgroundPreset,
            backgroundImagePath: profile.backgroundImagePath,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.35, 1],
                colors: [
                  Colors.black.withValues(alpha: 0.10),
                  Colors.black.withValues(alpha: 0.24),
                  Colors.black.withValues(alpha: 0.68),
                ],
              ),
            ),
          ),
          Positioned(
            right: 18,
            top: 16,
            child: _HeaderIconButton(
              icon: Icons.more_horiz_rounded,
              tooltip: '个人信息设置',
              onTap: _showProfileMoreActions,
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _AvatarView(profile: profile, size: 96),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  profile.primaryName,
                                  style: textTheme.headlineMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    height: 1.05,
                                  ),
                                ),
                                _MetaChip(
                                  icon: genderIcon,
                                  label: profile.gender,
                                ),
                                _MetaChip(
                                  icon: Icons.cake_rounded,
                                  label: ageLabel,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '账号 ID: ${profile.username}',
                              style: textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  profile.bio,
                  style: textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.96),
                    height: 1.55,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildLegacyHeroSection(BuildContext context, UserProfile profile) {
    final backgroundPreset = _backgroundPresetFor(profile.backgroundStyle);

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: SizedBox(
        height: 392,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _BackgroundPreview(
              preset: backgroundPreset,
              backgroundImagePath: profile.backgroundImagePath,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.20),
                    Colors.black.withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '我的',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  _AvatarView(profile: profile, size: 96),
                                  Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: GestureDetector(
                                      onTap: _showAvatarActions,
                                      child: Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.14,
                                              ),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.camera_alt_rounded,
                                          size: 16,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      profile.primaryName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            height: 1.1,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '账号：${profile.username}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.84,
                                            ),
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _MetaChip(
                                          icon: profile.gender == '男生'
                                              ? Icons.male_rounded
                                              : profile.gender == '女生'
                                              ? Icons.female_rounded
                                              : Icons.shield_outlined,
                                          label: profile.gender,
                                        ),
                                        _MetaChip(
                                          icon: Icons.cake_rounded,
                                          label: profile.age == null
                                              ? '年龄未设置'
                                              : '${profile.age} 岁',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            profile.bio,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  height: 1.45,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          const Spacer(),
                          Text(
                            '个人资料、头像和账号信息可从右上角三个点进入。',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.78),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection(BuildContext context) {
    final stats = _studyStats;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(34),
          bottom: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '我的学习资产',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '资料、错题和模型配置集中在这里；个人资料从右上角三个点进入。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          _SettingTile(
            icon: Icons.report_problem_rounded,
            title: '我的错题收藏',
            subtitle: stats == null
                ? '待同步'
                : '待处理 ${stats.wrongQuestionCount} 题，已掌握 ${stats.masteredQuestionCount} 题',
            onTap: () => _showMessage('请到任务页查看和处理错题'),
          ),
          _SettingTile(
            icon: Icons.collections_bookmark_rounded,
            title: '我的知识库收藏',
            subtitle: stats == null
                ? '待同步'
                : '${stats.documentCount} 份资料，${stats.generatedResultCount} 条学习成果',
            onTap: () => _showMessage('请到知识库页查看全部资料和成果'),
          ),
          _SettingTile(
            icon: Icons.auto_awesome_rounded,
            title: 'AI 大模型配置',
            subtitle: _llmConfig?.isConfigured == true
                ? '${_llmConfig!.provider.toUpperCase()} / ${_llmConfig!.effectiveModel}'
                : '填写 API Key、Base URL 和模型 ID',
            onTap: _editLlmConfig,
          ),
          _SettingTile(
            icon: Icons.info_outline_rounded,
            title: '账号信息',
            subtitle: '查看账号名和最近登录时间',
            onTap: _showAccountInfo,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('退出登录'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB91C1C),
                side: const BorderSide(color: Color(0xFFFCA5A5)),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  _BackgroundPreset _backgroundPresetFor(String backgroundStyle) {
    return _backgroundPresets.firstWhere(
      (preset) => preset.id == backgroundStyle,
      orElse: () => _backgroundPresets.first,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

// ========== 顶部视觉组件 ==========
// 这里放头像、背景预览与顶层按钮组件。
class _AvatarView extends StatelessWidget {
  const _AvatarView({required this.profile, required this.size});

  final UserProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final preset = _avatarPresets.firstWhere(
      (item) => item.id == profile.avatarStyle,
      orElse: () => _avatarPresets.first,
    );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 3,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: preset.gradientColors,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipOval(
        child: profile.avatarImagePath != null
            ? Image.file(
                File(profile.avatarImagePath!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _AvatarFallback(
                  profile: profile,
                  preset: preset,
                  size: size,
                ),
              )
            : _AvatarFallback(profile: profile, preset: preset, size: size),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({
    required this.profile,
    required this.preset,
    required this.size,
  });

  final UserProfile profile;
  final _AvatarPreset preset;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (preset.useLogoAsset)
          Padding(
            padding: EdgeInsets.all(size * 0.18),
            child: Image.asset(
              AppAssets.logoIcon,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.auto_stories_rounded,
                size: size * 0.36,
                color: preset.foregroundColor,
              ),
            ),
          )
        else
          Center(
            child: Text(
              profile.monogram,
              style: TextStyle(
                color: preset.foregroundColor,
                fontSize: size * 0.34,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        Positioned(
          right: size * 0.10,
          top: size * 0.10,
          child: Container(
            width: size * 0.24,
            height: size * 0.24,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              preset.icon,
              color: preset.foregroundColor,
              size: size * 0.14,
            ),
          ),
        ),
      ],
    );
  }
}

class _BackgroundPreview extends StatelessWidget {
  const _BackgroundPreview({required this.preset, this.backgroundImagePath});

  final _BackgroundPreset preset;
  final String? backgroundImagePath;

  @override
  Widget build(BuildContext context) {
    final hasCustomImage =
        backgroundImagePath != null && backgroundImagePath!.trim().isNotEmpty;
    final hasPresetImage = preset.imageAsset != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: preset.gradientColors,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasCustomImage)
            Image.file(
              File(backgroundImagePath!),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => hasPresetImage
                  ? Image.asset(preset.imageAsset!, fit: BoxFit.cover)
                  : const SizedBox.shrink(),
            )
          else if (hasPresetImage)
            Image.asset(
              preset.imageAsset!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            )
          else
            const SizedBox.shrink(),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.55, 1],
                colors: [
                  Colors.black.withValues(alpha: preset.overlayOpacity * 0.35),
                  Colors.black.withValues(alpha: preset.overlayOpacity * 0.18),
                  Colors.black.withValues(alpha: preset.overlayOpacity),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 42,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.24),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, size: size * 0.44, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

// ========== 设置区组件 ==========
// 这里放基础设置列表和空态展示。
class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: const Color(0xFF0F172A), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileUnavailableState extends StatelessWidget {
  const _ProfileUnavailableState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.person_off_rounded,
                size: 36,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '当前没有可展示的账号资料',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '请重新登录后再进入“我的”页。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }
}

// ========== 编辑资料页 ==========
// 这里放独立编辑页面，保存后回传草稿数据。
class _EditProfilePage extends StatefulWidget {
  const _EditProfilePage({required this.profile, required this.genderOptions});

  final UserProfile profile;
  final List<String> genderOptions;

  @override
  State<_EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<_EditProfilePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _ageController;
  late String _gender;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.displayName);
    _bioController = TextEditingController(text: widget.profile.bio);
    _ageController = TextEditingController(
      text: widget.profile.age?.toString() ?? '',
    );
    _gender = widget.profile.gender;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  void _submit() {
    final displayName = _nameController.text.trim();
    final bio = _bioController.text.trim();
    final ageText = _ageController.text.trim();

    if (displayName.isEmpty) {
      _showError('昵称不能为空');
      return;
    }

    if (displayName.length > 12) {
      _showError('昵称建议控制在 12 个字以内');
      return;
    }

    if (bio.isEmpty) {
      _showError('简介不能为空');
      return;
    }

    if (bio.length > 60) {
      _showError('简介建议控制在 60 个字以内');
      return;
    }

    int? age;
    if (ageText.isNotEmpty) {
      age = int.tryParse(ageText);
      if (age == null || age < 1 || age > 120) {
        _showError('年龄请输入 1 到 120 之间的数字');
        return;
      }
    }

    Navigator.of(context).pop(
      _ProfileEditDraft(
        displayName: displayName,
        bio: bio,
        gender: _gender,
        age: age,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑个人资料'),
        actions: [TextButton(onPressed: _submit, child: const Text('保存'))],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: _inputDecoration('昵称', '请输入你的昵称'),
                maxLength: 12,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _bioController,
                minLines: 2,
                maxLines: 3,
                maxLength: 60,
                decoration: _inputDecoration('简介', '写一句简短的自我介绍'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration('年龄', '例如 18'),
              ),
              const SizedBox(height: 14),
              Text(
                '性别',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: widget.genderOptions.map((option) {
                  return ChoiceChip(
                    label: Text(option),
                    selected: _gender == option,
                    onSelected: (_) {
                      setState(() {
                        _gender = option;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('保存资料'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hintText) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF0C4A6E), width: 1.5),
      ),
    );
  }
}

class _EditLlmConfigPage extends StatefulWidget {
  const _EditLlmConfigPage({required this.config});

  final LlmProviderConfig config;

  @override
  State<_EditLlmConfigPage> createState() => _EditLlmConfigPageState();
}

class _EditLlmConfigPageState extends State<_EditLlmConfigPage> {
  late final TextEditingController _providerController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _maxTokensController;

  @override
  void initState() {
    super.initState();
    _providerController = TextEditingController(
      text: widget.config.provider == LlmProvider.custom
          ? ''
          : widget.config.provider,
    );
    _apiKeyController = TextEditingController(text: widget.config.apiKey);
    _baseUrlController = TextEditingController(text: widget.config.baseUrl);
    _modelController = TextEditingController(text: widget.config.model);
    _maxTokensController = TextEditingController(
      text: widget.config.effectiveMaxTokens.toString(),
    );
  }

  @override
  void dispose() {
    _providerController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  void _submit() {
    final provider = _providerController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();
    if (apiKey.isEmpty) {
      _showError('请填写 API Key');
      return;
    }
    if (baseUrl.isEmpty) {
      _showError('请填写 Base URL');
      return;
    }
    if (model.isEmpty) {
      _showError('请填写模型 ID');
      return;
    }

    final maxTokens = int.tryParse(_maxTokensController.text.trim());
    if (maxTokens == null || maxTokens < 512) {
      _showError('最大输出 Token 至少为 512');
      return;
    }

    Navigator.of(context).pop(
      widget.config.copyWith(
        provider: provider.isEmpty ? LlmProvider.custom : provider,
        apiMode: LlmApiMode.openAiCompatible,
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
        maxTokens: maxTokens,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('AI 大模型配置'),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF0B1324),
        actions: [TextButton(onPressed: _submit, child: const Text('保存'))],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            Text(
              '通用大模型',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '这里按 OpenAI-compatible 接口调用。你填哪个服务商的 Base URL、API Key 和模型 ID，AI 生成结果就调用哪个模型。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF64748B),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _providerController,
              decoration: _llmInputDecoration(
                '服务商名称',
                '例如 kimi、deepseek、openai',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              obscureText: true,
              decoration: _llmInputDecoration('API Key', '粘贴你的 API Key'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baseUrlController,
              decoration: _llmInputDecoration(
                'Base URL',
                '例如 https://api.moonshot.cn/v1',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              decoration: _llmInputDecoration(
                '模型 ID',
                '例如 kimi-k2.5、deepseek-chat',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _maxTokensController,
              keyboardType: TextInputType.number,
              decoration: _llmInputDecoration('最大输出 Token', '4096'),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save_rounded),
              label: const Text('保存 AI 配置'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _llmInputDecoration(String label, String hintText) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF0C4A6E), width: 1.5),
      ),
    );
  }
}

// ========== 底部面板 ==========
// 这里放头像/背景选择、账号信息等弹层组件。
class _SheetContainer extends StatelessWidget {
  const _SheetContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.only(top: 48),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: child,
      ),
    );
  }
}

class _ActionListSheet extends StatelessWidget {
  const _ActionListSheet({
    required this.title,
    required this.description,
    required this.actions,
  });

  final String title;
  final String description;
  final List<_ActionItem> actions;

  @override
  Widget build(BuildContext context) {
    return _SheetContainer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            ...actions.map(
              (action) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ActionTile(item: action),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.item});

  final _ActionItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  item.icon,
                  color: const Color(0xFF0F172A),
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarPickerSheet extends StatelessWidget {
  const _AvatarPickerSheet({
    required this.currentAvatarId,
    required this.presets,
    required this.previewBuilder,
  });

  final String currentAvatarId;
  final List<_AvatarPreset> presets;
  final Widget Function(_AvatarPreset preset, double size) previewBuilder;

  @override
  Widget build(BuildContext context) {
    return _SheetContainer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '选择预设头像',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '如果你不想用本地头像，可以选择这里的预设样式。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 18),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: presets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.84,
              ),
              itemBuilder: (context, index) {
                final preset = presets[index];
                final isSelected = preset.id == currentAvatarId;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(preset.id),
                    borderRadius: BorderRadius.circular(20),
                    child: Ink(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFE0F2FE)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF0EA5E9)
                              : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          previewBuilder(preset, 58),
                          const SizedBox(height: 10),
                          Text(
                            preset.label,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundPickerSheet extends StatelessWidget {
  const _BackgroundPickerSheet({
    required this.currentBackgroundId,
    required this.presets,
  });

  final String currentBackgroundId;
  final List<_BackgroundPreset> presets;

  @override
  Widget build(BuildContext context) {
    return _SheetContainer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '选择预设背景',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '没有本地背景图时，会使用这里选择的默认背景。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 18),
            ...presets.map((preset) {
              final isSelected = preset.id == currentBackgroundId;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(preset.id),
                    borderRadius: BorderRadius.circular(22),
                    child: Ink(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF0EA5E9)
                              : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 116,
                            height: 74,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: _BackgroundPreview(preset: preset),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  preset.label,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  isSelected ? '当前使用中' : '点击切换这个背景',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF64748B),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF0EA5E9),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _AccountInfoSheet extends StatelessWidget {
  const _AccountInfoSheet({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final lastLoginText = profile.lastLoginAt == null
        ? '暂无记录'
        : '${profile.lastLoginAt!.year}-${profile.lastLoginAt!.month.toString().padLeft(2, '0')}-${profile.lastLoginAt!.day.toString().padLeft(2, '0')} '
              '${profile.lastLoginAt!.hour.toString().padLeft(2, '0')}:${profile.lastLoginAt!.minute.toString().padLeft(2, '0')}';

    return _SheetContainer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '账号信息',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            _InfoRow(label: '昵称', value: profile.primaryName),
            _InfoRow(label: '账号', value: profile.username),
            _InfoRow(label: '性别', value: profile.gender),
            _InfoRow(
              label: '年龄',
              value: profile.age == null ? '未设置' : '${profile.age} 岁',
            ),
            _InfoRow(label: '最近登录', value: lastLoginText),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 74,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== 局部模型 ==========
// 这里放页面内部用的小型模型结构。
class _ProfileEditDraft {
  const _ProfileEditDraft({
    required this.displayName,
    required this.bio,
    required this.gender,
    required this.age,
  });

  final String displayName;
  final String bio;
  final String gender;
  final int? age;
}

class _ActionItem {
  const _ActionItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
}

class _AvatarPreset {
  const _AvatarPreset({
    required this.id,
    required this.label,
    required this.icon,
    required this.gradientColors,
    required this.foregroundColor,
    this.useLogoAsset = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<Color> gradientColors;
  final Color foregroundColor;
  final bool useLogoAsset;
}

class _BackgroundPreset {
  const _BackgroundPreset({
    required this.id,
    required this.label,
    required this.gradientColors,
    this.imageAsset,
    this.overlayOpacity = 0.2,
  });

  final String id;
  final String label;
  final List<Color> gradientColors;
  final String? imageAsset;
  final double overlayOpacity;
}
