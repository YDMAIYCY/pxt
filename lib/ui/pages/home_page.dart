import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../common/app_assets.dart';
import '../../database/auth_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/premium_app_chrome.dart';
import 'login_page.dart';
import 'tabs/home_tab_page.dart';
import 'tabs/knowledge_tab_page.dart';
import 'tabs/focus_tab_page.dart';
import 'tabs/profile_tab_page.dart';
import 'tabs/tasks_tab_page.dart';

const List<_BottomDockItem> _bottomDockItems = [
  _BottomDockItem(label: '\u9996\u9875', iconAsset: AppAssets.navHome),
  _BottomDockItem(
    label: '\u77e5\u8bc6\u5e93',
    iconAsset: AppAssets.navKnowledge,
  ),
  _BottomDockItem(label: '\u4e13\u6ce8', icon: Icons.psychology_alt_rounded),
  _BottomDockItem(label: '\u4efb\u52a1', iconAsset: AppAssets.navTask),
  _BottomDockItem(label: '\u6211\u7684', iconAsset: AppAssets.navProfile),
];

// ========== Main Shell ==========
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static const routeName = '/home';

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AuthRepository _authRepository = AuthRepository();
  final ValueNotifier<int> _refreshNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _activeTabNotifier = ValueNotifier<int>(0);

  int _currentIndex = 0;
  bool _isCheckingSession = true;
  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = _buildTabs();
    _ensureActiveSession();
  }

  @override
  void dispose() {
    _refreshNotifier.dispose();
    _activeTabNotifier.dispose();
    super.dispose();
  }

  Future<void> _ensureActiveSession() async {
    await _authRepository.ensureInitialized();
    final currentUser = await _authRepository.getCurrentUserProfile();

    if (!mounted) return;

    if (currentUser == null) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(LoginPage.routeName, (route) => false);
      return;
    }

    setState(() => _isCheckingSession = false);
  }

  void _notifyDataChanged() {
    if (!mounted) return;
    _refreshNotifier.value++;
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _bottomDockItems.length) return;
    setState(() {
      _currentIndex = index;
    });
    _activeTabNotifier.value = index;
    _refreshNotifier.value++;
  }

  List<Widget> _buildTabs() {
    return [
      HomeTabPage(
        tabIndex: 0,
        refreshListenable: _refreshNotifier,
        activeTabListenable: _activeTabNotifier,
        onOpenTab: _selectTab,
        onDataChanged: _notifyDataChanged,
      ),
      KnowledgeTabPage(
        tabIndex: 1,
        refreshListenable: _refreshNotifier,
        activeTabListenable: _activeTabNotifier,
        onDataChanged: _notifyDataChanged,
      ),
      FocusTabPage(
        tabIndex: 2,
        refreshListenable: _refreshNotifier,
        activeTabListenable: _activeTabNotifier,
        onDataChanged: _notifyDataChanged,
      ),
      TasksTabPage(
        tabIndex: 3,
        refreshListenable: _refreshNotifier,
        activeTabListenable: _activeTabNotifier,
        onDataChanged: _notifyDataChanged,
      ),
      ProfileTabPage(
        tabIndex: 4,
        refreshListenable: _refreshNotifier,
        activeTabListenable: _activeTabNotifier,
        onOpenTab: _selectTab,
        onDataChanged: _notifyDataChanged,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.background,
      body: PremiumPageBackground(
        child: SafeArea(
          bottom: false,
          child: _isCheckingSession
              ? const Center(child: CircularProgressIndicator())
              : IndexedStack(index: _currentIndex, children: _tabs),
        ),
      ),
      bottomNavigationBar: _isCheckingSession
          ? null
          : _FloatingBottomDock(
              currentIndex: _currentIndex,
              items: _bottomDockItems,
              onSelect: _selectTab,
            ),
    );
  }
}

// ========== Bottom Navigation ==========
class _FloatingBottomDock extends StatelessWidget {
  const _FloatingBottomDock({
    required this.currentIndex,
    required this.items,
    required this.onSelect,
  });

  final int currentIndex;
  final List<_BottomDockItem> items;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: AppShadows.navList,
        ),
        child: Row(
          children: List.generate(items.length, (index) {
            final isSelected = currentIndex == index;
            return Expanded(
              child: _DockButton(
                item: items[index],
                isSelected: isSelected,
                onTap: () => onSelect(index),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final _BottomDockItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryLight.withValues(alpha: 0.72)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 2),
              if (item.iconAsset != null)
                SvgPicture.asset(
                  item.iconAsset!,
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(
                    isSelected ? AppColors.primary : AppColors.textTertiary,
                    BlendMode.srcIn,
                  ),
                )
              else if (item.icon != null)
                Icon(
                  item.icon,
                  size: 22,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textTertiary,
                ),
              const SizedBox(height: 2),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.primaryDark
                      : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomDockItem {
  const _BottomDockItem({required this.label, this.iconAsset, this.icon});

  final String label;
  final String? iconAsset;
  final IconData? icon;
}
