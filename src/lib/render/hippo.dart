import 'dart:math' as math;
import 'dart:ui' show Offset, Path;

import 'package:vector_math/vector_math_64.dart';

/// Where the animal's own axes end up in the die's.
///
/// Not the identity, and the reason is the numbering. The readout turns the
/// face a die landed on square to the glass and stands its numeral up, and on
/// a cube "up for a numeral" is a different direction on every face — so which
/// way the animal lies inside its cube decides which of the six rolls present
/// it on its feet and which lay it on its side. No arrangement gets all six —
/// the cube's six answers run in a cycle — but this one buys the two worth
/// having: the face carrying the 6, which is the one the picker introduces
/// every die by, presents a hippopotamus in profile, and the face carrying the
/// 2 presents it head on.
///
/// So the animal stands with its back along +z, its nose along +y and its
/// right along −x. Right, up and nose still make a right-handed set that way
/// round, which matters: the mirror image of this would turn every lump inside
/// out and light the animal from within.
Vector3 hippoToDie(Vector3 v) => Vector3(-v.x, v.z, v.y);

/// The animal's own directions, in the die's frame — what the ink on its hide
/// is laid out along.
final Vector3 kHippoUp = hippoToDie(Vector3(0, 1, 0));
final Vector3 kHippoNose = hippoToDie(Vector3(0, 0, 1));
final Vector3 kHippoRight = hippoToDie(Vector3(1, 0, 0));

/// One convex lump of the animal: eight corners and six quads.
///
/// Corners are indexed by their signs in the frame the lump was written in —
/// bit 0 is +x, bit 1 the second axis, bit 2 the third — which is what lets
/// [kLumpFaces] be one table for every lump rather than a loop per part.
class HippoLump {
  HippoLump._(this.vertices, this.normals, this.ink);

  /// Builds a lump, stands it up in the die, and works out which way each of
  /// its faces points.
  ///
  /// The normals are found rather than listed, in the same spirit as
  /// `ConvexShape`'s faces: a lump that tapers has no axis-aligned normals, and
  /// a table of them written by hand would be six chances to light one face as
  /// though it were another.
  factory HippoLump(List<Vector3> vertices, {bool ink = false}) {
    final List<Vector3> stood = <Vector3>[
      for (final Vector3 v in vertices) hippoToDie(v),
    ];
    return HippoLump._(stood, <Vector3>[
      for (final List<int> face in kLumpFaces)
        (stood[face[1]] - stood[face[0]]).cross(stood[face[2]] - stood[face[0]])
          ..normalize(),
    ], ink);
  }

  /// The eight corners, in the *die's* frame, in inradii — [hippoToDie] having
  /// already been applied.
  final List<Vector3> vertices;

  /// Outward unit normal per face, indexed as [kLumpFaces].
  final List<Vector3> normals;

  /// Painted in the die's ink rather than its body colour — the eyes, which
  /// are dark lumps rather than dots stuck on a pale one, so that they are
  /// still eyes from whichever side the hippo has landed.
  final bool ink;
}

/// The six quads of a lump, anticlockwise seen from outside — the winding the
/// painter culls by, and the same one `ConvexFace` keeps.
const List<List<int>> kLumpFaces = <List<int>>[
  <int>[4, 5, 7, 6], // +third axis
  <int>[1, 0, 2, 3], // −third axis
  <int>[5, 1, 3, 7], // +x
  <int>[0, 4, 6, 2], // −x
  <int>[6, 7, 3, 2], // +second axis
  <int>[0, 1, 5, 4], // −second axis
];

/// One end of a lump: how wide it is across, and how far the other axis runs.
///
/// Two rectangles make a lump, and they need not match — which is the whole of
/// the modelling here. A body that is wider in the middle than at either end is
/// two lumps that meet at their widest rectangle; a muzzle that flares is one
/// whose far end is broader than its near one.
class _Rect {
  const _Rect(this.x0, this.x1, this.lo, this.hi);

  final double x0;
  final double x1;
  final double lo;
  final double hi;
}

