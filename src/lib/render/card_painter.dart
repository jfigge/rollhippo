import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../cards/deck.dart';
import '../tray/tray.dart';
import 'hippo.dart';
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

/// The back's own middle: the hippopotamus, as a fraction of a card's width
/// from the tip of its tail to the tip of its nose. The face has nothing there
/// because the dice go there.
///
/// Two thirds of the card, which is far larger than the diamond that used to
/// stand here and has to be. A diamond is legible at any size because it is a
/// diamond; an animal has two eyes, two ears, four feet and a mouth, and below
/// about this it stops being a hippopotamus and becomes a smudge with a nose.
///
/// It is the *width* rather than the height because the animal is half again
/// as long as it is tall, so what stops this growing is the two corner pips it
/// would run into — not the top and bottom of the card, which have room to
/// spare.
const double _kBackHippo = 0.66;

/// How far in from the edge the printed dice keep, as a fraction of a card's
/// width.
///
/// Twice the rule's inset, so the rule reads as a border drawn round them
/// rather than as a line they are sitting on. It is also what the dice are
/// *sized* against, which is why it stayed the number the old red border was:
/// the layout below was settled against it, and the printing round it changing
/// is no reason for the dice on a three-dice card to change size.
const double _kFaceMargin = 0.055;

/// How far the outgoing card has turned by the time it is off the screen,
/// radians, clockwise.
///
/// Small. It is the difference between a card being swept off a table and one
/// being posted through a slot, and any more than this stops reading as a
/// sweep and starts reading as a card that has been thrown.
const double _kDiscardTilt = 0.14;

/// How far out of square a hand-shuffled pile stands, as a fraction of its own
/// height, and how far off the back wall the whole pile stands, metres.
///
/// Two millimetres, so the pile reads as standing in the box rather than as
/// printed on the back of it.
const double _kPileLean = 0.10;
const double _kPileGap = 0.002;

/// The cards under the top one. Shades of the back rather than of the stock:
/// a pile seen this near to head on shows no edge worth the name, so what says
/// "several" has to be the backs of the ones underneath — and a pale strip of
/// stock around a card reads as a fringe on it rather than as more cards.
const Color _cardEdge = Color(0xFF1B243E);
const Color _cardEdgeDark = Color(0xFF0D1220);

/// The whole card table: the box, the pile standing in it, and whatever has
/// been dealt onto the glass.
void paintCardScene(Canvas canvas, Size size, CardTable table) {
  final TrayCamera camera = cameraFor(size, table.width, table.height);

  paintTrayBox(
    canvas,
    camera,
    width: table.width,
    height: table.height,
    depth: table.depth,
  );

  _paintPile(canvas, camera, table);

  // A card in the air has already replaced [Deck.shown] — the draw happens the
  // moment it is asked for and only the arrival is animated — so while one is
  // flying, the card the deal remembers is the one being replaced, and that
  // one is on its way out of the bottom of the box.
  final Deal deal = table.deal;
  final PlayingCard? leaving = deal.under;

  // Nothing lies still on the glass while a deal is on. The card that was
  // there is leaving and the card that is coming has not arrived, so what is
  // drawn here is drawn only in the quiet between deals.
  final PlayingCard? lying = deal.busy ? null : table.deck.shown;
  if (lying != null) {
    _paintShadow(canvas, camera, 0, _drawnY(table), 0);
    _paintFace(canvas, camera, lying, 0, _drawnY(table), 0, _stylesOf(table));
  }

  // The one arriving, and then the one leaving in front of it — which is the
  // box's own order, honestly: the outgoing card is against the glass for the
  // whole of its slide, and the incoming one is behind the glass for all but
  // the last instant of its journey.
  //
  // This used to be a lie, and had to be. When the outgoing card stayed put
  // and was covered, drawing by depth left the new card hidden behind it for
  // the whole flight and popping into view at the end, so the two were swapped
  // over at the instant the flying card went edge on. Nothing needs swapping
  // now: the card underneath is falling out of the way, and the new one comes
  // out from behind it as it goes.
  _paintFlight(canvas, camera, table);
  if (leaving != null) {
    _paintDiscard(canvas, camera, table, leaving, deal.discard);
  }
}

