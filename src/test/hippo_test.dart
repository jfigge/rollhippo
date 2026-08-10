import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/chrome.dart';
import 'package:rollhippo/app/picker_screen.dart';
import 'package:rollhippo/app/profile_row.dart';
import 'package:rollhippo/app/profiles.dart';
import 'package:rollhippo/physics/shape.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/render/hippo.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_math/vector_math_64.dart';

/// The dice the rack is showing. Scoped to dice mode, because card mode is
/// built at the same time one screen to the side and has dice of its own.
List<DieSpec> rack(WidgetTester tester) => <DieSpec>[
  for (final DiePreview preview in tester.widgetList<DiePreview>(
    find.descendant(
      of: find.byKey(kDicePage),
      matching: find.byType(DiePreview),
    ),
  ))
    preview.spec,
];

/// One of the kind chips, by the word on it.
Finder chip(String label) =>
    find.descendant(of: find.byKey(kDicePage), matching: find.text(label));

Future<void> pumpPicker(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(kHarnessScreen);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
  await tester.pumpAndSettle();
}

/// Keeps what is on screen under [name], the way a thumb would: the dashed
/// profile, the dialog, the name, Create.
Future<void> createSave(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(kNewProfile));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), name);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Create'));
  await tester.pumpAndSettle();
}

/// A profile holding one die of [kind], and nothing else.
Profile oneDie(DieKind kind) => Profile(
  mode: ProfileMode.dice,
  groups: <List<DieSpec>>[
    <DieSpec>[DieSpec(kind: kind, colour: kDiceWhite)],
    <DieSpec>[],
    <DieSpec>[],
  ],
  colours: const <int>[kDiceWhite],
  decks: 1,
  reshuffleAt: 0,
);

