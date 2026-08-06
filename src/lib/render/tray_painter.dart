import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../physics/body.dart';
import '../physics/shape.dart';
import '../tray/tray.dart';

/// Maps tray space to the screen.
///
/// The tray's glass sits at z = 0 and fills the widget exactly, so at z = 0 the
/// projection is a straight scale and nothing about the tray's footprint has to
/// be corrected for. Everything deeper shrinks towards the centre, which is the
/// entire reason you can see the tray *has* a depth.
class TrayCamera {
  const TrayCamera({
    required this.pixelsPerMetre,
    required this.eyeDistance,
    required this.centre,
  });

  final double pixelsPerMetre;
  final double eyeDistance;
  final Offset centre;

  double scaleAt(double z) => eyeDistance / (eyeDistance - z);

  Offset project(Vector3 p) {
    final double s = scaleAt(p.z) * pixelsPerMetre;
    // Screen y runs down, tray y runs up.
    return Offset(centre.dx + p.x * s, centre.dy - p.y * s);
  }
}

/// How one die is painted: its body colour, and the ink its numbers are in.
class DieStyle {
  const DieStyle({required this.body, required this.ink});

  /// Derives the ink from the body, because a die is only ever printed in
  /// whichever of the two you can read against the other.
  factory DieStyle.of(int colour) {
    final double r = ((colour >> 16) & 0xFF) / 255.0;
    final double g = ((colour >> 8) & 0xFF) / 255.0;
    final double b = (colour & 0xFF) / 255.0;
    final double luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    return DieStyle(
      body: Color(colour),
      ink: luminance > 0.42 ? const Color(0xFF20242B) : const Color(0xFFF6EFE4),
    );
  }

  final Color body;
  final Color ink;
}

/// Direction from a surface *towards* the light — front, above, and a little to
/// the left, which is where a lamp is when you are looking down at a table.
final Vector3 _light = Vector3(-0.32, 0.52, 0.79)..normalize();

const double _ambient = 0.34;

/// The colour the tray fades towards while the dice are being read, and how far
/// it gets.
///
/// It is the app's own background, so the box does not darken so much as get
/// out of the way — and it stops short of vanishing, because the dice are
/// standing in a tray and a tray that disappears leaves them floating in a
/// void.
const Color _backdrop = Color(0xFF0B0E13);
const double _readoutDim = 0.72;

/// The blue a kept die glows. The selection colour the rack's ring is drawn in.
const Color _holdGlow = Color(0xFF6E9AD0);

Color _fade(Color colour, double amount) =>
    amount <= 0 ? colour : Color.lerp(colour, _backdrop, amount)!;

Color _shade(Color base, Vector3 normal) {
  final double lambert = math.max(0.0, normal.dot(_light));
  final double k = _ambient + (1 - _ambient) * lambert;
  return Color.fromARGB(
    255,
    (base.r * 255 * k).round().clamp(0, 255),
    (base.g * 255 * k).round().clamp(0, 255),
    (base.b * 255 * k).round().clamp(0, 255),
  );
}

/// Pip positions in face coordinates, each axis running −1 … 1.
///
/// Exposed so a test can assert the obvious thing: that the face showing a four
/// has four pips on it. A typo here would be invisible in code review and
/// glaring in a shipped dice app.
List<Offset>? pipLayout(int value) => _pips[value];

const double _p = 0.52;
const Map<int, List<Offset>> _pips = <int, List<Offset>>{
  1: <Offset>[Offset(0, 0)],
  2: <Offset>[Offset(-_p, -_p), Offset(_p, _p)],
  3: <Offset>[Offset(-_p, -_p), Offset(0, 0), Offset(_p, _p)],
  4: <Offset>[
    Offset(-_p, -_p),
    Offset(-_p, _p),
    Offset(_p, -_p),
    Offset(_p, _p),
  ],
  5: <Offset>[
    Offset(-_p, -_p),
    Offset(-_p, _p),
    Offset(0, 0),
    Offset(_p, -_p),
    Offset(_p, _p),
  ],
  6: <Offset>[
    Offset(-_p, -_p),
    Offset(-_p, 0),
    Offset(-_p, _p),
    Offset(_p, -_p),
    Offset(_p, 0),
    Offset(_p, _p),
  ],
};

