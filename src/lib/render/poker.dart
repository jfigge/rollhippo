/// The poker die's faces, drawn as the card faces they are.
///
/// A real poker die does not print J, Q, K and A on its court faces; it prints
/// the cards — pips laid out the way a card lays them out, and an engraved
/// figure for the three that have no pips — with a rank-and-suit index in the
/// corner at both ends. This is that, and it is drawn rather than set in a
/// font for the reason the hippopotamus is drawn: the app leaves `fontFamily`
/// null and takes the platform's own face (see [dieGlyphFont]), so anything
/// past the ASCII the numerals already use is a bet on what one phone's
/// fallback holds and another's does not. The suits and the courts are paths,
/// which are the same on both. Only the rank letter is text, and A, J, K, Q
/// and the digits are in every font there has ever been.
///
/// Everything here is drawn into a box one unit across, centred on the origin,
/// with y running *down* — the same space [dieGlyph] is laid out in and the
/// same one a face's own basis maps, so the caller sets up one transform and
/// this draws into it.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../tray/dice.dart';
import 'die_glyph.dart';

/// The four suits.
enum PokerSuit {
  spade,
  heart,
  diamond,
  club;

  /// Whether the suit is printed in red. Half of what a card carries: a nine
  /// of diamonds and a nine of spades differ in their colour before they
  /// differ in anything else.
  bool get red => this == PokerSuit.heart || this == PokerSuit.diamond;
}

/// One face: what rank it is, which suit it carries, and — for the three that
/// have pips — how many.
///
/// The suits are decoration rather than a hand. A real five-die poker set
/// varies them *between* dice so a flush is a thing you can roll; every poker
/// die here is one [DieKind] and so identical to every other, which means a
/// suit says which card this is and nothing about what a handful of them
/// makes. All four appear, which is what they are chosen for.
class PokerFace {
  const PokerFace(this.rank, this.suit, {this.pips = 0});

  final String rank;
  final PokerSuit suit;

  /// How many pips the face lays out, or zero for a court.
  final int pips;

  bool get court => pips == 0;
}

/// The six faces, by the value [DieKind.poker] prints on them — nine to ace as
/// 9 to 14, so that the numbers sort the way the ranks do.
///
/// All four suits appear, which is what the assignment is for. The ace is the
/// ace of spades because that is what an ace is; the king carries a red suit
/// so that the red it is printed in on an ivory die is also the red it falls
/// back to on every other body.
const Map<int, PokerFace> kPokerFaces = <int, PokerFace>{
  9: PokerFace('9', PokerSuit.spade, pips: 9),
  10: PokerFace('10', PokerSuit.diamond, pips: 10),
  11: PokerFace('J', PokerSuit.heart),
  12: PokerFace('Q', PokerSuit.club),
  13: PokerFace('K', PokerSuit.diamond),
  14: PokerFace('A', PokerSuit.spade, pips: 1),
};

/// What the three courts are printed in on an ivory die.
///
/// A real poker die prints its courts in three colours that have nothing to do
/// with their suits — the one this was drawn from has a red king, a green
/// queen and a blue jack — because three engraved figures at that size are
/// hard to tell apart and a colour is read before a crown is. It is a fact
/// about the *ivory* die alone: painted any other colour, a poker die has one
/// ink and one red like every other die here, and three inks nobody chose
/// against the body would be worse than no ink at all.
///
/// The blue and the green are [kDicePalette]'s, a step deeper — those were
/// picked to read as a die *body* against the tray's slate lining, and these
/// have to read as ink on ivory.
const Map<int, Color> _kCourtOnIvory = <int, Color>{
  11: Color(0xFF2E5FA8),
  12: Color(0xFF2F7D48),
  13: Color(0xFFB3453F),
};

/// Paints the card for [value] into the unit box centred on the origin.
///
/// [ink] is the die's own — dark on an ivory body, cream on a graphite one —
/// and [red] is what a red suit is printed in on that same body. Both come
/// from the `DieStyle`, so a poker die is still the colour its owner painted
/// it and the red still lifts off it. [body] is the colour it was painted,
/// and is asked only the one question in [_kCourtOnIvory].
void paintPokerFace(
  Canvas canvas,
  int value, {
  required Color ink,
  required Color red,
  required int body,
}) {
  final PokerFace? face = kPokerFaces[value];
  if (face == null) return;
  final Color suitInk =
      body == kDiceWhite && _kCourtOnIvory.containsKey(value)
          ? _kCourtOnIvory[value]!
          : face.suit.red
          ? red
          : ink;

  _index(canvas, face, suitInk);
  if (face.court) {
    _court(canvas, face, suitInk);
  } else {
    _pips(canvas, face, suitInk);
  }
}

