import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../motion/motion.dart';
import '../physics/body.dart';
import '../physics/collision.dart';
import '../physics/world.dart';
import 'dice.dart';
import 'tuning.dart';

export 'dice.dart';
export 'tuning.dart';

/// The six inward-facing planes of a tray `width` × `height` × `depth`.
///
/// The tray is axis-aligned and centred on x and y, with the glass at z = 0 and
/// the back at z = -depth — so screen space and tray space share an origin and
/// the projection has nothing to undo.
List<Wall> trayWalls({
  required double width,
  required double height,
  required double depth,
}) {
  Wall wall(
    Vector3 normal,
    double offset,
    double restitution,
    double friction,
  ) => Wall(
    normal: normal,
    offset: offset,
    restitution: restitution,
    friction: friction,
  );

  const double r = Tuning.wallRestitution;
  const double f = Tuning.wallFriction;
  return <Wall>[
    wall(Vector3(1, 0, 0), -width / 2, r, f), // left
    wall(Vector3(-1, 0, 0), -width / 2, r, f), // right
    wall(Vector3(0, 1, 0), -height / 2, r, f), // bottom
    wall(Vector3(0, -1, 0), -height / 2, r, f), // top
    wall(Vector3(0, 0, 1), -depth, r, f), // back
    wall(Vector3(0, 0, -1), 0, Tuning.glassRestitution, Tuning.glassFriction),
  ];
}

/// A tray of dice: the world, the dice in it, and the wiring from a
/// [MotionSource] to the forces inside.
class DiceTray {
  DiceTray({
    required this.width,
    required this.height,
    this.depth = Tuning.trayDepth,
    List<DieSpec>? dice,
    int diceCount = 2,
    math.Random? random,
  }) : specs = List<DieSpec>.unmodifiable(
         dice ??
             List<DieSpec>.generate(
               diceCount,
               (_) => const DieSpec(kind: DieKind.d6, colour: kDiceWhite),
             ),
       ),
       _random = random ?? math.Random() {
    world = PhysicsWorld(
      walls: trayWalls(width: width, height: height, depth: depth),
    );
    for (final DieSpec spec in specs) {
      world.bodies.add(
        RigidBody(
          shape: spec.shape,
          mass: spec.mass,
          restitution: Tuning.dieRestitution,
          friction: Tuning.dieFriction,
        ),
      );
    }
    throwDice();
  }

  final double width;
  final double height;
  final double depth;

  /// What each die is — its shape and its colour — in the same order as
  /// [dice]. The physics has no opinion about colour, so it lives here.
  final List<DieSpec> specs;

  final math.Random _random;

  late final PhysicsWorld world;

  List<RigidBody> get dice => world.bodies;

  /// Throws the dice in from the top of the tray.
  ///
  /// They start along the top edge on a grid spaced by their own width, so any
  /// mixture of shapes packs without starting inside each other, and they leave
  /// with enough downward speed to reach the floor at about 1.9 m/s — hard
  /// enough to bounce back a visible fraction of the tray before they settle.
  void throwDice() {
    double reach = 0;
    for (final RigidBody die in dice) {
      reach = math.max(reach, die.circumradius);
    }
    final double spacing = 2.05 * reach;

    // The band of depth the dice are launched into: the middle half of the
    // tray, so none of them start flat against the glass or lost at the back.
    final double bandNear = -depth * 0.25;
    final double bandFar = -depth * 0.75;

    final int columns = math.max(
      1,
      ((width - 2 * reach) / spacing).floor() + 1,
    );
    final int layers = math.max(
      1,
      ((bandNear - bandFar).abs() / spacing).floor() + 1,
    );

    double jitter(double scale) => (_random.nextDouble() - 0.5) * scale;

    for (int i = 0; i < dice.length; i++) {
      final RigidBody die = dice[i];
      final int column = i % columns;
      final int layer = (i ~/ columns) % layers;
      final int row = i ~/ (columns * layers);

      final double x =
          columns == 1
              ? 0.0
              : -(width / 2 - reach) +
                  column * (width - 2 * reach) / (columns - 1);
      final double z =
          layers == 1
              ? (bandNear + bandFar) / 2
              : bandNear + layer * (bandFar - bandNear) / (layers - 1);

      die.position = Vector3(
        x + jitter(reach * 0.3),
        height / 2 - reach - row * spacing,
        z + jitter(reach * 0.3),
      );
      die.orientation = _randomOrientation();
      die.velocity.setValues(
        jitter(0.3),
        -(Tuning.throwSpeed + _random.nextDouble() * 0.6),
        jitter(0.3),
      );
      die.angularVelocity.setValues(
        jitter(2 * Tuning.throwSpin),
        jitter(2 * Tuning.throwSpin),
        jitter(2 * Tuning.throwSpin),
      );
      die.syncDerived();
    }
    world.wake();
  }

