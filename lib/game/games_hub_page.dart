import 'package:flutter/material.dart';

import 'games/pattern_game_page.dart';
import 'games/math_game_page.dart';
import 'games/memory_game_page.dart';
import 'games/minesweeper_game_page.dart';
import 'games/slide_puzzle_game_page.dart';
import 'games/idiom_game_page.dart';
import 'games/game_2048_page.dart';

class GamesHubPage extends StatelessWidget {
  const GamesHubPage({super.key});

  static const routeName = '/games-hub';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('益智游戏'),
        backgroundColor: const Color(0xFF0C4A6E),
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF0F9FF), Color(0xFFF8FAFC)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                '选择一款游戏开始挑战',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _GameCard(
                  icon: Icons.psychology_rounded,
                  title: '找规律',
                  subtitle: '观察数列与图形规律',
                  color: const Color(0xFF6366F1),
                  onTap: () => _openGame(context, const PatternGamePage()),
                ),
                _GameCard(
                  icon: Icons.calculate_rounded,
                  title: '口算达人',
                  subtitle: '混合运算与应用题',
                  color: const Color(0xFF0EA5E9),
                  onTap: () => _openGame(context, const MathGamePage()),
                ),
                _GameCard(
                  icon: Icons.grid_view_rounded,
                  title: '记忆卡片',
                  subtitle: '翻牌配对考验记忆力',
                  color: const Color(0xFF8B5CF6),
                  onTap: () => _openGame(context, const MemoryGamePage()),
                ),
                _GameCard(
                  icon: Icons.dangerous_rounded,
                  title: '扫雷挑战',
                  subtitle: '双阶段逻辑扫雷',
                  color: const Color(0xFFEF4444),
                  onTap: () => _openGame(context, const MinesweeperGamePage()),
                ),
                _GameCard(
                  icon: Icons.apps_rounded,
                  title: '数字华容道',
                  subtitle: '3×3 到 4×4 滑块拼图',
                  color: const Color(0xFFF59E0B),
                  onTap: () => _openGame(context, const SlidePuzzleGamePage()),
                ),
                _GameCard(
                  icon: Icons.translate_rounded,
                  title: '成语寻踪',
                  subtitle: '在字阵中寻找成语',
                  color: const Color(0xFF10B981),
                  onTap: () => _openGame(context, const IdiomGamePage()),
                ),
                _GameCard(
                  icon: Icons.flip_to_back_rounded,
                  title: '2048',
                  subtitle: '经典数字合并挑战',
                  color: const Color(0xFFEC4899),
                  onTap: () => _openGame(context, const Game2048Page()),
                ),
              ].map((card) {
                return SizedBox(
                  width: _cardWidth(context),
                  child: card,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  static double _cardWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return (screenWidth - 44) / 2;
  }

  static void _openGame(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0B1324),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
