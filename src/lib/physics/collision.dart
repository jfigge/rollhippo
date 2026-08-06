import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'body.dart';
import 'contact.dart';

/// A static, inward-facing plane — one of the six sides of the tray.
///
/// A point is inside the tray when `dot(normal, p) >= offset`.
class Wall {
  const Wall({
    required this.normal,
    required this.offset,
    required this.restitution,
    required this.friction,
  });

  final Vector3 normal;
  final double offset;
  final double restitution;
  final double friction;
}

/// Materials combine geometrically, which is what Bullet and PhysX both do:
/// a bouncy die on a dead wall lands somewhere sensible in between.
double _mix(double x, double y) => math.sqrt(x * y);

/// Speculative contact margin.
///
/// Surfaces this far apart are still reported as contacts, and the solver
/// refuses to let them close faster than the gap between them. That buys two
/// separate things:
///
///  * a resting die keeps its contacts — and with them its warm-started
///    impulses — instead of flickering between "touching" and "not" every step;
///  * a die approaching a wall is caught *before* it arrives, so the deepest it
///    can ever be found inside one is bounded by how hard the shake is rather
///    than by the substep size.
///
/// Sized to match [PhysicsWorld.maxTravelPerStep]: a die cannot cross more than
/// that in a substep, so it cannot cross this margin unseen.
const double contactMargin = 3e-3;

/// Box against one tray wall.
///
/// Only vertices can be the deepest point of a box against a plane, so walking
/// the eight corners *is* the full manifold — four of them for a face landing,
/// two for an edge, one for a corner, and no special cases to write.
Manifold? collideBoxWall(RigidBox body, Wall wall, int wallIndex) {
  final List<ContactPoint> points = <ContactPoint>[];
  for (int i = 0; i < 8; i++) {
    final Vector3 v = body.coreVertex(i);
    final double separation = wall.normal.dot(v) - wall.offset - body.radius;
    if (separation < contactMargin) {
      points.add(
        ContactPoint(
          point: v - wall.normal * body.radius,
          separation: separation,
          featureId: i,
        ),
      );
    }
  }
  if (points.isEmpty) return null;

  // A box cannot rest on more than four corners; anything beyond that is a deep
  // overlap, and the four deepest points are the ones worth solving.
  if (points.length > 4) {
    points.sort(
      (ContactPoint x, ContactPoint y) => x.separation.compareTo(y.separation),
    );
    points.length = 4;
  }

  return Manifold(
    a: body,
    b: null,
    normal: wall.normal,
    points: points,
    restitution: _mix(body.restitution, wall.restitution),
    friction: _mix(body.friction, wall.friction),
    key: wallIndex,
  );
}

/// One candidate separating axis and what it told us.
class _Axis {
  _Axis(this.direction, this.separation, this.kind, this.i, this.j);

  /// Unit, oriented to point from A towards B.
  final Vector3 direction;
  final double separation;

  /// 0 = a face of A, 1 = a face of B, 2 = an edge pair.
  final int kind;
  final int i;
  final int j;
}

/// Half-width of [box]'s core projected onto a world-space unit [axis].
double _project(RigidBox box, Vector3 axis) =>
    box.core.x * axis.dot(box.axis(0)).abs() +
    box.core.y * axis.dot(box.axis(1)).abs() +
    box.core.z * axis.dot(box.axis(2)).abs();

_Axis? _test(RigidBox a, RigidBox b, Vector3 axis, int kind, int i, int j) {
  final double length = axis.length;
  // Near-parallel edge pairs produce a degenerate cross product. Their axis is
  // already covered by one of the six face axes, so dropping them loses nothing.
  if (length < 1e-8) return null;
  final Vector3 n = axis / length;
  final double centres = n.dot(b.position - a.position);
  final double separation = centres.abs() - (_project(a, n) + _project(b, n));
  return _Axis(centres < 0 ? -n : n, separation, kind, i, j);
}

