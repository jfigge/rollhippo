import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/motion/motion.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:vector_math/vector_math_64.dart';

const double kWidth = 393 / Tuning.logicalPixelsPerMetre;
const double kHeight = 852 / Tuning.logicalPixelsPerMetre;

DiceTray makeTray() =>
    DiceTray(width: kWidth, height: kHeight, random: math.Random(2));

MotionFrame frame(Vector3 proper, Vector3 gravity) => MotionFrame(
  properAcceleration: proper,
  gravityReading: gravity,
  angularVelocity: Vector3.zero(),
  angularAcceleration: Vector3.zero(),
);

void main() {
  test('a still phone falls at the scaled gravity', () {
    final DiceTray tray = makeTray();
    tray.update(MotionFrame.still, 1 / 60);

    expect(tray.world.gravity.x, closeTo(0, 1e-9));
    expect(tray.world.gravity.z, closeTo(0, 1e-9));
    expect(tray.world.gravity.y, closeTo(-9.81 * Tuning.gravityScale, 1e-6));
  });

  test('a shake keeps its full force at any gravity scale', () {
    final DiceTray tray = makeTray();
    // Upright, being thrown sideways at 5 m/s².
    tray.update(frame(Vector3(5, 9.81, 0), Vector3(0, 9.81, 0)), 1 / 60);

    // The sideways term is untouched by the scale; only the pull is softened.
    expect(tray.world.gravity.x, closeTo(-5, 1e-6));
    expect(tray.world.gravity.y, closeTo(-9.81 * Tuning.gravityScale, 1e-6));
  });

  test('tilting turns gravity without changing how strong it is', () {
    final ManualMotionSource motion = ManualMotionSource();
    motion.tilt(roll: 0.6);
    final MotionFrame tilted = motion.sample(1 / 60);

    expect(tilted.gravityReading.length, closeTo(9.81, 1e-6));
    // Held still, all of the reading is gravity and none of it is movement.
    expect(tilted.linearAcceleration.length, closeTo(0, 1e-9));

    final DiceTray tray = makeTray();
    tray.update(tilted, 1 / 60);
    expect(
      tray.world.gravity.length,
      closeTo(9.81 * Tuning.gravityScale, 1e-6),
    );
    expect(
      tray.world.gravity.x,
      isNot(closeTo(0, 1e-3)),
      reason: 'a tilted phone must pull the dice sideways',
    );
  });

  group('the sensor filters keep time in seconds', () {
    // Half a second of smoothing, run at three display rates. A filter with a
    // per-frame weight reaches a different place at each of them; one with a
    // time constant reaches the same place at all three, which is the whole
    // property — see [lowPass].
    double settledAt(int hz) {
      const double tau = 0.1026;
      final double dt = 1 / hz;
      double held = 0;
      for (int i = 0; i < hz ~/ 2; i++) {
        final double blend = lowPass(dt, tau);
        held = held * (1 - blend) + 1.0 * blend;
      }
      return held;
    }

    test('the same half second lands in the same place at any rate', () {
      final double at60 = settledAt(60);
      expect(
        at60,
        greaterThan(0.9),
        reason: 'half a second is most of the way',
      );
      expect(settledAt(120), closeTo(at60, 1e-9));
      expect(settledAt(240), closeTo(at60, 1e-9));
      // And the same half second under the per-frame weight this replaced,
      // which is what ProMotion used to get: twice the frames meant twice the
      // convergence, so "down" chased a shake harder on one handset than on
      // the other. Stated here so the test says what it is defending.
      double perFrame(int hz) {
        double held = 0;
        for (int i = 0; i < hz ~/ 2; i++) {
          held = held * 0.85 + 0.15;
        }
        return held;
      }

      expect(
        perFrame(120) - perFrame(60),
        greaterThan(0.007),
        reason: 'the weights really did land the two rates in different places',
      );
    });

    test('two short steps compose into one long one', () {
      // What a per-frame weight cannot do, and the reason a stall does not
      // put the filter somewhere a smooth run never would.
      const double tau = 0.05;
      double twice = 0;
      for (int i = 0; i < 2; i++) {
        final double blend = lowPass(1 / 120, tau);
        twice = twice * (1 - blend) + blend;
      }
      final double once = lowPass(1 / 60, tau);
      expect(twice, closeTo(once, 1e-12));
    });

    test(
      'a step much longer than the constant snaps rather than overshoots',
      () {
        expect(lowPass(10, 0.05), closeTo(1.0, 1e-9));
        expect(
          lowPass(0, 0.05),
          0.0,
          reason:
              'no time passed, so nothing moves — a 1 here would throw '
              'the whole estimate away on one raw sample',
        );
      },
    );
  });

  test(
    'the split is exact — gravity plus movement is what the sensor read',
    () {
      final Vector3 proper = Vector3(1.5, 9.0, -2.0);
      final Vector3 gravity = Vector3(0.5, 9.7, 0.2);
      final MotionFrame f = frame(proper, gravity);
      expect(
        (f.gravityReading + f.linearAcceleration - proper).length,
        closeTo(0, 1e-12),
      );
    },
  );
}
