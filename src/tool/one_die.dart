import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/physics/body.dart';
import 'package:rollhippo/render/tray_painter.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:vector_math/vector_math_64.dart';

/// Renders one die at a known orientation, big, so the pip mapping can be
/// checked by eye against what the code claims. Run with:
///
///     flutter test tool/one_die.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one die', () async {
    const Size screen = Size(420, 420);
    final DiceTray tray = DiceTray(
      width: screen.width / Tuning.logicalPixelsPerMetre,
      height: screen.height / Tuning.logicalPixelsPerMetre,
      dice: const <DieSpec>[DieSpec(kind: DieKind.d6, colour: kDiceWhite)],
      random: math.Random(0),
    );
    final RigidBody die = tray.dice.first;
    die.position = Vector3(0, 0, -Tuning.trayDepth * 0.35);
    // Identity: local +x points right, +y up, +z at the viewer. So the die
    // should show 1 on the right, 2 on top and 3 facing us — tipped slightly so
    // all three are visible at once.
    die.orientation = Quaternion.euler(-0.5, 0.42, 0);
    die.syncDerived();
    tray.world.gravity.setValues(0, -9.81, 0);

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    TrayPainter(
      tray: tray,
      repaint: ValueNotifier<int>(0),
    ).paint(canvas, screen);
    final ui.Image image = await recorder.endRecording().toImage(
      screen.width.round(),
      screen.height.round(),
    );
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    final String out =
        Platform.environment['DIE_OUT'] ??
        '${Directory.systemTemp.path}/rollhippo-die.png';
    File(out).writeAsBytesSync(png!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote $out — faceUp reads ${tray.faceUp(die)}');
  });
}
