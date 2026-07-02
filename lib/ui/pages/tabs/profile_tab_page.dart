import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../common/app_assets.dart';
import '../../../common/profile_image_store.dart';
import '../../../database/ai_generation_repository.dart';
import '../../../database/auth_repository.dart';
import '../../../database/favorite_repository.dart';
import '../../../database/source_document_repository.dart';
import '../../../database/llm_config_repository.dart';
import '../../../database/models/ai_result_records.dart';
import '../../../database/models/llm_provider_config.dart';
import '../../../database/models/user_profile.dart';
import '../../../llm/llm_model_catalog.dart';
import '../../theme/app_theme.dart';
import '../login_page.dart';
import 'knowledge_tab_page.dart';
import 'tasks_tab_page.dart';

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
    foregroundColor: AppColors.primary,
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
    gradientColors: [Color(0xFF0F766E), Color(0xFF14B8A6), Color(0xFF99F6E4)],
    overlayOpacity: 0.2,
  ),
];

class ProfileTabPage extends StatefulWidget {
  const ProfileTabPage({
    this.authRepository,
    this.sourceDocumentRepository,
    this.llmConfigRepository,
    this.aiGenerationRepository,
    this.refreshVersion = 0,
    this.refreshListenable,
    this.activeTabListenable,
    this.tabIndex,
    this.onOpenTab,
    this.onDataChanged,
    super.key,
  });

  final AuthRepository? authRepository;
  final SourceDocumentRepository? sourceDocumentRepository;
  final LlmConfigRepository? llmConfigRepository;
  final AiGenerationRepository? aiGenerationRepository;
  final int refreshVersion;
  final ValueListenable<int>? refreshListenable;
  final ValueListenable<int>? activeTabListenable;
  final int? tabIndex;
  final ValueChanged<int>? onOpenTab;
  final VoidCallback? onDataChanged;

  @override
  State<ProfileTabPage> createState() => _ProfileTabPageState();
}

class _ProfileTabPageState extends State<ProfileTabPage> {
  late final AuthRepository _authRepository;
  late final SourceDocumentRepository _sourceDocumentRepository;
  late final LlmConfigRepository _llmConfigRepository;
  late final AiGenerationRepository _aiGenerationRepository;
  late final FavoriteRepository _favoriteRepository;
  final ProfileImageStore _imageStore = ProfileImageStore();