/// The card being replaced, on its way out.
///
/// Straight down the glass and off the bottom of the box, turning a little as
/// it goes — which is the difference between a card being swept off a table
/// and a card being posted through a slot.
///
/// [gone] is 0 lying on the glass and 1 clear of the screen. It stays at z = 0
/// throughout: the card is against the glass when the slide starts and nothing
/// in the box pushes it back, so the only thing that changes is how far down
/// the glass it has got.
void _paintDiscard(
  Canvas canvas,
  TrayCamera camera,
  CardTable table,
  PlayingCard card,
  double gone,
) {
  final double from = _drawnY(table);
  final double y = from + (_discardY(table) - from) * gone;
  final double tilt = _kDiscardTilt * gone;
  _paintShadow(canvas, camera, 0, y, 0, tilt: tilt);
  _paintFace(canvas, camera, card, 0, y, 0, _stylesOf(table), tilt: tilt);
}

/// Where a card has gone when it has gone: its centre one whole card below the
/// bottom of the glass.
///
/// A card's height rather than half of one, because it is turning on the way
/// down and a tilted card reaches further from its own centre than an upright
/// one does. This clears every corner of it whatever angle it finished at,
/// which is cheaper than working out what that angle costs.
double _discardY(CardTable table) => -table.height / 2 - Tuning.cardHeight;

/// The card being dealt, wherever it has got to. Nothing, when none is.
///
/// [squash] is what is left of its height, and its sign is which side of it is
/// facing you: a card rotated about its own left-to-right axis keeps all of its
/// width and loses its height by the cosine of the angle, and past the quarter
/// turn that cosine goes negative — which is the card presenting its other
/// side. So the sign picks the side and what is left is how tall to draw it.
///
/// Each side is drawn the right way up in its own frame rather than mirrored
/// through the stock, which is what a real card is: two designs printed on
/// opposite faces of one piece of card, each the right way round from the only
/// place it can be seen from. It is the *face* that this is a lie about, and
/// deliberately: a card turned end over end really does arrive upside down,
/// and drawing it that way would hand the player a card they had to tilt their
/// head at. Court cards are double-headed for the same reason, and a card of
/// dice is symmetric enough to get away with it.
///
/// The back needs no such licence, and this is why it is allowed to carry an
/// animal that has a right way up. [squash] is the cosine of the turn, so the
/// back is drawn for the first quarter of it and no further — and through that
/// quarter a real card rotating about its own left-to-right axis keeps its top
/// edge on top. What is drawn is what would be there. The face takes over at
/// exactly the angle where that stops being true.
void _paintFlight(Canvas canvas, TrayCamera camera, CardTable table) {
  final PlayingCard? card = table.deal.card;
  if (card == null) return;

  // Which side of the card is facing you, and what is left of its height. A
  // card rotated about its own left-to-right axis keeps all of its width and
  // loses its height by the cosine of the angle, and past the quarter turn
  // that cosine goes negative — which is the card presenting its other side.
  // So the sign picks the side and what is left is how tall to draw it.
  final double squash = math.cos(table.deal.turn);

  // Off the top of the pile and down onto the glass. Both ends of the journey
  // are worked out from the tray exactly as the resting positions are, so the
  // card leaves the deck it was really dealt from and lands where a dealt card
  // lies, on whatever screen it is being dealt on.
  final Vector3 from = _pileTop(table);
  final Vector3 to = Vector3(0, _drawnY(table), 0);
  final Vector3 at = from + (to - from) * table.deal.travel;

  // The shadow gathers as the card comes forward. Back at the wall there is
  // nothing between the card and the glass for one to fall on.
  _paintShadow(
    canvas,
    camera,
    at.x,
    at.y,
    at.z,
    squash: squash.abs(),
    fade: table.deal.travel,
  );

  if (squash >= 0) {
    _paintBack(canvas, camera, at.x, at.y, at.z, squash: squash);
  } else {
    _paintFace(
      canvas,
      camera,
      card,
      at.x,
      at.y,
      at.z,
      _stylesOf(table),
      squash: -squash,
    );
  }
}

/// One style per die on a card, from the same derivation the tray uses on a
/// real one: the body is what was chosen and the ink is whichever of black and
/// ivory can be read against it. A card is a printed die, so it is printed the
/// same way.
///
/// Three of them however many the card carries, because the list is indexed by
/// position and a card is only ever the first one, two or three of them.
List<DieStyle> _stylesOf(CardTable table) => <DieStyle>[
  for (int i = 0; i < 3; i++) DieStyle.of(table.colourOf(i)),
];

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
  if (table.deck.remaining == 0) return;

  final double back = -table.depth + _kPileGap;
  final double thickness = _pileThickness(table);
  final double lean = _pileLean(table);

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

