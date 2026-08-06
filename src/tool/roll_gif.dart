import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rollhippo/motion/motion.dart';
import 'package:rollhippo/render/tray_painter.dart';
import 'package:rollhippo/tray/tray.dart';

/// Renders a scripted roll to an animated GIF, so the *motion* can be judged
/// rather than a set of poses. Run with:
///
///     flutter test tool/roll_gif.dart
///
/// The simulation always steps at 1/120 s; only the capture is thinned, so the
/// animation shows the same physics the app runs.
const Size kScreen = Size(393, 852);
const double kOutputScale = 0.46;
const int kCaptureEvery = 4; // 120 Hz simulation, 30 fps animation.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('roll gif', () async {
    final DiceTray tray = DiceTray(
      width: kScreen.width / Tuning.logicalPixelsPerMetre,
      height: kScreen.height / Tuning.logicalPixelsPerMetre,
      random: math.Random(11),
    );
    final ManualMotionSource motion = ManualMotionSource();

    final int width = (kScreen.width * kOutputScale).round();
    final int height = (kScreen.height * kOutputScale).round();
    final img.GifEncoder encoder = img.GifEncoder(repeat: 0);

    const double dt = 1 / 120;
    const double duration = 4.6;
    const double shakeAt = 1.3;
    bool shaken = false;

    for (int step = 0; step * dt < duration; step++) {
      final double t = step * dt;
      if (!shaken && t >= shakeAt) {
        motion.shake(seconds: 1.2, frequency: 4.5, amplitude: 0.05, twist: 9);
        shaken = true;
      }

      if (step % kCaptureEvery == 0) {
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final Canvas canvas = Canvas(recorder);
        canvas.scale(kOutputScale);
        TrayPainter(
          tray: tray,
          repaint: ValueNotifier<int>(0),
        ).paint(canvas, kScreen);
        final ui.Image shot = await recorder.endRecording().toImage(
          width,
          height,
        );
        final ByteData? raw = await shot.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        shot.dispose();

        encoder.addFrame(
          img.Image.fromBytes(
            width: width,
            height: height,
            bytes: raw!.buffer,
            numChannels: 4,
          ),
          // Hundredths of a second, to match the capture interval.
          duration: (100 * dt * kCaptureEvery).round(),
        );
      }

      tray.update(motion.sample(dt), dt);
    }

    final Uint8List? gif = encoder.finish();
    final String out =
        Platform.environment['GIF_OUT'] ??
        '${Directory.systemTemp.path}/rollhippo-roll.gif';
    File(out).writeAsBytesSync(gif!);
    // ignore: avoid_print
    print('wrote $out  ${(gif.length / 1024).round()} kB  ${width}x$height');
  });
}
