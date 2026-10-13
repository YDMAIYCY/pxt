import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

const bookThemes = {
  'math': '函数曲线',
  'letters': '字母建筑',
  'network': '网络节点',
  'building': '建筑剪影',
  'papers': '纸张文档',
};
const bookColors = [0xFF5B90FF, 0xFFF2A37D, 0xFF62BBA0, 0xFFA58CE5, 0xFFF0BC5C];

class KnowledgeBookCover extends StatelessWidget {
  const KnowledgeBookCover({
    required this.title,
    this.subtitle,
    this.theme = 'math',
    this.color = 0xFF5B90FF,
    this.onTap,
    this.onLongPress,
    super.key,
  });
  final String title, theme;
  final String? subtitle;
  final int color;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final accent = Color(color);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 100;
        return Semantics(
          button: onTap != null,
          label: title,
          child: AspectRatio(
            aspectRatio: .70,
            child: Container(
              margin: const EdgeInsets.fromLTRB(2, 2, 4, 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: .22),
                    blurRadius: 12,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: onTap,
                  onLongPress: onLongPress,
                  borderRadius: BorderRadius.circular(10),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(accent, Colors.white, .75)!,
                          Color.lerp(accent, Colors.white, .94)!,
                          Color.lerp(accent, Colors.white, .65)!,
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: CustomPaint(
                              painter: _CoverPainter(accent, theme),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: 12,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(9),
                              ),
                              gradient: LinearGradient(
                                colors: [
                                  accent.withValues(alpha: .50),
                                  Colors.white.withValues(alpha: .65),
                                  accent.withValues(alpha: .25),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 15,
                          top: 4,
                          bottom: 4,
                          child: Container(
                            width: 1,
                            color: Colors.white.withValues(alpha: .8),
                          ),
                        ),
                        Positioned(
                          right: 6,
                          top: 4,
                          bottom: 4,
                          child: Container(
                            width: 2,
                            color: Colors.white.withValues(alpha: .65),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 14,
                          child: CustomPaint(
                            size: const Size(12, 28),
                            painter: _BookmarkPainter(accent),
                          ),
                        ),
                        Positioned(
                          left: compact ? 14 : 26,
                          right: compact ? 7 : 14,
                          top: compact ? 12 : 32,
                          child: LayoutBuilder(
                            builder: (context, box) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: compact
                                        ? 10
                                        : box.maxWidth < 70
                                        ? 12
                                        : 16,
                                    height: 1.3,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.ink,
                                  ),
                                ),
                                if (subtitle != null && !compact) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    subtitle!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF7489A6),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Container(width: 13, height: 2, color: accent),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BookmarkPainter extends CustomPainter {
  _BookmarkPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height - 5)
      ..lineTo(0, size.height)
      ..close(),
    Paint()..color = color.withValues(alpha: .8),
  );
  @override
  bool shouldRepaint(_BookmarkPainter old) => color != old.color;
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.color, this.theme);
  final Color color;
  final String theme;
  @override
  void paint(Canvas canvas, Size s) {
    for (var layer = 0; layer < 3; layer++) {
      final p = Path()..moveTo(0, s.height * (.69 + layer * .10));
      for (var i = 0; i <= 40; i++) {
        final x = s.width * i / 40;
        p.lineTo(
          x,
          s.height * (.73 + layer * .08) +
              math.sin(i / 6 + layer * 1.7) * s.height * .06,
        );
      }
      p.lineTo(s.width, s.height);
      p.lineTo(0, s.height);
      p.close();
      canvas.drawPath(
        p,
        Paint()..color = color.withValues(alpha: .10 + layer * .08),
      );
    }
    final line = Paint()
      ..color = color.withValues(alpha: .65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final x = s.width * .42, y = s.height * .77;
    if (theme == 'math') {
      for (var i = 0; i < 5; i++) {
        final grid = Paint()..color = color.withValues(alpha: .12);
        canvas.drawLine(
          Offset(s.width * .28, s.height * (.64 + i * .045)),
          Offset(s.width * .9, s.height * (.64 + i * .045)),
          grid,
        );
        canvas.drawLine(
          Offset(s.width * (.3 + i * .14), s.height * .62),
          Offset(s.width * (.3 + i * .14), s.height * .92),
          grid,
        );
      }
      canvas.drawLine(
        Offset(x, s.height * .61),
        Offset(x, s.height * .94),
        line,
      );
      canvas.drawLine(Offset(s.width * .25, y), Offset(s.width * .93, y), line);
      final curve = Path()
        ..moveTo(s.width * .25, s.height * .87)
        ..cubicTo(
          s.width * .55,
          s.height * .58,
          s.width * .62,
          s.height * .97,
          s.width * .90,
          s.height * .60,
        );
      canvas.drawPath(curve, line..strokeWidth = 1.4);
    } else if (theme == 'network') {
      final nodes = [
        Offset(s.width * .38, y),
        Offset(s.width * .58, y - 20),
        Offset(s.width * .58, y + 20),
        Offset(s.width * .8, y - 10),
        Offset(s.width * .8, y + 20),
      ];
      for (var i = 0; i < nodes.length; i++) {
        for (var j = i + 1; j < nodes.length; j++) {
          canvas.drawLine(nodes[i], nodes[j], line..strokeWidth = .6);
        }
      }
      for (final n in nodes) {
        canvas.drawCircle(n, 4, Paint()..color = color.withValues(alpha: .65));
      }
    } else if (theme == 'letters') {
      final painter = TextPainter(
        text: TextSpan(
          text: 'A  B\n   C',
          style: TextStyle(
            color: color.withValues(alpha: .35),
            fontSize: s.width * .17,
            fontStyle: FontStyle.italic,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(s.width * .30, s.height * .60));
      canvas.drawRect(
        Rect.fromLTWH(
          s.width * .73,
          s.height * .61,
          s.width * .1,
          s.height * .28,
        ),
        Paint()..color = color.withValues(alpha: .2),
      );
      canvas.drawPath(
        Path()
          ..moveTo(s.width * .70, s.height * .61)
          ..lineTo(s.width * .78, s.height * .53)
          ..lineTo(s.width * .87, s.height * .61)
          ..close(),
        Paint()..color = color.withValues(alpha: .25),
      );
    } else if (theme == 'building') {
      for (var i = 0; i < 3; i++) {
        final top = s.height * (.68 + i * .06),
            width = s.width * (.27 + i * .1);
        canvas.drawRect(
          Rect.fromLTWH(s.width * .62 - width / 2, top, width, 8),
          Paint()..color = color.withValues(alpha: .32),
        );
        canvas.drawPath(
          Path()
            ..moveTo(s.width * .62 - width / 2 - 6, top)
            ..lineTo(s.width * .62, top - 8)
            ..lineTo(s.width * .62 + width / 2 + 6, top)
            ..close(),
          Paint()..color = color.withValues(alpha: .4),
        );
      }
    } else {
      for (var i = 0; i < 2; i++) {
        final rect = Rect.fromLTWH(
          s.width * (.36 + i * .18),
          s.height * (.72 - i * .09),
          s.width * .32,
          s.height * .20,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(5)),
          Paint()..color = Colors.white.withValues(alpha: .8),
        );
        for (var j = 1; j <= 3; j++) {
          canvas.drawLine(
            Offset(rect.left + 7, rect.top + j * rect.height / 5),
            Offset(rect.right - 7, rect.top + j * rect.height / 5),
            line..strokeWidth = 2,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CoverPainter old) =>
      color != old.color || theme != old.theme;
}
