import 'package:vector_math/vector_math_64.dart';

import 'body.dart';

/// One point of a [Manifold].
class ContactPoint {
  ContactPoint({
    required this.point,
    required this.separation,
    required this.featureId,
  });

  /// World-space position on the surface of body B.
  final Vector3 point;

  /// Signed gap along the manifold normal. Negative means overlapping.
  final double separation;

  /// Stable identifier for this point across steps — the vertex or clip index
  /// that produced it. Warm starting matches on it, so a wobbly id costs
  /// exactly the resting stability warm starting exists to buy.
  final int featureId;

  // Accumulated impulses. Carried between steps by the warm-start cache.
  double normalImpulse = 0.0;
  double tangentImpulse1 = 0.0;
  double tangentImpulse2 = 0.0;

  // Per-step scratch, filled by the solver's prepare pass.
  Vector3 ra = Vector3.zero();
  Vector3 rb = Vector3.zero();
  double normalMass = 0.0;
  double tangent1Mass = 0.0;
  double tangent2Mass = 0.0;
  double velocityTarget = 0.0;

  /// Approach speed along the normal as the step began, before any impulse.
  ///
  /// This is what restitution is computed from, and it has to be recorded
  /// rather than read back later: a die caught by a speculative contact has
  /// most of its approach taken off it by the non-penetration constraint before
  /// it ever touches, and bouncing off what is left is not bouncing at all.
  double approachSpeed = 0.0;

  /// The largest normal impulse this point carried during the step. Zero means
  /// the contact was speculative and never actually pushed, so there is nothing
  /// for restitution to act on.
  double maxNormalImpulse = 0.0;
}

/// A set of contact points sharing one normal.
class Manifold {
  Manifold({
    required this.a,
    required this.b,
    required this.normal,
    required this.points,
    required this.restitution,
    required this.friction,
    required this.key,
  }) {
    // A deterministic tangent basis. It has to be a pure function of [normal],
    // because warm-started friction impulses are stored in tangent coordinates
    // and a basis that spins frame to frame would replay last frame's friction
    // sideways.
    final Vector3 reference =
        normal.x.abs() < 0.57735 ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
    tangent1 = normal.cross(reference)..normalize();
    tangent2 = normal.cross(tangent1);
  }

  /// The dynamic body. Pushing it along `+normal` separates the pair.
  final RigidBody a;

  /// The other body, or null when A is resting on a static wall.
  final RigidBody? b;

  final Vector3 normal;
  final List<ContactPoint> points;
  final double restitution;
  final double friction;

  /// Identifies the pair (or body/wall) so impulses find their way back next
  /// step. Combined with [ContactPoint.featureId] to key the cache.
  final int key;

  late final Vector3 tangent1;
  late final Vector3 tangent2;
}
