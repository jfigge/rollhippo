import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../cards/deck.dart';
import '../tray/tray.dart';
import 'card_painter.dart';
import 'tray_painter.dart';

/// One card, face up and standing still, printed exactly as the table prints
/// the card it deals.
///
/// The picker's answer to `DiePreview`, and for the same reason: card mode is
/// configuring a card, and a rack of three-dimensional D6s says what the dice
/// are without ever saying what comes out. This is drawn by [paintCardInto], so
/// it is the same stock, the same rule, the same corner diamonds and the same
/// pip squares that arrive on the glass.
///
/// It has no size of its own — [Size.infinite], like `DiePreview` — and fits
/// the card into whatever box it is given, centred, on the card's own aspect.
class CardPreview extends StatelessWidget {
  const CardPreview({super.key, required this.faces, required this.colours});

  /// What the card reads, one value 1..6 per die, the head of the card first.
  final List<int> faces;

  /// What each of those dice is printed in, packed ARGB, in the same order —
  /// the same list [CardTable.colours] is, and for the same reason: the numbers
  /// are the card, the ink is not one of them.
  final List<int> colours;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CardPreviewPainter(faces: faces, colours: colours),
      size: Size.infinite,
    );
  }
}

class _CardPreviewPainter extends CustomPainter {
  const _CardPreviewPainter({required this.faces, required this.colours});

  final List<int> faces;
  final List<int> colours;

  @override
  void paint(Canvas canvas, Size size) {
    if (faces.isEmpty) return;

    // The largest card that fits, centred. The caller is expected to have
    // shaped its box already, but a card is a fixed thing and letting it out of
    // its proportions to fill a box would be the one distortion nothing else in
    // the app allows.
    const double aspect = Tuning.cardWidth / Tuning.cardHeight;
    final double width = math.min(size.width, size.height * aspect);
    final Rect rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: width,
      height: width / aspect,
    );

    paintCardInto(canvas, rect, PlayingCard(faces), <DieStyle>[
      for (final int colour in colours) DieStyle.of(colour),
    ]);
  }

  @override
  bool shouldRepaint(_CardPreviewPainter oldDelegate) =>
      !_same(oldDelegate.faces, faces) || !_same(oldDelegate.colours, colours);
}

/// Element-wise, because the lists are what the card *is*: a new one holding
/// the same numbers in the same ink is the same picture, and identity would
/// have it repaint on every rebuild of the picker.
bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
