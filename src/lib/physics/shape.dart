import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// One flat face of a [ConvexShape].
class ConvexFace {
  ConvexFace({
    required this.normal,
    required this.vertices,
    required this.centre,
    required this.inradius,
    required this.neighbours,
  });

  /// Unit outward normal, in the shape's own frame.
  final Vector3 normal;

  /// Indices into [ConvexShape.vertices], anticlockwise seen from outside.
  final List<int> vertices;

  /// Centroid of the polygon.
  final Vector3 centre;

  /// Shortest distance from [centre] to an edge — the largest circle a numeral
  /// can be printed inside.
  final double inradius;

  /// `neighbours[k]` is the face across the edge `vertices[k] → vertices[k+1]`.
  /// A D4 prints its numbers along its edges, and this is how it knows which.
  final List<int> neighbours;

  /// The number printed on this face. Filled in once the whole shape exists,
  /// because the value of a face is decided by which face is opposite it.
  int value = 0;
}

/// A set of parallel edges, and the direction they run in.
///
/// Separating-axis tests need one axis per *direction*, not one per edge — a
/// cube has twelve edges and three directions — but once a direction wins, the
/// contact is between two specific edges, so both are kept.
class EdgeGroup {
  EdgeGroup(this.direction) : ends = <int>[];

  /// Unit, sign arbitrary.
  final Vector3 direction;

  /// Flat list of vertex-index pairs: edge `n` runs `ends[2n] → ends[2n+1]`.
  final List<int> ends;

  int get length => ends.length ~/ 2;
}

/// A convex polyhedron with rounded edges — in this app, one die.
///
/// Dice are modelled as a polyhedron inflated by [bevel]: collision runs
/// against the shrunken [coreVertices] and then adds [bevel] back as a contact
/// margin, which is exactly the Minkowski sum of the polyhedron and a sphere.
///
/// That one detail is most of why these dice tumble instead of clunking. A
/// sharp-cornered solid landing on an edge pivots about a mathematical line and
/// stalls there; a bevelled one rolls continuously over the round of the edge
/// and carries on to the next face. Real dice are bevelled for the same reason.
///
/// Every shape here is *isohedral* — every face is the same distance [inradius]
/// from the centre — which is true of all six standard dice and is what lets
/// the bevel be a single uniform shrink rather than a per-face plane offset.
class ConvexShape {
  ConvexShape._({
    required this.vertices,
    required this.faces,
    required this.edges,
    required this.inradius,
    required this.circumradius,
    required this.volume,
    required this.inertiaPerMass,
    required this.bevel,
    required this.readsDownFace,
    required this.usesPips,
  }) : coreScale = (inradius - bevel) / inradius,
       coreInradius = inradius - bevel,
       coreVertices = <Vector3>[
         for (final Vector3 v in vertices) v * ((inradius - bevel) / inradius),
       ];

  /// The outer hull, in the shape's own frame, centred on its centre of mass.
  final List<Vector3> vertices;
  final List<ConvexFace> faces;
  final List<EdgeGroup> edges;

  /// Centre to face plane. The same for every face; see the class comment.
  final double inradius;

  /// Centre to the furthest vertex.
  final double circumradius;

  final double volume;

  /// Diagonal of the inertia tensor divided by mass, in the shape's own frame.
  ///
  /// Every standard die is symmetric enough that its inertia tensor is diagonal
  /// in the frame the shape is defined in — isotropic for the five Platonic
  /// solids, and diagonal about the axis of symmetry for the D10.
  final Vector3 inertiaPerMass;

  final double bevel;

  /// True for the D4, which is read off the face it is *resting* on: a
  /// tetrahedron at rest has a vertex pointing up, not a face.
  final bool readsDownFace;

  /// True for the D6, and only the D6 — the one die that is printed with pips
  /// rather than numerals.
  final bool usesPips;

  /// `(inradius - bevel) / inradius` — the shape collision actually runs
  /// against, before the bevel is added back as a margin.
  final double coreScale;
  final double coreInradius;
  final List<Vector3> coreVertices;

  int get sides => faces.length;

