import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/picker_screen.dart';
import 'package:rollhippo/motion/motion.dart';
import 'package:rollhippo/physics/body.dart';
import 'package:rollhippo/physics/shape.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:vector_math/vector_math_64.dart';

const double kWidth = 393 / Tuning.logicalPixelsPerMetre;
const double kHeight = 852 / Tuning.logicalPixelsPerMetre;
const double kStep = 1 / 120;

DiceTray trayOf(List<DieKind> kinds, {int seed = 3, bool readout = true}) =>
    DiceTray(
      width: kWidth,
      height: kHeight,
      readout: readout,
      dice: <DieSpec>[
        for (final DieKind kind in kinds)
          DieSpec(kind: kind, colour: kDiceWhite),
      ],
      random: math.Random(seed),
    );

/// Runs [seconds] of tray time.
void run(DiceTray tray, ManualMotionSource motion, double seconds) {
  for (double t = 0; t < seconds; t += kStep) {
    tray.update(motion.sample(kStep), kStep);
  }
}

/// Runs until the dice stop, then far enough past it for the readout to have
/// finished — the delay, the move, and a little over.
double present(DiceTray tray, ManualMotionSource motion, {double limit = 12}) {
  double t = 0;
  while (t < limit) {
    tray.update(motion.sample(kStep), kStep);
    t += kStep;
    if (t > 0.5 && tray.world.asleep) break;
  }
  run(tray, motion, Tuning.readoutDelay + Tuning.readoutDuration + 0.1);
  return t;
}

/// How much bigger or smaller than life a thing at [z] is drawn — the
/// projection [TrayCamera] applies, restated here so the test can check what
/// fits on the screen without reaching into `render/`.
double scaleAt(double z) => Tuning.eyeDistance / (Tuning.eyeDistance - z);

/// The face a die is showing the glass, and how squarely.
({int face, double facing}) frontFace(RigidBody die) {
  int best = 0;
  double facing = double.negativeInfinity;
  for (int f = 0; f < die.shape.faces.length; f++) {
    final double d = die.faceNormal(f).z;
    if (d > facing) {
      facing = d;
      best = f;
    }
  }
  return (face: best, facing: facing);
}

