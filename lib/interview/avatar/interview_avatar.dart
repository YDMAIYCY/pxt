import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum AvatarMood { idle, speaking, listening, thinking, happy, error }

/// A vector avatar. The playback service owns [mouthActivity] and should set
/// it to zero on pause/end; values are normalized to 0..1 by the painter.
class InterviewAvatar extends StatefulWidget {
  const InterviewAvatar({
    super.key,
    this.mood = AvatarMood.idle,
    this.mouthActivity,
    this.size = 240,
    this.renderer = const NativeInterviewAvatarRenderer(),
  }) : assert(size > 0 && size < double.infinity);

  final AvatarMood mood;
  final ValueListenable<double>? mouthActivity;
  final double size;
  final InterviewAvatarRenderer renderer;

  @override
  State<InterviewAvatar> createState() => _InterviewAvatarState();
}

class _InterviewAvatarState extends State<InterviewAvatar>
    with TickerProviderStateMixin {
  late final AnimationController _breathing = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );
  late final AnimationController _blinking = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4700),
  );
  bool _animate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    _animate =
        TickerMode.valuesOf(context).enabled &&
        !(media?.disableAnimations ?? false) &&
        !(media?.accessibleNavigation ?? false);
    for (final controller in [_breathing, _blinking]) {
      if (_animate && !controller.isAnimating) {
        controller.repeat();
      } else if (!_animate) {
        controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _breathing.dispose();
    _blinking.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = switch (widget.mood) {
      AvatarMood.idle => '准备就绪',
      AvatarMood.speaking => '讲解中',
      AvatarMood.listening => '倾听中',
      AvatarMood.thinking => '思考中',
      AvatarMood.happy => '答得很好',
      AvatarMood.error => '需要重试',
    };
    return Semantics(
      label: '面试助手，$status',
      image: true,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _InterviewAvatarPainter(
              mood: widget.mood,
              activity: widget.mouthActivity,
              breathing: _breathing,
              blinking: _blinking,
              animate: _animate,
              renderer: widget.renderer,
            ),
          ),
        ),
      ),
    );
  }
}

/// Receives normalized expression values without owning tickers or playback.
abstract class InterviewAvatarRenderer {
  const InterviewAvatarRenderer();

  void paint(
    Canvas canvas,
    Size size, {
    required AvatarMood mood,
    required double breathing,
    required double blink,
    required double mouthOpenness,
  });
}

class _InterviewAvatarPainter extends CustomPainter {
  _InterviewAvatarPainter({
    required this.mood,
    required this.activity,
    required this.breathing,
    required this.blinking,
    required this.animate,
    required this.renderer,
  }) : super(repaint: Listenable.merge([breathing, blinking, activity]));

  final AvatarMood mood;
  final ValueListenable<double>? activity;
  final AnimationController breathing;
  final AnimationController blinking;
  final bool animate;
  final InterviewAvatarRenderer renderer;

  @override
  void paint(Canvas canvas, Size size) {
    final volume = activity?.value ?? 0;
    // A short, full eyelid closure on its own clock, unrelated to speech.
    final blinkPhase = blinking.value * 4700;
    final blink = animate && blinkPhase >= 4400 && blinkPhase <= 4640
        ? (1 - (blinkPhase - 4520).abs() / 120).clamp(0.0, 1.0)
        : 0.0;
    renderer.paint(
      canvas,
      size,
      mood: mood,
      breathing: animate ? math.sin(breathing.value * math.pi * 2) : 0,
      blink: blink,
      mouthOpenness:
          mood == AvatarMood.speaking && volume.isFinite && volume > 0
          ? volume.clamp(0.0, 1.0)
          : 0,
    );
  }

  @override
  bool shouldRepaint(_InterviewAvatarPainter oldDelegate) =>
      mood != oldDelegate.mood ||
      activity != oldDelegate.activity ||
      breathing != oldDelegate.breathing ||
      blinking != oldDelegate.blinking ||
      animate != oldDelegate.animate ||
      renderer != oldDelegate.renderer;
}