  UserProfile? _profile;
  LlmProviderConfig? _llmConfig;
  StudyOverviewStats? _studyStats;
  late int _handledRefreshVersion;
  bool _reloadScheduled = false;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _sourceDocumentRepository =
        widget.sourceDocumentRepository ?? SourceDocumentRepository();
    _llmConfigRepository = widget.llmConfigRepository ?? LlmConfigRepository();
    _aiGenerationRepository =
        widget.aiGenerationRepository ?? AiGenerationRepository();
    _favoriteRepository = FavoriteRepository();
    _handledRefreshVersion = widget.refreshVersion;
    widget.refreshListenable?.addListener(_handleExternalRefresh);
    widget.activeTabListenable?.addListener(_handleExternalRefresh);
    _loadProfile();
  }

  @override
  void didUpdateWidget(covariant ProfileTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_handleExternalRefresh);
      widget.refreshListenable?.addListener(_handleExternalRefresh);
    }
    if (oldWidget.activeTabListenable != widget.activeTabListenable) {
      oldWidget.activeTabListenable?.removeListener(_handleExternalRefresh);
      widget.activeTabListenable?.addListener(_handleExternalRefresh);
    }
    if (widget.refreshVersion != _handledRefreshVersion) {
      _handledRefreshVersion = widget.refreshVersion;
      _scheduleReload();
    }
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_handleExternalRefresh);
    widget.activeTabListenable?.removeListener(_handleExternalRefresh);
    super.dispose();
  }

  bool get _canHandleExternalRefresh {
    final tabIndex = widget.tabIndex;
    final activeTab = widget.activeTabListenable?.value;
    return tabIndex == null || activeTab == null || activeTab == tabIndex;
  }

  void _handleExternalRefresh() {
    if (!_canHandleExternalRefresh) return;
    _scheduleReload();
  }

  void _scheduleReload() {
    if (!mounted || _reloadScheduled) return;
    _reloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reloadScheduled = false;
      _loadProfile();
    });
  }

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
      if (!mounted) return;
      setState(() {
        _profile = currentProfile;
        _llmConfig = llmConfig;
        _studyStats = studyStats;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage('加载资料失败：$error');
    }
  }

  Future<bool> _saveProfile(
    UserProfile profile, {
    required String successMessage,
  }) async {
    setState(() => _isSaving = true);
    try {
      final savedProfile = await _authRepository.saveUserProfile(profile);
      if (!mounted) return false;
      setState(() => _profile = savedProfile);
      _showMessage(successMessage);
      return true;
    } catch (error) {
      if (!mounted) return false;
      _showMessage('保存失败：$error');
      return false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _editProfile() async {
    final profile = _profile;
    if (profile == null) return;
    final result = await Navigator.of(context).push<_ProfileEditDraft>(
      MaterialPageRoute(
        builder: (_) =>
            _EditProfilePage(profile: profile, genderOptions: _genderOptions),
      ),
    );
    if (result == null) return;
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
    if (profile == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _ActionListSheet(
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
      ),
    );
  }

  Future<void> _showBackgroundActions() async {
    final profile = _profile;
    if (profile == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _ActionListSheet(
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
      ),
    );
  }

  Future<void> _showProfileMoreActions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _ActionListSheet(
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
      ),
    );
  }

  Future<void> _editLlmConfig() async {
    final profile = _profile;
    if (profile == null) return;
    final currentConfig =
        _llmConfig ?? LlmProviderConfig.emptyForUser(profile.id);
    final result = await Navigator.of(context).push<LlmProviderConfig>(
      MaterialPageRoute(
        builder: (_) => LlmConfigEditPage(config: currentConfig),
      ),
    );
    if (result == null) return;

    setState(() => _isSaving = true);
    try {
      final saved = await _llmConfigRepository.save(result);
      final p = _profile;
      final latestStats = p == null
          ? null
          : await _aiGenerationRepository.fetchStudyOverviewStats(p.id);
      if (!mounted) return;
      setState(() {
        _llmConfig = saved;
        _studyStats = latestStats;
      });
      _showMessage('AI 大模型配置已保存');
    } catch (error) {
      if (!mounted) return;
      _showMessage('保存 AI 配置失败：$error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickAvatarFromGallery() async {
    final profile = _profile;
    if (profile == null) return;
    final imagePath = await _imageStore.pickAndPersist(ProfileImageKind.avatar);
    if (imagePath == null) return;
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
    if (profile == null) return;
    final imagePath = await _imageStore.pickAndPersist(
      ProfileImageKind.background,
    );
    if (imagePath == null) return;
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
    if (profile == null) return;
    final selectedAvatar = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
    if (selectedAvatar == null) return;
    final oldPath = profile.avatarImagePath;
    final saved = await _saveProfile(
      profile.copyWith(avatarStyle: selectedAvatar, avatarImagePath: null),
      successMessage: '头像样式已更新',
    );
    if (saved) await _imageStore.deleteIfManaged(oldPath);
  }

  Future<void> _pickBackgroundStyle() async {
    final profile = _profile;
    if (profile == null) return;
    final selectedBackground = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _BackgroundPickerSheet(
        currentBackgroundId: profile.backgroundStyle,
        presets: _backgroundPresets,
      ),
    );
    if (selectedBackground == null) return;
    final oldPath = profile.backgroundImagePath;
    final saved = await _saveProfile(
      profile.copyWith(
        backgroundStyle: selectedBackground,
        backgroundImagePath: null,
      ),
      successMessage: '背景样式已更新',
    );
    if (saved) await _imageStore.deleteIfManaged(oldPath);
  }

  Future<void> _resetAvatarToDefault() async {
    final profile = _profile;
    if (profile == null) return;
    final oldPath = profile.avatarImagePath;
    final saved = await _saveProfile(
      profile.copyWith(
        avatarStyle: ProfilePresetIds.defaultAvatarStyle,
        avatarImagePath: null,
      ),
      successMessage: '已恢复默认头像',
    );
    if (saved) await _imageStore.deleteIfManaged(oldPath);
  }

  Future<void> _resetBackgroundToDefault() async {
    final profile = _profile;
    if (profile == null) return;
    final oldPath = profile.backgroundImagePath;
    final saved = await _saveProfile(
      profile.copyWith(
        backgroundStyle: ProfilePresetIds.defaultBackgroundStyle,
        backgroundImagePath: null,
      ),
      successMessage: '已恢复默认背景',
    );
    if (saved) await _imageStore.deleteIfManaged(oldPath);
  }

  Future<void> _showAccountInfo() async {
    final profile = _profile;
    if (profile == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
    if (shouldLogout != true) return;

    setState(() => _isSaving = true);
    try {
      await _authRepository.logoutCurrentUser();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(LoginPage.routeName, (route) => false);
    } catch (error) {
      if (!mounted) return;
      _showMessage('退出失败：$error');
      setState(() => _isSaving = false);
    }
  }

  // ignore: unused_element
  Future<void> _openWrongQuestionsEntry() async {
    final onOpenTab = widget.onOpenTab;
    if (onOpenTab != null) {
      onOpenTab(3);
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskListPage(
          kind: TaskListKind.wrongQuestions,
          authRepository: _authRepository,
          sourceDocumentRepository: _sourceDocumentRepository,
          aiGenerationRepository: _aiGenerationRepository,
          onDataChanged: widget.onDataChanged,
        ),
      ),
    );
    if (mounted) {
      widget.onDataChanged?.call();
      await _loadProfile();
    }
  }

  // ignore: unused_element
  Future<void> _openKnowledgeEntry() async {
    final onOpenTab = widget.onOpenTab;
    if (onOpenTab != null) {
      onOpenTab(1);
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Knowledge')),
          body: KnowledgeTabPage(onDataChanged: widget.onDataChanged),
        ),
      ),
    );
    if (mounted) {
      widget.onDataChanged?.call();
      await _loadProfile();
    }
  }

  Future<void> _openFavoritesEntry() async {
    final profile = _profile;
    if (profile == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FavoritesPage(
          userId: profile.id,
          favoriteRepository: _favoriteRepository,
        ),
      ),
    );
    if (mounted) {
      await _loadProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final profile = _profile;
    if (profile == null) return _ProfileUnavailableState(onRetry: _loadProfile);

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
      height: 420,
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
                  Colors.black.withValues(alpha: 0.22),
                  Colors.black.withValues(alpha: 0.60),
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
            bottom: 40,
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

  Widget _buildSettingsSection(BuildContext context) {
    final stats = _studyStats;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(34),
          bottom: Radius.circular(AppRadii.card),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF111827).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('我的学习资产', style: AppTextStyles.h2(context)),
          const SizedBox(height: 6),
          Text(
            '资料、错题和模型配置集中在这里；个人资料从右上角三个点进入。',
            style: AppTextStyles.bodySmall(context),
          ),
          const SizedBox(height: 16),
          _SettingTile(
            icon: Icons.collections_bookmark_rounded,
            title: '收藏',
            subtitle: stats == null ? '待同步' : '知识卡片、错题和 AI 学习成果集中查看',
            onTap: _openFavoritesEntry,
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
                foregroundColor: AppColors.error,
                side: const BorderSide(color: Color(0xFFFCA5A5)),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button),
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

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({
    required this.userId,
    required this.favoriteRepository,
    super.key,
  });

  final int userId;
  final FavoriteRepository favoriteRepository;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  late Future<List<FavoriteCategorySummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.favoriteRepository.fetchCategorySummaries(widget.userId);
  }

  Future<void> _refresh() async {
    final future = widget.favoriteRepository.fetchCategorySummaries(
      widget.userId,
    );
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _openCategory(FavoriteCategorySummary category) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FavoriteCategoryPage(
          userId: widget.userId,
          category: category,
          favoriteRepository: widget.favoriteRepository,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('我的收藏')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<FavoriteCategorySummary>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                snapshot.data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final categories = snapshot.data ?? const [];
            if (categories.isEmpty) {
              return const _FavoriteEmptyList(text: '还没有可查看的收藏内容。');
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: categories
                  .map(
                    (category) => _SettingTile(
                      icon: _favoriteIconFor(category.iconName),
                      title: category.title,
                      subtitle: '${category.count} 条收藏',
                      onTap: () => _openCategory(category),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ),
    );
  }
}

class FavoriteCategoryPage extends StatefulWidget {
  const FavoriteCategoryPage({
    required this.userId,
    required this.category,
    required this.favoriteRepository,
    super.key,
  });

  final int userId;
  final FavoriteCategorySummary category;
  final FavoriteRepository favoriteRepository;

  @override
  State<FavoriteCategoryPage> createState() => _FavoriteCategoryPageState();
}

class _FavoriteCategoryPageState extends State<FavoriteCategoryPage> {
  late Future<List<FavoriteItemRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<FavoriteItemRecord>> _load() {
    return widget.favoriteRepository.fetchFavoritesByType(
      userId: widget.userId,
      targetType: widget.category.type,
    );
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _setNote(FavoriteItemRecord item, String note) async {
    await widget.favoriteRepository.updateFavoriteNoteOnly(
      favoriteId: item.favoriteId,
      note: note,
    );
    if (mounted) await _refresh();
  }

  Future<void> _setHighlight(FavoriteItemRecord item, String highlight) async {
    await widget.favoriteRepository.updateFavoriteHighlightOnly(
      favoriteId: item.favoriteId,
      highlightText: highlight,
    );
    if (mounted) await _refresh();
  }

  Future<void> _removeFavorite(FavoriteItemRecord item) async {
    try {
      await widget.favoriteRepository.removeFavoriteById(item.favoriteId);
    } catch (error) {
      if (mounted) _showMessage('取消收藏失败：$error');
      return;
    }
    if (!mounted) return;
    _showMessage('已取消收藏');
    try {
      await _refresh();
    } catch (_) {
      if (mounted) {
        setState(() {
          _future = Future.value(const <FavoriteItemRecord>[]);
        });
      }
    }
  }

  Future<void> _editText({
    required FavoriteItemRecord item,
    required String title,
    required String initialText,
    required ValueChanged<String> onSaved,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) =>
          _FavoriteTextDialog(title: title, initialText: initialText),
    );
    if (result != null) onSaved(result);
  }

  void _showDetail(FavoriteItemRecord item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => _FavoriteDetailSheet(
        item: item,
        onEditHighlight: () {
          Navigator.of(context).pop();
          _editText(
            item: item,
            title: '高亮重点',
            initialText: item.highlightText ?? '',
            onSaved: (value) => _setHighlight(item, value),
          );
        },
        onClearHighlight: item.highlightText?.isNotEmpty == true
            ? () {
                Navigator.of(context).pop();
                _setHighlight(item, '');
              }
            : null,
        onEditNote: () {
          Navigator.of(context).pop();
          _editText(
            item: item,
            title: '添加笔记',
            initialText: item.note ?? '',
            onSaved: (value) => _setNote(item, value),
          );
        },
        onClearNote: item.note?.isNotEmpty == true
            ? () {
                Navigator.of(context).pop();
                _setNote(item, '');
              }
            : null,
        onRemoveFavorite: () {
          Navigator.of(context).pop();
          _removeFavorite(item);
        },
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.category.title)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<FavoriteItemRecord>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                snapshot.data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data ?? const [];
            if (items.isEmpty) {
              return const _FavoriteEmptyList(text: '这里没有可查看的收藏内容。');
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: items
                  .map(
                    (item) => _FavoriteItemTile(
                      item: item,
                      onTap: () => _showDetail(item),
                      onRemove: () => _removeFavorite(item),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ),
    );
  }
}

class _FavoriteItemTile extends StatelessWidget {
  const _FavoriteItemTile({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  final FavoriteItemRecord item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
        title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(item.subtitle),
            const SizedBox(height: 6),
            Text(item.body, maxLines: 5, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            const Text(
              '点击查看完整内容',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          tooltip: '取消收藏',
          onPressed: onRemove,
          icon: const Icon(Icons.star_border_rounded),
        ),
      ),
    );
  }
}

class _FavoriteDetailSheet extends StatelessWidget {
  const _FavoriteDetailSheet({
    required this.item,
    required this.onEditHighlight,
    required this.onClearHighlight,
    required this.onEditNote,
    required this.onClearNote,
    required this.onRemoveFavorite,
  });

  final FavoriteItemRecord item;
  final VoidCallback onEditHighlight;
  final VoidCallback? onClearHighlight;
  final VoidCallback onEditNote;
  final VoidCallback? onClearNote;
  final VoidCallback onRemoveFavorite;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: AppTextStyles.h2(context)),
              const SizedBox(height: 6),
              Text(item.subtitle, style: AppTextStyles.bodySmall(context)),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.highlightText?.isNotEmpty == true)
                        _FavoriteDetailBlock(
                          title: '高亮重点',
                          text: item.highlightText!,
                        ),
                      if (item.note?.isNotEmpty == true)
                        _FavoriteDetailBlock(title: '我的笔记', text: item.note!),
                      _FavoriteDetailBlock(title: '完整内容', text: item.body),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onEditHighlight,
                    icon: const Icon(Icons.highlight_rounded),
                    label: const Text('高亮'),
                  ),
                  if (onClearHighlight != null)
                    OutlinedButton.icon(
                      onPressed: onClearHighlight,
                      icon: const Icon(Icons.format_color_reset_rounded),
                      label: const Text('取消高亮'),
                    ),
                  OutlinedButton.icon(
                    onPressed: onEditNote,
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('笔记'),
                  ),
                  if (onClearNote != null)
                    OutlinedButton.icon(
                      onPressed: onClearNote,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('删除笔记'),
                    ),
                  FilledButton.icon(
                    onPressed: onRemoveFavorite,
                    icon: const Icon(Icons.star_border_rounded),
                    label: const Text('取消收藏'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteTextDialog extends StatefulWidget {
  const _FavoriteTextDialog({required this.title, required this.initialText});

  final String title;
  final String initialText;

  @override
  State<_FavoriteTextDialog> createState() => _FavoriteTextDialogState();
}

class _FavoriteTextDialogState extends State<_FavoriteTextDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 4,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _FavoriteDetailBlock extends StatelessWidget {
  const _FavoriteDetailBlock({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.bodySmall(
              context,
            ).copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          SelectableText(text, style: AppTextStyles.body(context)),
        ],
      ),
    );
  }
}

