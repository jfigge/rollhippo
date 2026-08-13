import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/haptics.dart';
import 'package:rollhippo/app/picker_screen.dart';
import 'package:rollhippo/app/settings.dart';
import 'package:rollhippo/physics/shape.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:vector_math/vector_math_64.dart'
    show Matrix3, Quaternion, Vector3;

/// The dice the rack is showing, left to right, top row then bottom.
List<DieSpec> rack(WidgetTester tester) => <DieSpec>[
  for (final DiePreview preview in tester.widgetList<DiePreview>(
    // Scoped to dice mode. Card mode is built at the same time, one screen to
    // the side, and it has dice of its own in it.
    find.descendant(
      of: find.byKey(kDicePage),
      matching: find.byType(DiePreview),
    ),
  ))
    preview.spec,
];

Future<void> tapDie(WidgetTester tester, int index) async {
  await tester.tap(
    find
        .descendant(
          of: find.byKey(kDicePage),
          matching: find.byType(DiePreview),
        )
        .at(index),
  );
  await tester.pump();
}

/// The dice panel's Remove — card mode, built one screen to the side, has one
/// of its own.
Future<void> tapRemove(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: find.byKey(kDicePage), matching: find.text('Remove')),
  );
  await tester.pump();
}

/// The palette swatch for one colour, in one mode's panel — a filled circle,
/// which is enough to tell it from every other [Container] on the screen.
///
/// Both modes have the whole palette in them and both are built at once, so a
/// swatch has to say which panel it belongs to the way the rack does.
Finder swatch(Key page, int colour) => find.descendant(
  of: find.byKey(page),
  matching: find.byWidgetPredicate(
    (Widget w) => w is Container && _fillOf(w) == Color(colour),
  ),
);

Future<void> tapText(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
}

/// Which slot of the first set has the ring round it: the die the panel below
/// is pointed at.
///
/// The panel's title used to say so in words — "Die 2" — and now names the set
/// instead, so the ring is the only place a selection is written down, which
/// is the whole reason the title stopped saying it. Read off the border rather
/// than through a key, because the ring is what a player is going by too.
int selectedDie(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byKey(const ValueKey<int>(0)),
        matching: find.byType(Container),
      ),
    )
    .toList()
    .indexWhere((Container slot) => _edgeOf(slot) == const Color(0xFF6E9AD0));

/// Puts a recorder in front of the phone's actuator for one test, and hands
/// it back. The picker's own taps do not go through a [HapticEngine] — there
/// is no impulse behind a press to weigh — so there is no engine to hand a
/// driver to. See [uiHaptic].
RecordedHaptics recordHaptics() {
  final RecordedHaptics driver = RecordedHaptics();
  debugUiHaptics = driver;
  addTearDown(() => debugUiHaptics = null);
  return driver;
}

/// The rack's plus: the empty slot the next die would land in, which is where
/// adding one is done.
///
/// Scoped to the first set. Card mode has a plus of its own one screen to the
/// side, and so does every group the page view has built.
final Finder diceAdd = find.descendant(
  of: find.byKey(const ValueKey<int>(0)),
  matching: find.byKey(kAddDie),
);

Future<void> tapAdd(WidgetTester tester) async {
  await tester.tap(diceAdd);
  await tester.pump();
}

