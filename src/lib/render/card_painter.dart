import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../cards/deck.dart';
import '../tray/tray.dart';
import 'tray_painter.dart';

/// The face of a card, and the ink the dice on it are printed in.
const Color _cardStock = Color(0xFFF6F2E8);
const Color _cardInk = Color(0xFF20242B);

/// The back. The blue everything chosen in this app is drawn in, so a pile of
/// cards belongs to the same object as a kept die and a selected slot.
const Color _cardBack = Color(0xFF3F6FA8);
const Color _cardBackDeep = Color(0xFF2F5581);
const Color _cardBackInk = Color(0xFF6E9AD0);

/// The face's border, and the rule inside it. The blue pair with its hue turned
/// round — same saturation, same lightness, 213° become 4° — so the two sides of
/// a card are the same printing in two inks rather than two different designs.
///
/// Red because the face is the side that says something. The pile it is lying
/// against is blue and so is everything else chosen in this app, and a dealt
/// card wants to be the one thing on the glass that is not.
const Color _cardFaceBorder = Color(0xFFA8463F);
const Color _cardFaceInk = Color(0xFFD0756E);

/// How much of the tray's depth the pile is allowed to take up.
const double _maxPileDepth = 0.45;

/// A card's corner radius, as a fraction of its width.
const double _kCorner = 0.06;

/// The blue border, as a fraction of a card's width. Both faces of a card carry
/// it, so it lives out here rather than twice over.
const double _kBorder = 0.055;

/// How far out of square a hand-shuffled pile stands, as a fraction of its own
/// height.
const double _kPileLean = 0.10;

/// The cards under the top one. Shades of the back rather than of the stock:
/// a pile seen this near to head on shows no edge worth the name, so what says
/// "several" has to be the backs of the ones underneath — and a pale strip of
/// stock around a card reads as a fringe on it rather than as more cards.
const Color _cardEdge = Color(0xFF35608F);
const Color _cardEdgeDark = Color(0xFF24405F);

/// The whole card table: the box, the pile standing in it, and whatever has
/// been dealt onto the glass.
void paintCardScene(Canvas canvas, Size size, CardTable table) {
  final TrayCamera camera = TrayCamera(
    pixelsPerMetre: size.width / table.width,
    eyeDistance: Tuning.eyeDistance,
    centre: Offset(size.width / 2, size.height / 2),
  );

  paintTrayBox(
    canvas,
    camera,
    width: table.width,
    height: table.height,
    depth: table.depth,
  );

  _paintPile(canvas, camera, table);

  final PlayingCard? shown = table.deck.shown;
  if (shown != null) {
    _paintShadow(canvas, camera, _drawnY(table), 0);
    _paintFace(canvas, camera, shown, _drawnY(table), 0);
  }
}

/// Where a drawn card lies: along the bottom of the glass.
///
/// The pile has the middle, and the two of them cannot both have it. A card at
/// full size on the glass is nearly half the height of the tray and the pile
/// two hundred millimetres behind it is a third, so a card laid over a centred
/// pile would hide the deck completely. The floor is where the dice used to
/// settle and where a thumb already is, and from there the card covers only the
/// bottom of the pile and leaves the top of it in view.
///
/// Worked out from the tray rather than pinned, because "on the floor" is a
/// different number on every screen and the one thing it must not be is a
/// number that happens to look right on one phone.
double _drawnY(CardTable table) =>
    -table.height / 2 + Tuning.cardHeight / 2 + Tuning.cardFloorGap;

/// One card-shaped rounded rect, at [y] and [z] in the tray, filled with
/// [paint].
///
/// A card at a constant depth projects to a plain rectangle — the perspective
/// scales it about the middle of the screen and leaves it a rectangle — so
/// there is nothing here that needs eight corners projected one at a time.
void _cardRect(
  Canvas canvas,
  TrayCamera camera,
  double x,
  double y,
  double z,
  Paint paint,
) {
  final double scale = camera.scaleAt(z) * camera.pixelsPerMetre;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: camera.project(Vector3(x, y, z)),
        width: Tuning.cardWidth * scale,
        height: Tuning.cardHeight * scale,
      ),
      Radius.circular(Tuning.cardWidth * _kCorner * scale),
    ),
    paint,
  );
}

