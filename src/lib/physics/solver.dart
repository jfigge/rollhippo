import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'body.dart';
import 'contact.dart';

/// Impulses carried from one step to the next, keyed by manifold and feature.
///
/// Warm starting is the difference between dice that settle and dice that
/// simmer. Starting each step from last step's answer means the solver begins
/// a hair from the solution instead of rebuilding a resting stack's support
/// from zero in a fixed iteration budget.
class ImpulseCache {
  final Map<int, Vector3> _previous = <int, Vector3>{};
  final Map<int, Vector3> _current = <int, Vector3>{};

  static int _key(Manifold m, ContactPoint c) => m.key * 64 + c.featureId;

  Vector3? recall(Manifold m, ContactPoint c) => _previous[_key(m, c)];

  void remember(Manifold m, ContactPoint c) {
    _current[_key(m, c)] = Vector3(
      c.normalImpulse,
      c.tangentImpulse1,
      c.tangentImpulse2,
    );
  }

  /// Rolls [_current] into [_previous]. Anything not touched this step is
  /// dropped, so a contact that breaks does not resurrect stale impulses.
  void commit() {
    _previous
      ..clear()
      ..addAll(_current);
    _current.clear();
  }
}

/// Sequential-impulse contact solver.
class Solver {
  Solver({
    this.velocityIterations = 12,
    this.positionIterations = 6,
    this.restitutionIterations = 3,
    this.restitutionThreshold = 0.12,
    this.penetrationSlop = 2e-4,
    this.correctionRate = 0.4,
    this.maxCorrectionSpeed = 2.0,
  });

  final int velocityIterations;
  final int positionIterations;

  /// Passes of the restitution solve. Separate from the main velocity solve
  /// because restitution is applied against the speed the step *started* with,
  /// and mixing that into the non-penetration iterations makes each one bounce
  /// off the last one's answer.
  final int restitutionIterations;

  /// Below this approach speed a contact is treated as resting, not bouncing.
  /// Without it a die at rest micro-bounces on its own restitution forever.
  final double restitutionThreshold;

  /// Overlap left uncorrected, so contacts stay in existence rather than being
  /// pushed apart and re-detected every step.
  final double penetrationSlop;

  final double correctionRate;
  final double maxCorrectionSpeed;

  void solve(List<Manifold> manifolds, double dt, ImpulseCache cache) {
    for (final Manifold m in manifolds) {
      _prepare(m, dt, cache);
    }
    for (int i = 0; i < velocityIterations; i++) {
      for (final Manifold m in manifolds) {
        _solveVelocity(m);
      }
    }
    for (int i = 0; i < restitutionIterations; i++) {
      for (final Manifold m in manifolds) {
        _applyRestitution(m);
      }
    }
    for (int i = 0; i < positionIterations; i++) {
      for (final Manifold m in manifolds) {
        _solvePosition(m, dt);
      }
    }
    for (final Manifold m in manifolds) {
      for (final ContactPoint c in m.points) {
        cache.remember(m, c);
      }
    }
    cache.commit();
  }

  double _effectiveMass(Manifold m, ContactPoint c, Vector3 direction) {
    final RigidBody a = m.a;
    final RigidBody? b = m.b;
    double k = a.invMass + (b?.invMass ?? 0.0);
    final Vector3 ran = c.ra.cross(direction);
    k += a.invInertiaWorld.transformed(ran).cross(c.ra).dot(direction);
    if (b != null) {
      final Vector3 rbn = c.rb.cross(direction);
      k += b.invInertiaWorld.transformed(rbn).cross(c.rb).dot(direction);
    }
    return k > 1e-12 ? 1.0 / k : 0.0;
  }

  Vector3 _relativeVelocity(Manifold m, ContactPoint c) {
    final Vector3 v = m.a.velocityAt(c.ra);
    final RigidBody? b = m.b;
    return b == null ? v : v - b.velocityAt(c.rb);
  }

  void _apply(Manifold m, ContactPoint c, Vector3 impulse) {
    m.a.applyImpulse(impulse, c.ra);
    m.b?.applyImpulse(-impulse, c.rb);
  }

