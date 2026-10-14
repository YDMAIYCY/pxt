import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/interview/avatar/interview_avatar.dart';

void main() {
  testWidgets('only speaking with actual playback activity opens the mouth', (
    tester,
  ) async {
    final activity = _Activity(0.8);
    final renderer = _RecordingRenderer();
    for (final mood in AvatarMood.values) {
      await tester.pumpWidget(
        _host(
          InterviewAvatar(
            mood: mood,
            mouthActivity: activity,
            renderer: renderer,
          ),
        ),
      );
      expect(renderer.mouth, mood == AvatarMood.speaking ? 0.8 : 0);
    }
    await tester.pumpWidget(
      _host(InterviewAvatar(mood: AvatarMood.speaking, renderer: renderer)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(renderer.mouth, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    activity.dispose();
  });

  testWidgets('activity repaints without rebuilding the avatar or chat', (
    tester,
  ) async {
    final activity = _Activity(0);
    final renderer = _RecordingRenderer();
    var chatBuilds = 0;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) {
            chatBuilds++;
            return InterviewAvatar(
              mood: AvatarMood.speaking,
              mouthActivity: activity,
              renderer: renderer,
            );
          },
        ),
      ),
    );
    final element = tester.element(find.byType(InterviewAvatar));
    final paintBefore = tester.widget<CustomPaint>(find.byType(CustomPaint));
    final initialBuilds = chatBuilds;
    expect(renderer.mouth, 0);
    for (final value in [
      0.4,
      1.0,
      0.0,
      -1.0,
      2.0,
      double.nan,
      double.infinity,
    ]) {
      final paintsBefore = renderer.paints;
      activity.value = value;
      await tester.pump();
      expect(renderer.paints, greaterThan(paintsBefore));
      expect(renderer.mouth, value.isFinite ? value.clamp(0.0, 1.0) : 0);
      expect(chatBuilds, initialBuilds);
      expect(tester.element(find.byType(InterviewAvatar)), same(element));
      expect(
        tester.widget<CustomPaint>(find.byType(CustomPaint)),
        same(paintBefore),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(activity.isObserved, isFalse);
    activity.dispose();
  });

  testWidgets('switching playback listenables detaches the previous source', (
    tester,
  ) async {
    final first = _Activity(0.7);
    final second = _Activity(0.2);
    final renderer = _RecordingRenderer();
    for (final source in [first, second]) {
      await tester.pumpWidget(
        _host(
          InterviewAvatar(
            mood: AvatarMood.speaking,
            mouthActivity: source,
            renderer: renderer,
          ),
        ),
      );
      expect(renderer.mouth, source.value);
    }
    expect(first.isObserved, isFalse);
    expect(second.isObserved, isTrue);
    first.value = 1;
    await tester.pump();
    expect(renderer.mouth, 0.2);
    second.value = 0;
    await tester.pump();
    expect(renderer.mouth, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(second.isObserved, isFalse);
    first.dispose();
    second.dispose();
  });

  testWidgets('breathing and full blinking use independent clocks', (
    tester,
  ) async {
    final renderer = _RecordingRenderer();
    await tester.pumpWidget(_host(InterviewAvatar(renderer: renderer)));
    await tester.pump(const Duration(milliseconds: 900));
    expect(renderer.breathing, closeTo(1, 0.001));
    expect(renderer.blink, 0);
    expect(renderer.mouth, 0);
    await tester.pump(const Duration(milliseconds: 3620));
    expect(renderer.blink, closeTo(1, 0.001));
    expect(renderer.breathing.abs(), greaterThan(0.9));
    expect(renderer.mouth, 0);
    await tester.pump(const Duration(milliseconds: 120));
    expect(renderer.blink, closeTo(0, 0.001));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('TickerMode and reduced motion stop and resume ambient tickers', (
    tester,
  ) async {
    final renderer = _RecordingRenderer();
    final activity = _Activity(0.6);
    final avatar = InterviewAvatar(
      mood: AvatarMood.speaking,
      mouthActivity: activity,
      renderer: renderer,
    );
    await tester.pumpWidget(_host(avatar));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.binding.transientCallbackCount, 2);
    for (final restriction in ['ticker', 'motion', 'navigation']) {
      await tester.pumpWidget(
        _host(
          avatar,
          tickers: restriction != 'ticker',
          reduceMotion: restriction == 'motion',
          accessibleNavigation: restriction == 'navigation',
        ),
      );
      expect(tester.binding.transientCallbackCount, 0);
      expect(renderer.breathing, 0);
      expect(renderer.blink, 0);
      final paints = renderer.paints;
      await tester.pump(const Duration(seconds: 5));
      expect(renderer.paints, paints);
      activity.value = activity.value == 0.6 ? 0.3 : 0.6;
      await tester.pump();
      expect(renderer.mouth, activity.value);
    }
    await tester.pumpWidget(_host(avatar));
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.binding.transientCallbackCount, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(activity.isObserved, isFalse);
    activity.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native renderer paints every mood at 360dp and disposes cleanly',
    (tester) async {
      final activity = _Activity(0.7);
      for (final mood in AvatarMood.values) {
        await tester.pumpWidget(
          _host(
            InterviewAvatar(size: 360, mood: mood, mouthActivity: activity),
          ),
        );
        expect(
          tester.getSize(find.byType(InterviewAvatar)),
          const Size(360, 360),
        );
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.descendant(
            of: find.byType(InterviewAvatar),
            matching: find.byType(RepaintBoundary),
          ),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          expect(image.width, 360);
          expect(image.height, 360);
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          expect(pixels.getUint8((165 * 360 + 180) * 4 + 3), 255);
          expect(pixels.getUint8((310 * 360 + 180) * 4 + 3), 255);
          expect(pixels.getUint8(3), 0);
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      activity.dispose();
    },
  );

  test(
    'native eye closure and playback mouth change the actual vector raster',
    () async {
      Future<List<int>> region({
        required double blink,
        required double mouth,
        required Rect area,
      }) async {
        final recorder = ui.PictureRecorder();
        const NativeInterviewAvatarRenderer().paint(
          Canvas(recorder),
          const Size(360, 360),
          mood: AvatarMood.speaking,
          breathing: 0,
          blink: blink,
          mouthOpenness: mouth,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(360, 360);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final pixels = <int>[];
        for (var y = area.top.toInt(); y < area.bottom; y++) {
          for (var x = area.left.toInt(); x < area.right; x++) {
            pixels.add(data.getUint32((y * 360 + x) * 4));
          }
        }
        image.dispose();
        picture.dispose();
        return pixels;
      }

      const eyes = Rect.fromLTWH(127, 150, 34, 32);
      const lips = Rect.fromLTWH(162, 194, 35, 24);
      final openEyes = await region(blink: 0, mouth: 0, area: eyes);
      final closedEyes = await region(blink: 1, mouth: 0, area: eyes);
      expect(listEquals(openEyes, closedEyes), isFalse);
      final restingMouth = await region(blink: 0, mouth: 0, area: lips);
      final speakingMouth = await region(blink: 0, mouth: 1, area: lips);
      expect(listEquals(restingMouth, speakingMouth), isFalse);
      expect(await region(blink: 0, mouth: 1, area: eyes), openEyes);
    },
  );
}

Widget _host(
  Widget child, {
  bool tickers = true,
  bool reduceMotion = false,
  bool accessibleNavigation = false,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: MediaQueryData(
      disableAnimations: reduceMotion,
      accessibleNavigation: accessibleNavigation,
    ),
    child: TickerMode(
      enabled: tickers,
      child: Center(child: child),
    ),
  ),
);

class _RecordingRenderer extends InterviewAvatarRenderer {
  double mouth = 0;
  double breathing = 0;
  double blink = 0;
  int paints = 0;

  @override
  void paint(
    Canvas canvas,
    Size size, {
    required AvatarMood mood,
    required double breathing,
    required double blink,
    required double mouthOpenness,
  }) {
    mouth = mouthOpenness;
    this.breathing = breathing;
    this.blink = blink;
    paints++;
  }
}

class _Activity extends ValueNotifier<double> {
  _Activity(super.value);

  bool get isObserved => hasListeners;
}
