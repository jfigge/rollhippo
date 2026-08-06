import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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
///
/// And a gif of the deal, because the one thing on this table that moves
/// cannot be judged from a still: a card coming off the pile and turning over
/// is either the weight of a hand putting a card down or it is not, and no
/// single frame of it says which.
const double _kOutputScale = 2;

/// The gif: small enough to look at whole, and the same 30 fps off a 120 Hz
/// clock the roll gif is captured on.
const double _kGifScale = 0.5;
const double _kGifStep = 1 / 120;
const int _kCaptureEvery = 4;

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

  test('a card being dealt', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final CardTable table = CardTable(
      width: kHarnessScreen.width / Tuning.logicalPixelsPerMetre,
      height: kHarnessScreen.height / Tuning.logicalPixelsPerMetre,
      deck: Deck(dice: 2, decks: 2, reshuffleAt: 5, random: math.Random(4)),
      colours: <int>[kDicePalette[5], kDicePalette[2]],
    );

    // A card already lying on the glass before the one being watched, because
    // that is what every deal after the first one lands on.
    table.draw();
    while (table.deal.flying) {
      table.advance(_kGifStep);
    }

    // A beat of the shoe standing still, the deal, and a beat of the card
    // lying where it landed. Both beats are for the loop: a gif that starts
    // moving on its first frame and stops dead on its last reads as a stutter
    // rather than as a card being dealt.
    const double lead = 0.25;
    const double hold = 0.6;
    final img.GifEncoder encoder = img.GifEncoder(repeat: 0);
    final int steps = ((lead + Tuning.dealDuration + hold) / _kGifStep).round();
    bool dealt = false;

    for (int step = 0; step <= steps; step++) {
      if (!dealt && step * _kGifStep >= lead) {
        table.draw();
        dealt = true;
      }
      if (step % _kCaptureEvery == 0) {
        encoder.addFrame(
          await _rgba(table),
          // Hundredths of a second, to match the capture interval.
          duration: (100 * _kGifStep * _kCaptureEvery).round(),
        );
      }
      table.advance(_kGifStep);
    }

    final String path = '$dir/cards-deal.gif';
    File(path).writeAsBytesSync(encoder.finish()!);
    // ignore: avoid_print
    print('wrote $path');
  });
}

/// One frame of the table, at gif size and in the bytes the encoder wants.
Future<img.Image> _rgba(CardTable table) async {
  const Size screen = kHarnessScreen;
  final int width = (screen.width * _kGifScale).round();
  final int height = (screen.height * _kGifScale).round();

  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.scale(_kGifScale);
  canvas.drawRect(
    Offset.zero & screen,
    Paint()..color = const Color(0xFF0B0E13),
  );
  paintCardScene(canvas, screen, table);

  final ui.Image shot = await recorder.endRecording().toImage(width, height);
  final ByteData? raw = await shot.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  shot.dispose();
  return img.Image.fromBytes(
    width: width,
    height: height,
    bytes: raw!.buffer,
    numChannels: 4,
  );
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