/// The corner index, at both ends — a rank over its suit, and the same again
/// through half a turn, because a card is read from either end and a die lands
/// either way up.
///
/// There is deliberately no underline under the nine, which is what
/// `_paintNumber` gives a numeral that reads as a six upside down. It has
/// nothing to disambiguate here: this die's ranks are nine, ten, jack, queen,
/// king and ace, so an upside-down nine names no face of it — and nine spades
/// are laid out in the middle either way up.
void _index(Canvas canvas, PokerFace face, Color ink) {
  for (int turn = 0; turn < 2; turn++) {
    canvas.save();
    canvas.rotate(turn * math.pi);
    _label(canvas, const Offset(-0.385, -0.375), face.rank, 0.135, ink);
    canvas.save();
    canvas.translate(-0.385, -0.235);
    canvas.scale(0.105);
    canvas.drawPath(pokerSuitPath(face.suit), Paint()..color = ink);
    canvas.restore();
    canvas.restore();
  }
}

/// The pips, in the arrangement a card of that rank uses: two flanking columns
/// of four with whatever is left over down the middle, and everything below
/// the waist upside down — which is the detail that makes it read as a nine of
/// spades rather than as nine spades.
void _pips(Canvas canvas, PokerFace face, Color ink) {
  // An ace's pip is the whole face; the rest are a row's worth.
  final double size = face.pips == 1 ? 0.40 : 0.145;
  final List<Offset> at = <Offset>[];
  if (face.pips == 1) {
    at.add(Offset.zero);
  } else {
    for (final double x in <double>[-0.155, 0.155]) {
      for (final double y in <double>[-0.285, -0.095, 0.095, 0.285]) {
        at.add(Offset(x, y));
      }
    }
    if (face.pips == 9) {
      at.add(Offset.zero);
    } else {
      at.add(const Offset(0, -0.19));
      at.add(const Offset(0, 0.19));
    }
  }

  final Path suit = pokerSuitPath(face.suit);
  final Paint paint = Paint()..color = ink;
  for (final Offset centre in at) {
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    if (centre.dy > 0.001) canvas.rotate(math.pi);
    canvas.scale(size);
    canvas.drawPath(suit, paint);
    canvas.restore();
  }
}

/// How far in a court figure is drawn from the edge of its face.
///
/// The figure is what a card's own is — a bust reaching the sides — and a card
/// can afford that because its index sits in a margin *outside* the picture. A
/// die face has no margin: it is square, and the index is on the picture. So
/// the whole figure shrinks towards the middle until the widest things on it
/// clear the corners — the sceptre, the flower and the halberd, every one of
/// which is held out to the side the index is in. The scale takes the stroke
/// width with it, which is what [_court] divides back out.
const double _courtInset = 0.80;

