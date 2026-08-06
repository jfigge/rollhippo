import 'package:vector_math/vector_math_64.dart';

import 'shape.dart';

/// A dynamic rigid body — in this app, one die.
///
/// The geometry lives in [shape]: a convex polyhedron, rounded by a bevel, with
/// its own inertia and its own numbering. Everything here is the part that
/// moves — position, orientation, and the impulses the solver applies.
///
/// Collision runs against the shape's *core*, the polyhedron shrunk so that its
/// faces sit [radius] inside the real ones, and then adds [radius] back as a
/// contact margin. That is exactly the Minkowski sum of the polyhedron and a
/// sphere, and it is most of why these dice tumble instead of clunking: a
/// sharp-cornered solid landing on an edge pivots about a mathematical line and
/// stalls there, while a bevelled one rolls over the round of the edge onto the
/// next face. Real dice are bevelled for the same reason.
class RigidBody {
  RigidBody({
    required this.shape,
    required this.mass,
    this.restitution = 0.2,
    this.friction = 0.5,
    Vector3? position,
    Quaternion? orientation,
  }) : position = position ?? Vector3.zero(),
       orientation = (orientation ?? Quaternion.identity())..normalize(),
       _worldCore = <Vector3>[
         for (int i = 0; i < shape.coreVertices.length; i++) Vector3.zero(),
       ],
       _worldNormals = <Vector3>[
         for (int i = 0; i < shape.faces.length; i++) Vector3.zero(),
       ],
       _worldEdges = <Vector3>[
         for (int i = 0; i < shape.edges.length; i++) Vector3.zero(),
       ] {
    invMass = mass > 0 ? 1.0 / mass : 0.0;
    final Vector3 inertia = shape.inertiaPerMass * mass;
    invInertiaLocal = Vector3(
      1.0 / inertia.x,
      1.0 / inertia.y,
      1.0 / inertia.z,
    );
    syncDerived();
  }

  final ConvexShape shape;
  final double mass;
  final double restitution;
  final double friction;

  /// The bevel — the contact margin collision adds back onto the core shape.
  double get radius => shape.bevel;

  /// Centre to furthest drawn vertex. What the broad phase and the containment
  /// backstop use to bound a die however it happens to be turned.
  double get circumradius => shape.circumradius;

  late final double invMass;
  late final Vector3 invInertiaLocal;

  Vector3 position;
  Quaternion orientation;
  final Vector3 velocity = Vector3.zero();
  final Vector3 angularVelocity = Vector3.zero();

  /// Split-impulse bookkeeping. Penetration is pushed out with these rather
  /// than with a Baumgarte term on the real velocity, so recovering from an
  /// overlap never injects energy the die then bounces away with.
  final Vector3 pseudoVelocity = Vector3.zero();
  final Vector3 pseudoAngularVelocity = Vector3.zero();

  /// Cached from [orientation] once per step.
  Matrix3 rotation = Matrix3.identity();
  Matrix3 invInertiaWorld = Matrix3.identity();

  /// The core vertices, face normals and edge directions in world space, all
  /// refreshed by [syncDerived].
  ///
  /// Collision walks these many times per step. Two D12s alone put two hundred
  /// and twenty-five candidate axes through the vertex lists, so rotating a
  /// vector inside those loops rather than once at the top of the step is the
  /// difference between a tray of ten dice costing one millisecond a frame and
  /// costing six.
  final List<Vector3> _worldCore;
  final List<Vector3> _worldNormals;
  final List<Vector3> _worldEdges;

  List<Vector3> get coreVertices => _worldCore;

  /// Outward face normals in world space, indexed as [ConvexShape.faces].
  List<Vector3> get faceNormals => _worldNormals;

  /// Edge-group directions in world space, indexed as [ConvexShape.edges].
  List<Vector3> get edgeDirections => _worldEdges;

  bool sleeping = false;