/// Original layered artwork in a 360 x 360 coordinate space; no image assets.
class NativeInterviewAvatarRenderer extends InterviewAvatarRenderer {
  const NativeInterviewAvatarRenderer();

  static const _ink = Color(0xFF303344);
  static const _hair = Color(0xFF35333D);
  static const _blue = Color(0xFF5689E3);
  static const _darkBlue = Color(0xFF345DA5);
  static const _skin = Color(0xFFFFD8BB);
  static const _white = Color(0xFFFFFEFC);

  @override
  void paint(
    Canvas canvas,
    Size size, {
    required AvatarMood mood,
    required double breathing,
    required double blink,
    required double mouthOpenness,
  }) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final scale = size.shortestSide / 360;
    canvas.translate(
      (size.width - 360 * scale) / 2,
      (size.height - 360 * scale) / 2,
    );
    canvas.scale(scale);
    _oval(
      canvas,
      const Rect.fromLTWH(28, 23, 304, 304),
      const Color(0xFFF0F6FF),
    );
    _oval(
      canvas,
      const Rect.fromLTWH(83, 328, 196, 14),
      const Color(0xFFDCE8F8),
    );
    _status(canvas, mood);

    canvas.save();
    canvas.translate(0, -breathing * 1.8);
    // Silhouette and hood, behind the face and arms.
    _shape(
      canvas,
      Path()
        ..moveTo(65, 326)
        ..cubicTo(63, 289, 79, 245, 123, 235)
        ..quadraticBezierTo(180, 215, 237, 235)
        ..cubicTo(281, 245, 298, 289, 294, 326)
        ..quadraticBezierTo(181, 350, 65, 326)
        ..close(),
      _white,
    );
    _oval(canvas, const Rect.fromLTWH(113, 218, 137, 69), _darkBlue);
    _shape(
      canvas,
      Path()
        ..moveTo(157, 205)
        ..lineTo(203, 205)
        ..lineTo(206, 246)
        ..quadraticBezierTo(180, 265, 154, 246)
        ..close(),
      _skin,
    );
    _shape(
      canvas,
      Path()
        ..moveTo(157, 212)
        ..quadraticBezierTo(180, 234, 203, 214)
        ..lineTo(204, 228)
        ..quadraticBezierTo(180, 241, 156, 230)
        ..close(),
      const Color(0xFFF3BC9C),
    );
    _shape(
      canvas,
      Path()
        ..moveTo(120, 235)
        ..quadraticBezierTo(140, 231, 158, 245)
        ..lineTo(180, 277)
        ..lineTo(205, 245)
        ..quadraticBezierTo(225, 230, 244, 236)
        ..lineTo(230, 263)
        ..lineTo(180, 292)
        ..lineTo(127, 265)
        ..close(),
      _blue,
    );
    _line(canvas, const Offset(157, 268), const Offset(159, 309), _darkBlue, 4);
    _line(canvas, const Offset(203, 268), const Offset(201, 309), _darkBlue, 4);
    _line(
      canvas,
      const Offset(180, 293),
      const Offset(180, 330),
      const Color(0xFFE2E9F4),
      2,
    );