/// A lump laid along the animal's length, between two upright rectangles.
List<Vector3> _alongZ(double z0, double z1, _Rect back, _Rect front) {
  final List<Vector3> corners = <Vector3>[];
  for (int i = 0; i < 8; i++) {
    final _Rect r = (i & 4) == 0 ? back : front;
    corners.add(
      Vector3(
        (i & 1) == 0 ? r.x0 : r.x1,
        (i & 2) == 0 ? r.lo : r.hi,
        (i & 4) == 0 ? z0 : z1,
      ),
    );
  }
  return corners;
}

/// A lump standing on end, between two flat rectangles — a leg, or an ear.
List<Vector3> _alongY(double y0, double y1, _Rect low, _Rect high) {
  final List<Vector3> corners = <Vector3>[];
  for (int i = 0; i < 8; i++) {
    final _Rect r = (i & 2) == 0 ? low : high;
    corners.add(
      Vector3(
        (i & 1) == 0 ? r.x0 : r.x1,
        (i & 2) == 0 ? y0 : y1,
        (i & 4) == 0 ? r.lo : r.hi,
      ),
    );
  }
  return corners;
}

/// A hippopotamus, sixteen millimetres of one, as the geometry to draw it with.
///
/// This is a *picture*, not a body. `DieKind.hippo` collides and is read as the
/// cube it is carved out of — see `_build` in `tray/dice.dart` — and everything
/// here is what the painter puts inside that cube. So no part of it may leave
/// the cube: a hippo whose nose stuck out through the drawn hull would sink
/// into the floor of the tray by exactly as much as it stuck out, because the
/// floor is where the *cube* stops. `hippo_test.dart` holds it to that.
///
/// Everything below is in units of the die's inradius — half the width of the
/// cube — so the animal is scaled by whatever a die is measured at rather than
/// carrying a millimetre of its own, and it is written in the animal's own
/// frame: +x to its right, +y its back, +z its nose. [hippoToDie] is what
/// stands it up inside the die, and it is not the identity — see there for the
/// one thing that decides which way a hippopotamus lies in its own cube.
///
/// The animal is deliberately a fat one. It has to touch all six walls of its
/// cube — feet, back, flanks, nose and rump — because whichever face the die
/// lands on is the face the tray floor is against, and a hippo that reached
/// only two thirds of the way to its own nose would hover a visible
/// millimetre above the floor every time it landed face-first.
///
/// The barrel is two lumps rather than one because a hippopotamus is widest
/// across the middle and this is how a box gets a waist: they meet at the
/// rectangle that touches both flanks of the cube, and taper away from it in
/// either direction.
final List<HippoLump> kHippo = <HippoLump>[
  // The barrel: rump to shoulder, and shoulder to chest. It hangs low, because
  // a hippopotamus is mostly belly and the legs under it are almost an
  // afterthought — which is the single thing that stops this reading as a dog.
  HippoLump(
    _alongZ(
      -0.96,
      -0.14,
      const _Rect(-0.76, 0.76, -0.52, 0.72),
      const _Rect(-1.00, 1.00, -0.62, 1.00),
    ),
  ),
  HippoLump(
    _alongZ(
      -0.14,
      0.30,
      const _Rect(-1.00, 1.00, -0.62, 1.00),
      const _Rect(-0.80, 0.80, -0.58, 0.86),
    ),
  ),
  // The head, narrower than the shoulders it comes out of, and the muzzle,
  // which flares back out wider than the head and hangs below it. That last
  // part is most of what makes this a hippopotamus and not a pig: the animal
  // is nearly all snout at the front, and the jaw is the deepest thing on it.
  // Both sit well under the line of the back — a hippopotamus carries its head
  // low and its eyes on top.
  HippoLump(
    _alongZ(
      0.30,
      0.62,
      const _Rect(-0.60, 0.60, -0.34, 0.66),
      const _Rect(-0.54, 0.54, -0.38, 0.48),
    ),
  ),
  HippoLump(
    _alongZ(
      0.62,
      1.00,
      const _Rect(-0.58, 0.58, -0.42, 0.46),
      const _Rect(-0.76, 0.76, -0.44, 0.34),
    ),
  ),
  // Four legs, stubby, and wider where they meet the body than where they meet
  // the floor. They reach the wall the animal stands on and the barrel does
  // not, which is what makes a landed hippo look like it is standing rather
  // than resting on its stomach.
  for (final double side in <double>[-1, 1]) ...<HippoLump>[
    HippoLump(
      _alongY(
        -1.00,
        -0.46,
        _Rect(side < 0 ? -0.74 : 0.38, side < 0 ? -0.38 : 0.74, 0.02, 0.36),
        _Rect(side < 0 ? -0.80 : 0.32, side < 0 ? -0.32 : 0.80, -0.04, 0.42),
      ),
    ),
    HippoLump(
      _alongY(
        -1.00,
        -0.42,
        _Rect(side < 0 ? -0.72 : 0.36, side < 0 ? -0.36 : 0.72, -0.74, -0.40),
        _Rect(side < 0 ? -0.78 : 0.30, side < 0 ? -0.30 : 0.78, -0.82, -0.32),
      ),
    ),
  ],
  // Ears, and the eyes in front of them. Both go on top of the skull, which is
  // the part of a hippopotamus that stays above the water.
  for (final double side in <double>[-1, 1]) ...<HippoLump>[
    HippoLump(
      _alongY(
        0.56,
        0.86,
        _Rect(side < 0 ? -0.52 : 0.26, side < 0 ? -0.26 : 0.52, 0.26, 0.46),
        _Rect(side < 0 ? -0.48 : 0.28, side < 0 ? -0.28 : 0.48, 0.29, 0.44),
      ),
    ),
    HippoLump(
      _alongY(
        0.42,
        0.68,
        _Rect(side < 0 ? -0.58 : 0.30, side < 0 ? -0.30 : 0.58, 0.48, 0.70),
        _Rect(side < 0 ? -0.54 : 0.32, side < 0 ? -0.32 : 0.54, 0.50, 0.68),
      ),
      ink: true,
    ),
  ],
  // The tail, which is what actually touches the wall behind it.
  HippoLump(
    _alongZ(
      -1.00,
      -0.88,
      const _Rect(-0.09, 0.09, 0.14, 0.34),
      const _Rect(-0.11, 0.11, 0.12, 0.38),
    ),
  ),
];

