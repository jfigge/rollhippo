import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../physics/body.dart';
import '../physics/shape.dart';

/// Which face of a die carries the number it rolled, and which of that face's
/// edges the number is written along.
///
/// The two are separate because they are not always the same face. On every die
/// but the D4 the number sits in the middle of the face that is showing, and
/// [edge] only says which way up it is printed. A D4 has no face showing at all
/// — it rests on one and points a vertex at the sky — so the number it rolled
/// is on a face you cannot see, printed along the edges its neighbours share
/// with it. Then [face] is one of those neighbours and [edge] is the edge they
/// have in common, which is the one the number is written along.
class DieMarking {
  const DieMarking({required this.face, required this.edge});

  /// Index into [ConvexShape.faces] of the face the number is printed on.
  final int face;

  /// Index into that face's `vertices`, naming the edge that runs from
  /// `vertices[edge]` to `vertices[edge + 1]`. Text is laid along it and stands
  /// up towards the middle of the face, so levelling it stands the number up.
  final int edge;
}

/// Index of the face a die is read off, given which way [up] points.
///
/// The loop [DiceTray.faceUp] used to hold, lifted out so that it can hand back
/// the face itself and not only the number on it — turning a die so you can
/// read it needs to know which face to turn.
///
/// A D4 is read the other way up, for the reason in [DieMarking].
int readFace(RigidBody die, Vector3 up) {
  final Vector3 towards = die.shape.readsDownFace ? -up : up;

  int best = 0;
  double bestDot = double.negativeInfinity;
  for (int f = 0; f < die.shape.faces.length; f++) {
    final double d = die.faceNormal(f).dot(towards);
    if (d > bestDot) {
      bestDot = d;
      best = f;
    }
  }
  return best;
}

/// Where the number on face [read] is actually printed.
///
/// Derived from the face's neighbour links rather than listed per kind, so a
/// new shape that reads off its down face needs nothing added here.
DieMarking readMarking(ConvexShape shape, int read) {
  if (!shape.readsDownFace) {
    // The numeral sits at the centroid and [paintDie] lays it along the face's
    // first edge, so that is the edge that decides which way up it reads. The
    // D6's pips take the same basis: a two, a three and a six are not
    // symmetric, and they lean the wrong way if it is ignored.
    return DieMarking(face: read, edge: 0);
  }

  // Any of the three neighbours will do — the die is about to be turned
  // anyway, so the cheapest correct choice is the first, which also makes the
  // answer the same every time the same face lands.
  final int face = shape.faces[read].neighbours[0];
  final List<int> neighbours = shape.faces[face].neighbours;
  for (int e = 0; e < neighbours.length; e++) {
    if (neighbours[e] == read) return DieMarking(face: face, edge: e);
  }
  // Unreachable for a closed solid: a neighbour of a face is a face that
  // names it back.
  return DieMarking(face: face, edge: 0);
}

/// The orientation that turns [marking] square to the glass with its number
/// standing upright.
///
/// Aim the face's normal down the line of sight, which leaves one degree of
/// freedom — the spin about that line — and spend it standing the numeral up.
/// [paintDie] runs text along the marked edge and stands it towards
/// `normal × along`, so that is the direction to bring round to screen up.
///
/// Turned by the rotation *matrix*, not by `Quaternion.rotated`: vector_math
/// builds its matrix from `q v q⁻¹` but rotates vectors by `q⁻¹ v q`, so the two
/// run opposite ways round. The matrix is the one [RigidBody] derives its world
/// geometry with, and so the one the painter will be looking at.
Quaternion markingToScreen(ConvexShape shape, DieMarking marking) {
  final ConvexFace face = shape.faces[marking.face];
  final int corners = face.vertices.length;
  final Vector3 along =
      (shape.vertices[face.vertices[(marking.edge + 1) % corners]] -
            shape.vertices[face.vertices[marking.edge]])
        ..normalize();

  final Quaternion align = Quaternion.fromTwoVectors(
    face.normal,
    Vector3(0, 0, 1),
  );
  final Matrix3 rotation = align.asRotationMatrix();
  final Vector3 turned = rotation.transformed(along);
  final Vector3 up = rotation.transformed(face.normal.clone()).cross(turned);

  // The face is square to the screen now, so `up` already lies in the screen
  // plane and the spin is simply the angle that brings it onto +y.
  final double spin = math.atan2(up.x, up.y);

  // Composed the same way round as [previewOrientation]: the right-hand
  // quaternion acts first, so the die is aimed and then spun about the line it
  // is now aimed along.
  return (Quaternion.axisAngle(Vector3(0, 0, 1), spin) * align)..normalize();
}

/// [markingToScreen], tipped back by [tilt] radians about the screen's
/// horizontal.
///
/// Square on, a die is a polygon: a D6 showing a six is a square with six dots
/// on it and nothing about it says "cube". Tipping the top away brings the
/// faces above and beside it into view, at the cost of foreshortening the
/// number by `cos(tilt)` — which at fifteen degrees is three percent, and
/// invisible.
///
/// Tipping about the screen's own x axis rather than the die's is what keeps
/// the numeral upright: screen up is carried to `(0, cos tilt, -sin tilt)`,
/// which still points straight up once it is projected.
///
/// It tips *back* — the top away from you — so the face being read turns up
/// towards the lamp rather than away from it. Tipping the other way is the
/// conventional angle to photograph a die from, and here it is the wrong one
/// twice over: it puts the reading face in its own shade, and it brings the
/// face above it into view in the gap between one row of the formation and the
/// next, which is exactly where there is no room.
Quaternion markingToScreenTilted(
  ConvexShape shape,
  DieMarking marking,
  double tilt,
) =>
    (Quaternion.axisAngle(Vector3(1, 0, 0), -tilt) *
          markingToScreen(shape, marking))
      ..normalize();
