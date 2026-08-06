import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/physics/shape.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:vector_math/vector_math_64.dart';

/// Analytic inertia of a solid of mass 1 and circumradius R, as a multiple of
/// R², for the shapes that have a published closed form. A die whose inertia is
/// wrong is a loaded die, and the polyhedron decomposition that produces these
/// is the one part of the geometry that cannot be checked by looking at it.
const Map<DieKind, double> _knownInertia = <DieKind, double>{
  // Cube of side a: I = m a²/6, and R = a√3/2, so I = m (2R²/3) / 6 × 3 ... see
  // below — expressed against R² directly.
  DieKind.d6: 2.0 / 9.0, // a = 2R/√3 → I = m a²/6 = m (4R²/3)/6
  // Regular tetrahedron: I = m a²/20 with R = a√(3/8).
  DieKind.d4: 2.0 / 15.0, // a² = 8R²/3 → I = m (8R²/3)/20
  // Regular octahedron: I = m a²/10 with R = a/√2.
  DieKind.d8: 1.0 / 5.0, // a² = 2R² → I = m 2R²/10
};

void main() {
  test('every die is the solid it claims to be', () {
    const Map<DieKind, int> vertexCount = <DieKind, int>{
      DieKind.d4: 4,
      DieKind.d6: 8,
      DieKind.d8: 6,
      DieKind.d10: 12,
      DieKind.d12: 20,
      DieKind.d20: 12,
    };

    for (final DieKind kind in DieKind.values) {
      final ConvexShape shape = shapeFor(kind);
      expect(
        shape.faces.length,
        kind.sides,
        reason: '${kind.label} must have ${kind.sides} faces',
      );
      expect(shape.vertices.length, vertexCount[kind], reason: kind.label);

      // Isohedral: every face the same distance from the centre. The uniform
      // bevel shrink depends on this being exactly true.
      for (final ConvexFace face in shape.faces) {
        expect(
          face.normal.dot(shape.vertices[face.vertices.first]),
          closeTo(shape.inradius, shape.inradius * 1e-9),
          reason: '${kind.label} face planes must share one inradius',
        );
      }

      // Every vertex inside every face plane, which is what makes it convex and
      // what the separating-axis test assumes.
      for (final ConvexFace face in shape.faces) {
        for (final Vector3 v in shape.vertices) {
          expect(
            face.normal.dot(v),
            lessThanOrEqualTo(shape.inradius * (1 + 1e-9)),
            reason: '${kind.label} is not convex',
          );
        }
      }
    }
  });

  test('the faces are numbered like a real die', () {
    for (final DieKind kind in DieKind.values) {
      final ConvexShape shape = shapeFor(kind);
      final List<int> values = <int>[
        for (final ConvexFace f in shape.faces) f.value,
      ]..sort();
      expect(
        values,
        List<int>.generate(kind.sides, (int i) => i + 1),
        reason: '${kind.label} must carry 1…${kind.sides} exactly once',
      );

      if (kind == DieKind.d4) continue; // No face is opposite another.
      for (final ConvexFace face in shape.faces) {
        final ConvexFace opposite = shape.faces.firstWhere(
          (ConvexFace other) => other.normal.dot(face.normal) < -0.999,
        );
        expect(
          face.value + opposite.value,
          kind.sides + 1,
          reason: '${kind.label}: opposite faces must sum to ${kind.sides + 1}',
        );
      }
    }
  });

  test('the d6 still numbers its faces the way the pips are painted', () {
    final ConvexShape cube = shapeFor(DieKind.d6);
    for (int axis = 0; axis < 3; axis++) {
      for (final int sign in <int>[1, -1]) {
        final Vector3 normal = Vector3.zero()..[axis] = sign.toDouble();
        final ConvexFace face = cube.faces.firstWhere(
          (ConvexFace f) => f.normal.dot(normal) > 0.999,
        );
        expect(face.value, faceValue(axis, sign));
      }
    }
  });

  test('the d10 is a trapezohedron with ten flat kites', () {
    final ConvexShape d10 = shapeFor(DieKind.d10);
    for (final ConvexFace face in d10.faces) {
      expect(face.vertices.length, 4, reason: 'a kite has four corners');
    }
  });

  test('inertia matches the published tensors', () {
    for (final MapEntry<DieKind, double> entry in _knownInertia.entries) {
      final ConvexShape shape = shapeFor(entry.key);
      final double r2 = shape.circumradius * shape.circumradius;
      for (int k = 0; k < 3; k++) {
        expect(
          shape.inertiaPerMass[k] / r2,
          closeTo(entry.value, entry.value * 1e-6),
          reason: '${entry.key.label} inertia about axis $k',
        );
      }
    }
  });

  test('every die is balanced about the frame it is defined in', () {
    for (final DieKind kind in DieKind.values) {
      expect(
        offDiagonalInertia(shapeFor(kind)),
        lessThan(1e-9),
        reason:
            '${kind.label} keeps only the diagonal of its inertia tensor, '
            'which is only right if its own frame is a principal frame',
      );
    }
  });

  test('volume matches the closed forms', () {
    // Cube of side a = 2R/√3.
    final ConvexShape cube = shapeFor(DieKind.d6);
    final double a = 2 * cube.circumradius / math.sqrt(3);
    expect(cube.volume, closeTo(a * a * a, a * a * a * 1e-9));

    // Icosahedron: V = (5/12)(3+√5) a³, with R = (a/4)√(10+2√5).
    final ConvexShape d20 = shapeFor(DieKind.d20);
    final double edge = 4 * d20.circumradius / math.sqrt(10 + 2 * math.sqrt(5));
    expect(
      d20.volume,
      closeTo(
        (5 / 12) * (3 + math.sqrt(5)) * edge * edge * edge,
        d20.volume * 1e-9,
      ),
    );
  });

  test('a 16 mm d6 is still a 16 mm d6', () {
    final DieSpec spec = const DieSpec(kind: DieKind.d6, colour: kDiceWhite);
    expect(spec.shape.inradius, closeTo(Tuning.dieSize / 2, 1e-9));
    expect(spec.shape.bevel, closeTo(Tuning.dieBevel, 1e-9));
    expect(spec.mass * 1000, closeTo(4.8, 0.3), reason: 'about 4.8 grams');
  });
}