/// Die against die.
///
/// Separating-axis test over the usual fifteen candidates, then a manifold from
/// whichever axis is least separated: face cases get reference/incident face
/// clipping, edge cases get the closest points of the two edges.
Manifold? collideBoxes(RigidBox a, RigidBox b, int key) {
  _Axis? best;
  _Axis? bestFace;

  void consider(_Axis? axis) {
    if (axis == null) return;
    if (best == null || axis.separation > best!.separation) best = axis;
    if (axis.kind != 2 &&
        (bestFace == null || axis.separation > bestFace!.separation)) {
      bestFace = axis;
    }
  }

  for (int i = 0; i < 3; i++) {
    consider(_test(a, b, a.axis(i), 0, i, -1));
  }
  for (int j = 0; j < 3; j++) {
    consider(_test(a, b, b.axis(j), 1, -1, j));
  }
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      consider(_test(a, b, a.axis(i).cross(b.axis(j)), 2, i, j));
    }
  }

  final _Axis? winner = best;
  if (winner == null) return null;

  final double skin = a.radius + b.radius;
  if (winner.separation > skin + contactMargin) return null;

  // Face and edge axes are often within a hair of each other when two dice
  // meet squarely. Left alone the winner flips between them frame to frame and
  // the manifold changes shape underneath the warm-start cache, which reads as
  // a buzz. Faces win ties by 0.1 mm.
  _Axis axis = winner;
  if (axis.kind == 2 &&
      bestFace != null &&
      axis.separation < bestFace!.separation + 1e-4) {
    axis = bestFace!;
  }

  final double restitution = _mix(a.restitution, b.restitution);
  final double friction = _mix(a.friction, b.friction);

  if (axis.kind == 2) {
    final ContactPoint? point = _edgeContact(a, b, axis, skin);
    if (point == null) return null;
    return Manifold(
      a: a,
      b: b,
      // [axis] runs A towards B; pushing A the other way is what separates them.
      normal: -axis.direction,
      points: <ContactPoint>[point],
      restitution: restitution,
      friction: friction,
      key: key,
    );
  }

  final bool referenceIsA = axis.kind == 0;
  final RigidBox reference = referenceIsA ? a : b;
  final RigidBox incident = referenceIsA ? b : a;
  // Outward normal of the reference face, pointing at the incident box.
  final Vector3 referenceNormal =
      referenceIsA ? axis.direction : -axis.direction;
  final int referenceAxis = referenceIsA ? axis.i : axis.j;

  final List<ContactPoint> points = _clipFaces(
    reference,
    incident,
    referenceNormal,
    referenceAxis,
  );
  if (points.isEmpty) return null;

  return Manifold(
    a: a,
    b: b,
    normal: referenceIsA ? -referenceNormal : referenceNormal,
    points: points,
    restitution: restitution,
    friction: friction,
    key: key,
  );
}

/// A point being carried through the clipper, with the feature id it keeps.
class _Clip {
  _Clip(this.point, this.id);
  final Vector3 point;
  final int id;
}

List<ContactPoint> _clipFaces(
  RigidBox reference,
  RigidBox incident,
  Vector3 referenceNormal,
  int referenceAxis,
) {
  // The incident face is the one facing most squarely back at the reference.
  int incidentAxis = 0;
  double incidentSign = 1.0;
  double most = double.infinity;
  for (int k = 0; k < 3; k++) {
    final double d = incident.axis(k).dot(referenceNormal);
    if (d < most) {
      most = d;
      incidentAxis = k;
      incidentSign = 1.0;
    }
    if (-d < most) {
      most = -d;
      incidentAxis = k;
      incidentSign = -1.0;
    }
  }

  final int u = (incidentAxis + 1) % 3;
  final int v = (incidentAxis + 2) % 3;
  final Vector3 faceCentre =
      incident.position +
      incident.axis(incidentAxis) *
          (incidentSign * incident.core[incidentAxis]);
  final Vector3 uEdge = incident.axis(u) * incident.core[u];
  final Vector3 vEdge = incident.axis(v) * incident.core[v];

  List<_Clip> polygon = <_Clip>[
    _Clip(faceCentre + uEdge + vEdge, 0),
    _Clip(faceCentre - uEdge + vEdge, 1),
    _Clip(faceCentre - uEdge - vEdge, 2),
    _Clip(faceCentre + uEdge - vEdge, 3),
  ];

  // Trim to the reference face's footprint, one side plane at a time.
  for (int k = 0; k < 3; k++) {
    if (k == referenceAxis) continue;
    for (final double sign in <double>[1.0, -1.0]) {
      final Vector3 planeNormal = reference.axis(k) * sign;
      final double limit = reference.core[k];
      polygon = _clipToPlane(polygon, reference.position, planeNormal, limit);
      if (polygon.isEmpty) return const <ContactPoint>[];
    }
  }

  final Vector3 planePoint =
      reference.position + referenceNormal * reference.core[referenceAxis];

  final List<ContactPoint> points = <ContactPoint>[];
  for (final _Clip clip in polygon) {
    final double gap = (clip.point - planePoint).dot(referenceNormal);
    final double separation = gap - reference.radius - incident.radius;
    if (separation >= contactMargin) continue;
    points.add(
      ContactPoint(
        // Sit the contact on the incident body's rounded surface.
        point: clip.point - referenceNormal * incident.radius,
        separation: separation,
        featureId: clip.id,
      ),
    );
  }

  if (points.length > 4) {
    points.sort(
      (ContactPoint x, ContactPoint y) => x.separation.compareTo(y.separation),
    );
    points.length = 4;
  }
  return points;
}

