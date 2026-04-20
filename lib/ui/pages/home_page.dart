import 'package:flutter/material.dart';

import '../../database/auth_repository.dart';
import 'login_page.dart';
import 'tabs/home_tab_page.dart';
import 'tabs/knowledge_tab_page.dart';
import 'tabs/profile_tab_page.dart';
import 'tabs/tasks_tab_page.dart';

// ========== 参数配置 ==========
// 这里放主界面底部导航需要的常量和标签配置。
const List<_BottomDockItem> _bottomDockItems = [
  _BottomDockItem(
    label: '首页',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  _BottomDockItem(
    label: '知识库',
    icon: Icons.collections_bookmark_outlined,
    selectedIcon: Icons.collections_bookmark_rounded,
  ),
  _BottomDockItem(
    label: '任务',
    icon: Icons.fact_check_outlined,
    selectedIcon: Icons.fact_check_rounded,
  ),
  _BottomDockItem(
    label: '我的',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
  ),
];

// ========== 主界面 ==========
// 管理底部 Tab，并确保只有有效登录态才能进入。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static const routeName = '/home';

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AuthRepository _authRepository = AuthRepository();

  int _currentIndex = 0;
  bool _isCheckingSession = true;

  static const _tabs = [
    HomeTabPage(),
    KnowledgeTabPage(),
    TasksTabPage(),
    ProfileTabPage(),
  ];

  @override
  void initState() {
    super.initState();
    _ensureActiveSession();
  }

  // ========== 数据读取 ==========
  // 这里放当前登录会话校验逻辑。
  Future<void> _ensureActiveSession() async {
    await _authRepository.ensureInitialized();
    final currentUser = await _authRepository.getCurrentUserProfile();

    if (!mounted) {
      return;
    }

    if (currentUser == null) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(LoginPage.routeName, (route) => false);
      return;
    }

    setState(() {
      _isCheckingSession = false;
    });
  }

  // ========== 页面构建 ==========
  // 这里拼装主内容区和自定义悬浮底部导航。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFFF8FAFC),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF0F9FF), Color(0xFFF8FAFC)],
          ),
        ),
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
              onSelect: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
            ),
    );
  }
}

// ========== 底部导航 ==========
// 这里放自定义悬浮式底部导航栏。
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
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Container(
          height: 78,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.10),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: const Color(0xFF94A3B8).withValues(alpha: 0.10),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isSelected = currentIndex == index;

              return Expanded(
                child: _DockButton(
                  item: item,
                  isSelected: isSelected,
                  onTap: () => onSelect(index),
                ),
              );
            }),
          ),
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
    final foregroundColor = isSelected
        ? const Color(0xFF0F172A)
        : const Color(0xFF94A3B8);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 34,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF111827)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isSelected ? item.selectedIcon : item.icon,
                  size: 19,
                  color: isSelected ? Colors.white : foregroundColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foregroundColor,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: isSelected ? 18 : 0,
                height: isSelected ? 3 : 0,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF111827)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========== 局部模型 ==========
// 这里放底部导航使用的轻量配置模型。
class _BottomDockItem {
  const _BottomDockItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