// Numbers are laid out once at this size and then scaled into each face by the
// canvas transform, which is both cheaper than re-laying them out every frame
// and the only way to get a numeral to sit in perspective on a tilted face.
const double _glyphFontSize = 100.0;
const double _glyphLayoutWidth = 400.0;
final Map<int, ui.Paragraph> _glyphs = <int, ui.Paragraph>{};

ui.Paragraph _glyph(int value, Color ink) {
  final int key = value * 0x100000000 + ink.toARGB32();
  return _glyphs[key] ??=
      (ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textAlign: TextAlign.center,
                fontSize: _glyphFontSize,
                fontWeight: FontWeight.w600,
              ),
            )
            ..pushStyle(ui.TextStyle(color: ink))
            ..addText('$value'))
          .build()
        ..layout(const ui.ParagraphConstraints(width: _glyphLayoutWidth));
}

/// Twice the signed area of a projected polygon, which is what decides whether
/// a face is worth printing a number on: at a grazing angle the number is a
/// smear a pixel or two wide, and laying it out costs the same as one you can
/// read.
double _screenArea(List<Offset> corners) {
  double sum = 0;
  for (int i = 0; i < corners.length; i++) {
    final Offset a = corners[i];
    final Offset b = corners[(i + 1) % corners.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum.abs() / 2;
}

/// One box and everything in it, filling [size].
///
/// A free function rather than a method, because the tray is drawn twice over
/// while a swipe is in flight and neither copy is the painter's own. The whole
/// scene is anchored on the canvas' origin, so a caller that wants it somewhere
/// else translates the canvas and calls this again.
void paintTrayScene(Canvas canvas, Size size, DiceTray tray) {
  final TrayCamera camera = TrayCamera(
    pixelsPerMetre: size.width / tray.width,
    eyeDistance: Tuning.eyeDistance,
    centre: Offset(size.width / 2, size.height / 2),
  );

  // While the dice are being presented the box behind them steps back, so
  // that what is lit is the thing you are being asked to read.
  final double dim = tray.readout.progress * _readoutDim;

  paintTrayBox(
    canvas,
    camera,
    width: tray.width,
    height: tray.height,
    depth: tray.depth,
    dim: dim,
  );
  for (final RigidBody die in tray.dice) {
    _paintShadow(canvas, camera, tray, die, dim);
  }

  // Whole dice back to front. Sorting by die rather than by face keeps the
  // order stable when two dice touch — per-face sorting flickers exactly when
  // the dice are most interesting.
  final List<int> order = List<int>.generate(tray.dice.length, (int i) => i)
    ..sort(
      (int a, int b) =>
          tray.dice[a].position.z.compareTo(tray.dice[b].position.z),
    );
  for (final int i in order) {
    final RigidBody die = tray.dice[i];
    // Behind the die, and inside the same back-to-front pass, so a die in
    // front of a held one covers its halo exactly as it covers the die.
    if (die.held) _paintHold(canvas, camera, die);
    paintDie(canvas, camera, die, DieStyle.of(tray.specs[i].colour));
  }
}

/// The glow behind a die the player is keeping.
///
/// Two blurred discs rather than an outline of the solid: the die is a
/// different silhouette every frame it turns, and a halo does not care. The
/// tight one gives the edge something to sit against, the wide one is what
/// carries across the tray — and the colour is the blue everything selected in
/// this app is drawn in, so a kept die and a selected slot in the rack say the
/// same thing the same way.
void _paintHold(Canvas canvas, TrayCamera camera, RigidBody die) {
  final Offset centre = camera.project(die.position);
  final double pixels =
      die.circumradius * camera.scaleAt(die.position.z) * camera.pixelsPerMetre;

  void halo(double spread, double blur, double alpha) => canvas.drawCircle(
    centre,
    pixels * spread,
    Paint()
      ..color = _holdGlow.withValues(alpha: alpha)
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, pixels * blur),
  );

  halo(0.88, 0.20, 0.42);
  halo(0.64, 0.09, 0.70);
}

/// Which die is under [local], or null for a tap that hit the tray.
///
/// Front to back, because that is the order they are drawn in and the one you
/// are looking at is the one on top. A die is taken to be the disc its
/// circumradius projects to, which is generous — but the formation stands them
/// a little over their own width apart, so a generous disc still cannot reach
/// its neighbour's centre.
int? dieAt(DiceTray tray, Size size, Offset local) {
  final TrayCamera camera = TrayCamera(
    pixelsPerMetre: size.width / tray.width,
    eyeDistance: Tuning.eyeDistance,
    centre: Offset(size.width / 2, size.height / 2),
  );

  final List<int> order = List<int>.generate(tray.dice.length, (int i) => i)
    ..sort(
      (int a, int b) =>
          tray.dice[b].position.z.compareTo(tray.dice[a].position.z),
    );
  for (final int i in order) {
    final RigidBody die = tray.dice[i];
    final double pixels =
        die.circumradius *
        camera.scaleAt(die.position.z) *
        camera.pixelsPerMetre;
    if ((camera.project(die.position) - local).distanceSquared <=
        pixels * pixels) {
      return i;
    }
  }
  return null;
}

class TrayPainter extends CustomPainter {
  TrayPainter({required this.tray, required this.repaint})
    : super(repaint: repaint);

  final DiceTray tray;
  final Listenable repaint;

  @override
  void paint(Canvas canvas, Size size) => paintTrayScene(canvas, size, tray);

  @override
  bool shouldRepaint(TrayPainter oldDelegate) => true;
}

/// A row of boxes, [page] of them in from the left edge.
///
/// A box fills the screen exactly, so swiping from one group to the next is a
/// matter of pushing the finished projection sideways. Sliding
/// [TrayCamera.centre] instead would carry the vanishing point along with it,
/// and the box would look like it was being walked around rather than pushed
/// out of the way.
class TrayPagesPainter extends CustomPainter {
  TrayPagesPainter({
    required this.trays,
    required this.page,
    required this.repaint,
  }) : super(repaint: repaint);

  /// One box per group, in the order they were configured.
  final List<DiceTray> trays;

  /// How far along the row we are, in pages. A whole number is a box squarely
  /// on screen; anything between is a swipe in flight.
  ///
  /// A listenable rather than a number so that dragging repaints without
  /// rebuilding the widget — the same bargain the frame notifier makes for the
  /// simulation.
  final ValueListenable<double> page;

  final Listenable repaint;

  @override
  void paint(Canvas canvas, Size size) {
    // A screen, plus the dark between two boxes. The gap is why you can tell
    // one box has left and another has arrived.
    final double pitch =
        size.width + Tuning.trayPageGap * Tuning.logicalPixelsPerMetre;
    final double at = page.value;

    canvas.clipRect(Offset.zero & size);
    for (int i = 0; i < trays.length; i++) {
      final double dx = (i - at) * pitch;
      if (dx.abs() >= size.width) continue;
      canvas.save();
      canvas.translate(dx, 0);
      paintTrayScene(canvas, size, trays[i]);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(TrayPagesPainter oldDelegate) => true;
}

/// The box itself: the back wall and the four sides, and nothing in it.
///
/// Taken by its measurements rather than by a [DiceTray], because the card
/// table is the same box with no dice in it and there is no sense in it
/// carrying a physics world around to be drawn.
void paintTrayBox(
  Canvas canvas,
  TrayCamera camera, {
  required double width,
  required double height,
  required double depth,
  double dim = 0,
}) {
  final double w = width / 2;
  final double h = height / 2;
  final double d = depth;

  Offset front(int i) =>
      camera.project(Vector3((i == 0 || i == 3) ? -w : w, (i < 2) ? h : -h, 0));
  Offset back(int i) => camera.project(
    Vector3((i == 0 || i == 3) ? -w : w, (i < 2) ? h : -h, -d),
  );

  final Paint paint = Paint()..style = PaintingStyle.fill;

  // Back wall.
  paint.color = _fade(_shade(const Color(0xFF1D2530), Vector3(0, 0, 1)), dim);
  canvas.drawPath(
    Path()
      ..moveTo(back(0).dx, back(0).dy)
      ..lineTo(back(1).dx, back(1).dy)
      ..lineTo(back(2).dx, back(2).dy)
      ..lineTo(back(3).dx, back(3).dy)
      ..close(),
    paint,
  );

  // The four sides, each shaded by the direction it faces so the tray reads
  // as a box rather than as a picture of one.
  const List<List<int>> sides = <List<int>>[
    <int>[0, 1], // top
    <int>[1, 2], // right
    <int>[2, 3], // bottom
    <int>[3, 0], // left
  ];
  final List<Vector3> normals = <Vector3>[
    Vector3(0, -1, 0),
    Vector3(-1, 0, 0),
    Vector3(0, 1, 0),
    Vector3(1, 0, 0),
  ];
  for (int s = 0; s < 4; s++) {
    final int i = sides[s][0];
    final int j = sides[s][1];
    paint.color = _fade(_shade(const Color(0xFF2A3442), normals[s]), dim);
    canvas.drawPath(
      Path()
        ..moveTo(front(i).dx, front(i).dy)
        ..lineTo(front(j).dx, front(j).dy)
        ..lineTo(back(j).dx, back(j).dy)
        ..lineTo(back(i).dx, back(i).dy)
        ..close(),
      paint,
    );
  }
}

/// A soft blob on the back wall, cast along the light. It is not a real
/// shadow, but it is the cheapest cue there is for how far off the back wall
/// a die is — and without it a tumbling die reads as a flat spinning sprite.
void _paintShadow(
  Canvas canvas,
  TrayCamera camera,
  DiceTray tray,
  RigidBody die,
  double dim,
) {
  final double travel = (die.position.z + tray.depth) / _light.z;
  if (travel <= 0) return;
  final Vector3 landing = die.position - _light * travel;

  final double softness = 1.0 + travel / (tray.depth * 1.6);
  final double radius = die.circumradius * softness;
  final Offset centre = camera.project(
    Vector3(landing.x, landing.y, -tray.depth),
  );
  final double pixels =
      radius * camera.scaleAt(-tray.depth) * camera.pixelsPerMetre;

  canvas.drawCircle(
    centre,
    pixels,
    Paint()
      ..color = Colors.black.withValues(alpha: (0.42 / softness) * (1 - dim))
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, pixels * 0.45),
  );
}

/// Paints one die: every face of it you can see, with its numbers on.
///
/// A free function rather than a method on [TrayPainter], because the picker
/// draws dice too. The rack on the config screen is the same solid, lit by the
/// same lamp and printed with the same numerals as the one that lands in the
/// tray — held still instead of thrown. Two code paths would drift, and the
/// picker would end up quietly showing you a different die from the one you
/// were choosing.
void paintDie(Canvas canvas, TrayCamera camera, RigidBody die, DieStyle style) {
  final ConvexShape shape = die.shape;
  final Vector3 eye = Vector3(0, 0, camera.eyeDistance);

  for (int f = 0; f < shape.faces.length; f++) {
    final ConvexFace face = shape.faces[f];
    final Vector3 normal = die.faceNormal(f);
    final Vector3 centre = die.faceCentre(f);

    // Cull anything pointing away. With a convex body that leaves exactly the
    // faces you can see, and no need to sort them against each other.
    if (normal.dot(eye - centre) <= 0) continue;

    final List<Offset> corners = <Offset>[
      for (final int v in face.vertices) camera.project(die.outerVertex(v)),
    ];

    final Path path = Path()..moveTo(corners[0].dx, corners[0].dy);
    for (int i = 1; i < corners.length; i++) {
      path.lineTo(corners[i].dx, corners[i].dy);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = _shade(style.body, normal),
    );
    // A hairline along the edges. Adjacent faces differ by very little in
    // shade at some angles, and without this the silhouette is all you can
    // read the rotation from.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.black.withValues(alpha: 0.18),
    );

    // Below this a number is a smudge and laying it out is wasted work.
    if (_screenArea(corners) < 90) continue;

    final Vector3 p0 = die.outerVertex(face.vertices[0]);
    final Vector3 p1 = die.outerVertex(face.vertices[1]);
    final double edge = (p1 - p0).length;
    final Vector3 along = (p1 - p0) / edge;
    // The face polygons wind anticlockwise seen from outside, so the interior
    // is always to the left of an edge — which is what keeps a numeral the
    // right way round rather than mirrored.
    final Vector3 inward = normal.cross(along);

    if (shape.usesPips) {
      _paintPips(
        canvas,
        camera,
        style,
        normal,
        centre,
        along,
        inward,
        edge / 2,
        face.value,
      );
    } else if (shape.readsDownFace) {
      _paintEdgeNumbers(canvas, camera, die, style, f, normal);
    } else {
      _paintNumber(
        canvas,
        camera,
        centre,
        along,
        inward,
        face.inradius,
        face.value,
        style.ink,
        1.75,
      );
    }
  }
}

void _paintPips(
  Canvas canvas,
  TrayCamera camera,
  DieStyle style,
  Vector3 normal,
  Vector3 centre,
  Vector3 along,
  Vector3 inward,
  double half,
  int value,
) {
  final List<Offset>? layout = _pips[value];
  if (layout == null) return;

  // Lift the pips a hair off the face so they cannot z-fight it.
  final Vector3 lift = normal * 2e-5;
  final Vector3 uEdge = along * half;
  final Vector3 vEdge = inward * half;
  final double radius = half * 0.165;
  final Paint paint =
      Paint()
        ..style = PaintingStyle.fill
        ..color = _shade(style.ink, normal);

  for (final Offset pip in layout) {
    final Vector3 pipCentre = centre + uEdge * pip.dx + vEdge * pip.dy + lift;

    // Drawn as a projected polygon rather than a screen-space circle: at a
    // grazing angle a pip is an ellipse, and a face full of circles is the
    // fastest way to make a 3D die look like a sticker.
    final Path path = Path();
    const int segments = 12;
    for (int i = 0; i < segments; i++) {
      final double a = i * 2 * math.pi / segments;
      final Vector3 p =
          pipCentre +
          along * (math.cos(a) * radius) +
          inward * (math.sin(a) * radius);
      final Offset o = camera.project(p);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }
}

/// A D4's numbers go along its edges, not in the middle of its faces.
///
/// The die is read off the face it is resting on, which you cannot see — so
/// each number is printed along the edge it shares with that face, on all
/// three of the faces you *can* see. Set a D4 down and the same number is
/// sitting on the table three times over.
void _paintEdgeNumbers(
  Canvas canvas,
  TrayCamera camera,
  RigidBody die,
  DieStyle style,
  int faceIndex,
  Vector3 normal,
) {
  final ConvexShape shape = die.shape;
  final ConvexFace face = shape.faces[faceIndex];
  final Vector3 centre = die.faceCentre(faceIndex);

  for (int e = 0; e < face.vertices.length; e++) {
    final int neighbour = face.neighbours[e];
    if (neighbour < 0) continue;
    final Vector3 p = die.outerVertex(face.vertices[e]);
    final Vector3 q = die.outerVertex(
      face.vertices[(e + 1) % face.vertices.length],
    );
    final Vector3 along = (q - p).normalized();
    final Vector3 inward = normal.cross(along);
    final Vector3 midpoint = (p + q) * 0.5;

    _paintNumber(
      canvas,
      camera,
      midpoint + (centre - midpoint) * 0.42,
      along,
      inward,
      face.inradius,
      shape.faces[neighbour].value,
      style.ink,
      0.95,
    );
  }
}

/// Lays one number onto a face, in the plane of that face.
///
/// The face's own basis becomes the canvas transform, so the glyph is
/// foreshortened exactly as the face is. It is an affine approximation of a
/// perspective projection — taken at the number's own position, where it is
/// indistinguishable at this size — which is what lets a laid-out paragraph
/// be reused rather than re-projected glyph by glyph.
void _paintNumber(
  Canvas canvas,
  TrayCamera camera,
  Vector3 anchor,
  Vector3 along,
  Vector3 inward,
  double unit,
  int value,
  Color ink,
  double height,
) {
  final ui.Paragraph glyph = _glyph(value, ink);
  final Offset origin = camera.project(anchor);
  final Offset du = camera.project(anchor + along * unit) - origin;
  final Offset dv = camera.project(anchor + inward * unit) - origin;

  // Face space runs x along the edge and y *down* the face, which is what
  // text expects — hence the negated second column.
  final Matrix4 place =
      Matrix4.identity()
        ..setEntry(0, 0, du.dx)
        ..setEntry(1, 0, du.dy)
        ..setEntry(0, 1, -dv.dx)
        ..setEntry(1, 1, -dv.dy)
        ..setEntry(0, 3, origin.dx)
        ..setEntry(1, 3, origin.dy);

  final double width = glyph.longestLine;
  double scale = height / glyph.height;
  // Two digits are wider than they are tall; shrink rather than overhang.
  const double widthLimit = 1.55;
  if (width * scale > widthLimit) scale = widthLimit / width;

  canvas.save();
  canvas.transform(place.storage);
  canvas.scale(scale);
  canvas.drawParagraph(
    glyph,
    Offset(-_glyphLayoutWidth / 2, -glyph.height / 2),
  );
  // A 6 and a 9 are the same glyph upside down, which on a die that can land
  // any way up is not a distinction you can leave to the reader.
  if (value == 6 || value == 9) {
    canvas.drawRect(
      Rect.fromLTWH(
        -width * 0.34,
        glyph.height * 0.40,
        width * 0.68,
        glyph.height * 0.055,
      ),
      Paint()..color = ink,
    );
  }
  canvas.restore();
}
