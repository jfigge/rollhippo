import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/physics/body.dart';
import 'package:rollhippo/physics/shape.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:vector_math/vector_math_64.dart';

/// The world-space direction text on [marking] runs along, and the direction it
/// stands up towards — the same two vectors [paintDie] builds its glyph
/// transform from, so this is what the reader will actually see.
({Vector3 along, Vector3 up}) marked(RigidBody die, DieMarking marking) {
  final ConvexFace face = die.shape.faces[marking.face];
  final int corners = face.vertices.length;
  final Vector3 p = die.outerVertex(face.vertices[marking.edge]);
  final Vector3 q = die.outerVertex(
    face.vertices[(marking.edge + 1) % corners],
  );
  final Vector3 along = (q - p)..normalize();
  return (along: along, up: die.faceNormal(marking.face).cross(along));
}

RigidBody posed(DieKind kind, Quaternion orientation) =>
    RigidBody(shape: shapeFor(kind), mass: 1.0, orientation: orientation);

void main() {
  group('turning a die to be read', () {
    test('every kind puts its number square to the glass', () {
      for (final DieKind kind in DieKind.values) {
        final ConvexShape shape = shapeFor(kind);
        for (int read = 0; read < shape.faces.length; read++) {
          final DieMarking marking = readMarking(shape, read);
          final RigidBody die = posed(kind, markingToScreen(shape, marking));

          expect(
            die.faceNormal(marking.face).z,
            closeTo(1.0, 1e-9),
            reason: '${kind.label} face $read is not facing the eye',
          );
          expect(
            marked(die, marking).up.y,
            closeTo(1.0, 1e-9),
            reason:
                '${kind.label} face $read is showing its number on its side',
          );
        }
      }
    });

    test('a d4 shows the face it is resting on, along the shared edge', () {
      final ConvexShape shape = shapeFor(DieKind.d4);
      for (int read = 0; read < shape.faces.length; read++) {
        final DieMarking marking = readMarking(shape, read);

        expect(
          marking.face,
          isNot(read),
          reason: 'a D4 cannot show the face it is sitting on',
        );
        expect(
          shape.faces[marking.face].neighbours[marking.edge],
          read,
          reason:
              'the levelled edge must be the one carrying the rolled number',
        );

        // The number is drawn along that edge, so the edge has to lie level and
        // below the middle of the face — which is where it sits on a real D4.
        final RigidBody die = posed(
          DieKind.d4,
          markingToScreen(shape, marking),
        );
        final ({Vector3 along, Vector3 up}) basis = marked(die, marking);
        expect(
          basis.along.y.abs(),
          lessThan(1e-9),
          reason: 'the edge is not level',
        );

        final ConvexFace face = shape.faces[marking.face];
        final Vector3 p = die.outerVertex(face.vertices[marking.edge]);
        final Vector3 q = die.outerVertex(
          face.vertices[(marking.edge + 1) % 3],
        );
        expect(
          ((p + q) * 0.5).y,
          lessThan(die.faceCentre(marking.face).y),
          reason: 'the number is above the middle of the face, not below it',
        );
      }
    });

    test('tipping back keeps the number upright', () {
      const double tilt = 0.26;
      for (final DieKind kind in DieKind.values) {
        final ConvexShape shape = shapeFor(kind);
        final DieMarking marking = readMarking(shape, 0);
        final RigidBody die = posed(
          kind,
          markingToScreenTilted(shape, marking, tilt),
        );

        final Vector3 normal = die.faceNormal(marking.face);
        expect(
          normal.y,
          closeTo(math.sin(tilt), 1e-9),
          reason: '${kind.label} is not tipped back by the angle asked for',
        );
        expect(normal.z, closeTo(math.cos(tilt), 1e-9));

        final Vector3 up = marked(die, marking).up;
        expect(
          math.atan2(up.x, up.y).abs(),
          lessThan(1e-9),
          reason: '${kind.label} leans once it is tipped',
        );
      }
    });

    test('readFace reads the same number faceUp does', () {
      final DiceTray tray = DiceTray(
        width: 393 / Tuning.logicalPixelsPerMetre,
        height: 852 / Tuning.logicalPixelsPerMetre,
        dice: <DieSpec>[
          for (final DieKind kind in DieKind.values)
            DieSpec(kind: kind, colour: kDiceWhite),
        ],
        random: math.Random(3),
      );
      final Vector3 up = -tray.world.gravity.normalized();
      for (final RigidBody die in tray.dice) {
        expect(die.shape.faces[readFace(die, up)].value, tray.faceUp(die));
      }
    });
  });
}