void main() {
  group('the picker', () {
    testWidgets('shows one die per die, and starts on the first', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));

      expect(rack(tester).length, kDefaultDice.length);
      expect(selectedDie(tester), 0);
      // One set with anything in it, and you are on it.
      expect(find.text('Dice - Set 1/1'), findsOneWidget);
    });

    testWidgets('a colour lands on the selected die and nowhere else', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await tapDie(tester, 1);
      expect(selectedDie(tester), 1);

      const int red = 0xFFB3453F;
      await tester.tap(swatch(kDicePage, red));
      await tester.pump();

      expect(rack(tester)[0].colour, kDiceWhite);
      expect(rack(tester)[1].colour, red);
    });

    testWidgets('selecting another die drops the first', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await tapDie(tester, 1);
      await tapText(tester, 'D20');
      await tapDie(tester, 0);
      await tapText(tester, 'D4');

      expect(rack(tester)[0].kind, DieKind.d4);
      expect(rack(tester)[1].kind, DieKind.d20);
      expect(selectedDie(tester), 0);
    });

    testWidgets('a new die arrives selected, matching the one before it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await tapDie(tester, 1);
      await tapText(tester, 'D12');
      await tapAdd(tester);

      expect(rack(tester).length, 3);
      expect(rack(tester)[2].kind, DieKind.d12);
      expect(selectedDie(tester), 2);

      // The editor now points at the new die, so this only moves that one.
      await tapText(tester, 'D8');
      expect(rack(tester)[1].kind, DieKind.d12);
      expect(rack(tester)[2].kind, DieKind.d8);
    });

    testWidgets('the rack fills to ten and stops', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      for (int i = kDefaultDice.length; i < kMaxDice; i++) {
        await tapAdd(tester);
      }
      expect(rack(tester).length, kMaxDice);
      // And there it stops, because there is nothing left to ask with: the
      // plus is a slot, and a full rack has no slot to spare.
      expect(diceAdd, findsNothing);
    });

    testWidgets('removing selects a die that still exists', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await tapDie(tester, 1);
      await tapRemove(tester);

      expect(rack(tester).length, 1);
      expect(selectedDie(tester), 0);

      // The last die is the set, and cannot be taken away.
      await tapRemove(tester);
      expect(rack(tester).length, 1);
    });
  });

  group('the taps the editor makes', () {
    testWidgets('one for every press on the rack or the panel, all light', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      final RecordedHaptics taps = recordHaptics();

      // Every one of these is the same kind of act — a press that arranges
      // the set, or says which die the arranging is about — so they are
      // answered the same way, and none of them is the firmer tap: the rack
      // and the chips say what happened, and the hand is only agreeing. See
      // [uiHaptic].
      await tapDie(tester, 1);
      await tester.tap(swatch(kDicePage, 0xFFB3453F));
      await tester.pump();
      await tapText(tester, 'D8');
      await tapAdd(tester);
      await tapRemove(tester);

      expect(taps.fired, List<HapticLevel>.filled(5, HapticLevel.light));
    });

    testWidgets('including the one press that changes nothing about the set', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      final RecordedHaptics taps = recordHaptics();

      // Selecting moves a ring one slot wide and nothing else, on the part of
      // the screen a thumb is covering. It is the press with least to show for
      // itself, which is why it is answered rather than in spite of it.
      await tapDie(tester, 1);
      expect(selectedDie(tester), 1);
      expect(rack(tester).length, 2, reason: 'nothing about the set moved');
      expect(taps.fired, <HapticLevel>[HapticLevel.light]);

      // And the die already selected is still a press, and still says so.
      await tapDie(tester, 1);
      expect(taps.fired.length, 2);
    });

    testWidgets('and none for a press it turns down', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await tapRemove(tester);
      final RecordedHaptics taps = recordHaptics();

      // One die left, which is the set: Remove is greyed out and does nothing.
      // A tap for it would be the phone agreeing to something it declined.
      await tapRemove(tester);
      expect(rack(tester).length, 1);
      expect(taps.fired, isEmpty);
    });

    testWidgets('and none at all with the calibration turned off', (
      WidgetTester tester,
    ) async {
      final double was = settings.hapticGain;
      addTearDown(() => settings.hapticGain = was);
      settings.hapticGain = 0;

      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      final RecordedHaptics taps = recordHaptics();

      await tester.tap(swatch(kDicePage, 0xFFB3453F));
      await tester.pump();
      await tapText(tester, 'D8');

      // The slider is described against the tray and is still the only switch
      // there is. Off is a word with one meaning.
      expect(rack(tester)[0].kind, DieKind.d8);
      expect(taps.fired, isEmpty);
    });
  });

  group('the preview angle', () {
    test('turns the highest number towards you, the right way up', () {
      for (final DieKind kind in DieKind.values) {
        final ConvexShape shape = shapeFor(kind);
        // Through [previewFor] rather than [previewOrientation], because the
        // hippopotamus is introduced at an angle of its own and what is being
        // held here is the promise the rack makes, not the search that
        // usually keeps it.
        //
        // The matrix, not `Quaternion.rotated`: the two run opposite ways
        // round in vector_math, and the matrix is what the painter sees.
        final Quaternion q = previewFor(kind);
        final Matrix3 rotation = q.asRotationMatrix();

        int highest = 0;
        for (int f = 1; f < shape.faces.length; f++) {
          if (shape.faces[f].value > shape.faces[highest].value) highest = f;
        }
        expect(shape.faces[highest].value, kind.numbers.last);

        // Which face actually has that number written on it, which is the one
        // carrying it everywhere but the D4 — a D4 prints its numbers along
        // the edges of the three faces *around* the one they name, so the face
        // to show is a neighbour and the number is on the edge they share.
        final DieMarking marking = readMarking(shape, highest);
        final int front = marking.face;
        final ConvexFace face = shape.faces[front];
        final int corners = face.vertices.length;
        expect(
          shape.readsDownFace
              ? shape.faces[face.neighbours[marking.edge]].value
              : face.value,
          kind.numbers.last,
          reason:
              '${kind.label} is not introducing itself with a '
              '${kind.numbers.last} anywhere you can see',
        );

        // No face leans further out of the screen than the one being shown.
        final List<Vector3> normals = <Vector3>[
          for (final ConvexFace face in shape.faces)
            rotation.transformed(face.normal),
        ];
        for (int f = 0; f < normals.length; f++) {
          if (f == front) continue;
          expect(
            normals[f].z,
            lessThan(normals[front].z),
            reason: '${kind.label} is showing the wrong face',
          );
        }

        // And it is tilted, not square on: you can see round it.
        expect(
          normals.where((Vector3 n) => n.z > 0).length,
          greaterThanOrEqualTo(2),
          reason: '${kind.label} reads as a flat shape, not a solid',
        );

        // Text runs along the edge the number is written on and stands up
        // towards `normal × along` — see [paintDie] — so on screen, where x is
        // right and y is up, that direction has to come out plumb. Plumb and
        // *upwards* also puts the edge below the middle of the face, which is
        // where a D4 wears its numbers.
        final Vector3 along = rotation.transformed(
          shape.vertices[face.vertices[(marking.edge + 1) % corners]] -
              shape.vertices[face.vertices[marking.edge]],
        )..normalize();
        final Vector3 up = normals[front].cross(along);
        expect(
          up.x,
          closeTo(0, 1e-9),
          reason: '${kind.label} is showing its number off the vertical',
        );
        expect(
          up.y,
          greaterThan(0),
          reason: '${kind.label} is showing its number upside down',
        );
      }
    });
  });
}

/// The colour a [Container] is filled with, whatever shape it is.
Color? _fillOf(Container container) {
  final Decoration? decoration = container.decoration;
  return decoration is BoxDecoration ? decoration.color : null;
}

/// The colour a [Container] is edged with — every slot in the rack has a
/// border, and only the selected one has that border in blue.
Color? _edgeOf(Container container) {
  final Decoration? decoration = container.decoration;
  final BoxBorder? border =
      decoration is BoxDecoration ? decoration.border : null;
  return border is Border ? border.top.color : null;
}