/// What is left of the shoe, face down in the middle of the back wall.
///
/// Drawn as a run of cards rather than as a box with a card printed on the
/// front of it. A box has square corners, and a square corner behind a rounded
/// one pokes out past it — which is exactly the pale fringe a slab of card
/// stock had around it before. Every layer here is card-shaped, so there is
/// nothing in the pile that is not the shape of a card.
void _paintPile(Canvas canvas, TrayCamera camera, CardTable table) {
  final int count = table.deck.remaining;
  if (count == 0) return;

  // Two millimetres off the wall, so the pile reads as standing in the box
  // rather than printed on the back of it.
  //
  // Real stock while a real stack would fit, and no thicker. Three dice across
  // three decks is six hundred and forty-eight cards, which at 0.32 mm each is
  // a pile deeper than the tray — it would come out through the glass. Past
  // the cap the pile stops being a measurement and goes back to being a
  // picture of one, which is the only thing it can be at that size.
  final double back = -table.depth + 0.002;
  final double thickness = math.min(
    count * Tuning.cardThickness,
    table.depth * _maxPileDepth,
  );
  // The lean of the pile, and the whole reason you can tell there is more than
  // one card in it. A stack this square to the glass hides its own edge — the
  // front card is nearer, so it projects larger than every card behind it and
  // covers the lot. A pile that has been shuffled by hand is not square, and
  // this is how far out of true it is: a tenth of its own height, which is
  // nothing for the six cards left at the end of a shoe and a visible fan for
  // the six hundred at the start of one.
  //
  // Taken off the middle rather than added to one side of it, so that the pile
  // as a whole still stands in the centre of the wall and only the fan itself
  // is off square.
  final double lean = thickness * _kPileLean;

  // Enough layers to read as a stack and not so many that the near ones land
  // inside a pixel of each other.
  const int layers = 16;
  final Paint edge = Paint();
  for (int i = 0; i < layers; i++) {
    final double t = i / layers;
    edge.color = Color.lerp(_cardEdgeDark, _cardEdge, t)!;
    _cardRect(canvas, camera, (0.5 - t) * lean, 0, back + thickness * t, edge);
  }

  _paintBack(canvas, camera, -lean / 2, 0, back + thickness);
}

/// The top of the pile: the back of a card.
///
/// A lattice inside a border, which is what the back of a playing card has
/// looked like since somebody worked out that a plain one shows every crease.
/// Drawn in the card's own millimetres and scaled into place, so the pattern
/// holds together at whatever size the pile happens to be seen at.
void _paintBack(
  Canvas canvas,
  TrayCamera camera,
  double x,
  double y,
  double z,
) {
  const double w = Tuning.cardWidth;
  const double h = Tuning.cardHeight;

  canvas.save();
  _intoCard(canvas, camera, x, y, z);

  const Rect rect = Rect.fromLTRB(-w / 2, -h / 2, w / 2, h / 2);
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(w * _kCorner)),
    Paint()..color = _cardBack,
  );

  final RRect panel = RRect.fromRectAndRadius(
    rect.deflate(w * _kBorder),
    const Radius.circular(w * 0.045),
  );
  canvas.drawRRect(panel, Paint()..color = _cardBackDeep);

  canvas.save();
  canvas.clipRRect(panel);
  final Paint hatch =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.013
        ..color = _cardBackInk.withValues(alpha: 0.5);
  const double reach = w + h;
  for (double d = -reach; d <= reach; d += w * 0.15) {
    canvas.drawLine(Offset(d, -reach), Offset(d + 2 * reach, reach), hatch);
    canvas.drawLine(Offset(d, reach), Offset(d + 2 * reach, -reach), hatch);
  }
  canvas.restore();

  canvas.drawRRect(
    panel,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.020
      ..color = _cardBackInk,
  );

  // A lozenge in the middle, which is where a card back puts whatever it has
  // instead of a picture. It also gives the eye somewhere to settle on a
  // pattern that is otherwise the same everywhere.
  final Path lozenge =
      Path()
        ..moveTo(0, h * 0.15)
        ..lineTo(w * 0.21, 0)
        ..lineTo(0, -h * 0.15)
        ..lineTo(-w * 0.21, 0)
        ..close();
  canvas.drawPath(lozenge, Paint()..color = _cardBack);
  canvas.drawPath(
    lozenge,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.015
      ..color = _cardBackInk,
  );

  canvas.restore();
}

/// Puts the canvas into one card's own frame: millimetres, y running up.
void _intoCard(Canvas canvas, TrayCamera camera, double x, double y, double z) {
  final double scale = camera.scaleAt(z) * camera.pixelsPerMetre;
  final Offset centre = camera.project(Vector3(x, y, z));
  canvas.translate(centre.dx, centre.dy);
  canvas.scale(scale, -scale);
}

