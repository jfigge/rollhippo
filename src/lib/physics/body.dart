import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// A dynamic rigid box — in this app, one die.
///
/// Dice are modelled as *rounded* boxes. [halfExtents] is the true outer half
/// size and [radius] is the corner bevel; collision runs against the shrunken
/// [core] box and then adds [radius] back as a contact margin, which is exactly
/// the Minkowski sum of a box and a sphere.
///
/// That one detail is most of why these dice tumble instead of clunking. A
/// sharp-cornered cube landing on an edge pivots about a mathematical line and
/// stalls there; a bevelled one rolls continuously over the round of the edge
/// and carries on to the next face. Real dice are bevelled for the same reason.
class RigidBox {
  RigidBox({
    required this.halfExtents,
    required this.mass,
    this.radius = 0.0,
    this.restitution = 0.2,
    this.friction = 0.5,
    Vector3? position,
    Quaternion? orientation,
  }) : position = position ?? Vector3.zero(),
       orientation = (orientation ?? Quaternion.identity())..normalize() {
    core = Vector3(
      math.max(halfExtents.x - radius, 1e-9),
      math.max(halfExtents.y - radius, 1e-9),
      math.max(halfExtents.z - radius, 1e-9),
    );
    invMass = mass > 0 ? 1.0 / mass : 0.0;

    // Solid cuboid about its centre. The bevel is ignored here: at a 1.5 mm
    // radius on a 16 mm die it shifts the inertia by under 2%, and a die you
    // can feel that difference in is a loaded die.
    final double m12 = mass / 12.0;
    final double w = 2 * halfExtents.x;
    final double h = 2 * halfExtents.y;
    final double d = 2 * halfExtents.z;
    invInertiaLocal = Vector3(
      1.0 / (m12 * (h * h + d * d)),
      1.0 / (m12 * (w * w + d * d)),
      1.0 / (m12 * (w * w + h * h)),
    );
    syncDerived();
  }

  /// True outer half size, bevel included.
  final Vector3 halfExtents;
  final double mass;
  final double radius;
  final double restitution;
  final double friction;

  /// `halfExtents - radius` — the box collision actually runs against.
  late final Vector3 core;
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

  bool sleeping = false;

  /// Recomputes the rotation matrix and the world-space inverse inertia.
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

  /// The eight corners of the [core] box in world space.
  ///
  /// Corner `i` takes its sign on each axis from bit `i` — bit 0 is x, bit 1 is
  /// y, bit 2 is z. Collision code leans on that being stable frame to frame,
  /// because the index doubles as the contact's feature id for warm starting.
  List<Vector3> coreVertices() => List<Vector3>.generate(8, coreVertex);

  Vector3 coreVertex(int i) =>
      position +
      rotation.transformed(
        Vector3(
          (i & 1) == 0 ? -core.x : core.x,
          (i & 2) == 0 ? -core.y : core.y,
          (i & 4) == 0 ? -core.z : core.z,
        ),
      );

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