/// How deep the pile stands, metres.
///
/// Real stock while a real stack would fit, and no thicker. Three dice across
/// three decks is six hundred and forty-eight cards, which at 0.32 mm each is
/// a pile deeper than the tray — it would come out through the glass. Past the
/// cap the pile stops being a measurement and goes back to being a picture of
/// one, which is the only thing it can be at that size.
double _pileThickness(CardTable table) => math.min(
  table.deck.remaining * Tuning.cardThickness,
  table.depth * _maxPileDepth,
);

/// How far out of true the pile stands, metres, and the whole reason you can
/// tell there is more than one card in it.
///
/// A stack this square to the glass hides its own edge — the front card is
/// nearer, so it projects larger than every card behind it and covers the lot.
/// A pile that has been shuffled by hand is not square, and this is how far
/// off: a tenth of its own height, which is nothing for the six cards left at
/// the end of a shoe and a visible fan for the six hundred at the start of one.
///
/// Taken off the middle rather than added to one side of it, so that the pile
/// as a whole still stands in the centre of the wall and only the fan itself is
/// off square.
double _pileLean(CardTable table) => _pileThickness(table) * _kPileLean;

/// Where the top of the pile stands, and so where a card is dealt from.
///
/// Read off the pile as it is *now*, one card lighter than it was when the card
/// in the air came off it. That difference is a third of a millimetre at the
/// back of a box three hundred deep, which is nothing you could see — and
/// paying for a second pile geometry to be exactly right about it would be
/// paying for nothing.
Vector3 _pileTop(CardTable table) => Vector3(
  -_pileLean(table) / 2,
  0,
  -table.depth + _kPileGap + _pileThickness(table),
);