  void _prepare(Manifold m, double dt, ImpulseCache cache) {
    for (final ContactPoint c in m.points) {
      c.ra = c.point - m.a.position;
      c.rb = m.b == null ? Vector3.zero() : c.point - m.b!.position;

      c.normalMass = _effectiveMass(m, c, m.normal);
      c.tangent1Mass = _effectiveMass(m, c, m.tangent1);
      c.tangent2Mass = _effectiveMass(m, c, m.tangent2);

      c.approachSpeed = _relativeVelocity(m, c).dot(m.normal);
      c.maxNormalImpulse = 0.0;

      // Not touching yet? The surfaces may close — but no faster than exactly
      // meeting by the end of the step, which is what stops a fast die from
      // stepping through a wall between two frames.
      //
      // This has to be the target outright rather than a floor under the
      // resting target of zero: a merely *nearby* die held to "no approach" is
      // a die hovering a contact margin above the floor. What it must not also
      // do is *swallow* the approach, which is what [_applyRestitution] is for.
      c.velocityTarget = c.separation > 0 ? -c.separation / dt : 0.0;

      final Vector3? remembered = cache.recall(m, c);
      if (remembered != null) {
        c.normalImpulse = remembered.x;
        c.tangentImpulse1 = remembered.y;
        c.tangentImpulse2 = remembered.z;
        _apply(
          m,
          c,
          m.normal * c.normalImpulse +
              m.tangent1 * c.tangentImpulse1 +
              m.tangent2 * c.tangentImpulse2,
        );
      }
    }
  }

  void _solveVelocity(Manifold m) {
    // Friction before the normal impulse, bounded by the normal impulse the
    // last iteration settled on. Solving it the other way round lets a die
    // slide for one iteration every step, which reads as a die that drifts.
    for (final ContactPoint c in m.points) {
      final Vector3 v = _relativeVelocity(m, c);
      double t1 = c.tangentImpulse1 - v.dot(m.tangent1) * c.tangent1Mass;
      double t2 = c.tangentImpulse2 - v.dot(m.tangent2) * c.tangent2Mass;

      // Clamp the pair to a circle, not each axis to its own box — a square
      // friction cone makes dice slide further on the diagonal than along an
      // axis, and on a tumbling die that asymmetry is visible.
      final double limit = m.friction * c.normalImpulse;
      final double magnitude = math.sqrt(t1 * t1 + t2 * t2);
      if (magnitude > limit && magnitude > 1e-12) {
        final double scale = limit / magnitude;
        t1 *= scale;
        t2 *= scale;
      }

      _apply(
        m,
        c,
        m.tangent1 * (t1 - c.tangentImpulse1) +
            m.tangent2 * (t2 - c.tangentImpulse2),
      );
      c.tangentImpulse1 = t1;
      c.tangentImpulse2 = t2;
    }

    for (final ContactPoint c in m.points) {
      final double vn = _relativeVelocity(m, c).dot(m.normal);
      final double lambda = (c.velocityTarget - vn) * c.normalMass;
      final double total = math.max(c.normalImpulse + lambda, 0.0);
      _apply(m, c, m.normal * (total - c.normalImpulse));
      c.normalImpulse = total;
      c.maxNormalImpulse = math.max(c.maxNormalImpulse, total);
    }
  }

  /// Bounces the contacts that were a real impact, off the speed they arrived
  /// with rather than off whatever is left after non-penetration has had its
  /// way.
  ///
  /// A die falling at two metres a second is caught by a speculative contact a
  /// millimetre out and held to exactly reaching the floor by the end of the
  /// substep. Read its velocity at that moment and it is a hundredth of what it
  /// was, so restitution returns nothing and the die lands dead. Restitution
  /// belongs against [ContactPoint.approachSpeed], which is what it was doing
  /// before anything touched it.
  void _applyRestitution(Manifold m) {
    if (m.restitution <= 0) return;
    for (final ContactPoint c in m.points) {
      // Below the threshold a contact is resting, not bouncing, and restitution
      // there is a die that jitters on the spot forever. A contact that never
      // pushed is one the die is merely near.
      if (c.approachSpeed > -restitutionThreshold) continue;
      if (c.maxNormalImpulse <= 0) continue;

      final double vn = _relativeVelocity(m, c).dot(m.normal);
      final double lambda =
          -(vn + m.restitution * c.approachSpeed) * c.normalMass;
      final double total = math.max(c.normalImpulse + lambda, 0.0);
      _apply(m, c, m.normal * (total - c.normalImpulse));
      c.normalImpulse = total;
    }
  }

  /// Split-impulse pass: pushes overlap out using a shadow velocity that never
  /// reaches the body's real motion, so recovering from a deep overlap cannot
  /// fling a die across the tray.
  void _solvePosition(Manifold m, double dt) {
    for (final ContactPoint c in m.points) {
      final double overlap = -c.separation - penetrationSlop;
      if (overlap <= 0) continue;

      final double target = math.min(
        overlap * correctionRate / dt,
        maxCorrectionSpeed,
      );

      final RigidBody? b = m.b;
      Vector3 v = m.a.pseudoVelocityAt(c.ra);
      if (b != null) v = v - b.pseudoVelocityAt(c.rb);

      final double lambda = (target - v.dot(m.normal)) * c.normalMass;
      if (lambda <= 0) continue;

      final Vector3 impulse = m.normal * lambda;
      m.a.applyPseudoImpulse(impulse, c.ra);
      b?.applyPseudoImpulse(-impulse, c.rb);
    }
  }
}