/// A card lying face up, with the roll it stands for printed on it.
///
/// Bordered the way the back is, and for the same reason a printer borders one:
/// a card that is stock all the way to the corner is a slab of white, and next
/// to a blue pile it reads as a hole in the picture rather than as the other
/// side of the same card. The rim and the pale rule inside it are the same
/// numbers [_paintBack] uses — same inset, same radius, same stroke — and only
/// the ink is different, so the card the deck deals is visibly the card the
/// deck is made of.
void _paintFace(
  Canvas canvas,
  TrayCamera camera,
  PlayingCard card,
  double y,
  double z,
) {
  const double w = Tuning.cardWidth;
  const double h = Tuning.cardHeight;

  canvas.save();
  _intoCard(canvas, camera, 0, y, z);

  const Rect rect = Rect.fromLTRB(-w / 2, -h / 2, w / 2, h / 2);
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(w * _kCorner)),
    Paint()..color = _cardFaceBorder,
  );

  const double inset = w * _kBorder;
  final RRect panel = RRect.fromRectAndRadius(
    rect.deflate(inset),
    const Radius.circular(w * 0.045),
  );
  canvas.drawRRect(panel, Paint()..color = _cardStock);
  canvas.drawRRect(
    panel,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.020
      ..color = _cardFaceInk,
  );

  // One pip square per die, down the card, sized to whichever runs out first —
  // the width of the card with one die on it, or its height with three. Both
  // measured inside the border rather than across the whole card: three dice
  // sized against the full height would have the top and bottom ones sitting on
  // the rule.
  final int count = card.faces.length;
  final double side = math.min(
    (w - 2 * inset) * 0.62,
    (h - 2 * inset) / (count + 0.6),
  );
  final double pitch = side * 1.16;
  for (int i = 0; i < count; i++) {
    _paintPipSquare(
      canvas,
      Offset(0, (count - 1) / 2 * pitch - i * pitch),
      side,
      card.faces[i],
    );
  }

  canvas.restore();
}

/// One die face on a card: the outline of a die, and the pips it is showing.
void _paintPipSquare(Canvas canvas, Offset centre, double side, int value) {
  final Rect box = Rect.fromCenter(center: centre, width: side, height: side);
  canvas.drawRRect(
    RRect.fromRectAndRadius(box, Radius.circular(side * 0.16)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.045
      ..color = _cardInk.withValues(alpha: 0.35),
  );

  final List<Offset>? layout = pipLayout(value);
  if (layout == null) return;
  // The layout runs −1 … 1 across a face, so ±1 is the edge of the square and
  // the reach is half of it — the same mapping `_paintPips` uses on a real die,
  // where the coordinate is scaled by the face's half-width. Getting that wrong
  // is what had a six's three pips down a side overlapping each other: pulled
  // into a third of the square they were nearer together than they were wide.
  // The radius follows from the same place, 0.165 of the half-width.
  final double reach = side / 2;
  final Paint ink = Paint()..color = _cardInk;
  for (final Offset pip in layout) {
    canvas.drawCircle(
      centre + Offset(pip.dx * reach, pip.dy * reach),
      reach * 0.165,
      ink,
    );
  }
}

/// The soft blob a card sitting against the glass casts back into the box.
///
/// Not cast along the light the dice use: a card on the glass is flat against
/// the front of the tray, and what reads is a plain drop shadow behind it.
void _paintShadow(Canvas canvas, TrayCamera camera, double y, double z) {
  final double scale = camera.scaleAt(z) * camera.pixelsPerMetre;
  final Offset centre = camera.project(Vector3(0, y, z));
  final Rect rect = Rect.fromCenter(
    center: centre.translate(0, Tuning.cardWidth * _kCorner * scale),
    width: Tuning.cardWidth * scale,
    height: Tuning.cardHeight * scale,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      rect,
      Radius.circular(Tuning.cardWidth * _kCorner * scale),
    ),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..maskFilter = ui.MaskFilter.blur(
        ui.BlurStyle.normal,
        Tuning.cardWidth * 0.10 * scale,
      ),
  );
}

/// Paints [table] whenever [repaint] says something about it has changed.
class CardPainter extends CustomPainter {
  const CardPainter({required this.table});

  final CardTable table;

  @override
  void paint(Canvas canvas, Size size) => paintCardScene(canvas, size, table);

  @override
  bool shouldRepaint(CardPainter oldDelegate) => true;
}
