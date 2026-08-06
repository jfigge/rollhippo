import 'dart:math' as math;
import 'dart:ui' as ui;

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

class TrayPainter extends CustomPainter {
  TrayPainter({required this.tray, required this.repaint})
    : super(repaint: repaint);

  final DiceTray tray;
  final Listenable repaint;

  @override
  void paint(Canvas canvas, Size size) {
    final TrayCamera camera = TrayCamera(
      pixelsPerMetre: size.width / tray.width,
      eyeDistance: Tuning.eyeDistance,
      centre: Offset(size.width / 2, size.height / 2),
    );

    _paintTray(canvas, camera);
    for (final RigidBody die in tray.dice) {
      _paintShadow(canvas, camera, die);
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
      paintDie(canvas, camera, tray.dice[i], DieStyle.of(tray.specs[i].colour));
    }
  }

  void _paintTray(Canvas canvas, TrayCamera camera) {
    final double w = tray.width / 2;
    final double h = tray.height / 2;
    final double d = tray.depth;

    Offset front(int i) => camera.project(
      Vector3((i == 0 || i == 3) ? -w : w, (i < 2) ? h : -h, 0),
    );
    Offset back(int i) => camera.project(
      Vector3((i == 0 || i == 3) ? -w : w, (i < 2) ? h : -h, -d),
    );

    final Paint paint = Paint()..style = PaintingStyle.fill;

    // Back wall.
    paint.color = _shade(const Color(0xFF1D2530), Vector3(0, 0, 1));
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
      paint.color = _shade(const Color(0xFF2A3442), normals[s]);
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
  void _paintShadow(Canvas canvas, TrayCamera camera, RigidBody die) {
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
        ..color = Colors.black.withValues(alpha: 0.42 / softness)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, pixels * 0.45),
    );
  }

  @override
  bool shouldRepaint(TrayPainter oldDelegate) => true;
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
