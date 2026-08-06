import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/tray_screen.dart';
import 'package:rollhippo/motion/motion.dart';
import 'package:rollhippo/physics/body.dart';
import 'package:rollhippo/render/tray_painter.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:vector_math/vector_math_64.dart' show Quaternion, Vector3;

const Size kScreen = Size(393, 852);
const DieSpec white = DieSpec(kind: DieKind.d6, colour: kDiceWhite);

DiceTray trayOf(int count, {int seed = 7}) => DiceTray(
  width: kScreen.width / Tuning.logicalPixelsPerMetre,
  height: kScreen.height / Tuning.logicalPixelsPerMetre,
  dice: List<DieSpec>.filled(count, white),
  readout: true,
  random: math.Random(seed),
);

/// Runs the tray under a still phone until [until], or gives up.
///
/// Returns false if it never happened, so a test can say so rather than
/// asserting something misleading about a tray that simply never got there.
bool runUntil(DiceTray tray, bool Function() until, {double limit = 12}) {
  double elapsed = 0;
  while (!until() && elapsed < limit) {
    tray.update(MotionFrame.still, 1 / 120);
    elapsed += 1 / 120;
  }
  return until();
}

bool settled(DiceTray tray) => runUntil(tray, () => tray.world.asleep);

/// Runs until the formation has been worked out *and* the dice have finished
/// travelling into it. Stopping at the first — which is the instant the numbers
/// are captured — leaves every die still sitting where it landed.
bool presented(DiceTray tray) =>
    runUntil(tray, () => tray.readout.values != null) &&
    runUntil(tray, () => !tray.readout.moving);

