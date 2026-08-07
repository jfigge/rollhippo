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

/// Renders the hippopotamus, which is the one die whose picture is not its own
/// solid and so the one that cannot be checked by reading it. Run with:
///
///     flutter test tool/hippo.dart
///
/// Three rows. The top is the six poses the readout can present it in — one
/// per face of the cube it is carved from, turned exactly as a roll would turn
/// it — which is what to look at after moving a lump: four of them should be a
/// hippopotamus you could photograph, and the other two are the ones the
/// numbering costs (see [paintHippo]). The middle row is the same animal
/// tumbling, which is where a lump drawn in the wrong order shows itself. The
/// bottom row is the rack: the angle the picker introduces it at, in the
/// colours it can be.
///
/// The numbers are real, unlike everywhere else `flutter test` draws them:
/// this borrows a face off the machine rendering the sheet — see
/// [dieGlyphFont] — because a numeral printed on an animal can only be judged
/// against the animal.
/// What the borrowed face is registered as. Any name will do; nothing else in
/// the app asks for one.
const String _font = 'RollHippoTool';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the hippopotamus', () async {
    // A real font, so the numbers on the animal are numbers rather than the
    // boxes `flutter test` draws by default — see [dieGlyphFont]. They are
    // half of what this sheet is for: a numeral printed on a hippopotamus can
    // only be judged against the hippopotamus. Whatever the machine rendering
    // this happens to have, and no numbers at all if it has none of them.
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
    const int rows = 4;
    const Size size = Size(cell * columns, cell * rows);

    final ConvexShape hippo = shapeFor(DieKind.hippo);
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
      DieKind kind = DieKind.hippo,
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
    // on: turned square to the glass with its number standing up.
    for (int f = 0; f < hippo.faces.length; f++) {
      draw(
        f,
        0,
        markingToScreenTilted(
          hippo,
          DieMarking(face: f, edge: 0),
          Tuning.readoutTilt,
        ),
        kDiceWhite,
      );
    }

    // Tumbling: six orientations off a fixed seed, so the sheet is the same
    // every time it is rendered and a change to it is a change to the animal.
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
      draw(i, 2, previewFor(DieKind.hippo), kDicePalette[i]);
    }

    // And the die it is: the same six faces, presented the same way, so that
    // the numbers on the animal can be judged against the numbers they are
    // standing in for rather than against nothing.
    for (int f = 0; f < hippo.faces.length; f++) {
      draw(
        f,
        3,
        markingToScreenTilted(
          shapeFor(DieKind.d6),
          DieMarking(face: f, edge: 0),
          Tuning.readoutTilt,
        ),
        kDiceWhite,
        kind: DieKind.d6,
      );
    }

    final ui.Image image = await recorder.endRecording().toImage(
      size.width.round(),
      size.height.round(),
    );
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    final String out =
        Platform.environment['HIPPO_OUT'] ??
        '${Directory.systemTemp.path}/rollhippo-hippo.png';
    File(out).writeAsBytesSync(png!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote $out');
  });
}
