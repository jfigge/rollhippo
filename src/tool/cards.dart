import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/chrome.dart';
import 'package:rollhippo/cards/deck.dart';
import 'package:rollhippo/render/card_painter.dart';
import 'package:rollhippo/tray/tray.dart';

/// Renders the card table, so the shoe and a dealt card can be looked at
/// without a device in your hand. Run with:
///
///     flutter test tool/cards.dart
///
/// Three images: the position the table starts in, the same table one draw
/// later, and that card with its two dice printed in two of the picker's
/// colours — which is the whole of what the card panel's swatches do. Everything with a shape
/// to it is exactly what the phone draws; the pips are real, because they are
/// circles rather than glyphs.
const double _kOutputScale = 2;

void main() {
  final String dir =
      Platform.environment['CARDS_OUT'] ?? Directory.systemTemp.path;

  test('the card table, before and after a draw', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // One deck, looked at through three tables: the shoe is what it is, and
    // the colour is only how the dice on a card are printed. Sharing it means
    // the coloured picture is the same card as the ivory one, so the two can
    // be held up against each other.
    final Deck deck = Deck(
      dice: 2,
      decks: 2,
      reshuffleAt: 5,
      random: math.Random(4),
    );
    CardTable table({List<int> colours = const <int>[]}) => CardTable(
      width: kHarnessScreen.width / Tuning.logicalPixelsPerMetre,
      height: kHarnessScreen.height / Tuning.logicalPixelsPerMetre,
      deck: deck,
      colours: colours,
    );

    await _write('$dir/cards-fresh.png', table());
    deck.draw();
    await _write('$dir/cards-drawn.png', table());
    // Two colours, because they are chosen a die at a time: the top die of the
    // card is the first of them and the one below it the second, which is also
    // the only thing on a card that says which die is which.
    await _write(
      '$dir/cards-colour.png',
      table(colours: <int>[kDicePalette[5], kDicePalette[2]]),
    );
  });
}

Future<void> _write(String path, CardTable table) async {
  const Size screen = kHarnessScreen;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  // The scene is laid out in logical pixels; the image is twice that, so that
  // the pips and the lattice on a card back can be looked at.
  canvas.scale(_kOutputScale);
  canvas.drawRect(
    Offset.zero & screen,
    Paint()..color = const Color(0xFF0B0E13),
  );
  paintCardScene(canvas, screen, table);

  final ui.Image image = await recorder.endRecording().toImage(
    (screen.width * _kOutputScale).round(),
    (screen.height * _kOutputScale).round(),
  );
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote $path');
}