/// Sutherland–Hodgman against `dot(p - origin, normal) <= limit`.
List<_Clip> _clipToPlane(
  List<_Clip> polygon,
  Vector3 origin,
  Vector3 normal,
  double limit,
) {
  final List<_Clip> out = <_Clip>[];
  for (int i = 0; i < polygon.length; i++) {
    final _Clip current = polygon[i];
    final _Clip next = polygon[(i + 1) % polygon.length];
    final double dc = (current.point - origin).dot(normal) - limit;
    final double dn = (next.point - origin).dot(normal) - limit;

    if (dc <= 0) out.add(current);
    if ((dc > 0) != (dn > 0)) {
      final double t = dc / (dc - dn);
      // A point born on an edge inherits the id of the vertex it runs towards,
      // offset so it can never be confused with an original corner.
      out.add(
        _Clip(current.point + (next.point - current.point) * t, 4 + next.id),
      );
    }
  }
  return out;
}

/// Closest points of the two support edges named by an edge-edge axis.
ContactPoint? _edgeContact(RigidBox a, RigidBox b, _Axis axis, double skin) {
  final Vector3 n = axis.direction;

  // Walk out from each centre along the axes the edge does *not* run along,
  // taking whichever sign faces the other box.
  Vector3 support(RigidBox box, int along, double towards) {
    Vector3 p = box.position.clone();
    for (int k = 0; k < 3; k++) {
      if (k == along) continue;
      final Vector3 ax = box.axis(k);
      final double side = ax.dot(n) * towards;
      p += ax * (side >= 0 ? box.core[k] : -box.core[k]);
    }
    return p;
  }

  final Vector3 pa = support(a, axis.i, 1.0);
  final Vector3 pb = support(b, axis.j, -1.0);
  final Vector3 da = a.axis(axis.i);
  final Vector3 db = b.axis(axis.j);
  final double ha = a.core[axis.i];
  final double hb = b.core[axis.j];

  // Standard closest-point-between-two-segments, clamped to each half length.
  final Vector3 r = pa - pb;
  final double f = db.dot(r);
  final double c = da.dot(r);
  final double bDot = da.dot(db);
  final double denominator = 1.0 - bDot * bDot;
  double ta;
  if (denominator.abs() < 1e-8) {
    ta = 0.0;
  } else {
    ta = (bDot * f - c) / denominator;
  }
  ta = ta.clamp(-ha, ha);
  double tb = (bDot * ta + f).clamp(-hb, hb);
  ta = (bDot * tb - c).clamp(-ha, ha);

  final Vector3 closestA = pa + da * ta;
  final Vector3 closestB = pb + db * tb;

  return ContactPoint(
    point: (closestA + closestB) * 0.5,
    separation: axis.separation - skin,
    featureId: 32 + axis.i * 3 + axis.j,
  );
}