/// One spot of ink on the animal, lying in a plane of constant y.
class HippoSpot {
  const HippoSpot({
    required this.x,
    required this.y,
    required this.z,
    required this.radius,
  });

  final double x;
  final double y;
  final double z;
  final double radius;

  /// Where it sits in the die's frame, the animal having been stood up.
  Vector3 get centre => hippoToDie(Vector3(x, y, z));
}

/// The nostrils: two dark spots on top of the muzzle, where a hippopotamus
/// keeps them.
///
/// Spots rather than lumps because they are holes, not bumps — and drawn on
/// the muzzle's upper face, which is the face the animal shows when it is
/// swimming and the one you are looking at when it is standing.
const List<HippoSpot> kHippoNostrils = <HippoSpot>[
  HippoSpot(x: -0.30, y: 0.39, z: 0.88, radius: 0.13),
  HippoSpot(x: 0.30, y: 0.39, z: 0.88, radius: 0.13),
];

/// How far the animal reaches along [n], in inradii.
///
/// What the painter anchors a numeral to. A die prints its numbers in the
/// middle of the face they belong to; a hippo has no faces, so the number goes
/// on whatever part of the animal reaches furthest that way — the flank, the
/// back, the end of its nose — and rides up and down with the shape of it.
double hippoReach(Vector3 n) {
  double best = double.negativeInfinity;
  for (final HippoLump lump in kHippo) {
    for (final Vector3 v in lump.vertices) {
      best = math.max(best, n.dot(v));
    }
  }
  return best;
}