  /// Recomputes the rotation matrix, the world-space inverse inertia and the
  /// world-space core vertices.
  ///
  /// `I⁻¹_world = R · I⁻¹_local · Rᵀ`, which for a diagonal local inertia is
  /// cheap enough to just write out.
  void syncDerived() {
    rotation = orientation.asRotationMatrix();
    final Matrix3 r = rotation;
    final Vector3 d = invInertiaLocal;
    // R · diag(d) scales column i of R by d[i]; multiplying by Rᵀ then gives
    // the symmetric result below.
    final Matrix3 rd = Matrix3(
      r.entry(0, 0) * d.x,
      r.entry(1, 0) * d.x,
      r.entry(2, 0) * d.x,
      r.entry(0, 1) * d.y,
      r.entry(1, 1) * d.y,
      r.entry(2, 1) * d.y,
      r.entry(0, 2) * d.z,
      r.entry(1, 2) * d.z,
      r.entry(2, 2) * d.z,
    );
    invInertiaWorld = rd * r.transposed() as Matrix3;

    final double r00 = r.entry(0, 0), r01 = r.entry(0, 1), r02 = r.entry(0, 2);
    final double r10 = r.entry(1, 0), r11 = r.entry(1, 1), r12 = r.entry(1, 2);
    final double r20 = r.entry(2, 0), r21 = r.entry(2, 1), r22 = r.entry(2, 2);

    void rotate(Vector3 v, Vector3 out) => out.setValues(
      r00 * v.x + r01 * v.y + r02 * v.z,
      r10 * v.x + r11 * v.y + r12 * v.z,
      r20 * v.x + r21 * v.y + r22 * v.z,
    );

    final List<Vector3> local = shape.coreVertices;
    for (int i = 0; i < local.length; i++) {
      rotate(local[i], _worldCore[i]);
      _worldCore[i].add(position);
    }
    for (int i = 0; i < shape.faces.length; i++) {
      rotate(shape.faces[i].normal, _worldNormals[i]);
    }
    for (int i = 0; i < shape.edges.length; i++) {
      rotate(shape.edges[i].direction, _worldEdges[i]);
    }
  }

  /// One core vertex in world space.
  Vector3 coreVertex(int i) => _worldCore[i];

  /// One vertex of the *drawn* hull in world space — the outer shape, bevel
  /// included, which is what the painter wants and collision does not.
  Vector3 outerVertex(int i) =>
      position + rotation.transformed(shape.vertices[i]);

  /// Outward normal of face [i] in world space.
  Vector3 faceNormal(int i) => _worldNormals[i];

  /// Centroid of face [i] in world space.
  Vector3 faceCentre(int i) =>
      position + rotation.transformed(shape.faces[i].centre);

  /// Furthest the core reaches along [n], and the least. Together they are the
  /// interval a separating-axis test projects the body onto.
  double supportMax(Vector3 n) {
    double best = double.negativeInfinity;
    for (int i = 0; i < _worldCore.length; i++) {
      final Vector3 v = _worldCore[i];
      final double d = n.x * v.x + n.y * v.y + n.z * v.z;
      if (d > best) best = d;
    }
    return best;
  }

  double supportMin(Vector3 n) {
    double best = double.infinity;
    for (int i = 0; i < _worldCore.length; i++) {
      final Vector3 v = _worldCore[i];
      final double d = n.x * v.x + n.y * v.y + n.z * v.z;
      if (d < best) best = d;
    }
    return best;
  }

  /// World-space velocity of the material point at offset [r] from the centre.
  Vector3 velocityAt(Vector3 r) => velocity + angularVelocity.cross(r);

  Vector3 pseudoVelocityAt(Vector3 r) =>
      pseudoVelocity + pseudoAngularVelocity.cross(r);

  void applyImpulse(Vector3 impulse, Vector3 r) {
    velocity.addScaled(impulse, invMass);
    angularVelocity.add(invInertiaWorld.transformed(r.cross(impulse)));
  }

  void applyPseudoImpulse(Vector3 impulse, Vector3 r) {
    pseudoVelocity.addScaled(impulse, invMass);
    pseudoAngularVelocity.add(invInertiaWorld.transformed(r.cross(impulse)));
  }

  /// Column [axis] of the rotation matrix — the world direction of a local axis.
  Vector3 axis(int axis) => Vector3(
    rotation.entry(0, axis),
    rotation.entry(1, axis),
    rotation.entry(2, axis),
  );

  /// Advances position and orientation. Velocities are integrated separately,
  /// before the solver runs.
  void integrate(double dt) {
    position.addScaled(velocity, dt);
    position.addScaled(pseudoVelocity, dt);

    // q' = q + ½ dt (ω ⊗ q), the standard first-order quaternion derivative.
    // Both the real and the pseudo angular velocity move the body; only the
    // real one survives into the next step.
    final Vector3 w = angularVelocity + pseudoAngularVelocity;
    final Quaternion q = orientation;
    final double hx = 0.5 * dt * w.x;
    final double hy = 0.5 * dt * w.y;
    final double hz = 0.5 * dt * w.z;
    orientation = Quaternion(
      q.x + hy * q.z - hz * q.y + hx * q.w,
      q.y + hz * q.x - hx * q.z + hy * q.w,
      q.z + hx * q.y - hy * q.x + hz * q.w,
      q.w - hx * q.x - hy * q.y - hz * q.z,
    )..normalize();

    pseudoVelocity.setZero();
    pseudoAngularVelocity.setZero();
    syncDerived();
  }

  void wake() => sleeping = false;

  void sleep() {
    sleeping = true;
    velocity.setZero();
    angularVelocity.setZero();
  }
}
