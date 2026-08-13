import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../physics/shape.dart';
import 'tuning.dart';

/// The dice a set can contain.
///
/// **The order of this list is the wire format.** `share_code.dart` writes a
/// die as `kind.index << 4 | colour`, and the preferences file holds every
/// saved profile's dice in exactly those bytes — so inserting a kind rather
/// than appending one silently turns every stored hippopotamus into whatever
/// took its number. New kinds go on the end, and the four bits leave room for
/// sixteen of them.
enum DieKind {
  d4(4),
  d6(6),
  d8(8),
  d10(10),
  d12(12),
  d20(20),

  /// A hippopotamus, sixteen millimetres of one, which rolls like a D6 because
  /// underneath the animal it *is* a D6 — see [_build] and `paintHippo`.
  ///
  /// Not offered until it is asked for by name: see [secret], and
  /// `kHippoProfile` for what the name is.
  hippo(6, marked: 'Hippo'),

  /// A poker die: nine, ten, jack, queen, king and ace, printed as the card
  /// faces they are — see `render/poker.dart`.
  ///
  /// A D6 underneath, exactly as [hippo] is, so it rolls as fairly as one.
  /// Its faces carry 9 to 14 rather than 1 to 6, which is what puts an ace
  /// above a king when anything compares two of them.
  poker(6, marked: 'Poker');

  const DieKind(this.sides, {String? marked}) : _marked = marked;

  final int sides;

  /// What this kind is called, when counting its faces does not say it.
  final String? _marked;

  String get label => _marked ?? 'D$sides';

  /// The numbers this kind's faces carry, in ascending order.
  ///
  /// One to [sides] for most dice and stated rather than assumed, because one
  /// of them counts otherwise: the poker die's ranks are 9 to 14, so that an
  /// ace sorts above a king. Anything that wants to know what a reading can be
  /// asks here rather than counting faces.
  List<int> get numbers => switch (this) {
    DieKind.poker => <int>[9, 10, 11, 12, 13, 14],
    _ => <int>[for (int i = 1; i <= sides; i++) i],
  };

  /// True of the kinds the picker keeps back until you have named a
  /// profile after them. The hippopotamus, and nothing else.
  ///
  /// Kept here rather than in the picker because it is a fact about the die —
  /// a share code carrying one still decodes, a save holding one still opens,
  /// and a tray full of them still rolls. All that is withheld is the chip
  /// that puts one in the rack.
  bool get secret => this == DieKind.hippo;
}

/// One die in the tray: what shape it is and what colour it is.
class DieSpec {
  const DieSpec({required this.kind, required this.colour});

  final DieKind kind;

  /// Body colour, packed ARGB. An int rather than a `Color` so that nothing
  /// below the widgets has to know Flutter exists.
  final int colour;

  DieSpec copyWith({DieKind? kind, int? colour}) =>
      DieSpec(kind: kind ?? this.kind, colour: colour ?? this.colour);

  /// A die is two choices and nothing else, so two of them with the same
  /// answers are the same die. [Profile] compares whole sets this way, which is
  /// how a scanned code can tell whether it is the save you already have.
  @override
  bool operator ==(Object other) =>
      other is DieSpec && other.kind == kind && other.colour == colour;

  @override
  int get hashCode => Object.hash(kind, colour);

  ConvexShape get shape => shapeFor(kind);

  /// Real acrylic, so a D20 is genuinely heavier than a D4 of the same width.
  double get mass => shape.volume * Tuning.dieDensity;
}

/// Ivory. What a die is unless you say otherwise.
const int kDiceWhite = 0xFFF3EBDD;

/// The colours a die can be. Chosen to stay distinguishable against the tray's
/// slate lining and from each other at die size, which rules out anything too
/// dark or too desaturated.
const List<int> kDicePalette = <int>[
  kDiceWhite,
  0xFF20242B, // graphite
  0xFFB3453F, // red
  0xFFD98032, // orange
  0xFFD8B23A, // amber
  0xFF4A8A55, // green
  0xFF3F6FA8, // blue
  0xFF7B5AA6, // violet
];

/// Pip value of the D6 face whose outward local normal is [sign] on axis
/// [axis].
///
/// +x is 1, +y is 2, +z is 3 and opposite faces sum to seven, which is the
/// standard right-handed western die: looking in at the corner where 1, 2 and 3
/// meet, they read anticlockwise.
int faceValue(int axis, int sign) {
  const List<int> positive = <int>[1, 2, 3];
  final int value = positive[axis];
  return sign > 0 ? value : 7 - value;
}

final Map<DieKind, ConvexShape> _shapes = <DieKind, ConvexShape>{};

/// The geometry of one kind of die, built once and shared by every die of that
/// kind — the shapes are immutable, and finding a D12's faces is not work worth
/// repeating ten times.
ConvexShape shapeFor(DieKind kind) => _shapes[kind] ??= _build(kind);

/// Every die is built to the same circumradius as a 16 mm D6.
///
/// A set could be normalised by volume instead, or by edge length, and each
/// gives a different-looking set. Matching the circumradius means every die
/// measures the same across its widest point, which is both how a real dice set
/// reads and — more usefully — what lets one spawn grid pack any mixture of
/// them without them starting inside each other.
final double kDieCircumradius = Tuning.dieSize * 0.5 * math.sqrt(3);

/// The bevel as a fraction of the inradius, taken from the D6 so that a 16 mm
/// cube keeps exactly the 1.3 mm bevel the feel was tuned against.
final double _bevelFraction = Tuning.dieBevel / (Tuning.dieSize * 0.5);