/// The animal in one line, for printing on something flat.
///
/// The same hippopotamus as [kHippo] — the barrel that is mostly belly, the
/// head carried low and the legs that are almost an afterthought — but drawn
/// from a picture rather than derived from the lumps, and it does one thing
/// the lumps cannot: it turns its head. The die's hippopotamus is in strict
/// profile because a box has no other view; this one is three quarters on, so
/// both eyes, both ears and both nostrils are in it, and that is most of what
/// makes it read as an animal looking back at you rather than as a silhouette.
///
/// It faces −x. The rest of this file has the animal's nose along +z and would
/// have put it the other way round, and the reason it does not is that the
/// drawing this was taken from faces left and a card back is a picture before
/// it is a coordinate system.
///
/// It is not a hull, and nothing here is held to the cube the way [kHippo] is:
/// nothing collides with this and no floor comes up to meet it. That is what
/// buys the ears, the toes, the tail and the face.
///
/// What it leaves out is everything the card has no room for. At the size this
/// prints — a little over half a card wide, which is ninety-odd pixels on a
/// phone — a wrinkle is a smudge and a freckle is nothing at all. Every line
/// below earns its place by still being legible there.
class HippoDrawing {
  /// The animal [width] wide from its nose to its rump, centred on the origin,
  /// in a frame where +y is up.
  ///
  /// Up, rather than down, because that is the frame the rest of this file is
  /// written in and a drawing of the animal that ran the other way to the
  /// model of it would be a trap. A canvas whose y runs down has to turn it
  /// over — which is one `scale(1, -1)`, and is what the card back does anyway
  /// to get into a card's own millimetres.
  factory HippoDrawing({required double width}) {
    // One transform rather than a scale factor threaded through two hundred
    // coordinates: the drawing below is written once, in its own units, and
    // moved into place afterwards. Set entry by entry, like the numeral
    // placement in `tray_painter.dart` — this is a uniform scale and a shift
    // along one axis, and spelling it out is shorter than composing it.
    final double scale = width / _kDrawingWidth;
    final Matrix4 into =
        Matrix4.identity()
          ..setEntry(0, 0, scale)
          ..setEntry(1, 1, scale)
          ..setEntry(1, 3, -scale * _kDrawingCentre);
    return HippoDrawing._(
      _outline().transform(into.storage),
      _lines().transform(into.storage),
      <Offset>[
        for (final List<double> eye in _kEyes)
          Offset(eye[0] * scale, (eye[1] - _kDrawingCentre) * scale),
      ],
      _kEyeRadius * scale,
    );
  }

  const HippoDrawing._(this.outline, this.lines, this.eyes, this.eyeRadius);

  /// The whole animal, closed: muzzle, both ears, the back, the rump, and the
  /// two legs on this side of it.
  final Path outline;

  /// Everything else, as open strokes in the same pen — the two legs on the far
  /// side, the crease where the head meets the shoulder, the jaw, the line
  /// round the muzzle, the mouth, the nostrils, the toes and the tail.
  ///
  /// One path rather than a dozen, because they are all drawn identically and
  /// a `Path` holds as many subpaths as it likes. Naming each of them would be
  /// naming the same `drawPath` twelve times.
  final Path lines;

  /// Where the two eyes go, and how big they are — spots rather than paths,
  /// because they are the one thing on the animal that is filled. Two of them,
  /// which is the whole point of turning the head.
  final List<Offset> eyes;
  final double eyeRadius;
}

/// How wide the drawing below is written, in its own units, and where the
/// middle of its height falls — the numbers it is centred and scaled by.
///
/// Nose to rump is exactly two, so [_kDrawingWidth] is what a caller's `width`
/// buys. The height is whatever the animal came to, which is a little over
/// two thirds of that: a hippopotamus is a long low thing, and the reason this
/// is stated rather than measured is that `Path.getBounds` counts control
/// points, and half the control points here are outside the ink.
const double _kDrawingWidth = 2.0;
const double _kDrawingCentre = -0.01;

/// The eyes: on the forehead, above the muzzle and clear of it. A hippopotamus
/// carries them on top of its skull rather than in the sides of it, and on a
/// head turned three quarters on that puts both of them in view with the whole
/// snout below.
///
/// Two numbers each rather than an `Offset`, because an `Offset` is not const
/// enough to sit in a table like this one.
const List<List<double>> _kEyes = <List<double>>[
  <double>[-0.85, 0.33],
  <double>[-0.50, 0.31],
];
const double _kEyeRadius = 0.038;

