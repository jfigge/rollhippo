import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart'
    show Matrix3, Quaternion, Vector3;

import '../physics/body.dart';
import '../physics/shape.dart';
import '../tray/tray.dart';
import 'tray_painter.dart';

/// One die, held still, drawn exactly as the tray would draw it.
///
/// The picker shows the solid itself rather than an icon of one, which is the
/// only honest way to answer "what is a D10?" — and it costs almost nothing,
/// because [paintDie] is the same code that paints the tray.
class DiePreview extends StatelessWidget {
  const DiePreview({super.key, required this.spec});

  final DieSpec spec;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _DiePainter(spec), size: Size.infinite);
  }
}

/// How far from face-on a die may be turned. Past this the number on the front
/// is more foreshortened than it is worth, whatever it buys in solidity.
const double _maxTilt = math.pi / 4;

/// How much of the front face's share of the light a neighbour may take before
/// the die stops reading as that face turned towards you.
const double _dominance = 0.9;

/// The angle one kind of die is shown at.
///
/// Found rather than listed, in the same spirit as the shapes themselves: the
/// six solids differ too much for one set of numbers to flatter all of them.
/// A cube face-on with a small tilt is a die; a tetrahedron face-on is a
/// triangle, because its neighbouring faces lean 109° away and every one of
/// them falls out of sight behind it.
///
/// So the rule is stated instead of the answer. Turn the face carrying the
/// die's highest number towards the viewer — a D20 should introduce itself with
/// a 20 on it — then rotate away from square-on in whichever direction, and as
/// far, as brings the next two faces round it most fully into view, stopping
/// while that face is still plainly the one you are being shown. On a cube that finds the corner
/// and gives the familiar three-quarter view; on a D4 it finds an edge, which
/// is exactly how a real one is photographed; on a D20, whose neighbours are
/// only 42° apart, it stops early because turning further would hand the die to
/// a face with no number you asked for on it.
Quaternion previewOrientation(ConvexShape shape) {
  int front = 0;
  for (int f = 1; f < shape.faces.length; f++) {
    if (shape.faces[f].value > shape.faces[front].value) front = f;
  }
  final ConvexFace face = shape.faces[front];
  final Vector3 normal = face.normal;

  // A basis in the plane of that face to sweep the tilt direction through. Its
  // first edge is as good a place to start from as any, and it makes the sweep
  // depend on nothing outside the shape.
  final Vector3 u =
      (shape.vertices[face.vertices[1]] - shape.vertices[face.vertices[0]])
        ..normalize();
  final Vector3 w = normal.cross(u);

  Vector3 view = normal;
  double best = -1;
  const int tilts = 12;
  const int bearings = 48;
  for (int t = 1; t <= tilts; t++) {
    final double tilt = _maxTilt * t / tilts;
    for (int b = 0; b < bearings; b++) {
      final double bearing = 2 * math.pi * b / bearings;
      final Vector3 candidate =
          normal * math.cos(tilt) +
          (u * math.cos(bearing) + w * math.sin(bearing)) * math.sin(tilt);

      // What makes a die read as a solid is the next two faces round from the
      // one you are being shown, so those are what the angle is scored on: how
      // squarely the best two of them meet the eye. Scoring the whole visible
      // area instead sounds better and is worse — on a D12 or a D20 it is
      // nearly the same in every direction, and what little it does vary by
      // peaks square on to a face, which is the one view that flattens them.
      final double facing = normal.dot(candidate);
      double first = 0;
      double second = 0;
      bool dominant = true;
      for (int f = 0; f < shape.faces.length && dominant; f++) {
        if (f == front) continue;
        final double d = shape.faces[f].normal.dot(candidate);
        // A neighbour this square on is no longer a neighbour: the die has been
        // turned far enough that it is being shown a different face.
        if (d > facing * _dominance) dominant = false;
        if (d > first) {
          second = first;
          first = d;
        } else if (d > second) {
          second = d;
        }
      }
      if (dominant && first + second > best) {
        best = first + second;
        view = candidate;
      }
    }
  }

  // Turn whatever that direction was towards the eye, which sits out along +z.
  final Quaternion align = Quaternion.fromTwoVectors(view, Vector3(0, 0, 1));

  // That leaves one degree of freedom — the spin about the line of sight — and
  // it goes on standing the numeral up. Which way up it sits is decided by the
  // face's first edge, since [paintDie] lays text along it: text runs along
  // that edge and stands towards `normal × along`, so that is the direction to
  // bring round to screen up.
  //
  // Turned by the rotation *matrix*, not by `Quaternion.rotated`: vector_math
  // builds its matrix from `q v q⁻¹` but rotates vectors by `q⁻¹ v q`, so the
  // two run opposite ways round. The matrix is the one [RigidBody] derives its
  // world geometry with, and so the one the painter will be looking at.
  final Matrix3 rotation = align.asRotationMatrix();
  final Vector3 along = rotation.transformed(u.clone());
  final Vector3 up = rotation.transformed(normal.clone()).cross(along);
  // Only the part of it across the line of sight can be corrected, so that is
  // the part the angle is taken from.
  final Vector3 flat = Vector3(up.x, up.y, 0)..normalize();
  final double spin = math.atan2(flat.x, flat.y);

  // Composed the same way round: the right-hand quaternion acts first, so the
  // die is aimed and then spun about the line it is now aimed along.
  return (Quaternion.axisAngle(Vector3(0, 0, 1), spin) * align)..normalize();
}

/// One body per kind, shared by every preview of that kind.
///
/// Nothing ever moves them — the picker is a still life — so a die at the
/// preview angle is as reusable as the shape it is built from, and searching
/// for the same angle again on every rebuild would be work for nothing.
final Map<DieKind, RigidBody> _bodies = <DieKind, RigidBody>{};

RigidBody _body(DieKind kind) =>
    _bodies[kind] ??= RigidBody(
      shape: shapeFor(kind),
      mass: 1.0,
      orientation: previewOrientation(shapeFor(kind)),
    );

class _DiePainter extends CustomPainter {
  const _DiePainter(this.spec);

  final DieSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final RigidBody die = _body(spec.kind);
    // Every die is built to the same circumradius, so scaling by it leaves the
    // whole set the same size in the rack — which is what they are in the hand.
    // A shade over twice it, to leave the corners of a die turned to a corner
    // somewhere to go.
    final double span = 2.1 * die.circumradius;
    paintDie(
      canvas,
      TrayCamera(
        pixelsPerMetre: size.shortestSide / span,
        eyeDistance: Tuning.eyeDistance,
        centre: Offset(size.width / 2, size.height / 2),
      ),
      die,
      DieStyle.of(spec.colour),
    );
  }

  @override
  bool shouldRepaint(_DiePainter oldDelegate) =>
      oldDelegate.spec.kind != spec.kind ||
      oldDelegate.spec.colour != spec.colour;
}
