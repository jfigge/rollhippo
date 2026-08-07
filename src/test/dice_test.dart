import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/motion/motion.dart';
import 'package:rollhippo/physics/body.dart';
import 'package:rollhippo/physics/collision.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:vector_math/vector_math_64.dart';

const double kWidth = 393 / Tuning.logicalPixelsPerMetre;
const double kHeight = 852 / Tuning.logicalPixelsPerMetre;

DiceTray trayOf(List<DieSpec> dice, {int seed = 3}) => DiceTray(
  width: kWidth,
  height: kHeight,
  dice: dice,
  random: math.Random(seed),
);

DieSpec spec(DieKind kind) => DieSpec(kind: kind, colour: kDiceWhite);

/// Runs until every die has stopped, or [limit] seconds have gone by.
double settle(DiceTray tray, ManualMotionSource motion, {double limit = 12}) {
  const double dt = 1 / 120;
  double t = 0;
  while (t < limit) {
    tray.update(motion.sample(dt), dt);
    t += dt;
    if (t > 0.5 && tray.world.asleep) break;
  }
  return t;
}

void main() {
  group('every kind of die', () {
    for (final DieKind kind in DieKind.values) {
      test('a ${kind.label} lands flat on a face and reads it', () {
        final DiceTray tray = trayOf(<DieSpec>[spec(kind)]);
        final ManualMotionSource motion = ManualMotionSource();
        final double took = settle(tray, motion);

        expect(
          tray.world.asleep,
          isTrue,
          reason: 'a ${kind.label} must stop rolling (gave up after ${took}s)',
        );

        final RigidBody die = tray.dice.single;
        final Vector3 up = -tray.world.gravity.normalized();
        // A D4 has no face up when it is at rest — it is read off the one it is
        // sitting on, so that is the one that has to be flat.
        final Vector3 towards = kind == DieKind.d4 ? -up : up;

        double best = -2;
        int landed = 0;
        for (int f = 0; f < die.shape.faces.length; f++) {
          final double d = die.faceNormal(f).dot(towards);
          if (d > best) {
            best = d;
            landed = die.shape.faces[f].value;
          }
        }
        expect(
          best,
          greaterThan(0.985),
          reason: '${kind.label} settled on an edge, not a face',
        );
        expect(landed, tray.faceUp(die));
        expect(landed, inInclusiveRange(1, kind.sides));
      });
    }
  });

  test('a die is thrown hard enough to bounce off the floor', () {
    // Judged over a spread of throws rather than one, because a die that lands
    // on a corner while spinning skitters instead of bouncing — which is what a
    // real one does, and not something a single seed should be able to call a
    // regression.
    final List<double> rebounds = <double>[];
    final double floor = -kHeight / 2;

    for (int seed = 0; seed < 16; seed++) {
      final DiceTray tray = trayOf(<DieSpec>[spec(DieKind.d6)], seed: seed);
      final ManualMotionSource motion = ManualMotionSource();
      final RigidBody die = tray.dice.single;
      final double start = die.position.y;
      expect(start, greaterThan(kHeight * 0.25), reason: 'thrown from the top');

      const double dt = 1 / 240;
      double lowest = double.infinity;
      double peak = double.negativeInfinity;
      bool landed = false;
      for (double t = 0; t < 3.0; t += dt) {
        tray.update(motion.sample(dt), dt);
        lowest = math.min(lowest, die.position.y);
        // Touching down, not "moving upwards": a die can pick up upward
        // velocity off a side wall on the way past without having landed.
        landed |= die.position.y - floor < die.circumradius;
        if (landed) peak = math.max(peak, die.position.y);
      }

      expect(landed, isTrue, reason: 'seed $seed never reached the floor');
      // A die touching the floor has its centre no higher than its own
      // circumradius above it, whichever corner it is standing on.
      expect(
        die.position.y - floor,
        lessThan(die.circumradius + 1e-3),
        reason: 'seed $seed settled off the floor rather than on it',
      );
      rebounds.add(peak - lowest);
    }

    rebounds.sort();
    expect(
      rebounds[rebounds.length ~/ 2],
      greaterThan(0.015),
      reason: 'the usual throw must come back up off the floor, not just land',
    );
  });

  test('a full tray of assorted dice starts apart and stays inside', () {
    // The six solids, and not the hippopotamus: it is a cube with an animal
    // drawn on it, so it would put a seventh die in the mixture without
    // putting a seventh shape in it.
    final List<DieKind> shapes = <DieKind>[
      for (final DieKind kind in DieKind.values)
        if (!kind.secret) kind,
    ];
    final List<DieSpec> set = <DieSpec>[
      for (int i = 0; i < 10; i++) spec(shapes[i % shapes.length]),
    ];
    final DiceTray tray = trayOf(set, seed: 5);

    // The spawn grid's whole job: ten dice of six different shapes, none of
    // them starting inside another.
    for (int i = 0; i < tray.dice.length; i++) {
      for (int j = i + 1; j < tray.dice.length; j++) {
        final RigidBody a = tray.dice[i];
        final RigidBody b = tray.dice[j];
        expect(
          (a.position - b.position).length,
          greaterThan(a.shape.inradius + b.shape.inradius),
          reason: 'dice $i and $j are thrown in on top of each other',
        );
      }
    }

    final ManualMotionSource motion = ManualMotionSource();
    const double dt = 1 / 60;
    double worst = 0;
    for (int i = 0; i < 60 * 6; i++) {
      if (i % 45 == 0) {
        motion.shake(seconds: 1.0, frequency: 6.0, amplitude: 0.06, twist: 12);
      }
      tray.update(motion.sample(dt), dt);
      for (final RigidBody d in tray.dice) {
        for (final Vector3 corner in d.coreVertices) {
          for (final Wall wall in tray.world.walls) {
            worst = math.min(
              worst,
              wall.normal.dot(corner) - wall.offset - d.radius,
            );
          }
        }
      }
    }
    // The deepest a bevelled corner got into a wall at any instant, which is
    // not the same question as whether a die escaped: the guard for *that* is
    // `_containStrays`, and it does not fire until a die's centre is a whole
    // circumradius outside, which is tens of millimetres. A couple of
    // millimetres is the solver working as designed — `penetrationSlop` is
    // 2e-4 and recovery is capped at `maxCorrectionSpeed`, so a die arriving
    // at a wall hard enough is meant to be pushed back out over the following
    // frames rather than stopped dead in one.
    //
    // The bound is loose on purpose. Six seconds of ten dice with a fresh
    // shake every 45 frames is chaotic, so the *peak* is not reproducible
    // across machines the way the rest of the suite is: `sin` and `cos` differ
    // by an ulp between glibc x86-64 and macOS arm64, and one ulp in the first
    // shake sample is a different trajectory by the end. A bound drawn tight
    // around one platform's peak passes there and fails on the other, which is
    // exactly what -1.5e-3 did. This one is comfortably clear of the worst
    // seen on either, and still an order of magnitude below an actual escape.
    expect(
      worst,
      greaterThan(-4e-3),
      reason: 'a die went through a wall (worst overlap ${worst * 1000} mm)',
    );
  });

  test('a d20 is fair enough to gamble on', () {
    // Fewer rolls than the D6 suite runs, because a D20 costs more per roll and
    // this is a smoke test for a *biased* die — a lopsided inertia tensor or a
    // face the reader can never pick — not a certificate of randomness.
    final math.Random rng = math.Random(17);
    final DiceTray tray = trayOf(<DieSpec>[spec(DieKind.d20)]);
    final ManualMotionSource motion = ManualMotionSource();
    final Map<int, int> counts = <int, int>{};

    const int rolls = 120;
    for (int i = 0; i < rolls; i++) {
      tray.throwDice();
      motion.shake(
        seconds: 0.6 + rng.nextDouble() * 0.6,
        frequency: 3.5 + rng.nextDouble() * 2.5,
        amplitude: 0.035 + rng.nextDouble() * 0.03,
        twist: 5 + rng.nextDouble() * 8,
      );
      settle(tray, motion, limit: 10);
      counts.update(
        tray.faceUp(tray.dice.single),
        (int n) => n + 1,
        ifAbsent: () => 1,
      );
    }

    expect(
      counts.length,
      greaterThan(14),
      reason:
          'a D20 that only ever shows ${counts.length} of its 20 faces '
          'is not a D20',
    );
    for (final int value in counts.keys) {
      expect(value, inInclusiveRange(1, 20));
    }
    expect(
      counts.values.reduce(math.max),
      lessThan(rolls / 4),
      reason: 'no face may swallow a quarter of the rolls',
    );
  });
}
