import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo2/motion/motion.dart';
import 'package:rollhippo2/tray/tray.dart';
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
