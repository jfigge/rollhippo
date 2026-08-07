import 'dart:math' as math;

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