  /// Builds a shape from its vertices alone.
  ///
  /// The faces are *found* rather than listed: every plane through three
  /// vertices that has all the others on one side of it is a face. That is
  /// O(n³) at n ≤ 20 vertices and runs once per die kind, and it is the
  /// difference between transcribing sixty pentagon indices by hand and not.
  ///
  /// [valueFor] names the number on a face given its outward normal. Leave it
  /// null and the faces are numbered 1…n with opposite faces summing to n+1,
  /// which is what a real die does and what makes it fair to read.
  factory ConvexShape.fromVertices(
    List<Vector3> points, {
    required double circumradius,
    required double bevelFraction,
    bool readsDownFace = false,
    bool usesPips = false,
    int Function(Vector3 normal)? valueFor,
  }) {
    // Scale to the requested size first, so every tolerance below is in metres
    // and means the same thing for every shape.
    double longest = 0;
    for (final Vector3 p in points) {
      longest = math.max(longest, p.length);
    }
    final double k = circumradius / longest;
    final List<Vector3> vertices = <Vector3>[
      for (final Vector3 p in points) p * k,
    ];

    final List<List<int>> polygons = _findFaces(vertices, circumradius);
    final _MassProperties mass = _massProperties(vertices, polygons);

    // Everything below assumes the centre of mass is the origin — the inertia
    // is taken about it, and the bevel is a shrink towards it.
    for (final Vector3 v in vertices) {
      v.sub(mass.centre);
    }

    final List<ConvexFace> faces = <ConvexFace>[];
    double inradius = double.infinity;
    for (final List<int> polygon in polygons) {
      final Vector3 a = vertices[polygon[0]];
      final Vector3 b = vertices[polygon[1]];
      final Vector3 c = vertices[polygon[2]];
      final Vector3 normal = (b - a).cross(c - a)..normalize();
      final double offset = normal.dot(a);
      inradius = math.min(inradius, offset);

      final Vector3 centre = Vector3.zero();
      for (final int i in polygon) {
        centre.add(vertices[i]);
      }
      centre.scale(1.0 / polygon.length);

      double faceInradius = double.infinity;
      for (int e = 0; e < polygon.length; e++) {
        final Vector3 p = vertices[polygon[e]];
        final Vector3 q = vertices[polygon[(e + 1) % polygon.length]];
        final Vector3 along = (q - p)..normalize();
        final Vector3 toCentre = centre - p;
        faceInradius = math.min(
          faceInradius,
          (toCentre - along * along.dot(toCentre)).length,
        );
      }

      faces.add(
        ConvexFace(
          normal: normal,
          vertices: polygon,
          centre: centre,
          inradius: faceInradius,
          neighbours: List<int>.filled(polygon.length, -1),
        ),
      );
    }

    _linkNeighbours(faces);
    _numberFaces(faces, valueFor);

    return ConvexShape._(
      vertices: vertices,
      faces: faces,
      edges: _groupEdges(vertices, faces),
      inradius: inradius,
      circumradius: circumradius,
      volume: mass.volume,
      inertiaPerMass: mass.inertiaPerMass,
      bevel: inradius * bevelFraction,
      readsDownFace: readsDownFace,
      usesPips: usesPips,
    );
  }
}

/// Every plane through three vertices with all the rest behind it.
List<List<int>> _findFaces(List<Vector3> vertices, double scale) {
  // Loose enough to gather every vertex of a face onto its plane despite the
  // rounding in a cross product, tight enough that two genuinely different
  // faces are never confused. Dice are not near-degenerate solids; there is a
  // lot of room between those two.
  final double tolerance = scale * 1e-6;
  final List<Vector3> normals = <Vector3>[];
  final List<List<int>> found = <List<int>>[];
  final int n = vertices.length;

  for (int i = 0; i < n; i++) {
    for (int j = i + 1; j < n; j++) {
      for (int k = j + 1; k < n; k++) {
        Vector3 normal = (vertices[j] - vertices[i]).cross(
          vertices[k] - vertices[i],
        );
        if (normal.length < tolerance) continue;
        normal = normal.normalized();
        double offset = normal.dot(vertices[i]);
        if (offset.abs() < tolerance) continue; // A plane through the centre.
        if (offset < 0) {
          normal = -normal;
          offset = -offset;
        }

        // Deduped by direction rather than by a rounded key: two triples of
        // the same face agree to fifteen digits, and any hash fine enough to
        // separate real faces is fine enough to split one in two at a rounding
        // boundary.
        bool already = false;
        for (final Vector3 seen in normals) {
          if (seen.dot(normal) > 1 - 1e-9) {
            already = true;
            break;
          }
        }
        if (already) continue;

        final List<int> on = <int>[];
        bool outside = false;
        for (int v = 0; v < n; v++) {
          final double d = normal.dot(vertices[v]) - offset;
          if (d > tolerance) {
            outside = true;
            break;
          }
          if (d > -tolerance) on.add(v);
        }
        if (outside || on.length < 3) continue;

        normals.add(normal);
        found.add(_sortAnticlockwise(vertices, on, normal));
      }
    }
  }
  return found;
}

