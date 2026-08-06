import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/haptics.dart';
import 'package:rollhippo/motion/motion.dart';
import 'package:rollhippo/tray/tray.dart';

const double kWidth = 393 / Tuning.logicalPixelsPerMetre;
const double kHeight = 852 / Tuning.logicalPixelsPerMetre;

DiceTray trayOf(List<DieSpec> dice, {int seed = 3}) => DiceTray(
  width: kWidth,
  height: kHeight,
  dice: dice,
  random: math.Random(seed),
);

DieSpec spec(DieKind kind) => DieSpec(kind: kind, colour: kDiceWhite);

/// Runs the tray forward, returning the hardest wall impact seen on any frame.
///
/// The peak across frames rather than the last frame's: a throw is over in a
/// fraction of a second and the frame it lands on is not one a test can pick
/// out in advance.
double loudest(
  DiceTray tray,
  MotionFrame Function() motion, {
  double seconds = 4,
}) {
  const double dt = 1 / 120;
  double peak = 0;
  for (double t = 0; t < seconds; t += dt) {
    tray.update(motion(), dt);
    if (tray.world.lastWallImpulse > peak) peak = tray.world.lastWallImpulse;
    if (t > 0.5 && tray.world.asleep) break;
  }
  return peak;
}

void main() {
  group('what the tray reports', () {
    test('a thrown die registers hitting the floor', () {
      final DiceTray tray = trayOf(<DieSpec>[spec(DieKind.d6)]);
      final ManualMotionSource motion = ManualMotionSource();
      tray.throwDice();

      final double peak = loudest(tray, () => motion.sample(1 / 120));

      // Across seeds a thrown D6 peaks somewhere between 2 and 11 mN·s: it is
      // spinning as well as falling, and a die that lands on a corner spends
      // some of its arrival on rotation rather than on the floor. Both bounds
      // are well clear of that spread, because the thing being asserted is
      // that the signal exists and is the right order of magnitude — the exact
      // number is a property of the seed.
      expect(
        peak,
        greaterThan(Tuning.hapticFloor),
        reason: 'a die dropped the length of the tray must be felt',
      );
      expect(
        peak,
        lessThan(0.03),
        reason: 'a single 4.8 g die cannot deliver 30 mN·s',
      );
    });

    test('a tray with nothing happening in it reports nothing', () {
      final DiceTray tray = trayOf(<DieSpec>[spec(DieKind.d6)]);
      // Settle first, then keep going: dice resting on the floor put a real
      // impulse through their contacts on every substep to stay there, and
      // this is the gate that stops that reading as a wall being hit.
      loudest(tray, () => MotionFrame.still, seconds: 6);
      expect(
        tray.world.asleep,
        isTrue,
        reason: 'the die never settled, so this proves nothing',
      );

      final double resting = loudest(
        tray,
        () => MotionFrame.still,
        seconds: 0.5,
      );
      expect(
        resting,
        0.0,
        reason: 'a die lying on the floor is not hitting it',
      );
    });

    test('a heavier die hits harder than a lighter one at the same speed', () {
      // Every die is the same width across, so a D20 is genuinely the heavier
      // object — and an impulse, unlike a speed, says so. This is the whole
      // reason the haptic is keyed on impulse.
      final ManualMotionSource light = ManualMotionSource();
      final ManualMotionSource heavy = ManualMotionSource();
      final DiceTray d4 = trayOf(<DieSpec>[spec(DieKind.d4)])..throwDice();
      final DiceTray d20 = trayOf(<DieSpec>[spec(DieKind.d20)])..throwDice();

      final double small = loudest(d4, () => light.sample(1 / 120));
      final double big = loudest(d20, () => heavy.sample(1 / 120));

      expect(
        big,
        greaterThan(small),
        reason: 'a D20 (8.0 g) must land harder than a D4 (1.6 g)',
      );
    });
  });

  group('what it feels like', () {
    test('an impact under the floor is not one', () {
      final HapticEngine engine = HapticEngine();
      expect(engine.levelFor(Tuning.hapticFloor * 0.5), isNull);
      expect(engine.levelFor(0), isNull);
    });

    test('harder never means gentler', () {
      final HapticEngine engine = HapticEngine();
      HapticLevel last = HapticLevel.selection;
      for (
        double j = Tuning.hapticFloor;
        j < Tuning.hapticCeiling * 2;
        j += Tuning.hapticFloor / 4
      ) {
        final HapticLevel level = engine.levelFor(j)!;
        expect(
          level.index,
          greaterThanOrEqualTo(last.index),
          reason: 'the scale went backwards at ${j * 1000} mN·s',
        );
        last = level;
      }
      expect(
        last,
        HapticLevel.heavy,
        reason: 'twice the ceiling has to be the hardest tap there is',
      );
    });

    test('a slam is the hardest tap and a nudge is the softest', () {
      final HapticEngine engine = HapticEngine();
      expect(engine.levelFor(Tuning.hapticCeiling), HapticLevel.heavy);
      expect(engine.levelFor(Tuning.hapticFloor), HapticLevel.selection);
    });

    test('the gain moves the whole scale, floor included', () {
      // Below the floor at the default, felt at three times it — which is the
      // actual complaint the control exists to answer.
      final double quiet = Tuning.hapticFloor * 0.6;
      expect(HapticEngine(gain: 1).levelFor(quiet), isNull);
      expect(HapticEngine(gain: 3).levelFor(quiet), isNotNull);

      // And off is off, however hard the knock.
      expect(HapticEngine(gain: 0).levelFor(Tuning.hapticCeiling * 10), isNull);
    });

    test('ten dice landing at once are one tap, not ten', () {
      final RecordedHaptics driver = RecordedHaptics();
      final HapticEngine engine = HapticEngine(driver: driver);
      // Ten frames at 120 Hz is 83 ms, well under two gaps.
      for (int i = 0; i < 10; i++) {
        engine.impact(Tuning.hapticCeiling, 1 / 120);
      }
      expect(
        driver.fired.length,
        lessThanOrEqualTo(2),
        reason: '83 ms of continuous slamming is not eight separate taps',
      );
    });

    test('a harder knock interrupts one that is still ringing', () {
      final RecordedHaptics driver = RecordedHaptics();
      final HapticEngine engine = HapticEngine(driver: driver);
      engine.impact(Tuning.hapticFloor, 1 / 120);
      expect(driver.fired, <HapticLevel>[HapticLevel.selection]);

      // Same frame's worth of time later, so well inside the gap.
      engine.impact(Tuning.hapticCeiling, 1 / 120);
      expect(
        driver.fired,
        <HapticLevel>[HapticLevel.selection, HapticLevel.heavy],
        reason: 'a die slamming the wall must not be swallowed by a nudge',
      );

      // But the reverse is not true: a nudge behind a slam waits.
      engine.impact(Tuning.hapticFloor, 1 / 120);
      expect(driver.fired.length, 2);
    });

    test('the gap reopens once it has elapsed', () {
      final RecordedHaptics driver = RecordedHaptics();
      final HapticEngine engine = HapticEngine(driver: driver);
      engine.impact(Tuning.hapticCeiling, 1 / 120);
      engine.impact(Tuning.hapticCeiling, Tuning.hapticGap);
      expect(driver.fired.length, 2);
    });

    test('silent frames still keep the clock', () {
      // The gap is fed from the frame time whether or not anything hit, which
      // is why [HapticEngine.impact] is called every frame.
      final RecordedHaptics driver = RecordedHaptics();
      final HapticEngine engine = HapticEngine(driver: driver);
      engine.impact(Tuning.hapticCeiling, 1 / 120);
      for (int i = 0; i < 8; i++) {
        engine.impact(0, 1 / 120);
      }
      engine.impact(Tuning.hapticFloor, 1 / 120);
      expect(
        driver.fired.length,
        2,
        reason: '75 ms of quiet is longer than the gap, so the tap is due',
      );
    });

    test('the slider plays something back at every setting but off', () {
      final RecordedHaptics driver = RecordedHaptics();
      final HapticEngine engine = HapticEngine(driver: driver);
      for (double gain = 0.25; gain <= Tuning.hapticMaxGain; gain += 0.25) {
        engine.gain = gain;
        engine.demo();
      }
      expect(
        driver.fired.length,
        12,
        reason: 'every notch of the slider has to answer',
      );

      driver.clear();
      engine.gain = 0;
      engine.demo();
      expect(driver.fired, isEmpty, reason: 'off is off');
    });
  });
}