class _FavoriteEmptyList extends StatelessWidget {
  const _FavoriteEmptyList({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: AppTextStyles.body(context),
        ),
      ],
    );
  }
}

IconData _favoriteIconFor(String name) {
  switch (name) {
    case 'wrong':
      return Icons.report_problem_rounded;
    case 'outline':
      return Icons.list_alt_rounded;
    case 'mindmap':
      return Icons.account_tree_rounded;
    case 'quiz':
      return Icons.quiz_rounded;
    default:
      return Icons.style_rounded;
  }
}

// ========== Avatar & Background views ==========
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
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

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
            width: 42,
            height: 42,
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
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

// ========== Settings section ==========
class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.cardSmall),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadii.cardSmall),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: AppTextStyles.caption(
                          context,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
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
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.person_off_rounded,
                size: 36,
                color: AppColors.primary,
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
              '请重新登录后再进入"我的"页。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }
}

// ========== Edit profile page ==========
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
                children: widget.genderOptions
                    .map(
                      (option) => ChoiceChip(
                        label: Text(option),
                        selected: _gender == option,
                        onSelected: (_) => setState(() => _gender = option),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.input),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}

// ========== LLM config page ==========
class LlmConfigEditPage extends StatefulWidget {
  const LlmConfigEditPage({super.key, required this.config});
  final LlmProviderConfig config;

