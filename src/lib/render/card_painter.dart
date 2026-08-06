import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../cards/deck.dart';
import '../tray/tray.dart';
import 'tray_painter.dart';

/// The stock a card is printed on. What the dice on it are printed in is not a
/// constant — it is whatever colour was chosen for them, and the ink follows
/// the body the way it does on a real die. See [DieStyle.of].
const Color _cardStock = Color(0xFFF5ECD9);

/// The outline around a printed die: how wide it is as a fraction of the die,
/// and how solid it is as a fraction of that die's own ink.
///
/// There is one at all because the palette's ivory on this card's cream stock
/// is two shades of the same thing: without a rule around it a white die is a
/// square that is not quite there. Faint, because on any of the other seven
/// colours the body already draws its own edge and a full-strength line would
/// read as a frame somebody put round it.
const double _kDieOutlineWidth = 0.045;
const double _kDieOutline = 0.35;

/// The back: navy stock, printed in gold.
///
/// Two navies rather than one, because a card back that is a single flat
/// colour reads as a hole cut in the picture. They run corner to corner — the
/// lighter one at the top left, where the light in this tray comes from — so
/// the top of the pile catches it the way the dice standing next to it do.
const Color _cardBack = Color(0xFF1E2946);
const Color _cardBackDeep = Color(0xFF13192C);

/// The ink the back is printed in, and the deeper gold of the one thing on it
/// that is filled rather than drawn.
const Color _cardGold = Color(0xFFC1945A);
const Color _cardGoldDeep = Color(0xFFA88355);

/// The gold the face is ruled in.
///
/// The same gold as the back, a shade warmer. A gold mixed to read against
/// navy goes pale on cream — there is no more contrast left above it, only
/// less — so the one that keeps its weight on this stock is the one with more
/// red in it. Held to the same lightness, because the two sides of a card are
/// one printing in two inks and a face ruled in a visibly *darker* gold would
/// be two designs.
const Color _cardFaceGold = Color(0xFFC9924F);

/// How much of the tray's depth the pile is allowed to take up.
const double _maxPileDepth = 0.45;

/// A card's corner radius, as a fraction of its width.
const double _kCorner = 0.06;

/// The rule and the four corners, as fractions of a card's width.
///
/// One set of numbers rather than two, because both sides of a card carry
/// them: [_kRuleInset] is how far inside the edge the rule runs, [_kRuleLine]
/// how heavy every line on either side is, and [_kCornerInset] with
/// [_kCornerPip] place and size the small diamond at each corner — that far in
/// from *both* edges, which is the same distance in millimetres at the top as
/// at the side and is what makes the four of them read as one border rather
/// than as four marks that happen to be near the corners.
const double _kRuleInset = 0.025;
const double _kRuleLine = 0.007;
const double _kCornerInset = 0.090;
const double _kCornerPip = 0.036;

/// The back's own middle: the outlined diamond, and the filled one inside it.
/// The face has nothing there because the dice go there.
const double _kBackDiamond = 0.174;
const double _kBackPip = 0.079;

/// How far in from the edge the printed dice keep, as a fraction of a card's
/// width.
///
/// Twice the rule's inset, so the rule reads as a border drawn round them
/// rather than as a line they are sitting on. It is also what the dice are
/// *sized* against, which is why it stayed the number the old red border was:
/// the layout below was settled against it, and the printing round it changing
/// is no reason for the dice on a three-dice card to change size.
const double _kFaceMargin = 0.055;

/// How far out of square a hand-shuffled pile stands, as a fraction of its own
/// height.
const double _kPileLean = 0.10;

/// The cards under the top one. Shades of the back rather than of the stock:
/// a pile seen this near to head on shows no edge worth the name, so what says
/// "several" has to be the backs of the ones underneath — and a pale strip of
/// stock around a card reads as a fringe on it rather than as more cards.
const Color _cardEdge = Color(0xFF1B243E);
const Color _cardEdgeDark = Color(0xFF0D1220);

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
    // One style per die, from the same derivation the tray uses on a real one:
    // the body is what was chosen and the ink is whichever of black and ivory
    // can be read against it. A card is a printed die, so it is printed the
    // same way.
    _paintFace(canvas, camera, shown, _drawnY(table), 0, <DieStyle>[
      for (int i = 0; i < shown.faces.length; i++)
        DieStyle.of(table.colourOf(i)),
    ]);
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
/// Navy, ruled in gold, with a diamond in the middle and a smaller one in each
/// corner — which is what the back of a playing card has looked like since
/// somebody worked out that a plain one shows every crease. Nothing here is
/// asymmetric: a back has to look the same whichever way up the card is dealt,
/// and a diamond is the shape that manages it about both axes at once.
///
/// Drawn in the card's own millimetres and scaled into place, so the design
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

  // y runs up in here, so the corner the light comes from is +y and the far
  // one is −y. The gradient goes between those two and nowhere near the
  // Rect's own idea of top and bottom, which is upside down by this point.
  const Rect rect = Rect.fromLTRB(-w / 2, -h / 2, w / 2, h / 2);
  final RRect card = RRect.fromRectAndRadius(
    rect,
    const Radius.circular(w * _kCorner),
  );
  canvas.drawRRect(
    card,
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(-w / 2, h / 2),
        const Offset(w / 2, -h / 2),
        const <Color>[_cardBack, _cardBackDeep],
      ),
  );

  final Paint gold = _rulePaint(_cardGold);
  _paintRule(canvas, card, gold);

  // And the middle, which is the back's alone: one diamond drawn, one filled
  // inside it.
  canvas.drawPath(_diamond(Offset.zero, w * _kBackDiamond), gold);
  canvas.drawPath(
    _diamond(Offset.zero, w * _kBackPip),
    Paint()..color = _cardGoldDeep,
  );

  canvas.restore();
}

