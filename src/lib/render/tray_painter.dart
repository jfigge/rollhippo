import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../physics/body.dart';
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

/// How one die is painted.
class DieStyle {
  const DieStyle({required this.body, required this.pip});
  final Color body;
  final Color pip;

  static const List<DieStyle> palette = <DieStyle>[
    DieStyle(body: Color(0xFFF3EBDD), pip: Color(0xFF20242B)),
    DieStyle(body: Color(0xFFB3453F), pip: Color(0xFFF6EFE4)),
    DieStyle(body: Color(0xFF3F6FA8), pip: Color(0xFFF6EFE4)),
  ];
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

class TrayPainter extends CustomPainter {
  TrayPainter({
    required this.tray,
    required this.repaint,
    this.showContacts = false,
  }) : super(repaint: repaint);

  final DiceTray tray;
  final Listenable repaint;
  final bool showContacts;

  @override
  void paint(Canvas canvas, Size size) {
    final TrayCamera camera = TrayCamera(
      pixelsPerMetre: size.width / tray.width,
      eyeDistance: Tuning.eyeDistance,
      centre: Offset(size.width / 2, size.height / 2),
    );

    _paintTray(canvas, camera);
    for (final RigidBox die in tray.dice) {
      _paintShadow(canvas, camera, die);
    }

    // Whole dice back to front. Sorting by die rather than by face keeps the
    // order stable when two dice touch — per-face sorting flickers exactly when
    // the dice are most interesting.
    final List<RigidBox> order = List<RigidBox>.of(tray.dice)
      ..sort((RigidBox a, RigidBox b) => a.position.z.compareTo(b.position.z));
    for (final RigidBox die in order) {
      _paintDie(
        canvas,
        camera,
        die,
        DieStyle.palette[tray.dice.indexOf(die) % DieStyle.palette.length],
      );
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
  void _paintShadow(Canvas canvas, TrayCamera camera, RigidBox die) {
    final double travel = (die.position.z + tray.depth) / _light.z;
    if (travel <= 0) return;
    final Vector3 landing = die.position - _light * travel;

    final double softness = 1.0 + travel / (tray.depth * 1.6);
    final double radius = die.halfExtents.length * softness;
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

  void _paintDie(
    Canvas canvas,
    TrayCamera camera,
    RigidBox die,
    DieStyle style,
  ) {
    final Vector3 eye = Vector3(0, 0, camera.eyeDistance);

    for (int k = 0; k < 3; k++) {
      for (final int sign in <int>[1, -1]) {
        final Vector3 normal = die.axis(k) * sign.toDouble();
        final Vector3 centre = die.position + normal * die.halfExtents[k];

        // Cull anything pointing away. With a convex box that leaves exactly
        // the three faces you can see, and no need to sort them against each
        // other.
        if (normal.dot(eye - centre) <= 0) continue;

        final int u = (k + 1) % 3;
        final int v = (k + 2) % 3;
        final Vector3 uEdge = die.axis(u) * die.halfExtents[u];
        final Vector3 vEdge = die.axis(v) * die.halfExtents[v];

        final List<Offset> corners = <Offset>[
          camera.project(centre + uEdge + vEdge),
          camera.project(centre - uEdge + vEdge),
          camera.project(centre - uEdge - vEdge),
          camera.project(centre + uEdge - vEdge),
        ];

        final Path path = Path()..moveTo(corners[0].dx, corners[0].dy);
        for (int i = 1; i < 4; i++) {
          path.lineTo(corners[i].dx, corners[i].dy);
        }
        path.close();

        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.fill
            ..color = _shade(style.body, normal),
        );
        // A hairline along the edges. Adjacent faces of a die differ by very
        // little in shade at some angles, and without this the silhouette is
        // all you can read the rotation from.
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = Colors.black.withValues(alpha: 0.18),
        );

        _paintPips(
          canvas,
          camera,
          die,
          style,
          normal,
          centre,
          uEdge,
          vEdge,
          faceValue(k, sign),
        );
      }
    }
  }

  void _paintPips(
    Canvas canvas,
    TrayCamera camera,
    RigidBox die,
    DieStyle style,
    Vector3 normal,
    Vector3 centre,
    Vector3 uEdge,
    Vector3 vEdge,
    int value,
  ) {
    final List<Offset>? layout = _pips[value];
    if (layout == null) return;

    // Lift the pips a hair off the face so they cannot z-fight it.
    final Vector3 lift = normal * 2e-5;
    final double radius = die.halfExtents.x * 0.165;
    final Paint paint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = _shade(style.pip, normal);

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
            uEdge.normalized() * (math.cos(a) * radius) +
            vEdge.normalized() * (math.sin(a) * radius);
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

  @override
  bool shouldRepaint(TrayPainter oldDelegate) => true;
}
