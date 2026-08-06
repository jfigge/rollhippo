import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'body.dart';
import 'collision.dart';
import 'contact.dart';
import 'solver.dart';

/// The simulation, expressed in the *tray's* frame of reference.
///
/// This is the decision the whole feel rests on. The tray is the phone, and the
/// phone is not an inertial frame — so rather than move the walls around a
/// fixed world, the walls stay put and the physics carries the pseudo-forces
/// that a non-inertial frame implies. Two consequences fall out of that:
///
///  * [gravity] is not a constant. It is the *effective* acceleration field
///    inside the tray, which for a phone is exactly the negated accelerometer
///    reading — one vector that already contains both which way is down and
///    every jolt of a shake, with no threshold, no gesture detector, and no
///    special case where tilting stops and shaking starts.
///  * A phone that is being twisted adds Euler, Coriolis and centrifugal terms,
///    which is what makes a wrist flick roll dice instead of merely sliding
///    them from one end to the other.
class PhysicsWorld {
  PhysicsWorld({required this.walls, Solver? solver})
    : solver = solver ?? Solver();

  final List<Wall> walls;
  final List<RigidBody> bodies = <RigidBody>[];
  final Solver solver;
  final ImpulseCache _cache = ImpulseCache();

  /// Effective acceleration field in the tray frame, m/s². Set this to the
  /// negated accelerometer reading; see the class comment.
  final Vector3 gravity = Vector3(0, -9.81, 0);

  /// The tray's own rotation, from the gyroscope. Drives the frame terms.
  final Vector3 trayAngularVelocity = Vector3.zero();
  final Vector3 trayAngularAcceleration = Vector3.zero();

  /// Scales the rotational pseudo-forces. 0 turns them off, which is a useful
  /// A/B when judging how much of the feel they are actually buying.
  double rotationalEffects = 1.0;

  double linearDamping = 0.08;
  double angularDamping = 0.12;

  /// Backstop against tunnelling if a shake ever produces a silly reading.
  double maxSpeed = 8.0;

  /// Longest distance any point of a die may travel in one substep. The substep
  /// count is chosen from this, so a hard shake automatically buys finer
  /// integration instead of passing a die through a wall.
  double maxTravelPerStep = 0.003;

  double maxStep = 1.0 / 240.0;
  int maxSubsteps = 24;

  // Sleep thresholds. Dice are small and light; these are deliberately tight,
  // because a die that stops a frame too early stops visibly.
  double sleepLinearSpeed = 0.012;
  double sleepAngularSpeed = 0.25;
  double sleepDelay = 0.35;
  double _restTimer = 0.0;

  bool get asleep =>
      bodies.isNotEmpty && bodies.every((RigidBody b) => b.sleeping);

  /// Peak contact speed seen during the last [advance], m/s — the hook a
  /// dice-clack sound or a haptic tick will want.
  double lastImpactSpeed = 0.0;

  void wake() {
    _restTimer = 0.0;
    for (final RigidBody body in bodies) {
      body.wake();
    }
  }

  /// Advances by a display frame's worth of time, in as many fixed substeps as
  /// the fastest die needs.
  void advance(double dt) {
    if (dt <= 0) return;
    lastImpactSpeed = 0.0;
    if (asleep) return;

    // How fast is anything about to move? Corners of a spinning die outrun its
    // centre, and a hard shake adds most of a frame's speed *during* the frame
    // — so both go into the estimate. Sizing substeps off the current centre
    // velocity alone is how a die ends up a wall-thickness inside a wall.
    double fastest = 0.0;
    for (final RigidBody body in bodies) {
      fastest = math.max(
        fastest,
        body.velocity.length + body.angularVelocity.length * body.circumradius,
      );
    }
    fastest += gravity.length * dt;

    double step = maxStep;
    if (fastest > 0) {
      step = math.min(step, maxTravelPerStep / fastest);
    }
    int count = math.max(1, (dt / step).ceil());
    if (count > maxSubsteps) count = maxSubsteps;
    final double h = dt / count;

    for (int i = 0; i < count; i++) {
      _step(h);
    }
  }

  void _step(double h) {
    _integrateVelocities(h);

    final List<Manifold> manifolds = _collide();
    if (manifolds.isNotEmpty) {
      solver.solve(manifolds, h, _cache);
    }

    for (final RigidBody body in bodies) {
      body.integrate(h);
    }

    _containStrays();
    _updateSleep(h);
  }