    // Short, tousled hair silhouette and ears.
    _shape(
      canvas,
      Path()
        ..moveTo(103, 184)
        ..cubicTo(74, 155, 78, 101, 99, 83)
        ..lineTo(88, 82)
        ..quadraticBezierTo(117, 52, 146, 54)
        ..lineTo(136, 43)
        ..quadraticBezierTo(174, 36, 202, 56)
        ..quadraticBezierTo(220, 37, 233, 45)
        ..lineTo(225, 62)
        ..quadraticBezierTo(263, 66, 275, 97)
        ..lineTo(263, 93)
        ..cubicTo(289, 132, 270, 193, 246, 210)
        ..lineTo(112, 210)
        ..close(),
      _hair,
    );
    _oval(canvas, const Rect.fromLTWH(91, 152, 37, 49), _skin);
    _oval(canvas, const Rect.fromLTWH(235, 152, 35, 49), _skin);
    _oval(
      canvas,
      const Rect.fromLTWH(99, 164, 20, 26),
      const Color(0xFFF4B79B),
    );
    _shape(
      canvas,
      Path()
        ..moveTo(114, 119)
        ..cubicTo(124, 93, 237, 88, 247, 123)
        ..lineTo(245, 173)
        ..cubicTo(241, 211, 215, 234, 181, 235)
        ..cubicTo(147, 234, 118, 213, 113, 177)
        ..close(),
      _skin,
    );
    // Fringe, kept short so the expressive eyes remain visible.
    _shape(
      canvas,
      Path()
        ..moveTo(99, 142)
        ..quadraticBezierTo(91, 87, 139, 73)
        ..quadraticBezierTo(192, 54, 235, 82)
        ..quadraticBezierTo(267, 104, 251, 147)
        ..quadraticBezierTo(230, 140, 215, 108)
        ..quadraticBezierTo(210, 133, 226, 144)
        ..quadraticBezierTo(194, 144, 180, 103)
        ..quadraticBezierTo(170, 119, 173, 136)
        ..quadraticBezierTo(151, 128, 148, 112)
        ..quadraticBezierTo(128, 146, 107, 157)
        ..close(),
      _hair,
    );
    _stroke(
      canvas,
      Path()
        ..moveTo(114, 102)
        ..quadraticBezierTo(142, 72, 177, 77),
      const Color(0xFF514A54),
      5,
    );
    _stroke(
      canvas,
      Path()
        ..moveTo(204, 78)
        ..quadraticBezierTo(236, 86, 244, 109),
      const Color(0xFF514A54),
      4,
    );

    final worried = mood == AvatarMood.error;
    final thinking = mood == AvatarMood.thinking;
    _stroke(
      canvas,
      Path()
        ..moveTo(130, worried ? 148 : 147)
        ..quadraticBezierTo(
          144,
          worried ? 149 : 138,
          157,
          worried ? 139 : (thinking ? 150 : 144),
        ),
      _hair,
      4,
    );
    _stroke(
      canvas,
      Path()
        ..moveTo(201, worried ? 139 : (thinking ? 137 : 144))
        ..quadraticBezierTo(214, worried ? 149 : 138, 228, 147),
      _hair,
      4,
    );
    _eye(canvas, 144, blink, mood);
    _eye(canvas, 214, blink, mood);
    _oval(
      canvas,
      const Rect.fromLTWH(120, 187, 25, 11),
      const Color(0xFFF6BBA9),
    );
    _oval(
      canvas,
      const Rect.fromLTWH(215, 187, 25, 11),
      const Color(0xFFF6BBA9),
    );
    _line(
      canvas,
      const Offset(180, 181),
      const Offset(179, 186),
      const Color(0xFFEBA886),
      3,
    );
    _mouth(canvas, mood, mouthOpenness);

    // Headset and microphone, layered in front of the cheek.
    _stroke(
      canvas,
      Path()
        ..moveTo(95, 151)
        ..cubicTo(86, 60, 269, 55, 269, 153),
      _ink,
      7,
    );
    _rounded(canvas, const Rect.fromLTWH(89, 145, 19, 45), 9, _darkBlue);
    _rounded(canvas, const Rect.fromLTWH(248, 144, 27, 54), 13, _ink);
    _rounded(canvas, const Rect.fromLTWH(256, 148, 20, 43), 10, _blue);
    _stroke(
      canvas,
      Path()
        ..moveTo(260, 190)
        ..quadraticBezierTo(254, 218, 220, 217),
      _ink,
      5,
    );
    _rounded(canvas, const Rect.fromLTWH(206, 210, 23, 12), 6, _ink);

