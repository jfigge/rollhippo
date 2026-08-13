import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/physics/body.dart';
import 'package:rollhippo/physics/shape.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/render/tray_painter.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:vector_math/vector_math_64.dart';

/// Renders the poker die, whose faces cannot be checked by reading a number
/// off them. Run with:
///
///     flutter test tool/poker.dart
///
/// Three rows. The top is its six faces, each turned square to the glass the
/// way the readout turns the one a die landed on — which is what to look at
/// after moving a path, because a court that reads at 260 pixels and not at 98
/// is a court that does not work. The second is the same die tumbling, where a
/// card printed on the wrong basis shows itself by arriving mirrored or on its
/// side. The third is the rack angle, in the colours a die can be: the one
/// that matters is the red body, which is where the red suits have the
/// furthest to move to stay red — see `DieStyle.red`.
///
/// The numbers are real, unlike most places `flutter test` draws them: this
/// borrows a face off the machine rendering the sheet — see [dieGlyphFont] —
/// because a rank in the corner of a card can only be judged against the card.
/// What the borrowed face is registered as. Any name will do; nothing else in
/// the app asks for one.
const String _font = 'RollHippoTool';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the poker die', () async {
    for (final String face in const <String>[
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      '/System/Library/Fonts/Helvetica.ttc',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ]) {
      final File file = File(face);
      if (!file.existsSync()) continue;
      final FontLoader loader = FontLoader(_font)..addFont(
        Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
      );
      await loader.load();
      dieGlyphFont = _font;
      addTearDown(() => dieGlyphFont = null);
      break;
    }

    const double cell = 260;
    const int columns = 6;
    const int rows = 3;
    const Size size = Size(cell * columns, cell * rows);

    final ConvexShape poker = shapeFor(DieKind.poker);
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0B0E13),
    );

    void draw(
      int column,
      int row,
      Quaternion orientation,
      int colour, {
      DieKind kind = DieKind.poker,
    }) {
      final RigidBody die = RigidBody(
        shape: shapeFor(kind),
        mass: 1,
        orientation: orientation,
      );
      canvas.save();
      canvas.translate(column * cell, row * cell);
      paintDie(
        canvas,
        TrayCamera(
          pixelsPerMetre: cell / (2.4 * die.circumradius),
          eyeDistance: Tuning.eyeDistance,
          centre: const Offset(cell / 2, cell / 2),
        ),
        die,
        DieStyle.ofSpec(DieSpec(kind: kind, colour: colour)),
      );
      canvas.restore();
    }

    // Every face, presented the way the readout presents the one a die landed
    // on: turned square to the glass with its card standing up.
    for (int f = 0; f < poker.faces.length; f++) {
      draw(
        f,
        0,
        markingToScreenTilted(
          poker,
          DieMarking(face: f, edge: 0),
          Tuning.readoutTilt,
        ),
        kDiceWhite,
      );
    }

    // Tumbling: six orientations off a fixed seed, so the sheet is the same
    // every time it is rendered and a change to it is a change to the drawing.
    final math.Random random = math.Random(7);
    for (int i = 0; i < columns; i++) {
      final double u1 = random.nextDouble();
      final double u2 = random.nextDouble();
      final double u3 = random.nextDouble();
      final double a = math.sqrt(1 - u1);
      final double b = math.sqrt(u1);
      draw(
        i,
        1,
        Quaternion(
          a * math.sin(2 * math.pi * u2),
          a * math.cos(2 * math.pi * u2),
          b * math.sin(2 * math.pi * u3),
          b * math.cos(2 * math.pi * u3),
        )..normalize(),
        kDicePalette[i % kDicePalette.length],
      );
    }

    // The rack angle, in six of the eight colours.
    for (int i = 0; i < columns; i++) {
      draw(i, 2, previewFor(DieKind.poker), kDicePalette[i]);
    }

    final ui.Image image = await recorder.endRecording().toImage(
      size.width.round(),
      size.height.round(),
    );
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    final String out =
        Platform.environment['POKER_OUT'] ??
        '${Directory.systemTemp.path}/rollhippo-poker.png';
    File(out).writeAsBytesSync(png!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote $out');
  });
}