/// The top of the pile: the back of a card.
///
/// Navy, ruled in gold, with a small diamond in each corner — which is what
/// the back of a playing card has looked like since somebody worked out that a
/// plain one shows every crease — and the hippopotamus in the middle of it.
///
/// The animal is the one thing on either side of a card that is not symmetric
/// about both of its axes, and a real deck could not have it: turn one of
/// these cards end over end and its back would be standing on its head, which
/// is a mark, and a marked back is a deck you can read from behind. It is free
/// here for the reason given at [_paintFlight] — the back is on screen only
/// for the first quarter of the turn, where a real card's back is still the
/// right way up, and the pile is drawn upright because it is a pile.
///
/// Drawn in the card's own millimetres and scaled into place, so the design
/// holds together at whatever size the pile happens to be seen at.
void _paintBack(
  Canvas canvas,
  TrayCamera camera,
  double x,
  double y,
  double z, {
  double squash = 1,
  double tilt = 0,
}) {
  const double w = Tuning.cardWidth;
  const double h = Tuning.cardHeight;

  canvas.save();
  _intoCard(canvas, camera, x, y, z, squash, tilt);

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

  // And the middle, which is the back's alone: the animal, in one fine gold
  // line, and the one thing on the card that is filled rather than drawn for
  // its eye.
  //
  // Drawn with the rule's own pen — the same gold at the same weight — so the
  // border and the hippopotamus read as one printing rather than as a picture
  // somebody put inside a frame. Rounded at the joins and the ends, which the
  // rule has no use for and an animal does: a mitre on the point of an ear or
  // the heel of a foot puts a spur on it at this line width.
  final HippoDrawing hippo = HippoDrawing(width: w * _kBackHippo);
  final Paint pen =
      _rulePaint(_cardGold)
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
  canvas.drawPath(hippo.outline, pen);
  canvas.drawPath(hippo.lines, pen);
  final Paint pupil = Paint()..color = _cardGoldDeep;
  for (final Offset eye in hippo.eyes) {
    canvas.drawCircle(eye, hippo.eyeRadius, pupil);
  }

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
///
/// [squash] is how much of its height a card turning over has left, 1 for one
/// lying flat to the glass and 0 for one exactly edge on. It goes on the one
/// axis, because that is the whole of what a turn about the card's left-to-
/// right axis does to it from here — the printing on the card foreshortens with
/// the card, which is why it is done to the frame rather than to the shape.
///
/// [tilt] is the other turn a card can make, the one about the axis you are
/// looking down. Only the card being discarded uses it.
void _intoCard(
  Canvas canvas,
  TrayCamera camera,
  double x,
  double y,
  double z,
  double squash,
  double tilt,
) {
  final double scale = camera.scaleAt(z) * camera.pixelsPerMetre;
  final Offset centre = camera.project(Vector3(x, y, z));
  canvas.translate(centre.dx, centre.dy);
  // Between the two, so the card turns about its own middle in the plane of
  // the glass rather than about anything on screen. It is in screen space —
  // y still runs down at this point — so a positive [tilt] is clockwise, which
  // is the way a card swept off to the left goes over.
  canvas.rotate(tilt);
  canvas.scale(scale, -scale * squash);
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
  double x,
  double y,
  double z,
  List<DieStyle> styles, {
  double squash = 1,
  double tilt = 0,
}) {
  canvas.save();
  _intoCard(canvas, camera, x, y, z, squash, tilt);
  _printFace(canvas, card, styles);
  canvas.restore();
}

/// The same card, printed into a plain box on screen instead of into the tray.
///
/// What [CardPreview] draws, and the reason the printing below is its own
/// function: a card standing still in a rack is not in the box, has no depth to
/// be projected from and no turn to be foreshortened by, but it has to be the
/// *same* card — same stock, same rule, same corner diamonds, same pip squares
/// — or the rack would be advertising a card the deal does not hand over. So
/// the two of them differ in nothing but how the canvas gets into the card's
/// own frame: through the camera there, through [box] here.
///
/// That last paragraph is about a rack that does not exist yet. This and
/// [CardPreview] were written together and neither was ever wired in — the
/// picker's card rack still shows the three D6s themselves where the card they
/// stand for would go. What is described here is what the seam is *for*, not
/// something the app presently does.
///
/// The card keeps its proportions inside [box] and is centred in it, on the
/// larger of the two axes it does not fill. Stretching a card to fill a box
/// would be the one distortion nothing else in the app allows.
void paintCardInto(
  Canvas canvas,
  Rect box,
  PlayingCard card,
  List<DieStyle> styles,
) {
  final double scale = math.min(
    box.width / Tuning.cardWidth,
    box.height / Tuning.cardHeight,
  );

  canvas.save();
  canvas.translate(box.center.dx, box.center.dy);
  // Negative on y for the same reason [_intoCard] is: the card's frame runs
  // millimetres with y up, and everything printed below is written in it.
  canvas.scale(scale, -scale);
  _printFace(canvas, card, styles);
  canvas.restore();
}

/// The printing, in the card's own frame — millimetres, y up, the middle of the
/// card at the origin. Whoever put the canvas there decides how big it is and
/// which way it is turned; this only prints.
void _printFace(Canvas canvas, PlayingCard card, List<DieStyle> styles) {
  const double w = Tuning.cardWidth;
  const double h = Tuning.cardHeight;

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
///
/// [squash] is the turn, exactly as [_intoCard] takes it — a card edge on has
/// no face left to block the light with. [fade] is for a card still crossing
/// the box: against the back wall there is nothing behind it for a shadow to
/// fall on, and one that arrives at full strength the moment a card is dealt
/// would read as a second card rather than as this one's shadow.
void _paintShadow(
  Canvas canvas,
  TrayCamera camera,
  double x,
  double y,
  double z, {
  double squash = 1,
  double fade = 1,
  double tilt = 0,
}) {
  final double scale = camera.scaleAt(z) * camera.pixelsPerMetre;
  final Offset centre = camera.project(Vector3(x, y, z));

  // The shadow turns with the card, about the same point. A blurred blob is
  // forgiving about most things and unforgiving about this one: leave it
  // square under a card that is not and the corners of the card hang over the
  // ends of their own shadow.
  canvas.save();
  canvas.translate(centre.dx, centre.dy);
  canvas.rotate(tilt);
  canvas.translate(-centre.dx, -centre.dy);

  final Rect rect = Rect.fromCenter(
    center: centre.translate(0, Tuning.cardWidth * _kCorner * scale),
    width: Tuning.cardWidth * scale,
    height: Tuning.cardHeight * scale * squash,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      rect,
      Radius.circular(Tuning.cardWidth * _kCorner * scale),
    ),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.45 * fade)
      ..maskFilter = ui.MaskFilter.blur(
        ui.BlurStyle.normal,
        Tuning.cardWidth * 0.10 * scale,
      ),
  );
  canvas.restore();
}

/// Paints [table] whenever [repaint] says something about it has changed.
class CardPainter extends CustomPainter {
  CardPainter({required this.table, required this.repaint})
    : super(repaint: repaint);

  final CardTable table;

  /// Ticked on the frames a card is in the air, and on no others. Nothing else
  /// on this table moves — the pile stands where it stands and a card that has
  /// landed stays landed — so a repaint it does not ask for is a repaint of
  /// exactly the same picture.
  final Listenable repaint;

  @override
  void paint(Canvas canvas, Size size) => paintCardScene(canvas, size, table);

  @override
  bool shouldRepaint(CardPainter oldDelegate) => true;
}