/// A court figure: the top half, and then the same again through half a turn,
/// which is how a real court card is built and half the drawing.
///
/// A bust, and a large-headed one, and both of those are the size. The half a
/// court gets is 44 hundredths of a face, which on a 16 mm die at 3× is about
/// 43 real pixels — a figure drawn to a card's own proportions puts the head
/// inside eight of them. Every interior line costs more than it gives at that
/// size, too: the version of this with a sash and a seam down the robe read as
/// a grid with two heads on it. So crown, head, ruff, shoulders, one held
/// thing, and nothing else.
void _court(Canvas canvas, PokerFace face, Color ink) {
  final Paint line =
      Paint()
        ..style = PaintingStyle.stroke
        // Divided by [_courtInset] below, so that shrinking the figure to
        // clear the index does not thin every line on it as well.
        ..strokeWidth = 0.016 / _courtInset
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = ink;
  final Paint fill = Paint()..color = ink;

  canvas.save();
  canvas.scale(_courtInset);

  // The waist, which both halves stop at. Let them cross it and the two
  // copies overlap into a blob.
  canvas.drawLine(const Offset(-0.34, 0), const Offset(0.34, 0), line);

  for (int turn = 0; turn < 2; turn++) {
    canvas.save();
    canvas.rotate(turn * math.pi);

    // Shoulders: out to the sides and down to the waist, and no further.
    canvas.drawPath(
      Path()
        ..moveTo(-0.34, -0.02)
        ..cubicTo(-0.33, -0.115, -0.26, -0.155, -0.175, -0.165)
        ..lineTo(0.175, -0.165)
        ..cubicTo(0.26, -0.155, 0.33, -0.115, 0.34, -0.02),
      line,
    );
    // The ruff, which is the one detail that says "court" on its own.
    canvas.drawPath(
      Path()
        ..moveTo(-0.185, -0.16)
        ..lineTo(-0.10, -0.105)
        ..lineTo(0, -0.16)
        ..lineTo(0.10, -0.105)
        ..lineTo(0.185, -0.16),
      line,
    );

    // The head, filling most of the half, with a face on it.
    canvas.drawCircle(const Offset(0, -0.275), 0.112, line);
    canvas.drawCircle(const Offset(-0.042, -0.295), 0.014, fill);
    canvas.drawCircle(const Offset(0.042, -0.295), 0.014, fill);

    switch (face.rank) {
      case 'K':
        // A crown with a cross on it, a beard, and a sceptre up the side.
        canvas.drawPath(
          Path()
            ..moveTo(-0.135, -0.345)
            ..lineTo(-0.115, -0.44)
            ..lineTo(-0.058, -0.375)
            ..lineTo(0, -0.455)
            ..lineTo(0.058, -0.375)
            ..lineTo(0.115, -0.44)
            ..lineTo(0.135, -0.345)
            ..close(),
          fill,
        );
        canvas.drawRect(const Rect.fromLTRB(-0.016, -0.50, 0.016, -0.44), fill);
        canvas.drawRect(const Rect.fromLTRB(-0.05, -0.485, 0.05, -0.455), fill);
        // The beard, which is most of what tells a king from a jack.
        canvas.drawPath(
          Path()
            ..moveTo(-0.098, -0.245)
            ..cubicTo(-0.105, -0.15, -0.05, -0.125, 0, -0.125)
            ..cubicTo(0.05, -0.125, 0.105, -0.15, 0.098, -0.245),
          line,
        );
        canvas.drawLine(
          const Offset(0.30, -0.44),
          const Offset(0.235, -0.10),
          line,
        );
        canvas.drawCircle(const Offset(0.305, -0.465), 0.028, fill);
      case 'Q':
        // A coronet on loose hair, and a flower up the side.
        canvas.drawPath(
          Path()
            ..moveTo(-0.12, -0.345)
            ..lineTo(-0.10, -0.415)
            ..lineTo(0, -0.365)
            ..lineTo(0.10, -0.415)
            ..lineTo(0.12, -0.345)
            ..close(),
          fill,
        );
        for (final double x in <double>[-0.10, 0, 0.10]) {
          canvas.drawCircle(Offset(x, -0.428), 0.024, fill);
        }
        canvas.drawPath(
          Path()
            ..moveTo(-0.108, -0.31)
            ..cubicTo(-0.19, -0.26, -0.20, -0.19, -0.165, -0.15)
            ..moveTo(0.108, -0.31)
            ..cubicTo(0.19, -0.26, 0.20, -0.19, 0.165, -0.15),
          line,
        );
        canvas.drawLine(
          const Offset(-0.30, -0.41),
          const Offset(-0.235, -0.10),
          line,
        );
        for (int petal = 0; petal < 5; petal++) {
          final double a = petal * 2 * math.pi / 5;
          canvas.drawCircle(
            Offset(-0.305 + 0.036 * math.cos(a), -0.44 + 0.036 * math.sin(a)),
            0.026,
            fill,
          );
        }
      case 'J':
        // A soft cap with a feather in it, and a halberd.
        canvas.drawPath(
          Path()
            ..moveTo(-0.115, -0.335)
            ..cubicTo(-0.15, -0.44, 0.06, -0.475, 0.125, -0.40)
            ..cubicTo(0.145, -0.375, 0.135, -0.345, 0.115, -0.335)
            ..close(),
          fill,
        );
        canvas.drawPath(
          Path()
            ..moveTo(0.12, -0.415)
            ..cubicTo(0.215, -0.49, 0.28, -0.50, 0.305, -0.475),
          line,
        );
        canvas.drawLine(
          const Offset(-0.30, -0.415),
          const Offset(-0.235, -0.10),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(-0.305, -0.445)
            ..lineTo(-0.25, -0.35)
            ..lineTo(-0.345, -0.365)
            ..close(),
          fill,
        );
    }
    canvas.restore();
  }
  canvas.restore();
}

