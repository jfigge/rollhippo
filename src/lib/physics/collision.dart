import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'body.dart';
import 'contact.dart';
import 'shape.dart';

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

/// The most contact points one manifold is allowed to carry.
///
/// A face landing on a wall touches at most five points — a D12's pentagon —
/// and solving all of them is both cheaper and steadier than picking four of
/// the five, which is a choice that flickers when all five are the same depth.
const int _maxContactPoints = 8;

/// A die against one tray wall.
///
/// Only vertices can be the deepest point of a convex body against a plane, so
/// walking the vertices *is* the full manifold — a polygon's worth for a face
/// landing, two for an edge, one for a corner, and no special cases to write.
Manifold? collideBodyWall(RigidBody body, Wall wall, int wallIndex) {
  final List<ContactPoint> points = <ContactPoint>[];
  final List<Vector3> vertices = body.coreVertices;
  for (int i = 0; i < vertices.length; i++) {
    final Vector3 v = vertices[i];
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
  _keepDeepest(points);

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

/// Trims a manifold to [_maxContactPoints], deepest first.
///
/// The feature id breaks ties, because a die resting flat presents several
/// contacts at identical depth and a sort that reorders them frame to frame
/// costs exactly the warm-start stability the ids exist to buy.
void _keepDeepest(List<ContactPoint> points) {
  if (points.length <= _maxContactPoints) return;
  points.sort((ContactPoint x, ContactPoint y) {
    final int byDepth = x.separation.compareTo(y.separation);
    return byDepth != 0 ? byDepth : x.featureId.compareTo(y.featureId);
  });
  points.length = _maxContactPoints;
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

/// Die against die.
///
/// A separating-axis test over the face normals of both bodies and the cross
/// products of their edge directions — the faces of the Minkowski difference,
/// which is the complete candidate set for two convex polyhedra. Then a
/// manifold from whichever axis is least separated: face cases get
/// reference/incident face clipping, edge cases the closest points of the two
/// edges.
///
/// Face axes are deliberately one-sided. A face normal can only separate on the
/// side it points at; the other side belongs to some other face, and the cases
/// no face covers are exactly the ones the edge products are there for.
Manifold? collideBodies(RigidBody a, RigidBody b, int key) {
  final double skin = a.radius + b.radius;

  _Axis? best;
  _Axis? bestFace;

  for (int f = 0; f < a.faceNormals.length; f++) {
    final Vector3 n = a.faceNormals[f];
    final double separation =
        b.supportMin(n) - (n.dot(a.position) + a.shape.coreInradius) - skin;
    if (separation > contactMargin) return null;
    if (best == null || separation > best.separation) {
      best = _Axis(n, separation, 0, f, -1);
      bestFace = best;
    }
  }

  for (int f = 0; f < b.faceNormals.length; f++) {
    final Vector3 n = b.faceNormals[f];
    final double separation =
        a.supportMin(n) - (n.dot(b.position) + b.shape.coreInradius) - skin;
    if (separation > contactMargin) return null;
    if (best == null || separation > best.separation) {
      // [n] points out of B, so it points from B towards A.
      best = _Axis(-n, separation, 1, -1, f);
      bestFace = best;
    }
  }

  // The edge phase is where the time goes — a D12 against a D20 is fifteen
  // directions against fifteen — so it is written against raw doubles and the
  // bodies' cached world-space vectors. No cross product, no normalisation and
  // no support point allocates.
  final List<Vector3> edgesA = a.edgeDirections;
  final List<Vector3> edgesB = b.edgeDirections;
  final List<Vector3> coreA = a.coreVertices;
  final List<Vector3> coreB = b.coreVertices;
  for (int i = 0; i < edgesA.length; i++) {
    final Vector3 da = edgesA[i];
    for (int j = 0; j < edgesB.length; j++) {
      final Vector3 db = edgesB[j];
      double nx = da.y * db.z - da.z * db.y;
      double ny = da.z * db.x - da.x * db.z;
      double nz = da.x * db.y - da.y * db.x;
      final double length2 = nx * nx + ny * ny + nz * nz;
      // Near-parallel edge pairs give a degenerate axis. Whatever they would
      // have separated on is already covered by one of the face normals, so
      // dropping them loses nothing.
      if (length2 < 1e-16) continue;
      final double inverse = 1.0 / math.sqrt(length2);
      nx *= inverse;
      ny *= inverse;
      nz *= inverse;

      double aMin = double.infinity;
      double aMax = double.negativeInfinity;
      for (int k = 0; k < coreA.length; k++) {
        final Vector3 v = coreA[k];
        final double d = nx * v.x + ny * v.y + nz * v.z;
        if (d < aMin) aMin = d;
        if (d > aMax) aMax = d;
      }
      double bMin = double.infinity;
      double bMax = double.negativeInfinity;
      for (int k = 0; k < coreB.length; k++) {
        final Vector3 v = coreB[k];
        final double d = nx * v.x + ny * v.y + nz * v.z;
        if (d < bMin) bMin = d;
        if (d > bMax) bMax = d;
      }

      final double ahead = bMin - aMax;
      final double behind = aMin - bMax;
      final double separation = math.max(ahead, behind) - skin;
      if (separation > contactMargin) return null;
      if (best == null || separation > best.separation) {
        final double sign = ahead >= behind ? 1.0 : -1.0;
        best = _Axis(
          Vector3(nx * sign, ny * sign, nz * sign),
          separation,
          2,
          i,
          j,
        );
      }
    }
  }

  final _Axis? winner = best;
  if (winner == null) return null;

  // Face and edge axes are often within a hair of each other when two dice meet
  // squarely. Left alone the winner flips between them frame to frame and the
  // manifold changes shape underneath the warm-start cache, which reads as a
  // buzz. Faces win ties by 0.1 mm.
  _Axis axis = winner;
  if (axis.kind == 2 &&
      bestFace != null &&
      axis.separation < bestFace.separation + 1e-4) {
    axis = bestFace;
  }

  final double restitution = _mix(a.restitution, b.restitution);
  final double friction = _mix(a.friction, b.friction);

  if (axis.kind == 2) {
    final ContactPoint? point = _edgeContact(a, b, axis);
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
  final RigidBody reference = referenceIsA ? a : b;
  final RigidBody incident = referenceIsA ? b : a;
  final int referenceFace = referenceIsA ? axis.i : axis.j;
  // Outward normal of the reference face, pointing at the incident body.
  final Vector3 referenceNormal = reference.faceNormal(referenceFace);

  final List<ContactPoint> points = _clipFaces(
    reference,
    incident,
    referenceNormal,
    referenceFace,
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

/// Where each band of [ContactPoint.featureId] begins.
///
/// Three kinds of point come out of this file and they have to be numbered so
/// that no two of them can collide: below [_clippedId] an id is a vertex of
/// the incident face, from there to [_edgeId] it is a point the clipper
/// invented, and from [_edgeId] up it is a pair of edges. The widest die here
/// has twenty vertices and pentagonal faces, so the first two bands are used
/// to 20 and to 41 respectively — the rest is headroom for a shape with more
/// corners than a D12.
///
/// [_edgePitch] is how many edge *directions* the last band allows a die, and
/// so what puts its ceiling at `_edgeId + _edgePitch²` = 1152. A D12 and a D20
/// have fifteen apiece, which is the most of any die in the set.
/// `physics_test.dart` holds every kind under it, because a shape that
/// overran it would not fail — it would quietly hand its contacts somebody
/// else's ids.
const int _clippedId = 32;
const int _edgeId = 128;
const int _edgePitch = 32;

List<ContactPoint> _clipFaces(
  RigidBody reference,
  RigidBody incident,
  Vector3 referenceNormal,
  int referenceFace,
) {
  // The incident face is the one facing most squarely back at the reference.
  int incidentFace = 0;
  double most = double.infinity;
  for (int f = 0; f < incident.faceNormals.length; f++) {
    final double d = incident.faceNormals[f].dot(referenceNormal);
    if (d < most) {
      most = d;
      incidentFace = f;
    }
  }

  final List<int> incidentLoop = incident.shape.faces[incidentFace].vertices;
  List<_Clip> polygon = <_Clip>[
    for (int i = 0; i < incidentLoop.length; i++)
      _Clip(incident.coreVertex(incidentLoop[i]), incidentLoop[i]),
  ];

  // Trim to the reference face's footprint, one side plane at a time. Each
  // plane is raised on an edge of the reference polygon and faces outwards.
  final List<int> referenceLoop = reference.shape.faces[referenceFace].vertices;
  for (int e = 0; e < referenceLoop.length; e++) {
    final Vector3 p = reference.coreVertex(referenceLoop[e]);
    final Vector3 q = reference.coreVertex(
      referenceLoop[(e + 1) % referenceLoop.length],
    );
    final Vector3 outward = (q - p).cross(referenceNormal)..normalize();
    polygon = _clipToPlane(polygon, p, outward, e);
    if (polygon.isEmpty) return const <ContactPoint>[];
  }

  final Vector3 planePoint =
      reference.position + referenceNormal * reference.shape.coreInradius;
  final double skin = reference.radius + incident.radius;

  final List<ContactPoint> points = <ContactPoint>[];
  for (final _Clip clip in polygon) {
    final double separation =
        (clip.point - planePoint).dot(referenceNormal) - skin;
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

  _keepDeepest(points);
  return points;
}

/// Sutherland–Hodgman against `dot(p - origin, normal) <= 0`.
List<_Clip> _clipToPlane(
  List<_Clip> polygon,
  Vector3 origin,
  Vector3 normal,
  int planeIndex,
) {
  final List<_Clip> out = <_Clip>[];
  for (int i = 0; i < polygon.length; i++) {
    final _Clip current = polygon[i];
    final _Clip next = polygon[(i + 1) % polygon.length];
    final double dc = (current.point - origin).dot(normal);
    final double dn = (next.point - origin).dot(normal);

    if (dc <= 0) out.add(current);
    if ((dc > 0) != (dn > 0)) {
      final double t = dc / (dc - dn);
      // A point the clipper invented is identified by the edge that made it and
      // which way the boundary was crossed, both of which hold still while the
      // dice are in contact — which is all warm starting asks of an id.
      out.add(
        _Clip(
          current.point + (next.point - current.point) * t,
          _clippedId + planeIndex * 2 + (dc > 0 ? 0 : 1),
        ),
      );
    }
  }
  return out;
}

/// Closest points of the two support edges named by an edge-edge axis.
ContactPoint? _edgeContact(RigidBody a, RigidBody b, _Axis axis) {
  final Vector3 n = axis.direction;

  // The winning axis names a *direction*, and a die has several edges running
  // that way. The one in contact is the one furthest along the axis.
  (Vector3, Vector3)? pick(RigidBody body, EdgeGroup group, double towards) {
    double best = double.negativeInfinity;
    Vector3? from;
    Vector3? to;
    for (int e = 0; e < group.length; e++) {
      final Vector3 p = body.coreVertex(group.ends[e * 2]);
      final Vector3 q = body.coreVertex(group.ends[e * 2 + 1]);
      final double reach = (n.dot(p) + n.dot(q)) * 0.5 * towards;
      if (reach > best) {
        best = reach;
        from = p;
        to = q;
      }
    }
    if (from == null || to == null) return null;
    return (from, to);
  }

  final (Vector3, Vector3)? edgeA = pick(a, a.shape.edges[axis.i], 1.0);
  final (Vector3, Vector3)? edgeB = pick(b, b.shape.edges[axis.j], -1.0);
  if (edgeA == null || edgeB == null) return null;

  final Vector3 pa = edgeA.$1;
  final Vector3 pb = edgeB.$1;
  final Vector3 da = edgeA.$2 - pa;
  final Vector3 db = edgeB.$2 - pb;

  // Standard closest point between two segments, both parametrised 0…1.
  final Vector3 r = pa - pb;
  final double aa = da.dot(da);
  final double bb = db.dot(db);
  final double ab = da.dot(db);
  final double ar = da.dot(r);
  final double br = db.dot(r);
  final double denominator = aa * bb - ab * ab;

  double ta =
      denominator.abs() < 1e-18
          ? 0.0
          : ((ab * br - ar * bb) / denominator).clamp(0.0, 1.0);
  double tb = bb < 1e-18 ? 0.0 : ((ab * ta + br) / bb).clamp(0.0, 1.0);
  ta = aa < 1e-18 ? 0.0 : ((ab * tb - ar) / aa).clamp(0.0, 1.0);

  final Vector3 closestA = pa + da * ta;
  final Vector3 closestB = pb + db * tb;

  // The pair of edge groups names the feature, and the band keeps it clear of
  // every vertex and clipped id. See [_clippedId] for the layout, and
  // [featureIdLimit] for what depends on the whole of it staying inside.
  assert(
    axis.i < _edgePitch && axis.j < _edgePitch,
    'a shape with $_edgePitch or more edge directions overruns the edge band',
  );
  return ContactPoint(
    point: (closestA + closestB) * 0.5,
    separation: axis.separation,
    featureId: _edgeId + axis.i * _edgePitch + axis.j,
  );
}