/// The pen both sides of a card are ruled with, in whichever gold the stock
/// under it takes.
Paint _rulePaint(Color gold) =>
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = Tuning.cardWidth * _kRuleLine
      ..color = gold;

/// The printing both sides of a card share: a rule just inside the edge,
/// following it round, and a small diamond in each of the four corners.
///
/// The rule is deflated by the inset *and* half the line, so the whole stroke
/// lies inside the card rather than half of it hanging over the edge into
/// whatever is behind.
void _paintRule(Canvas canvas, RRect card, Paint gold) {
  const double w = Tuning.cardWidth;
  const double h = Tuning.cardHeight;
  canvas.drawRRect(card.deflate(w * (_kRuleInset + _kRuleLine / 2)), gold);

  final double x = w / 2 - w * _kCornerInset;
  final double y = h / 2 - w * _kCornerInset;
  for (final double sx in <double>[-1, 1]) {
    for (final double sy in <double>[-1, 1]) {
      canvas.drawPath(_diamond(Offset(sx * x, sy * y), w * _kCornerPip), gold);
    }
  }
}

/// A diamond: a square stood on its corner, [radius] from the middle to each
/// of the four points.
Path _diamond(Offset centre, double radius) =>
    Path()
      ..moveTo(centre.dx, centre.dy + radius)
      ..lineTo(centre.dx + radius, centre.dy)
      ..lineTo(centre.dx, centre.dy - radius)
      ..lineTo(centre.dx - radius, centre.dy)
      ..close();

/// Puts the canvas into one card's own frame: millimetres, y running up.
void _intoCard(Canvas canvas, TrayCamera camera, double x, double y, double z) {
  final double scale = camera.scaleAt(z) * camera.pixelsPerMetre;
  final Offset centre = camera.project(Vector3(x, y, z));
  canvas.translate(centre.dx, centre.dy);
  canvas.scale(scale, -scale);
}

/// A card lying face up, with the roll it stands for printed on it.
///
/// The same printing as the back — the same rule at the same inset, the same
/// diamond in each corner, the same weight of line — on cream instead of navy.
/// That is the whole of what makes a dealt card visibly the card the deck is
/// made of: turn one over and nothing about the border has moved, only the
/// ground it is printed on and what is standing in the middle of it.
void _paintFace(
  Canvas canvas,
  TrayCamera camera,
  PlayingCard card,
  double y,
  double z,
  List<DieStyle> styles,
) {
  const double w = Tuning.cardWidth;
  const double h = Tuning.cardHeight;

  canvas.save();
  _intoCard(canvas, camera, 0, y, z);

  const Rect rect = Rect.fromLTRB(-w / 2, -h / 2, w / 2, h / 2);
  final RRect stock = RRect.fromRectAndRadius(
    rect,
    const Radius.circular(w * _kCorner),
  );
  canvas.drawRRect(stock, Paint()..color = _cardStock);
  _paintRule(canvas, stock, _rulePaint(_cardFaceGold));

  // One pip square per die, down the card, sized to whichever runs out first —
  // the width of the card with one die on it, or its height with three. Both
  // measured inside [_kFaceMargin] rather than across the whole card: three
  // dice sized against the full height would have the top and bottom ones
  // sitting on the rule.
  const double margin = w * _kFaceMargin;
  final int count = card.faces.length;
  final double side = math.min(
    (w - 2 * margin) * 0.62,
    (h - 2 * margin) / (count + 0.6),
  );
  final double pitch = side * 1.16;
  for (int i = 0; i < count; i++) {
    _paintPipSquare(
      canvas,
      Offset(0, (count - 1) / 2 * pitch - i * pitch),
      side,
      card.faces[i],
      styles[i],
    );
  }

  canvas.restore();
}

/// One die face on a card: a die in [style]'s colours, and the pips it shows.
///
/// Printed flat, without any of the shading a die in the tray gets. There is
/// no light on a card — it is ink on stock, and a gradient across a square
/// this size would read as a smudge rather than as a solid.
void _paintPipSquare(
  Canvas canvas,
  Offset centre,
  double side,
  int value,
  DieStyle style,
) {
  final Rect box = Rect.fromCenter(center: centre, width: side, height: side);
  final RRect face = RRect.fromRectAndRadius(box, Radius.circular(side * 0.16));
  final double outline = side * _kDieOutlineWidth;
  canvas.drawRRect(face, Paint()..color = style.body);
  // Wholly inside the die rather than across its edge. A stroke centred on the
  // boundary puts half its width on the stock, and a faint dark line there
  // comes out pale — a grey halo around a green die, which reads as a gap
  // between the die and the card rather than as the edge of the die.
  canvas.drawRRect(
    face.deflate(outline / 2),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = outline
      ..color = style.ink.withValues(alpha: _kDieOutline),
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
  final Paint ink = Paint()..color = style.ink;
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