/// Orders the vertices of one face anticlockwise as seen from outside it.
List<int> _sortAnticlockwise(
  List<Vector3> vertices,
  List<int> face,
  Vector3 normal,
) {
  final Vector3 centre = Vector3.zero();
  for (final int i in face) {
    centre.add(vertices[i]);
  }
  centre.scale(1.0 / face.length);

  final Vector3 u = (vertices[face[0]] - centre)..normalize();
  final Vector3 v = normal.cross(u);
  double angle(int i) {
    final Vector3 d = vertices[i] - centre;
    return math.atan2(v.dot(d), u.dot(d));
  }

  final List<int> sorted = List<int>.of(face)
    ..sort((int a, int b) => angle(a).compareTo(angle(b)));
  return sorted;
}

/// Fills in which face lies across each edge.
void _linkNeighbours(List<ConvexFace> faces) {
  final Map<int, int> edgeOwner = <int, int>{};
  int key(int a, int b) => a < b ? a * 1024 + b : b * 1024 + a;

  for (int f = 0; f < faces.length; f++) {
    final List<int> loop = faces[f].vertices;
    for (int e = 0; e < loop.length; e++) {
      final int id = key(loop[e], loop[(e + 1) % loop.length]);
      final int? other = edgeOwner[id];
      if (other == null) {
        edgeOwner[id] = f;
        continue;
      }
      faces[f].neighbours[e] = other;
      final List<int> otherLoop = faces[other].vertices;
      for (int g = 0; g < otherLoop.length; g++) {
        if (key(otherLoop[g], otherLoop[(g + 1) % otherLoop.length]) == id) {
          faces[other].neighbours[g] = f;
          break;
        }
      }
    }
  }
}

/// Numbers the faces 1…n, opposite faces summing to n+1 where there *is* an
/// opposite face. A tetrahedron has none, so it simply counts.
void _numberFaces(List<ConvexFace> faces, int Function(Vector3)? valueFor) {
  if (valueFor != null) {
    for (final ConvexFace face in faces) {
      face.value = valueFor(face.normal);
    }
    return;
  }

  final int n = faces.length;
  int next = 1;
  for (int i = 0; i < n; i++) {
    if (faces[i].value != 0) continue;
    int opposite = -1;
    for (int j = i + 1; j < n; j++) {
      if (faces[j].value == 0 &&
          faces[j].normal.dot(faces[i].normal) < -0.999) {
        opposite = j;
        break;
      }
    }
    faces[i].value = next;
    if (opposite >= 0) faces[opposite].value = n + 1 - next;
    next++;
  }
}

/// Collects the edges of every face and groups them by direction.
List<EdgeGroup> _groupEdges(List<Vector3> vertices, List<ConvexFace> faces) {
  final List<EdgeGroup> groups = <EdgeGroup>[];
  final Set<int> seen = <int>{};

  for (final ConvexFace face in faces) {
    final List<int> loop = face.vertices;
    for (int e = 0; e < loop.length; e++) {
      final int a = loop[e];
      final int b = loop[(e + 1) % loop.length];
      final int id = a < b ? a * 1024 + b : b * 1024 + a;
      if (!seen.add(id)) continue;

      final Vector3 direction = (vertices[b] - vertices[a])..normalize();
      EdgeGroup? group;
      for (final EdgeGroup candidate in groups) {
        if (candidate.direction.dot(direction).abs() > 1 - 1e-9) {
          group = candidate;
          break;
        }
      }
      if (group == null) {
        group = EdgeGroup(direction);
        groups.add(group);
      }
      group.ends.addAll(<int>[a, b]);
    }
  }
  return groups;
}

