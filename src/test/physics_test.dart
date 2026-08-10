import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/motion/motion.dart';
import 'package:rollhippo/physics/body.dart';
import 'package:rollhippo/physics/collision.dart';
import 'package:rollhippo/physics/contact.dart';
import 'package:rollhippo/physics/solver.dart';
import 'package:rollhippo/physics/world.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:vector_math/vector_math_64.dart';

/// An iPhone-sized tray, in metres.
const double kWidth = 393 / Tuning.logicalPixelsPerMetre;
const double kHeight = 852 / Tuning.logicalPixelsPerMetre;

const DieSpec kD6 = DieSpec(kind: DieKind.d6, colour: kDiceWhite);

RigidBody die({Vector3? at, Quaternion? facing, DieSpec spec = kD6}) =>
    RigidBody(
      shape: spec.shape,
      mass: spec.mass,
      restitution: Tuning.dieRestitution,
      friction: Tuning.dieFriction,
      position: at,
      orientation: facing,
    );

/// Runs [seconds] of simulation at 60 fps.
void run(PhysicsWorld world, double seconds) {
  const double dt = 1 / 60;
  for (int i = 0; i < (seconds / dt).round(); i++) {
    world.advance(dt);
  }
}

void main() {
  group('integration', () {
    test('a die in free fall accelerates at g', () {
      // Walls pushed far away so nothing is touched.
      final PhysicsWorld world = PhysicsWorld(
        walls: trayWalls(width: 100, height: 100, depth: 100),
      );
      world.linearDamping = 0;
      final RigidBody d = die(at: Vector3.zero());
      world.bodies.add(d);

      run(world, 0.5);

      expect(d.velocity.y, closeTo(-9.81 * 0.5, 0.05));
      expect(d.position.y, closeTo(-0.5 * 9.81 * 0.25, 0.01));
    });

    test('angular velocity turns the body the right way', () {
      final RigidBody d = die();
      d.angularVelocity.setValues(0, 0, math.pi / 2); // +90°/s about +z
      for (int i = 0; i < 240; i++) {
        d.integrate(1 / 240);
      }
      // One second later, the body's local +x should be pointing along +y.
      final Vector3 x = d.axis(0);
      expect(x.x, closeTo(0, 1e-3));
      expect(x.y, closeTo(1, 1e-3));
    });
  });

  group('resting', () {
    test('a die dropped flat settles on the floor and sleeps', () {
      final PhysicsWorld world = PhysicsWorld(
        walls: trayWalls(
          width: kWidth,
          height: kHeight,
          depth: Tuning.trayDepth,
        ),
      );
      final RigidBody d = die(
        at: Vector3(0, 0.02, -Tuning.trayDepth / 2),
        facing: Quaternion.identity(),
      );
      world.bodies.add(d);

      run(world, 3.0);

      final double floor = -kHeight / 2;
      expect(
        d.position.y - Tuning.dieSize / 2,
        closeTo(floor, 5e-4),
        reason: 'die should be sitting on the floor, not in it or above it',
      );
      expect(world.asleep, isTrue, reason: 'a settled die must stop');
    });

    test('a settled die does not drift', () {
      final PhysicsWorld world = PhysicsWorld(
        walls: trayWalls(
          width: kWidth,
          height: kHeight,
          depth: Tuning.trayDepth,
        ),
      );
      final RigidBody d = die(
        at: Vector3(0.005, 0.0, -Tuning.trayDepth / 2),
        facing: Quaternion.identity(),
      );
      world.bodies.add(d);
      run(world, 3.0);

      final Vector3 settled = d.position.clone();
      world.wake();
      run(world, 5.0);

      expect(
        (d.position - settled).length,
        lessThan(2e-4),
        reason: 'a die at rest must stay where it landed',
      );
    });

    test('a bounce loses height', () {
      final PhysicsWorld world = PhysicsWorld(
        walls: trayWalls(
          width: kWidth,
          height: kHeight,
          depth: Tuning.trayDepth,
        ),
      );
      final RigidBody d = die(
        at: Vector3(0, 0.04, -Tuning.trayDepth / 2),
        facing: Quaternion.identity(),
      );
      world.bodies.add(d);

      double peak = -1;
      const double dt = 1 / 240;
      bool landed = false;
      for (int i = 0; i < 240 * 2; i++) {
        world.advance(dt);
        final double floor = -kHeight / 2 + Tuning.dieSize / 2;
        if (!landed && d.position.y <= floor + 1e-4) landed = true;
        if (landed) peak = math.max(peak, d.position.y);
      }
      expect(
        peak,
        lessThan(0.04),
        reason: 'restitution below 1 cannot bounce back to the drop height',
      );
      expect(
        peak,
        greaterThan(-kHeight / 2),
        reason: 'it should still bounce at all',
      );
    });
  });

  group('warm starting', () {
    // A manifold with one contact on it, which is all the cache looks at.
    Manifold manifold(int key, int featureId) => Manifold(
      a: die(),
      b: die(),
      normal: Vector3(0, 1, 0),
      points: <ContactPoint>[
        ContactPoint(
          point: Vector3.zero(),
          separation: 0,
          featureId: featureId,
        ),
      ],
      restitution: 0,
      friction: 0,
      key: key,
    );

    test('one contact cannot collect another one\'s impulse', () {
      // The pair that used to share a slot. Manifold 1001 is dice 0 and 1,
      // manifold 1003 is dice 0 and 3 — both of which a tray of four dice
      // produces at once — and at the stride of 64 the first one's edge-pair
      // contact and the second one's face vertex both keyed to 64197.
      final ImpulseCache cache = ImpulseCache();
      final Manifold edge = manifold(1001, 128 + 5);
      final Manifold face = manifold(1003, 5);

      edge.points.first.normalImpulse = 0.25;
      cache
        ..remember(edge, edge.points.first)
        ..commit();

      expect(
        cache.recall(edge, edge.points.first)?.x,
        0.25,
        reason:
            'a contact has to find its own impulse again — that is the '
            'whole of what warm starting is',
      );
      expect(
        cache.recall(face, face.points.first),
        isNull,
        reason: 'and no other manifold may inherit it',
      );
    });

    test('no die overruns the space a feature id has', () {
      for (final DieKind kind in DieKind.values) {
        // The edge band numbers a contact by a pair of edge *directions*, and
        // allows a die 32 of them. Fifteen is the most any of these has; a
        // shape that went past it would not fail, it would start issuing ids
        // that belong to some other pair of edges.
        expect(
          shapeFor(kind).edges.length,
          lessThan(32),
          reason: '${kind.label} has too many edge directions to number',
        );
        expect(
          shapeFor(kind).vertices.length,
          lessThan(32),
          reason: kind.label,
        );
      }
    });
  });

  group('containment', () {
    test('dice stay inside the tray through a hard shake', () {
      final DiceTray tray = DiceTray(
        width: kWidth,
        height: kHeight,
        random: math.Random(7),
      );
      final ManualMotionSource motion = ManualMotionSource();

      const double dt = 1 / 60;
      double worst = 0;
      for (int i = 0; i < 60 * 8; i++) {
        // Restart the shake repeatedly — eight seconds of continuous violence.
        if (i % 45 == 0) {
          motion.shake(
            seconds: 1.0,
            frequency: 6.0,
            amplitude: 0.06,
            twist: 12,
          );
        }
        tray.update(motion.sample(dt), dt);

        for (final RigidBody d in tray.dice) {
          for (final Vector3 corner in d.coreVertices) {
            for (final Wall wall in tray.world.walls) {
              final double inside =
                  wall.normal.dot(corner) - wall.offset - d.radius;
              worst = math.min(worst, inside);
            }
          }
        }
      }
      // Sub-millimetre overlap is the solver's slop; anything more is a die
      // escaping, which is the failure that matters here.
      expect(
        worst,
        greaterThan(-1e-3),
        reason: 'a die left the tray (worst overlap ${worst * 1000} mm)',
      );
    });

    test('two dice do not pass through each other', () {
      final PhysicsWorld world = PhysicsWorld(
        walls: trayWalls(
          width: kWidth,
          height: kHeight,
          depth: Tuning.trayDepth,
        ),
      );
      // Dropped one directly above the other.
      world.bodies.add(
        die(
          at: Vector3(0, -kHeight / 2 + 0.008, -Tuning.trayDepth / 2),
          facing: Quaternion.identity(),
        ),
      );
      world.bodies.add(
        die(
          at: Vector3(0, -kHeight / 2 + 0.05, -Tuning.trayDepth / 2),
          facing: Quaternion.identity(),
        ),
      );

      run(world, 4.0);

      final double gap =
          (world.bodies[0].position - world.bodies[1].position).length;
      expect(
        gap,
        greaterThan(Tuning.dieSize * 0.9),
        reason: 'dice must not share space',
      );
      // Stacked, the upper die sits a die-height above the lower one.
      expect(
        world.bodies[1].position.y,
        greaterThan(world.bodies[0].position.y),
      );
    });
  });

  group('reading the die', () {
    test('face up matches the orientation', () {
      final DiceTray tray = DiceTray(
        width: kWidth,
        height: kHeight,
        diceCount: 1,
        random: math.Random(1),
      );
      final RigidBody d = tray.dice.first;
      d.orientation = Quaternion.identity();
      d.syncDerived();
      tray.world.gravity.setValues(0, -9.81, 0);

      // Local +y is up, and +y is the 2.
      expect(tray.faceUp(d), 2);

      // Roll it a quarter turn about +x: local +z comes up, which is the 3.
      d.orientation = Quaternion.axisAngle(Vector3(1, 0, 0), -math.pi / 2);
      d.syncDerived();
      expect(tray.faceUp(d), 3);
    });

    test('opposite faces sum to seven', () {
      for (int axis = 0; axis < 3; axis++) {
        expect(faceValue(axis, 1) + faceValue(axis, -1), 7);
      }
    });
  });
}