/// One suit, in a box one unit across centred on the origin.
Path pokerSuitPath(PokerSuit suit) {
  switch (suit) {
    case PokerSuit.spade:
      return Path()
        ..moveTo(0, -0.46)
        ..cubicTo(-0.10, -0.22, -0.46, -0.10, -0.46, 0.10)
        ..cubicTo(-0.46, 0.28, -0.30, 0.36, -0.16, 0.31)
        ..cubicTo(-0.10, 0.29, -0.06, 0.25, -0.04, 0.21)
        ..cubicTo(-0.05, 0.34, -0.10, 0.42, -0.16, 0.46)
        ..lineTo(0.16, 0.46)
        ..cubicTo(0.10, 0.42, 0.05, 0.34, 0.04, 0.21)
        ..cubicTo(0.06, 0.25, 0.10, 0.29, 0.16, 0.31)
        ..cubicTo(0.30, 0.36, 0.46, 0.28, 0.46, 0.10)
        ..cubicTo(0.46, -0.10, 0.10, -0.22, 0, -0.46)
        ..close();
    case PokerSuit.heart:
      return Path()
        ..moveTo(0, -0.26)
        ..cubicTo(0.12, -0.46, 0.46, -0.40, 0.46, -0.08)
        ..cubicTo(0.46, 0.14, 0.20, 0.30, 0, 0.46)
        ..cubicTo(-0.20, 0.30, -0.46, 0.14, -0.46, -0.08)
        ..cubicTo(-0.46, -0.40, -0.12, -0.46, 0, -0.26)
        ..close();
    case PokerSuit.diamond:
      // Slightly waisted rather than a plain rhombus, which is what a printed
      // diamond is and what stops it reading as a lozenge at die size.
      return Path()
        ..moveTo(0, -0.48)
        ..cubicTo(0.10, -0.22, 0.22, -0.10, 0.33, 0)
        ..cubicTo(0.22, 0.10, 0.10, 0.22, 0, 0.48)
        ..cubicTo(-0.10, 0.22, -0.22, 0.10, -0.33, 0)
        ..cubicTo(-0.22, -0.10, -0.10, -0.22, 0, -0.48)
        ..close();
    case PokerSuit.club:
      return Path.combine(
        PathOperation.union,
        Path()
          ..addOval(
            Rect.fromCircle(center: const Offset(0, -0.22), radius: 0.19),
          )
          ..addOval(
            Rect.fromCircle(center: const Offset(-0.24, 0.10), radius: 0.19),
          )
          ..addOval(
            Rect.fromCircle(center: const Offset(0.24, 0.10), radius: 0.19),
          ),
        Path()
          ..moveTo(-0.05, 0.02)
          ..cubicTo(-0.05, 0.22, -0.12, 0.38, -0.19, 0.47)
          ..lineTo(0.19, 0.47)
          ..cubicTo(0.12, 0.38, 0.05, 0.22, 0.05, 0.02)
          ..close(),
      );
  }
}

/// The rank letter, centred on [at] and scaled to a cap height of [height].
void _label(Canvas canvas, Offset at, String text, double height, Color ink) {
  final ui.Paragraph glyph = dieGlyph(text, ink);
  // A paragraph's height is its line box — ascent, descent and leading — and
  // what wants to be [height] is the letter inside it.
  final double scale = height / (glyph.height * 0.72);
  canvas.save();
  canvas.translate(at.dx, at.dy);
  canvas.scale(scale);
  canvas.drawParagraph(
    glyph,
    Offset(-dieGlyphLayoutWidth / 2, -glyph.height / 2),
  );
  canvas.restore();
}