/// The silhouette, clockwise from the tip of the nose: up the front of the
/// face, over both ears, along the back, down the rump, and forward again
/// under the animal past the two legs on this side of it.
Path _outline() =>
    Path()
      // Up the front of the face, which on a hippopotamus is very nearly
      // vertical and very nearly flat.
      ..moveTo(-1.00, 0.02)
      ..cubicTo(-1.01, 0.18, -0.98, 0.30, -0.93, 0.37)
      // The brow over the near eye, and then the near ear: small, round, and
      // set on the very top of the skull where the animal keeps them.
      ..cubicTo(-0.92, 0.40, -0.91, 0.43, -0.90, 0.45)
      ..cubicTo(-0.89, 0.56, -0.86, 0.63, -0.82, 0.63)
      ..cubicTo(-0.78, 0.63, -0.75, 0.55, -0.74, 0.47)
      // The dip between the ears, and the far one. The far ear is smaller and
      // sits lower, which is the whole of what says the head is turned.
      ..cubicTo(-0.68, 0.45, -0.60, 0.45, -0.52, 0.47)
      ..cubicTo(-0.50, 0.54, -0.46, 0.59, -0.42, 0.59)
      ..cubicTo(-0.38, 0.59, -0.34, 0.53, -0.32, 0.47)
      // Up over the shoulder and along the back, which is the highest line on
      // the animal and rises a little past the ears before it turns over.
      ..cubicTo(-0.18, 0.56, -0.02, 0.64, 0.16, 0.67)
      ..cubicTo(0.34, 0.69, 0.56, 0.66, 0.72, 0.55)
      // The rump, which is where a hippopotamus is roundest.
      ..cubicTo(0.80, 0.46, 0.89, 0.28, 0.90, 0.06)
      ..cubicTo(0.92, -0.10, 0.91, -0.24, 0.89, -0.34)
      // The near hind leg: down the back of it, round the foot, up the front.
      ..cubicTo(0.92, -0.46, 0.91, -0.56, 0.90, -0.64)
      ..cubicTo(0.86, -0.69, 0.78, -0.69, 0.74, -0.64)
      ..cubicTo(0.73, -0.54, 0.72, -0.44, 0.70, -0.38)
      // The belly, which sags between the legs. This is the line that stops
      // the animal reading as a dog.
      ..cubicTo(0.48, -0.44, 0.20, -0.47, -0.04, -0.42)
      // The near foreleg, the same way round.
      ..cubicTo(-0.06, -0.50, -0.08, -0.58, -0.09, -0.66)
      ..cubicTo(-0.13, -0.71, -0.21, -0.71, -0.25, -0.66)
      ..cubicTo(-0.26, -0.56, -0.27, -0.46, -0.28, -0.40)
      // The chest, and then the underside of the jaw — the deepest part of the
      // head, and most of what makes this a hippopotamus rather than a pig.
      ..cubicTo(-0.40, -0.34, -0.50, -0.28, -0.58, -0.26)
      ..cubicTo(-0.72, -0.25, -0.86, -0.24, -0.94, -0.18)
      ..cubicTo(-0.99, -0.14, -1.00, -0.06, -1.00, 0.02)
      ..close();