void main() {
  group('the animal', () {
    test('stays inside the die it is carved from', () {
      final ConvexShape shape = shapeFor(DieKind.hippo);
      for (final HippoLump lump in kHippo) {
        for (final Vector3 v in lump.vertices) {
          for (final ConvexFace face in shape.faces) {
            // In inradii, so a face plane is at 1 and anything past it is a
            // hippo poking out through the hull the tray collides with — which
            // would sink into the floor by exactly as much as it stuck out.
            expect(
              face.normal.dot(v),
              lessThanOrEqualTo(1 + 1e-9),
              reason: 'a lump reaches outside the die',
            );
          }
        }
      }
    });

    test('reaches every wall of it', () {
      // The other half of the same claim. Whichever face the die lands on is
      // the face the floor is against, so a hippopotamus that fell short of
      // one of its own six walls would hover above the floor every time it
      // landed that way up.
      for (final ConvexFace face in shapeFor(DieKind.hippo).faces) {
        expect(
          hippoReach(face.normal),
          greaterThan(0.99),
          reason: 'nothing on the animal touches one of its six walls',
        );
      }
    });

    test('is lit from outside', () {
      // Every lump's faces point away from the middle of that lump. The thing
      // this is really holding is [hippoToDie]: stand the animal up with a
      // reflection rather than a rotation and every normal comes out reversed,
      // which is a hippopotamus lit from within and shaded like a hole.
      for (final HippoLump lump in kHippo) {
        final Vector3 middle = Vector3.zero();
        for (final Vector3 v in lump.vertices) {
          middle.add(v);
        }
        middle.scale(1 / lump.vertices.length);

        for (int f = 0; f < kLumpFaces.length; f++) {
          final Vector3 corner = lump.vertices[kLumpFaces[f][0]];
          expect(
            lump.normals[f].dot(corner - middle),
            greaterThan(0),
            reason: 'a lump is inside out',
          );
        }
      }
    });
  });

  group('the die underneath', () {
    test('is the D6, exactly', () {
      final ConvexShape hippo = shapeFor(DieKind.hippo);
      final ConvexShape d6 = shapeFor(DieKind.d6);

      expect(hippo.faces.length, 6);
      expect(hippo.volume, closeTo(d6.volume, d6.volume * 1e-12));
      for (int f = 0; f < 6; f++) {
        expect(hippo.faces[f].value, d6.faces[f].value);
        expect(
          hippo.faces[f].normal.dot(d6.faces[f].normal),
          closeTo(1, 1e-12),
        );
      }
      // The one thing it does not share, and the whole reason it is a separate
      // shape: a hippopotamus has no faces to put pips on.
      expect(d6.usesPips, isTrue);
      expect(hippo.usesPips, isFalse);
    });
  });

  group('the pose it is presented in', () {
    /// The rotation the readout turns [value]'s face to the glass with.
    Matrix3 presenting(int value) {
      final ConvexShape shape = shapeFor(DieKind.hippo);
      final int face = shape.faces.indexWhere(
        (ConvexFace f) => f.value == value,
      );
      return markingToScreen(
        shape,
        DieMarking(face: face, edge: 0),
      ).asRotationMatrix();
    }

    test('stands it up in profile on the face that carries the six', () {
      // Which is the face the picker introduces every die by — see
      // [previewOrientation] — so this is the pose the rack shows, and the one
      // [hippoToDie] was chosen for.
      final Matrix3 rotation = presenting(6);
      expect(
        rotation.transformed(kHippoUp).dot(Vector3(0, 1, 0)),
        closeTo(1, 1e-9),
        reason: 'the animal is not the right way up on its own portrait',
      );
      expect(
        rotation.transformed(kHippoNose).dot(Vector3(0, 0, 1)).abs(),
        lessThan(1e-9),
        reason: 'the animal is not side on',
      );
    });

    test('and faces you on the face that carries the two', () {
      final Matrix3 rotation = presenting(2);
      expect(
        rotation.transformed(kHippoUp).dot(Vector3(0, 1, 0)),
        closeTo(1, 1e-9),
      );
      expect(
        rotation.transformed(kHippoNose).dot(Vector3(0, 0, 1)),
        closeTo(1, 1e-9),
        reason: 'the animal is not looking at you',
      );
    });
  });

  group('the easter egg', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await profiles.load();
    });

    testWidgets('is not in the rack until it is asked for by name', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      for (final DieKind kind in DieKind.values) {
        expect(
          chip(kind.label),
          kind.secret ? findsNothing : findsOneWidget,
          reason: '${kind.label} is on the wrong side of the secret',
        );
      }
    });

    testWidgets('comes out for a profile called hippo', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      // Trimmed and case-folded: it is a name somebody typed, and " Hippo "
      // is the same request as "hippo".
      await createSave(tester, ' Hippo ');

      expect(chip('Hippo'), findsOneWidget);

      await tester.tap(chip('Hippo'));
      await tester.pumpAndSettle();
      expect(rack(tester).first.kind, DieKind.hippo);
      // And the die says what it is, in the line above the chips.
      expect(chip('Die 1 — Hippo'), findsOneWidget);
    });

    testWidgets('and goes back in when you open something else', (
      WidgetTester tester,
    ) async {
      profiles.add('Yahtzee', oneDie(DieKind.d6));
      await pumpPicker(tester);
      await createSave(tester, 'hippo');
      expect(chip('Hippo'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(kProfileRow),
          matching: find.text('Yahtzee'),
        ),
      );
      await tester.pumpAndSettle();

      expect(chip('Hippo'), findsNothing);
      expect(rack(tester).single.kind, DieKind.d6);
    });

    testWidgets('but a die that is already one keeps its chip', (
      WidgetTester tester,
    ) async {
      // What you are left holding after a scanned code, or after renaming the
      // save you made it in. The picker has to be able to say what the die in
      // front of you is, whatever it is not offering.
      profiles.add('Someone Else', oneDie(DieKind.hippo));
      await pumpPicker(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(kProfileRow),
          matching: find.text('Someone Else'),
        ),
      );
      await tester.pumpAndSettle();

      expect(rack(tester).single.kind, DieKind.hippo);
      expect(chip('Hippo'), findsOneWidget);

      // Left it for a D6, and now there is nothing on screen that is one.
      await tester.tap(chip('D6'));
      await tester.pumpAndSettle();
      expect(chip('Hippo'), findsNothing);
    });
  });
}