  @override
  State<LlmConfigEditPage> createState() => _LlmConfigEditPageState();
}

class _LlmConfigEditPageState extends State<LlmConfigEditPage> {
  late final TextEditingController _providerController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _maxTokensController;
  List<LlmModelOption> _modelOptions = const [];
  int _selectedModelIndex = 0;
  bool _isRefreshingModels = false;
  String? _modelListMessage;

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
    _modelOptions = LlmModelCatalog.modelsFor(
      provider: _providerController.text,
      baseUrl: _baseUrlController.text,
      currentModel: _modelController.text,
    );
    _selectedModelIndex = _indexForSelectedModel(
      _modelController.text,
      _modelOptions,
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

  void _applyProviderPreset(LlmProviderPreset preset) {
    _providerController.text = preset.provider;
    _baseUrlController.text = preset.baseUrl;
    final nextOptions = LlmModelCatalog.modelsFor(
      provider: preset.provider,
      baseUrl: preset.baseUrl,
      currentModel: _modelController.text,
    );
    final nextIndex = nextOptions.isEmpty
        ? 0
        : _indexForSelectedModel(_modelController.text, nextOptions);
    final shouldSelectFirstModel =
        _modelController.text.trim().isEmpty && nextOptions.isNotEmpty;
    setState(() {
      _modelOptions = nextOptions;
      _selectedModelIndex = shouldSelectFirstModel ? 0 : nextIndex;
      if (shouldSelectFirstModel) _modelController.text = nextOptions.first.id;
      _modelListMessage = '${preset.label} 已填入默认接口地址，可继续滑动选择模型。';
    });
  }

  void _syncModelOptionsFromInputs() {
    final nextOptions = LlmModelCatalog.modelsFor(
      provider: _providerController.text,
      baseUrl: _baseUrlController.text,
      currentModel: _modelController.text,
    );
    setState(() {
      _modelOptions = nextOptions;
      _selectedModelIndex = _indexForSelectedModel(
        _modelController.text,
        nextOptions,
      );
    });
  }

  Future<void> _refreshRemoteModels() async {
    if (_isRefreshingModels) return;
    setState(() {
      _isRefreshingModels = true;
      _modelListMessage = null;
    });
    try {
      final remoteModels = await LlmModelCatalog.fetchModels(
        baseUrl: _baseUrlController.text,
        apiKey: _apiKeyController.text,
      );
      if (!mounted) return;
      final nextOptions = _includeCurrentModel(remoteModels);
      var nextIndex = _indexForSelectedModel(
        _modelController.text,
        nextOptions,
      );
      if (_modelController.text.trim().isEmpty && nextOptions.isNotEmpty) {
        _modelController.text = nextOptions.first.id;
        nextIndex = 0;
      }
      setState(() {
        _modelOptions = nextOptions;
        _selectedModelIndex = nextIndex;
        _modelListMessage = '已从接口读取 ${nextOptions.length} 个可用模型。';
      });
    } catch (error) {
      if (!mounted) return;
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _isRefreshingModels = false);
    }
  }