ConvexShape _build(DieKind kind) {
  switch (kind) {
    case DieKind.d4:
      return _shape(_tetrahedron(), readsDownFace: true);
    case DieKind.d6:
      return _shape(_cube(), usesPips: true, valueFor: _cubeValue);
    case DieKind.d8:
      return _shape(_octahedron());
    case DieKind.d10:
      return _shape(_trapezohedron());
    case DieKind.d12:
      return _shape(_dodecahedron());
    case DieKind.d20:
      return _shape(_icosahedron());
    case DieKind.poker:
      // The same cube as the D6 and a separate shape only so that the painter
      // can tell the two apart — the hippopotamus's arrangement exactly, and
      // for the same reason. What is printed on it is a card rather than a
      // number, which is `paintPokerFace`'s business and not the solid's.
      return _shape(_cube(), valueFor: _pokerValue);
    case DieKind.hippo:
      // The same cube as the D6, numbered the same way, and a separate shape
      // only so that the painter can tell the two apart.
      //
      // A hippopotamus is not convex — it has four legs with gaps between them
      // — and this app's collision is convex-polyhedron SAT. Simulating one
      // honestly would mean either a hull that is a lumpy stone with none of
      // the animal left in it, or a compound body and a fairness argument
      // nobody could make. So the hippo is *carved out of* a 16 mm die rather
      // than replacing it: the cube is what the tray collides with and what
      // decides the number, and `paintHippo` draws the animal inside it. It
      // rolls exactly as fairly as the D6 does, because it is one.
      return _shape(_cube(), valueFor: _cubeValue);
  }
}

/// The poker die's numbering: the D6's, moved up so that a nine is a nine.
///
/// Nine, ten, jack, queen, king, ace against one to six, which keeps the
/// cube's pairing — an ace lands opposite a nine the way a six lands opposite
/// a one — and means the numbers a die reads out are in the order the ranks
/// are, so anything that compares or sorts them is right without being told
/// about cards.
int _pokerValue(Vector3 n) => _cubeValue(n) + 8;

/// The D6's numbering, which the hippo carved out of one keeps.
///
/// Stated rather than taken from the generic pairing because the pip painter
/// and the tests were written against it — see [faceValue].
int _cubeValue(Vector3 n) {
  for (int axis = 0; axis < 3; axis++) {
    if (n[axis] > 0.5) return faceValue(axis, 1);
    if (n[axis] < -0.5) return faceValue(axis, -1);
  }
  return 1;
}

ConvexShape _shape(
  List<Vector3> vertices, {
  bool readsDownFace = false,
  bool usesPips = false,
  int Function(Vector3 normal)? valueFor,
}) => ConvexShape.fromVertices(
  vertices,
  circumradius: kDieCircumradius,
  bevelFraction: _bevelFraction,
  readsDownFace: readsDownFace,
  usesPips: usesPips,
  valueFor: valueFor,
);

// The five Platonic solids, at whatever scale is convenient; `fromVertices`
// scales them and finds their faces.

List<Vector3> _tetrahedron() => <Vector3>[
  Vector3(1, 1, 1),
  Vector3(1, -1, -1),
  Vector3(-1, 1, -1),
  Vector3(-1, -1, 1),
];

List<Vector3> _cube() => <Vector3>[
  for (int i = 0; i < 8; i++)
    Vector3(
      (i & 1) == 0 ? -1 : 1,
      (i & 2) == 0 ? -1 : 1,
      (i & 4) == 0 ? -1 : 1,
    ),
];

List<Vector3> _octahedron() => <Vector3>[
  Vector3(1, 0, 0),
  Vector3(-1, 0, 0),
  Vector3(0, 1, 0),
  Vector3(0, -1, 0),
  Vector3(0, 0, 1),
  Vector3(0, 0, -1),
];

const double _phi = 1.618033988749895; // (1 + √5) / 2

List<Vector3> _icosahedron() => <Vector3>[
  for (final int a in <int>[-1, 1])
    for (final int b in <int>[-1, 1]) ...<Vector3>[
      Vector3(0, a * 1.0, b * _phi),
      Vector3(a * 1.0, b * _phi, 0),
      Vector3(a * _phi, 0, b * 1.0),
    ],
];

List<Vector3> _dodecahedron() => <Vector3>[
  for (int i = 0; i < 8; i++)
    Vector3(
      (i & 1) == 0 ? -1 : 1,
      (i & 2) == 0 ? -1 : 1,
      (i & 4) == 0 ? -1 : 1,
    ),
  for (final int a in <int>[-1, 1])
    for (final int b in <int>[-1, 1]) ...<Vector3>[
      Vector3(0, a / _phi, b * _phi),
      Vector3(a / _phi, b * _phi, 0),
      Vector3(a * _phi, 0, b / _phi),
    ],
];

/// The D10 — a pentagonal trapezohedron, and the only die here that is not a
/// Platonic solid.
///
/// Two rings of five vertices, offset by 36°, with an apex above and below. The
/// apex height is not free: it is the one value that makes the ten kite faces
/// flat, which falls out of requiring the apex, the far ring vertex and the
/// midpoint of the near pair to be collinear.
List<Vector3> _trapezohedron() {
  const double ring = 0.105573; // Chosen so the solid is as tall as it is wide.
  final double c = math.cos(math.pi / 5);
  final double apex = ring * (1 + c) / (1 - c);
  return <Vector3>[
    Vector3(0, 0, apex),
    Vector3(0, 0, -apex),
    for (int k = 0; k < 5; k++) ...<Vector3>[
      Vector3(
        math.cos(2 * math.pi * k / 5),
        math.sin(2 * math.pi * k / 5),
        ring,
      ),
      Vector3(
        math.cos(2 * math.pi * k / 5 + math.pi / 5),
        math.sin(2 * math.pi * k / 5 + math.pi / 5),
        -ring,
      ),
    ],
  ];
}