class _MassProperties {
  _MassProperties(this.volume, this.centre, this.inertiaPerMass);
  final double volume;
  final Vector3 centre;
  final Vector3 inertiaPerMass;
}

/// Volume, centroid and inertia of a closed polyhedron, by decomposing it into
/// tetrahedra with a common apex at the origin.
///
/// Doing this rather than looking up a formula per solid is what makes a D10
/// possible at all: a pentagonal trapezohedron's inertia is not in any table,
/// and a die whose inertia is wrong is a loaded die.
_MassProperties _massProperties(List<Vector3> vertices, List<List<int>> faces) {
  double volume = 0;
  final Vector3 centroid = Vector3.zero();
  // Second moments ∫x⊗x dV. Only the diagonal is kept: every die here is
  // symmetric enough that its own frame is a principal frame, and
  // [offDiagonalInertia] is how that claim is held to account.
  double cxx = 0, cyy = 0, czz = 0;

  for (final List<int> face in faces) {
    for (int t = 1; t + 1 < face.length; t++) {
      final Vector3 a = vertices[face[0]];
      final Vector3 b = vertices[face[t]];
      final Vector3 c = vertices[face[t + 1]];

      final double det = a.dot(b.cross(c));
      volume += det / 6.0;
      centroid.addScaled(a + b + c, det / 24.0);

      // ∫x⊗x over the tetrahedron (0, a, b, c) is
      // (det/120)·(a⊗a + b⊗b + c⊗c + s⊗s) with s = a+b+c.
      final Vector3 s = a + b + c;
      final double w = det / 120.0;
      cxx += w * (a.x * a.x + b.x * b.x + c.x * c.x + s.x * s.x);
      cyy += w * (a.y * a.y + b.y * b.y + c.y * c.y + s.y * s.y);
      czz += w * (a.z * a.z + b.z * b.z + c.z * c.z + s.z * s.z);
    }
  }

  centroid.scale(1.0 / volume);

  // Shift the second moments onto the centre of mass, then I = tr(C)·1 − C.
  cxx -= volume * centroid.x * centroid.x;
  cyy -= volume * centroid.y * centroid.y;
  czz -= volume * centroid.z * centroid.z;

  return _MassProperties(
    volume,
    centroid,
    Vector3(cyy + czz, cxx + czz, cxx + cyy) / volume,
  );
}

/// How far the products of inertia are from zero, relative to the diagonal.
///
/// [ConvexShape.inertiaPerMass] keeps only the diagonal, which is exact when
/// the shape's own frame is a principal frame and silently wrong when it is
/// not. Exposed so a test can hold every die to that.
double offDiagonalInertia(ConvexShape shape) {
  final List<List<int>> polygons = <List<int>>[
    for (final ConvexFace f in shape.faces) f.vertices,
  ];
  double cxy = 0, cxz = 0, cyz = 0, scale = 0;
  for (final List<int> face in polygons) {
    for (int t = 1; t + 1 < face.length; t++) {
      final Vector3 a = shape.vertices[face[0]];
      final Vector3 b = shape.vertices[face[t]];
      final Vector3 c = shape.vertices[face[t + 1]];
      final double det = a.dot(b.cross(c));
      final Vector3 s = a + b + c;
      final double w = det / 120.0;
      cxy += w * (a.x * a.y + b.x * b.y + c.x * c.y + s.x * s.y);
      cxz += w * (a.x * a.z + b.x * b.z + c.x * c.z + s.x * s.z);
      cyz += w * (a.y * a.z + b.y * b.z + c.y * c.z + s.y * s.z);
      scale += w * (a.x * a.x + b.x * b.x + c.x * c.x + s.x * s.x);
    }
  }
  final double worst = math.max(cxy.abs(), math.max(cxz.abs(), cyz.abs()));
  return worst / scale.abs();
}