  Quaternion _randomOrientation() {
    // Shoemake's uniform random quaternion — an even spread over orientations,
    // rather than the pole-heavy one you get from random Euler angles.
    final double u1 = _random.nextDouble();
    final double u2 = _random.nextDouble();
    final double u3 = _random.nextDouble();
    final double a = math.sqrt(1 - u1);
    final double b = math.sqrt(u1);
    return Quaternion(
      a * math.sin(2 * math.pi * u2),
      a * math.cos(2 * math.pi * u2),
      b * math.sin(2 * math.pi * u3),
      b * math.cos(2 * math.pi * u3),
    )..normalize();
  }

  /// Feeds one sensor frame into the world and advances by [dt].
  void update(MotionFrame motion, double dt) {
    // The effective field inside the tray: the negated accelerometer reading,
    // with the gravity half of it scaled. At [Tuning.gravityScale] of 1 this is
    // exactly `-properAcceleration` and the tray is a box on Earth.
    Vector3 field =
        -(motion.gravityReading * Tuning.gravityScale +
            motion.linearAcceleration);
    final double magnitude = field.length;
    if (magnitude > Tuning.maxFieldMagnitude) {
      field = field * (Tuning.maxFieldMagnitude / magnitude);
    }
    world.gravity.setFrom(field);
    world.trayAngularVelocity.setFrom(motion.angularVelocity);
    world.trayAngularAcceleration.setFrom(motion.angularAcceleration);

    if (motion.properAcceleration.length > Tuning.wakeAcceleration ||
        motion.angularVelocity.length > 3.0) {
      world.wake();
    }

    // Real time goes to the sensors — angular acceleration is a physical rate
    // and has no business being scaled. Only the simulation is slowed.
    world.advance(dt * Tuning.timeScale);
  }

  /// The number showing on top, where "up" is opposite the current field.
  ///
  /// Reading the die off its actual orientation rather than choosing a number
  /// and animating towards it is the whole point of simulating in 3D: the face
  /// you see is the face the physics landed on.
  ///
  /// A D4 is read the other way up. A tetrahedron at rest has a *vertex*
  /// pointing at the sky and no face at all, so the number it rolled is the one
  /// on the face it is sitting on — which is why a real D4 prints that number
  /// along the bottom edge of the three faces you can see.
  int faceUp(RigidBody die) {
    final Vector3 up =
        world.gravity.length2 > 1e-6
            ? -world.gravity.normalized()
            : Vector3(0, 0, 1);
    final Vector3 towards = die.shape.readsDownFace ? -up : up;

    int best = 1;
    double bestDot = double.negativeInfinity;
    for (int f = 0; f < die.shape.faces.length; f++) {
      final double d = die.faceNormal(f).dot(towards);
      if (d > bestDot) {
        bestDot = d;
        best = die.shape.faces[f].value;
      }
    }
    return best;
  }

  /// What every die is showing, in tray order.
  List<int> get faces => <int>[for (final RigidBody die in dice) faceUp(die)];
}