    // A relaxed raised hand and blue cuff.
    _shape(
      canvas,
      Path()
        ..moveTo(75, 280)
        ..lineTo(66, 255)
        ..quadraticBezierTo(49, 242, 44, 228)
        ..quadraticBezierTo(43, 220, 50, 222)
        ..lineTo(65, 235)
        ..lineTo(53, 207)
        ..quadraticBezierTo(52, 199, 60, 202)
        ..lineTo(76, 229)
        ..lineTo(69, 196)
        ..quadraticBezierTo(71, 188, 78, 195)
        ..lineTo(88, 228)
        ..lineTo(90, 208)
        ..quadraticBezierTo(94, 200, 99, 209)
        ..lineTo(99, 243)
        ..quadraticBezierTo(97, 261, 96, 277)
        ..close(),
      _skin,
    );
    _shape(
      canvas,
      Path()
        ..moveTo(64, 268)
        ..quadraticBezierTo(79, 279, 103, 270)
        ..lineTo(109, 289)
        ..quadraticBezierTo(88, 304, 66, 291)
        ..close(),
      _blue,
    );
    _stroke(
      canvas,
      Path()
        ..moveTo(67, 297)
        ..quadraticBezierTo(91, 320, 115, 288),
      const Color(0xFFE5EAF3),
      3,
    );