void main() {
  group('the readout', () {
    test('every kind turns the number it rolled to the glass', () {
      for (final DieKind kind in DieKind.values) {
        final DiceTray tray = trayOf(<DieKind>[kind]);
        final ManualMotionSource motion = ManualMotionSource();
        present(tray, motion);

        expect(
          tray.readout.active,
          isTrue,
          reason: '${kind.label} never made it into the formation',
        );

        final RigidBody die = tray.dice.first;
        final int shown = tray.faces.first;
        final ({int face, double facing}) front = frontFace(die);

        // Tipped back by exactly the angle asked for, and nothing else is
        // closer to square-on than the face being shown.
        expect(
          die.faceNormal(front.face).y,
          closeTo(math.sin(Tuning.readoutTilt), 1e-6),
          reason: '${kind.label} is not tipped back the way it was told to',
        );
        expect(
          front.facing,
          closeTo(math.cos(Tuning.readoutTilt), 1e-6),
          reason: '${kind.label} is not showing a face square to the glass',
        );

        if (!die.shape.readsDownFace) {
          expect(
            die.shape.faces[front.face].value,
            shown,
            reason: '${kind.label} is showing a number it did not roll',
          );
          continue;
        }

        // A D4 is read off the face it is sitting on, so what has to be facing
        // you is a *neighbour* of that face, with the shared edge — the one
        // the number is printed along — level and along the bottom.
        final ConvexFace face = die.shape.faces[front.face];
        final int edge = face.neighbours.indexWhere(
          (int n) => die.shape.faces[n].value == shown,
        );
        expect(
          edge,
          isNot(-1),
          reason: 'the D4 is not showing the face it rolled on at all',
        );

        final Vector3 p = die.outerVertex(face.vertices[edge]);
        final Vector3 q = die.outerVertex(face.vertices[(edge + 1) % 3]);
        expect(
          (q - p).normalized().y.abs(),
          lessThan(1e-6),
          reason: 'the D4 is showing its number on the slant',
        );
        expect(
          ((p + q) * 0.5).y,
          lessThan(die.faceCentre(front.face).y),
          reason: 'the D4 is showing its number along the top edge',
        );
      }
    });

    test('the numbers do not change while the dice are moving', () {
      final DiceTray tray = trayOf(<DieKind>[
        DieKind.d20,
        DieKind.d6,
        DieKind.d6,
        DieKind.d8,
      ]);
      final ManualMotionSource motion = ManualMotionSource();

      double t = 0;
      while (t < 12) {
        tray.update(motion.sample(kStep), kStep);
        t += kStep;
        if (t > 0.5 && tray.world.asleep) break;
      }
      // Read off the dice where they landed, before anything has turned them.
      final List<int> landed = tray.faces;
      expect(tray.readout.values, isNull);

      for (int i = 0; i < 200; i++) {
        tray.update(motion.sample(kStep), kStep);
        expect(
          tray.faces,
          landed,
          reason: 'the readout changed the answer on frame $i',
        );
      }
      expect(tray.readout.active, isTrue);
      expect(tray.readout.progress, 1.0);
    });

    test('a full tray fits on the screen without touching', () {
      final DiceTray tray = trayOf(<DieKind>[
        for (int i = 0; i < 10; i++) DieKind.values[i % DieKind.values.length],
      ]);
      present(tray, ManualMotionSource());

      for (int i = 0; i < tray.dice.length; i++) {
        final RigidBody a = tray.dice[i];
        // Drawn size, at the depth the formation stands at.
        final double scale = scaleAt(a.position.z);
        final double reach = a.circumradius * scale;

        expect(
          (a.position.x * scale).abs() + reach,
          lessThanOrEqualTo(kWidth / 2 + 1e-9),
          reason: 'die $i hangs off the side of the screen',
        );
        expect(
          a.position.y * scale + reach,
          lessThanOrEqualTo(kHeight / 2 - Tuning.readoutTopClearance + 1e-9),
          reason: 'die $i is up behind the Close and Throw buttons',
        );
        expect(
          a.position.y * scale - reach,
          greaterThanOrEqualTo(-kHeight / 2 - 1e-9),
          reason: 'die $i hangs off the bottom of the screen',
        );

        for (int j = i + 1; j < tray.dice.length; j++) {
          final RigidBody b = tray.dice[j];
          expect(
            (a.position - b.position).length,
            greaterThan(a.circumradius + b.circumradius),
            reason: 'dice $i and $j are inside each other in the formation',
          );
        }
      }
    });

    test('putting them down returns them to where they landed', () {
      final DiceTray tray = trayOf(<DieKind>[
        DieKind.d20,
        DieKind.d6,
        DieKind.d4,
        DieKind.d12,
      ]);
      final ManualMotionSource motion = ManualMotionSource();

      // Where the physics actually left them, before anything lifted them.
      double t = 0;
      while (t < 12) {
        tray.update(motion.sample(kStep), kStep);
        t += kStep;
        if (t > 0.5 && tray.world.asleep) break;
      }
      final List<Vector3> landed = <Vector3>[
        for (final RigidBody die in tray.dice) die.position.clone(),
      ];
      final List<Quaternion> turned = <Quaternion>[
        for (final RigidBody die in tray.dice) die.orientation.clone(),
      ];
      final List<int> rolled = tray.faces;

      run(tray, motion, Tuning.readoutDelay + Tuning.readoutDuration + 0.1);
      expect(tray.readout.active, isTrue);
      for (int i = 0; i < tray.dice.length; i++) {
        expect(
          (tray.dice[i].position - landed[i]).length,
          greaterThan(tray.dice[i].circumradius),
          reason: 'die $i never left the floor',
        );
      }

      final List<Vector3> lifted = <Vector3>[
        for (final RigidBody die in tray.dice) die.position.clone(),
      ];

      tray.readout.putDown();
      // Halfway home: travelling, not teleporting. Off both ends of the
      // journey, and the tray half un-dimmed behind them.
      run(tray, motion, Tuning.readoutReturn / 2);
      expect(tray.readout.moving, isTrue);
      expect(tray.readout.progress, inExclusiveRange(0.0, 1.0));
      for (int i = 0; i < tray.dice.length; i++) {
        final double reach = tray.dice[i].circumradius;
        expect(
          (tray.dice[i].position - lifted[i]).length,
          greaterThan(reach),
          reason: 'die $i jumped straight home instead of travelling',
        );
        expect(
          (tray.dice[i].position - landed[i]).length,
          greaterThan(reach),
          reason: 'die $i was already home halfway through the journey',
        );
      }

      run(tray, motion, Tuning.readoutReturn / 2 + 0.1);

      expect(tray.readout.down, isTrue);
      expect(tray.readout.active, isFalse);
      expect(tray.readout.progress, 0.0);
      expect(
        tray.world.asleep,
        isTrue,
        reason: 'the dice were put down, not dropped',
      );

      for (int i = 0; i < tray.dice.length; i++) {
        final RigidBody die = tray.dice[i];
        expect(
          (die.position - landed[i]).length,
          lessThan(1e-12),
          reason: 'die $i did not come back to where it was thrown',
        );
        expect(
          die.orientation.asRotationMatrix().transformed(Vector3(1, 2, 3))
            ..sub(turned[i].asRotationMatrix().transformed(Vector3(1, 2, 3))),
          predicate<Vector3>((Vector3 v) => v.length < 1e-12),
          reason: 'die $i came back facing a different way',
        );
      }

      // And it reads the same as it did, because it is the same roll — now
      // read live off the dice again rather than from what was captured.
      expect(tray.readout.values, isNull);
      expect(tray.faces, rolled, reason: 'the roll changed on the way home');
    });

    test('a second tap lifts them again', () {
      final DiceTray tray = trayOf(<DieKind>[DieKind.d20, DieKind.d8]);
      final ManualMotionSource motion = ManualMotionSource();
      present(tray, motion);
      final List<int> shown = tray.faces;

      tray.readout.putDown();
      run(tray, motion, Tuning.readoutReturn + 0.1);
      expect(tray.readout.down, isTrue);

      // Left alone, they stay down — the readout does not pick them straight
      // back up the moment it notices they are at rest again.
      run(tray, motion, 2.0);
      expect(tray.readout.down, isTrue);
      expect(tray.readout.active, isFalse);

      tray.readout.pickUp();
      run(tray, motion, Tuning.readoutDelay + Tuning.readoutDuration + 0.1);
      expect(tray.readout.active, isTrue);
      expect(tray.faces, shown, reason: 'the roll changed on the way back up');
    });

    test('handing them straight back still puts them where they landed', () {
      final DiceTray tray = trayOf(<DieKind>[DieKind.d10, DieKind.d10]);
      final ManualMotionSource motion = ManualMotionSource();

      double t = 0;
      while (t < 12) {
        tray.update(motion.sample(kStep), kStep);
        t += kStep;
        if (t > 0.5 && tray.world.asleep) break;
      }
      final List<Vector3> landed = <Vector3>[
        for (final RigidBody die in tray.dice) die.position.clone(),
      ];
      run(tray, motion, Tuning.readoutDelay + Tuning.readoutDuration + 0.1);
      expect(tray.readout.active, isTrue);

      // What a shake gets: no journey home, but the same destination. This is
      // the call [DiceTray.update] makes the instant anything wakes the world,
      // so a scattered die is scattered from the spot it rolled to rather than
      // from wherever the formation had lifted it to.
      tray.readout.release();

      expect(tray.readout.active, isFalse);
      expect(tray.readout.values, isNull);
      for (int i = 0; i < tray.dice.length; i++) {
        expect(
          (tray.dice[i].position - landed[i]).length,
          lessThan(1e-12),
          reason: 'die $i was handed back from mid-air',
        );
      }
    });

    test('a shake takes the dice back off the readout', () {
      final DiceTray tray = trayOf(<DieKind>[DieKind.d20, DieKind.d20]);
      final ManualMotionSource motion = ManualMotionSource();
      present(tray, motion);
      expect(tray.readout.active, isTrue);

      final List<Vector3> held = <Vector3>[
        for (final RigidBody die in tray.dice) die.position.clone(),
      ];

      motion.shake();
      run(tray, motion, 0.1);

      expect(
        tray.readout.active,
        isFalse,
        reason: 'the formation survived a shake',
      );
      expect(
        tray.readout.values,
        isNull,
        reason: 'the captured numbers outlived the formation',
      );
      expect(tray.world.asleep, isFalse);

      run(tray, motion, 1.5);
      for (int i = 0; i < tray.dice.length; i++) {
        expect(
          (tray.dice[i].position - held[i]).length,
          greaterThan(tray.dice[i].circumradius),
          reason: 'die $i is still standing where the readout parked it',
        );
      }
    });

    test('a throw takes the dice back off the readout', () {
      final DiceTray tray = trayOf(<DieKind>[DieKind.d6, DieKind.d6]);
      present(tray, ManualMotionSource());
      expect(tray.readout.active, isTrue);

      tray.throwDice();
      expect(tray.readout.active, isFalse);
      expect(tray.readout.values, isNull);
    });

    test('turned off, the dice stay where they landed', () {
      final DiceTray tray = trayOf(<DieKind>[
        DieKind.d6,
        DieKind.d20,
      ], readout: false);
      final ManualMotionSource motion = ManualMotionSource();
      present(tray, motion);

      expect(tray.readout.active, isFalse);
      expect(tray.readout.progress, 0.0);

      final List<Vector3> resting = <Vector3>[
        for (final RigidBody die in tray.dice) die.position.clone(),
      ];
      run(tray, motion, 2.0);

      final double floor = -kHeight / 2;
      for (int i = 0; i < tray.dice.length; i++) {
        final RigidBody die = tray.dice[i];
        expect(
          (die.position - resting[i]).length,
          lessThan(1e-4),
          reason: 'die $i moved with the readout switched off',
        );
        expect(
          die.position.y - floor,
          lessThan(die.circumradius + 1e-3),
          reason: 'die $i is not on the floor of the tray',
        );
      }
    });
  });

  group('the picker', () {
    testWidgets('offers no choice about tidying up any more', (
      WidgetTester tester,
    ) async {
      // A phone, not the 800x600 the harness defaults to: the column this is
      // checking the bottom of is the one that has to fit a real screen.
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));

      // Every roll is presented now, so there is nothing left to ask about.
      expect(find.text('Tidy up to read'), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });
  });

  group('slerp', () {
    test('takes the short way round', () {
      final Quaternion a = Quaternion.axisAngle(Vector3(0, 0, 1), 0.2);
      // The same orientation as a small turn the other way, written the long
      // way round. Lerping towards it unnegated would sweep almost a full turn.
      final Quaternion b = Quaternion.axisAngle(Vector3(0, 0, 1), -0.2);
      final Quaternion far = Quaternion(-b.x, -b.y, -b.z, -b.w);

      final Vector3 v = Vector3(1, 0, 0);
      final Vector3 half = slerp(
        a,
        far,
        0.5,
      ).asRotationMatrix().transformed(v.clone());
      expect(
        half.angleTo(v),
        lessThan(0.21),
        reason: 'slerp went the long way round',
      );
    });

    test('ends where it was asked to', () {
      final Quaternion a = Quaternion.axisAngle(
        Vector3(1, 2, 3)..normalize(),
        2.4,
      );
      final Quaternion b = Quaternion.axisAngle(
        Vector3(-2, 1, 0.5)..normalize(),
        1.1,
      );
      final Vector3 v = Vector3(0.3, -0.7, 0.2);

      expect(
        slerp(a, b, 0)
            .asRotationMatrix()
            .transformed(v.clone())
            .distanceTo(a.asRotationMatrix().transformed(v.clone())),
        lessThan(1e-12),
      );
      expect(
        slerp(a, b, 1)
            .asRotationMatrix()
            .transformed(v.clone())
            .distanceTo(b.asRotationMatrix().transformed(v.clone())),
        lessThan(1e-12),
      );
    });
  });
}
