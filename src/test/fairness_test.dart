import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo2/motion/motion.dart';
import 'package:rollhippo2/physics/body.dart';
import 'package:rollhippo2/tray/tray.dart';

const double kWidth = 393 / Tuning.logicalPixelsPerMetre;
const double kHeight = 852 / Tuning.logicalPixelsPerMetre;

/// Shakes the tray once and runs until the dice stop, returning the faces.
List<int> roll(DiceTray tray, ManualMotionSource motion, math.Random rng) {
  tray.scatter();
  motion.shake(
    seconds: 0.6 + rng.nextDouble() * 0.6,
    frequency: 3.5 + rng.nextDouble() * 2.5,
    amplitude: 0.035 + rng.nextDouble() * 0.03,
    twist: 5 + rng.nextDouble() * 8,
  );

  const double dt = 1 / 60;
  double t = 0;
  while (t < 8.0) {
    tray.update(motion.sample(dt), dt);
    t += dt;
    if (t > 1.5 && tray.world.asleep) break;
  }
  return tray.dice.map((RigidBox d) => tray.faceUp(d)).toList();
}

void main() {
  test('every roll settles', () {
    final DiceTray tray = DiceTray(
      width: kWidth,
      height: kHeight,
      random: math.Random(5),
    );
    final ManualMotionSource motion = ManualMotionSource();
    final math.Random rng = math.Random(5);

    for (int i = 0; i < 25; i++) {
      roll(tray, motion, rng);
      expect(
        tray.world.asleep,
        isTrue,
        reason:
            'roll $i never came to rest — dice that never stop are dice '
            'you cannot read',
      );
    }
  });

  test('a shake tumbles the dice rather than sliding them', () {
    final DiceTray tray = DiceTray(
      width: kWidth,
      height: kHeight,
      diceCount: 1,
      random: math.Random(9),
    );
    final ManualMotionSource motion = ManualMotionSource();
    final RigidBox die = tray.dice.first;

    motion.shake(seconds: 1.2, frequency: 4.5, amplitude: 0.05, twist: 9);

    const double dt = 1 / 120;
    int changes = 0;
    int previous = tray.faceUp(die);
    for (int i = 0; i < 120 * 2; i++) {
      tray.update(motion.sample(dt), dt);
      final int face = tray.faceUp(die);
      if (face != previous) changes++;
      previous = face;
    }
    // A die being pushed around a flat plane keeps whatever face it started on.
    // Real tumbling turns it over many times in a one-second shake.
    expect(
      changes,
      greaterThan(12),
      reason: 'the die is being slid, not tumbled ($changes face changes)',
    );
  });

  test('faces come up about equally often', () {
    final DiceTray tray = DiceTray(
      width: kWidth,
      height: kHeight,
      random: math.Random(21),
    );
    final ManualMotionSource motion = ManualMotionSource();
    final math.Random rng = math.Random(21);

    final List<int> counts = List<int>.filled(7, 0);
    const int rolls = 220;
    for (int i = 0; i < rolls; i++) {
      for (final int face in roll(tray, motion, rng)) {
        counts[face]++;
      }
    }

    final int total = counts.skip(1).reduce((int a, int b) => a + b);
    final double expected = total / 6;
    double chiSquare = 0;
    for (int f = 1; f <= 6; f++) {
      expect(counts[f], greaterThan(0), reason: 'face $f never came up');
      final double d = counts[f] - expected;
      chiSquare += d * d / expected;
    }

    // Five degrees of freedom; 20.5 is the 0.999 critical value. This is a
    // smoke test for gross bias — a die that favours a face, or a tray that
    // always lands the same way up — not a certification of randomness.
    expect(
      chiSquare,
      lessThan(20.5),
      reason: 'face distribution looks biased: $counts (chi2 $chiSquare)',
    );
    // ignore: avoid_print
    print(
      'faces 1-6: ${counts.skip(1).toList()}  chi2 '
      '${chiSquare.toStringAsFixed(2)}  n=$total',
    );
  });
}