    // Tablet, screen details and the supporting hand.
    canvas.save();
    canvas.translate(254, 283);
    canvas.rotate(0.16);
    _rounded(
      canvas,
      const Rect.fromLTWH(-39, -45, 78, 106),
      10,
      const Color(0xFFBACAE1),
    );
    _rounded(
      canvas,
      const Rect.fromLTWH(-34, -40, 68, 94),
      7,
      const Color(0xFFE6EEFA),
    );
    _oval(canvas, const Rect.fromLTWH(-25, -32, 6, 6), _darkBlue);
    _rounded(
      canvas,
      const Rect.fromLTWH(-22, -12, 44, 30),
      5,
      const Color(0xFFC8DCFA),
    );
    _line(canvas, const Offset(-12, 29), const Offset(15, 29), _blue, 3);
    _line(canvas, const Offset(-12, 37), const Offset(7, 37), _blue, 3);
    canvas.restore();
    _shape(
      canvas,
      Path()
        ..moveTo(222, 281)
        ..quadraticBezierTo(208, 269, 204, 279)
        ..quadraticBezierTo(204, 286, 219, 298)
        ..quadraticBezierTo(201, 285, 199, 296)
        ..quadraticBezierTo(199, 309, 218, 318)
        ..quadraticBezierTo(231, 326, 245, 316)
        ..lineTo(250, 301)
        ..quadraticBezierTo(242, 289, 222, 281)
        ..close(),
      _skin,
    );
    _stroke(
      canvas,
      Path()
        ..moveTo(209, 296)
        ..quadraticBezierTo(217, 305, 225, 307),
      const Color(0xFFEFB190),
      2,
    );
    _shape(
      canvas,
      Path()
        ..moveTo(245, 297)
        ..quadraticBezierTo(262, 300, 266, 314)
        ..lineTo(253, 331)
        ..quadraticBezierTo(239, 326, 235, 318)
        ..close(),
      _blue,
    );
    canvas.restore();
    canvas.restore();
  }

  void _eye(Canvas canvas, double x, double blink, AvatarMood mood) {
    final height = 28 * (1 - blink);
    if (height < 3 || mood == AvatarMood.happy) {
      _stroke(
        canvas,
        Path()
          ..moveTo(x - 12, 165)
          ..quadraticBezierTo(
            x,
            mood == AvatarMood.happy ? 151 : 173,
            x + 12,
            165,
          ),
        _ink,
        3,
      );
      return;
    }
    _oval(
      canvas,
      Rect.fromCenter(center: Offset(x, 165), width: 29, height: height + 5),
      _white,
    );
    final glance = mood == AvatarMood.thinking ? 3.0 : 0.0;
    canvas.save();
    canvas.clipPath(
      Path()..addOval(
        Rect.fromCenter(center: Offset(x, 165), width: 29, height: height + 5),
      ),
    );
    _oval(
      canvas,
      Rect.fromCenter(
        center: Offset(x + glance, 167),
        width: 18,
        height: height,
      ),
      _ink,
    );
    _oval(
      canvas,
      Rect.fromCenter(center: Offset(x + glance + 3, 161), width: 5, height: 5),
      _white,
    );
    canvas.restore();
  }

  void _mouth(Canvas canvas, AvatarMood mood, double openness) {
    if (openness > 0) {
      final height = 3 + 18 * openness;
      final rect = Rect.fromCenter(
        center: const Offset(180, 205),
        width: 25 + 6 * openness,
        height: height,
      );
      _oval(canvas, rect, const Color(0xFFA54C4C));
      canvas.save();
      canvas.clipPath(Path()..addOval(rect));
      _oval(
        canvas,
        Rect.fromLTWH(167, 204 + height * .12, 27, height),
        const Color(0xFFF4938C),
      );
      _rounded(canvas, Rect.fromLTWH(167, rect.top - 1, 27, 5), 2, _white);
      canvas.restore();
    } else {
      final error = mood == AvatarMood.error;
      _stroke(
        canvas,
        Path()
          ..moveTo(168, error ? 209 : 202)
          ..quadraticBezierTo(180, error ? 198 : 213, 192, error ? 209 : 202),
        const Color(0xFFAF6660),
        2.5,
      );
    }
  }

  void _status(Canvas canvas, AvatarMood mood) {
    final color = switch (mood) {
      AvatarMood.listening => const Color(0xFF39A694),
      AvatarMood.happy => const Color(0xFFEAB755),
      AvatarMood.error => const Color(0xFFD77778),
      _ => _blue,
    };
    _oval(canvas, const Rect.fromLTWH(285, 58, 38, 38), _white);
    switch (mood) {
      case AvatarMood.idle:
        _oval(canvas, const Rect.fromLTWH(300, 73, 8, 8), color);
      case AvatarMood.speaking:
      case AvatarMood.listening:
        for (var i = 0; i < 3; i++) {
          final height = i == 1 ? 18.0 : 10.0;
          _line(
            canvas,
            Offset(296 + i * 8, 77 - height / 2),
            Offset(296 + i * 8, 77 + height / 2),
            color,
            3,
          );
        }
        if (mood == AvatarMood.listening) {
          _stroke(
            canvas,
            Path()
              ..moveTo(53, 150)
              ..quadraticBezierTo(41, 164, 53, 178),
            color,
            3,
          );
          _stroke(
            canvas,
            Path()
              ..moveTo(44, 144)
              ..quadraticBezierTo(28, 164, 44, 184),
            color,
            2,
          );
        }
      case AvatarMood.thinking:
        for (var i = 0; i < 3; i++) {
          _oval(
            canvas,
            Rect.fromCircle(center: Offset(296 + i * 8, 77), radius: 2),
            color,
          );
        }
        _oval(canvas, const Rect.fromLTWH(273, 102, 9, 9), color);
      case AvatarMood.happy:
        _stroke(
          canvas,
          Path()
            ..moveTo(294, 77)
            ..lineTo(301, 84)
            ..lineTo(314, 70),
          color,
          3,
        );
        _line(canvas, const Offset(53, 99), const Offset(53, 119), color, 3);
        _line(canvas, const Offset(43, 109), const Offset(63, 109), color, 3);
      case AvatarMood.error:
        _line(canvas, const Offset(304, 67), const Offset(304, 79), color, 3);
        _oval(canvas, const Rect.fromLTWH(302, 84, 4, 4), color);
    }
  }

  void _shape(Canvas canvas, Path path, Color color) =>
      canvas.drawPath(path, Paint()..color = color);

  void _oval(Canvas canvas, Rect rect, Color color) =>
      canvas.drawOval(rect, Paint()..color = color);

  void _rounded(Canvas canvas, Rect rect, double radius, Color color) =>
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        Paint()..color = color,
      );

  void _stroke(Canvas canvas, Path path, Color color, double width) =>
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

  void _line(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
    double width,
  ) => canvas.drawLine(
    start,
    end,
    Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round,
  );
}
