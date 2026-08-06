import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/config_screen.dart';
import 'package:rollhippo/physics/shape.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:vector_math/vector_math_64.dart'
    show Matrix3, Quaternion, Vector3;

/// The dice the rack is showing, left to right, top row then bottom.
List<DieSpec> rack(WidgetTester tester) => <DieSpec>[
  for (final DiePreview preview in tester.widgetList<DiePreview>(
    find.byType(DiePreview),
  ))
    preview.spec,
];

Future<void> tapDie(WidgetTester tester, int index) async {
  await tester.tap(find.byType(DiePreview).at(index));
  await tester.pump();
}

Future<void> tapText(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
}

void main() {
  group('the picker', () {
    testWidgets('shows one die per die, and starts on the first', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));

      expect(rack(tester).length, kDefaultDice.length);
      expect(find.text('Die 1 — D6'), findsOneWidget);
    });

    testWidgets('a colour lands on the selected die and nowhere else', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tapDie(tester, 1);
      expect(find.text('Die 2 — D6'), findsOneWidget);

      const int red = 0xFFB3453F;
      await tester.tap(
        find.byWidgetPredicate(
          (Widget w) => w is Container && _fillOf(w) == const Color(red),
        ),
      );
      await tester.pump();

      expect(rack(tester)[0].colour, kDiceWhite);
      expect(rack(tester)[1].colour, red);
    });

    testWidgets('selecting another die drops the first', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tapDie(tester, 1);
      await tapText(tester, 'D20');
      await tapDie(tester, 0);
      await tapText(tester, 'D4');

      expect(rack(tester)[0].kind, DieKind.d4);
      expect(rack(tester)[1].kind, DieKind.d20);
      expect(find.text('Die 1 — D4'), findsOneWidget);
    });

    testWidgets('a new die arrives selected, matching the one before it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tapDie(tester, 1);
      await tapText(tester, 'D12');
      await tapText(tester, 'Add a die');

      expect(rack(tester).length, 3);
      expect(rack(tester)[2].kind, DieKind.d12);
      expect(find.text('Die 3 — D12'), findsOneWidget);

      // The editor now points at the new die, so this only moves that one.
      await tapText(tester, 'D8');
      expect(rack(tester)[1].kind, DieKind.d12);
      expect(rack(tester)[2].kind, DieKind.d8);
    });

    testWidgets('the rack fills to ten and stops', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      for (int i = kDefaultDice.length; i < kMaxDice + 3; i++) {
        await tapText(tester, 'Add a die');
      }
      expect(rack(tester).length, kMaxDice);
    });

    testWidgets('removing selects a die that still exists', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tapDie(tester, 1);
      await tapText(tester, 'Remove');

      expect(rack(tester).length, 1);
      expect(find.text('Die 1 — D6'), findsOneWidget);

      // The last die is the set, and cannot be taken away.
      await tapText(tester, 'Remove');
      expect(rack(tester).length, 1);
    });
  });

  group('the preview angle', () {
    test('turns the highest number towards you, the right way up', () {
      for (final DieKind kind in DieKind.values) {
        final ConvexShape shape = shapeFor(kind);
        // The matrix, not `Quaternion.rotated`: the two run opposite ways
        // round in vector_math, and the matrix is what the painter sees.
        final Quaternion q = previewOrientation(shape);
        final Matrix3 rotation = q.asRotationMatrix();

        int front = 0;
        for (int f = 1; f < shape.faces.length; f++) {
          if (shape.faces[f].value > shape.faces[front].value) front = f;
        }
        expect(shape.faces[front].value, kind.sides);

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

        // Text on that face runs along its first edge and stands up towards
        // `normal × along` — see [paintDie] — so on screen, where x is right
        // and y is up, that direction has to come out plumb.
        final ConvexFace face = shape.faces[front];
        final Vector3 along = rotation.transformed(
          shape.vertices[face.vertices[1]] - shape.vertices[face.vertices[0]],
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