void main() {
  group('keeping a die', () {
    test('is only offered once the roll is being presented', () {
      final DiceTray tray = trayOf(3);
      expect(tray.canHold, isFalse, reason: 'mid-throw there is no result yet');

      tray.toggleHold(0);
      expect(tray.held, isEmpty, reason: 'a die was kept before it had landed');

      expect(presented(tray), isTrue);
      expect(tray.canHold, isTrue);
      tray.toggleHold(0);
      expect(tray.held.keys, <int>[0]);
      expect(tray.dice[0].held, isTrue);
    });

    test('and letting go puts it back in play', () {
      final DiceTray tray = trayOf(3);
      expect(presented(tray), isTrue);

      tray.toggleHold(1);
      tray.toggleHold(1);
      expect(tray.held, isEmpty);
      expect(tray.dice[1].held, isFalse);

      // Back to being an ordinary die: the next throw moves it.
      final Vector3 before = tray.dice[1].position.clone();
      tray.throwDice();
      expect(tray.dice[1].position, isNot(before));
    });

    test('keeps its number, and the spot it landed on, through a throw', () {
      final DiceTray tray = trayOf(4);

      // Where the physics actually left it, before the readout lifts it into
      // the formation. That is the spot a kept die has to go back to.
      expect(settled(tray), isTrue);
      final Vector3 landed = tray.dice[0].position.clone();
      final Quaternion landedTurned = tray.dice[0].orientation.clone();

      expect(presented(tray), isTrue);
      expect(
        tray.dice[0].position,
        isNot(landed),
        reason: 'the readout should have lifted it out of the tray',
      );
      final int kept = tray.faces[0];

      tray.toggleHold(0);
      tray.throwDice();

      expect(
        (tray.dice[0].position - landed).length,
        lessThan(1e-9),
        reason: 'a kept die should be back where it fell, not left in the air',
      );
      expect((tray.dice[0].orientation - landedTurned).length, lessThan(1e-9));

      // And it is still there, and still reads the same, at the far end of a
      // whole roll happening around it.
      final Vector3 frozen = tray.dice[0].position.clone();
      expect(presented(tray), isTrue);
      expect(tray.faces[0], kept, reason: 'a kept die changed its number');
      expect(tray.held[0], isNotNull);

      // It has been lifted into the formation again, glowing, showing the same
      // number — and putting it down again returns it to the very same spot.
      tray.throwDice();
      expect((tray.dice[0].position - frozen).length, lessThan(1e-9));
    });

    test('does not move, however hard the tray is shaken', () {
      final DiceTray tray = trayOf(4);
      expect(presented(tray), isTrue);
      tray.toggleHold(2);
      tray.throwDice();

      final Vector3 where = tray.dice[2].position.clone();
      final ManualMotionSource hand = ManualMotionSource();
      hand.shake(seconds: 2.0, amplitude: 0.09, twist: 12.0);
      for (int i = 0; i < 360; i++) {
        tray.update(hand.sample(1 / 120), 1 / 120);
        expect(
          (tray.dice[2].position - where).length,
          lessThan(1e-9),
          reason: 'a kept die moved on frame $i',
        );
        expect(tray.dice[2].velocity.length, 0);
      }
    });
  });

  group('a kept die is still solid', () {
    test('a falling die bounces off it instead of through it', () {
      final DiceTray tray = trayOf(2);
      final RigidBody pinned = tray.dice[0];
      final RigidBody falling = tray.dice[1];

      // Square on, one above the other, in the middle of the tray where no
      // wall can be what either of them hits.
      void place(RigidBody die, double y, Vector3 velocity) {
        die.position = Vector3(0, y, -tray.depth / 2);
        die.orientation = Quaternion.identity();
        die.velocity.setFrom(velocity);
        die.angularVelocity.setZero();
        die.syncDerived();
      }

      place(pinned, 0, Vector3.zero());
      pinned.held = true;
      place(falling, Tuning.dieSize * 1.6, Vector3(0, -0.8, 0));
      final Vector3 where = pinned.position.clone();
      tray.world.wake();

      bool bounced = false;
      for (int i = 0; i < 60; i++) {
        tray.update(MotionFrame.still, 1 / 240);
        if (falling.velocity.y > 0) bounced = true;
      }

      expect(bounced, isTrue, reason: 'it went straight through');
      expect(
        falling.position.y,
        greaterThan(pinned.position.y),
        reason: 'it ended up underneath a die it cannot pass',
      );
      expect(
        (pinned.position - where).length,
        lessThan(1e-9),
        reason: 'the die it hit was shoved',
      );
    });
  });

  group('finding the die under a finger', () {
    TrayCamera cameraFor(DiceTray tray) => TrayCamera(
      pixelsPerMetre: kScreen.width / tray.width,
      eyeDistance: Tuning.eyeDistance,
      centre: Offset(kScreen.width / 2, kScreen.height / 2),
    );

    test('every die in the formation answers for its own middle', () {
      final DiceTray tray = trayOf(6);
      expect(presented(tray), isTrue);
      // Let the formation finish arriving, so the dice are where they will be
      // sitting when somebody actually reaches for one.
      runUntil(tray, () => !tray.readout.moving);

      final TrayCamera camera = cameraFor(tray);
      for (int i = 0; i < tray.dice.length; i++) {
        expect(
          dieAt(tray, kScreen, camera.project(tray.dice[i].position)),
          i,
          reason: 'die $i did not answer for its own centre',
        );
      }
    });

    test('and a tap on the tray itself hits nothing', () {
      final DiceTray tray = trayOf(2);
      expect(presented(tray), isTrue);
      runUntil(tray, () => !tray.readout.moving);

      // The top corner: the formation keeps clear of it for the buttons.
      expect(dieAt(tray, kScreen, const Offset(8, 8)), isNull);
    });
  });

  group('the tray screen', () {
    final TargetPlatformVariant harness = TargetPlatformVariant.only(
      TargetPlatform.macOS,
    );

    DiceTray shownTray(WidgetTester tester) =>
        (tester
                    .widget<CustomPaint>(
                      find.byWidgetPredicate(
                        (Widget w) =>
                            w is CustomPaint && w.painter is TrayPagesPainter,
                      ),
                    )
                    .painter!
                as TrayPagesPainter)
            .trays
            .first;

    testWidgets('a tap on a die keeps it, and a second lets it go', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(kScreen);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: TrayScreen(
            groups: <List<DieSpec>>[
              <DieSpec>[white, white, white],
            ],
          ),
        ),
      );

      final DiceTray tray = shownTray(tester);
      // Roll, settle, and let the formation finish arriving. The binding's
      // clock is a fake one, so this is simulated time rather than a wait.
      for (int i = 0; i < 480; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (tray.readout.values != null && !tray.readout.moving) break;
      }
      expect(tray.canHold, isTrue, reason: 'the roll was never presented');

      final TrayCamera camera = TrayCamera(
        pixelsPerMetre: kScreen.width / tray.width,
        eyeDistance: Tuning.eyeDistance,
        centre: Offset(kScreen.width / 2, kScreen.height / 2),
      );

      await tester.tapAt(camera.project(tray.dice[1].position));
      await tester.pump();
      expect(tray.held.keys, <int>[1]);
      expect(tray.dice[1].held, isTrue);

      await tester.tapAt(camera.project(tray.dice[1].position));
      await tester.pump();
      expect(tray.held, isEmpty);
      expect(tray.dice[1].held, isFalse);
    }, variant: harness);

    testWidgets('a tap on the tray itself puts the roll back down', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(kScreen);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: TrayScreen(
            groups: <List<DieSpec>>[
              <DieSpec>[white, white],
            ],
          ),
        ),
      );

      final DiceTray tray = shownTray(tester);
      for (int i = 0; i < 480; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (tray.readout.values != null && !tray.readout.moving) break;
      }
      expect(tray.canHold, isTrue);

      await tester.tapAt(const Offset(8, 8));
      for (int i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (tray.readout.down) break;
      }
      expect(tray.readout.down, isTrue, reason: 'the dice were not put down');
      expect(tray.held, isEmpty);
    }, variant: harness);
  });
}