  void _selectModel(int index) {
    if (index < 0 || index >= _modelOptions.length) return;
    setState(() {
      _selectedModelIndex = index;
      _modelController.text = _modelOptions[index].id;
      _modelListMessage = null;
    });
  }

  List<LlmModelOption> _includeCurrentModel(List<LlmModelOption> models) {
    final selected = _modelController.text.trim();
    if (selected.isEmpty ||
        models.any(
          (model) => model.id.toLowerCase() == selected.toLowerCase(),
        )) {
      return models;
    }
    return [
      ...models,
      LlmModelOption(
        id: selected,
        label: selected,
        description: '当前已保存的自定义模型。',
      ),
    ];
  }

  int _indexForSelectedModel(
    String selectedModel,
    List<LlmModelOption> models,
  ) {
    final selected = selectedModel.trim().toLowerCase();
    if (models.isEmpty || selected.isEmpty) return 0;
    final index = models.indexWhere(
      (model) => model.id.toLowerCase() == selected,
    );
    return index < 0 ? 0 : index;
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
      backgroundColor: const Color(0xFFF7FCFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C4A6E),
        foregroundColor: Colors.white,
        title: const Text('AI 大模型配置'),
        actions: [
          TextButton(
            onPressed: _submit,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            const Text(
              '通用大模型',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0B1324),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '这里按 OpenAI-compatible 接口调用。',
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            _ProviderPresetSelector(
              presets: LlmModelCatalog.providerPresets,
              provider: _providerController.text,
              baseUrl: _baseUrlController.text,
              onSelected: _applyProviderPreset,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _providerController,
              onChanged: (_) => _syncModelOptionsFromInputs(),
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
              onChanged: (_) => _syncModelOptionsFromInputs(),
              decoration: _llmInputDecoration(
                'Base URL',
                '例如 https://api.moonshot.cn/v1',
              ),
            ),
            const SizedBox(height: 12),
            _ModelSliderSelector(
              models: _modelOptions,
              selectedIndex: _selectedModelIndex,
              isRefreshing: _isRefreshingModels,
              message: _modelListMessage,
              onChanged: _selectModel,
              onRefresh: _refreshRemoteModels,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              onChanged: (_) => _syncModelOptionsFromInputs(),
              decoration: _llmInputDecoration('当前模型 ID', '也可以手动输入官方列表之外的模型'),
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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.input),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}

// ========== Provider preset selector ==========
class _ProviderPresetSelector extends StatelessWidget {
  const _ProviderPresetSelector({
    required this.presets,
    required this.provider,
    required this.baseUrl,
    required this.onSelected,
  });
  final List<LlmProviderPreset> presets;
  final String provider, baseUrl;
  final ValueChanged<LlmProviderPreset> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedPreset = LlmModelCatalog.presetFor(
      provider: provider,
      baseUrl: baseUrl,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '常用服务商',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0B1324),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((preset) {
            final isSelected = selectedPreset?.provider == preset.provider;
            return ChoiceChip(
              selected: isSelected,
              label: Text(preset.label),
              avatar: Icon(
                isSelected ? Icons.check_rounded : Icons.auto_awesome_rounded,
                size: 18,
              ),
              onSelected: (_) => onSelected(preset),
              selectedColor: AppColors.primarySoft,
              labelStyle: TextStyle(
                color: isSelected
                    ? AppColors.primaryDark
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
              side: BorderSide(
                color: isSelected ? AppColors.primary : AppColors.border,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ========== Model slider selector ==========
class _ModelSliderSelector extends StatelessWidget {
  const _ModelSliderSelector({
    required this.models,
    required this.selectedIndex,
    required this.isRefreshing,
    required this.onChanged,
    required this.onRefresh,
    this.message,
  });
  final List<LlmModelOption> models;
  final int selectedIndex;
  final bool isRefreshing;
  final ValueChanged<int> onChanged;
  final VoidCallback onRefresh;
  final String? message;

  int _safeIndex() {
    if (models.isEmpty) return 0;
    if (selectedIndex < 0) return 0;
    if (selectedIndex >= models.length) return models.length - 1;
    return selectedIndex;
  }

  @override
  Widget build(BuildContext context) {
    final hasModels = models.isNotEmpty;
    final safeIndex = _safeIndex();
    final selectedModel = hasModels ? models[safeIndex] : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '滑动选择模型',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0B1324),
                  ),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: isRefreshing ? null : onRefresh,
                icon: isRefreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: 18),
                label: const Text('刷新'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasModels)
            const Text(
              '选择上方服务商会出现官方模型预设；填好 API Key 后，也可以刷新接口读取账号可用模型。',
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedModel!.label,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedModel.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF14B8A6),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (selectedModel.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      selectedModel.description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (models.length > 1)
              Slider(
                min: 0,
                max: (models.length - 1).toDouble(),
                divisions: models.length - 1,
                value: safeIndex.toDouble(),
                label: selectedModel.id,
                onChanged: (value) => onChanged(value.round()),
              )
            else
              const Text(
                '当前列表只有一个模型，已自动选中。',
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              ),
            Text(
              '${safeIndex + 1} / ${models.length}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
          ],
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(
              message!,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF0EA5A4),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ========== Bottom sheets ==========
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
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
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
  final String title, description;
  final List<_ActionItem> actions;

  @override
  Widget build(BuildContext context) {
    return _SheetContainer(
      child: SingleChildScrollView(
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
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(title, style: AppTextStyles.h2(context)),
              const SizedBox(height: 6),
              Text(description, style: AppTextStyles.bodySmall(context)),
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
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(item.icon, color: AppColors.primary, size: 19),
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
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
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
      child: SingleChildScrollView(
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
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('选择预设头像', style: AppTextStyles.h2(context)),
              const SizedBox(height: 6),
              Text(
                '如果你不想用本地头像，可以选择这里的预设样式。',
                style: AppTextStyles.bodySmall(context),
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
                              ? AppColors.primarySoft
                              : AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.border,
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
      child: SingleChildScrollView(
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
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('选择预设背景', style: AppTextStyles.h2(context)),
              const SizedBox(height: 6),
              Text(
                '没有本地背景图时，会使用这里选择的默认背景。',
                style: AppTextStyles.bodySmall(context),
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
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.border,
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isSelected ? '当前使用中' : '点击切换这个背景',
                                    style: AppTextStyles.caption(
                                      context,
                                    ).copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.primary,
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
      child: SingleChildScrollView(
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
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('账号信息', style: AppTextStyles.h2(context)),
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
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 74,
              child: Text(label, style: AppTextStyles.bodySmall(context)),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary,
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

// ========== Local models ==========
class _ProfileEditDraft {
  const _ProfileEditDraft({
    required this.displayName,
    required this.bio,
    required this.gender,
    required this.age,
  });
  final String displayName, bio, gender;
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
  final String id, label;
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
  final String id, label;
  final List<Color> gradientColors;
  final String? imageAsset;
  final double overlayOpacity;
}