/// Everything that is not the silhouette, in one path.
Path _lines() {
  final Path path = Path();

  // Inside each ear, the fold that says it is an ear and not a bump.
  path
    ..moveTo(-0.855, 0.480)
    ..cubicTo(-0.845, 0.540, -0.825, 0.565, -0.805, 0.555)
    ..moveTo(-0.475, 0.495)
    ..cubicTo(-0.465, 0.535, -0.450, 0.555, -0.430, 0.548);

  // The crease where the head stops and the shoulder starts. A hippopotamus
  // has no neck, so this is the only thing that separates the two, and without
  // it the head is simply the front of the body.
  path
    ..moveTo(-0.30, 0.46)
    ..cubicTo(-0.20, 0.30, -0.13, 0.10, -0.14, -0.08)
    ..cubicTo(-0.15, -0.22, -0.20, -0.32, -0.28, -0.38);

  // The muzzle, and it is the whole of the face. A hippopotamus's snout is a
  // rounded lump stuck on the front of its head, so the line that cuts it off
  // is a shallow arc that turns *down* and back at the far end — a lobe, with
  // no corner anywhere in it. Drawn as a straight band across the face with a
  // corner at the end it reads as a strap buckled round the animal's nose,
  // which is what it did until this was written properly.
  //
  // It starts high on the front of the face and finishes on the jaw, so the
  // snout is a closed shape rather than a mark that stops in mid-air.
  //
  // There is no cheek line under the far ear, which the drawing this came from
  // has. Three curves down one side of a head is one more than this size can
  // hold: at ninety pixels they stop being a jaw and become hatching, and this
  // is the one that has to survive.
  path
    ..moveTo(-0.99, 0.20)
    ..cubicTo(-0.86, 0.18, -0.72, 0.15, -0.58, 0.11)
    ..cubicTo(-0.48, 0.08, -0.42, -0.01, -0.42, -0.12)
    ..cubicTo(-0.42, -0.22, -0.43, -0.28, -0.45, -0.30);

  // The mouth, which hugs the jaw rather than crossing the face. On a
  // hippopotamus the mouth *is* the bottom of the snout — it runs a whisker
  // above the chin, roughly parallel to it. Anywhere higher and it is a second
  // muzzle line.
  //
  // It stops short of the chin at both ends rather than running the whole
  // width. Carried right out to the front of the face it converges with the
  // jaw into a long thin sliver, which reads as a zip rather than a mouth, and
  // the gap it leaves at the front is the lip.
  path
    ..moveTo(-0.90, -0.13)
    ..cubicTo(-0.82, -0.17, -0.72, -0.19, -0.62, -0.19);

  // The nostrils: two curls high on the snout, not two dots. A dot is a stud;
  // the curl is what a hippopotamus has. One shape placed twice rather than
  // two written out, because two hand-drawn approximations of the same curl
  // come out as two different marks, and at this size the second one stops
  // reading as a nostril and starts reading as a question mark.
  for (final List<double> nostril in _kNostrils) {
    path
      ..moveTo(nostril[0] - 0.039, nostril[1] + 0.013)
      ..cubicTo(
        nostril[0] - 0.013,
        nostril[1] + 0.062,
        nostril[0] + 0.042,
        nostril[1] + 0.029,
        nostril[0] + 0.018,
        nostril[1] - 0.023,
      );
  }

  // The two legs on the far side, drawn as far as they are visible: down the
  // back, round the foot, and up the front, stopping where the body covers
  // them. Open strokes rather than part of the silhouette, because that is
  // what standing behind something looks like.
  path
    ..moveTo(-0.34, -0.40)
    ..cubicTo(-0.36, -0.52, -0.37, -0.60, -0.38, -0.66)
    ..cubicTo(-0.42, -0.70, -0.50, -0.70, -0.54, -0.66)
    ..cubicTo(-0.55, -0.58, -0.55, -0.50, -0.54, -0.44)
    ..moveTo(0.62, -0.40)
    ..cubicTo(0.60, -0.52, 0.59, -0.60, 0.58, -0.66)
    ..cubicTo(0.54, -0.70, 0.46, -0.70, 0.42, -0.66)
    ..cubicTo(0.41, -0.58, 0.41, -0.50, 0.42, -0.44);

  // Toes. Two strokes to a foot, which is three toes, which is what a
  // hippopotamus stands on. Short, because at this size a long one closes the
  // foot up into a grid.
  for (final List<double> foot in _kFeet) {
    for (final double side in <double>[-1, 1]) {
      path
        ..moveTo(foot[0] + side * 0.030, foot[1])
        ..lineTo(foot[0] + side * 0.026, foot[1] + 0.055);
    }
  }

  // The tail: thin, hanging down the back of the rump, with the tuft on the
  // end that is the only part of one anybody ever draws.
  //
  // It stands further off the rump than the drawing this came from puts it,
  // where the two lines very nearly touch. At this size very nearly touching
  // is one thick line, and the tail disappears into the animal.
  path
    ..moveTo(0.86, 0.34)
    ..cubicTo(0.94, 0.26, 0.98, 0.12, 0.98, -0.02)
    ..moveTo(0.98, -0.02)
    ..lineTo(0.94, -0.13)
    ..moveTo(0.98, -0.02)
    ..lineTo(0.98, -0.15)
    ..moveTo(0.98, -0.02)
    ..lineTo(1.00, -0.12);

  return path;
}

/// Where each nostril sits on the snout, well clear of the muzzle line above
/// it and the mouth below.
const List<List<double>> _kNostrils = <List<double>>[
  <double>[-0.90, 0.04],
  <double>[-0.68, 0.00],
];

/// The middle of each foot, at the sole. The toe strokes run *up* from here
/// into the foot: a hippopotamus's toes are divisions in the front of it, and
/// the same strokes drawn downwards are claws on a cat.
const List<List<double>> _kFeet = <List<double>>[
  <double>[-0.17, -0.685],
  <double>[-0.46, -0.685],
  <double>[0.50, -0.685],
  <double>[0.82, -0.685],
];
