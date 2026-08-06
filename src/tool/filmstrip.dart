import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/motion/motion.dart';
import 'package:rollhippo/render/tray_painter.dart';
import 'package:rollhippo/tray/tray.dart';

/// Renders a scripted roll to a contact sheet, so the motion can be looked at
/// without a device in the loop. Run with:
///
///     flutter test tool/filmstrip.dart
const Size kScreen = Size(393, 852); // iPhone 15 Pro, logical pixels.

Future<ui.Image> frame(DiceTray tray) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  TrayPainter(
    tray: tray,
    repaint: ValueNotifier<int>(0),
  ).paint(canvas, kScreen);
  return recorder.endRecording().toImage(
    kScreen.width.round(),
    kScreen.height.round(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('filmstrip', () async {
    final DiceTray tray = DiceTray(
      width: kScreen.width / Tuning.logicalPixelsPerMetre,
      height: kScreen.height / Tuning.logicalPixelsPerMetre,
      readout: true,
      random: math.Random(11),
    );
    final ManualMotionSource motion = ManualMotionSource();

    // Held upright and still, then shaken for a second, then held still again.
    const double shakeStart = 1.0;
    const List<double> captures = <double>[
      0.02, 0.09, 0.16, 0.30, // falling in and landing
      1.06, 1.16, 1.30, 1.55, // mid-shake
      2.05, 2.25, 2.60, 3.40, // settling and settled
      3.75, 3.95, 4.15, 4.45, // turning to be read, and read
    ];

    final List<ui.Image> frames = <ui.Image>[];
    const double dt = 1 / 120;
    double t = 0;
    int next = 0;
    bool shaken = false;

    while (next < captures.length) {
      if (!shaken && t >= shakeStart) {
        motion.shake(seconds: 1.0, frequency: 4.5, amplitude: 0.05, twist: 9);
        shaken = true;
      }
      if (t >= captures[next]) {
        frames.add(await frame(tray));
        next++;
      }
      tray.update(motion.sample(dt), dt);
      t += dt;
    }

    // Contact sheet, four across.
    const int columns = 4;
    const double scale = 0.42;
    const double gap = 10;
    final double cellW = kScreen.width * scale;
    final double cellH = kScreen.height * scale;
    final int rows = (frames.length / columns).ceil();

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final double sheetW = columns * cellW + (columns + 1) * gap;
    final double sheetH = rows * cellH + (rows + 1) * gap;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, sheetW, sheetH),
      Paint()..color = const Color(0xFF07090D),
    );
    for (int i = 0; i < frames.length; i++) {
      final double x = gap + (i % columns) * (cellW + gap);
      final double y = gap + (i ~/ columns) * (cellH + gap);
      canvas.drawImageRect(
        frames[i],
        Rect.fromLTWH(0, 0, kScreen.width, kScreen.height),
        Rect.fromLTWH(x, y, cellW, cellH),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }

    final ui.Image sheet = await recorder.endRecording().toImage(
      sheetW.round(),
      sheetH.round(),
    );
    final ByteData? png = await sheet.toByteData(
      format: ui.ImageByteFormat.png,
    );

    final String out =
        Platform.environment['FILMSTRIP_OUT'] ??
        '${Directory.systemTemp.path}/rollhippo-filmstrip.png';
    File(out).writeAsBytesSync(png!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote $out  (${sheetW.round()}x${sheetH.round()})');
  });
}