  void _integrateVelocities(double h) {
    for (final RigidBody body in bodies) {
      if (body.invMass == 0) continue;

      // Effective field at this die: gravity-plus-shake, then the terms that
      // exist only because the tray itself is turning.
      final Vector3 field = gravity.clone();
      if (rotationalEffects > 0 &&
          (trayAngularVelocity.length2 > 0 ||
              trayAngularAcceleration.length2 > 0)) {
        final Vector3 r = body.position;
        final Vector3 w = trayAngularVelocity;
        field
          ..addScaled(trayAngularAcceleration.cross(r), -rotationalEffects)
          ..addScaled(w.cross(body.velocity), -2.0 * rotationalEffects)
          ..addScaled(w.cross(w.cross(r)), -rotationalEffects);
      }
      body.velocity.addScaled(field, h);

      // A die with no torque on it keeps its orientation in the *world*, so in
      // the tray's frame it appears to counter-rotate exactly as fast as the
      // tray turns. This one line is why a wrist flick tumbles the dice rather
      // than sliding them, and it is the single largest difference between
      // this and a tray that just points gravity somewhere new.
      if (rotationalEffects > 0) {
        body.angularVelocity.addScaled(
          trayAngularAcceleration,
          -h * rotationalEffects,
        );
      }

      final double linear = 1.0 / (1.0 + h * linearDamping);
      final double angular = 1.0 / (1.0 + h * angularDamping);
      body.velocity.scale(linear);
      body.angularVelocity.scale(angular);

      final double speed = body.velocity.length;
      if (speed > maxSpeed) body.velocity.scale(maxSpeed / speed);
    }
  }

  List<Manifold> _collide() {
    final List<Manifold> manifolds = <Manifold>[];
    for (int i = 0; i < bodies.length; i++) {
      final RigidBody body = bodies[i];
      for (int w = 0; w < walls.length; w++) {
        final Manifold? m = collideBodyWall(body, walls[w], i * 8 + w);
        if (m != null) {
          manifolds.add(m);
          _noteImpact(m);
        }
      }
    }
    // Bounding spheres first. Ten dice are forty-five pairs, nearly all of them
    // nowhere near each other, and a rejected pair costs one subtraction here
    // against a few hundred dot products in the separating-axis test.
    for (int i = 0; i < bodies.length; i++) {
      final RigidBody a = bodies[i];
      for (int j = i + 1; j < bodies.length; j++) {
        final RigidBody b = bodies[j];
        final double reach = a.circumradius + b.circumradius + contactMargin;
        if ((a.position - b.position).length2 > reach * reach) continue;

        final Manifold? m = collideBodies(a, b, 1000 + i * 16 + j);
        if (m != null) {
          manifolds.add(m);
          _noteImpact(m);
        }
      }
    }
    return manifolds;
  }

  void _noteImpact(Manifold m) {
    for (final ContactPoint c in m.points) {
      if (c.separation > 0) continue;
      final Vector3 ra = c.point - m.a.position;
      Vector3 v = m.a.velocityAt(ra);
      final RigidBody? b = m.b;
      if (b != null) v = v - b.velocityAt(c.point - b.position);
      final double approach = -v.dot(m.normal);
      if (approach > lastImpactSpeed) lastImpactSpeed = approach;
    }
  }

  /// Last line of defence. Interpenetration recovery and a bad sensor frame can
  /// in principle conspire to put a die outside; if that ever happens, put it
  /// back rather than letting it sail off screen.
  void _containStrays() {
    for (final RigidBody body in bodies) {
      // A held die is where it was put, and being put back is still moving.
      if (body.held) continue;
      bool moved = false;
      for (final Wall wall in walls) {
        final double distance = wall.normal.dot(body.position) - wall.offset;
        final double minimum = body.circumradius;
        if (distance < -minimum) {
          body.position.addScaled(wall.normal, -distance);
          moved = true;
        }
      }
      if (moved) {
        body.velocity.scale(0.2);
        body.angularVelocity.scale(0.2);
      }
    }
  }

  void _updateSleep(double h) {
    bool settled = true;
    for (final RigidBody body in bodies) {
      if (body.velocity.length > sleepLinearSpeed ||
          body.angularVelocity.length > sleepAngularSpeed) {
        settled = false;
        break;
      }
    }
    // All or nothing: two dice in a tray are one island, and a die that dozed
    // off under a neighbour that is still moving is a die that gets shoved
    // through a wall.
    if (!settled) {
      _restTimer = 0.0;
      return;
    }
    _restTimer += h;
    if (_restTimer >= sleepDelay) {
      for (final RigidBody body in bodies) {
        body.sleep();
      }
    }
  }
}
