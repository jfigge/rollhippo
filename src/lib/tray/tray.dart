import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../motion/motion.dart';
import '../physics/body.dart';
import '../physics/collision.dart';
import '../physics/world.dart';

/// Everything with a number in it, in one place, in SI units.
///
/// The simulation is metric and life-sized on purpose. A 16 mm die weighing
/// 4.8 g falling under 9.81 m/s² inside a 5 cm box behaves like a 16 mm die
/// because it *is* one, and every constant below can be checked against a real
/// object rather than tuned until it looks about right.
class Tuning {
  /// Logical Flutter pixels per metre of real screen.
  ///
  /// Every modern iPhone lays out at very close to 155 logical points per inch
  /// — a 15 Pro is 393 pt across 64.4 mm, a 15 Pro Max 430 pt across 70.6 mm —
  /// so one constant sizes the tray correctly on all of them without asking the
  /// platform for a physical measurement it does not expose.
  static const double logicalPixelsPerMetre = 6100.0;

  /// Tray depth. Deep enough that the dice have somewhere to go in z, which is
  /// what stops a shake reading as a flat scramble.
  static const double trayDepth = 0.10;

  /// A standard 16 mm casino-size D6.
  static const double dieSize = 0.016;

  /// Corner bevel. Real dice are rounded; see [RigidBox] for why this matters
  /// more than its size suggests.
  static const double dieBevel = 0.0013;

  /// Cast acrylic, ~1180 kg/m³, so a 16 mm die comes out at 4.8 g — which is
  /// what a 16 mm die weighs.
  static const double dieDensity = 1180.0;

  static const double dieRestitution = 0.38;
  static const double dieFriction = 0.42;

  /// The tray lining. Deader than the dice, so a die dropped on it does not
  /// pogo, but not so dead that a shake feels like stirring porridge.
  static const double wallRestitution = 0.28;
  static const double wallFriction = 0.5;

  /// The pane you are looking through. Slightly livelier than the lining and
  /// nearly frictionless, so a die that gets thrown forward skates off it
  /// rather than sticking to the glass.
  static const double glassRestitution = 0.4;
  static const double glassFriction = 0.08;

  /// How far the eye sits from the glass. Real reading distance, which makes
  /// the perspective inside the tray the perspective you would actually see.
  static const double eyeDistance = 0.32;

  /// Fraction of real gravity the dice fall under.
  ///
  /// Below 1 the dice hang longer, tumble further per bounce and settle more
  /// slowly — a bigger tray than the phone really is. It scales *only* the
  /// steady pull: a shake still hits with the full force your hand put into it,
  /// exactly as it would on a smaller planet. Turning this down is not the same
  /// as turning the whole field down, which would just make everything slower.
  static const double gravityScale = 0.6;

  /// How fast simulated time runs against real time.
  ///
  /// Below 1 everything is slower without anything moving differently: the
  /// trajectories are identical, just played back at this rate. That is what
  /// separates it from turning gravity down, which changes the shape of the
  /// arcs as well as the pace of them.
  static const double timeScale = 0.85;

  /// Accelerometer magnitude beyond which we call it a shake and wake the dice.
  static const double wakeAcceleration = 12.5;

  /// Sensor readings are clamped here before becoming forces. A dropped phone
  /// or a sensor glitch should not launch the dice into next week.
  static const double maxFieldMagnitude = 70.0;
}

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
    int diceCount = 2,
    math.Random? random,
  }) : _random = random ?? math.Random() {
    world = PhysicsWorld(
      walls: trayWalls(width: width, height: height, depth: depth),
    );
    for (int i = 0; i < diceCount; i++) {
      world.bodies.add(_makeDie());
    }
    scatter();
  }

  final double width;
  final double height;
  final double depth;
  final math.Random _random;

  late final PhysicsWorld world;

  List<RigidBox> get dice => world.bodies;

  RigidBox _makeDie() {
    const double half = Tuning.dieSize / 2;
    final double volume = math.pow(Tuning.dieSize, 3).toDouble();
    return RigidBox(
      halfExtents: Vector3.all(half),
      mass: volume * Tuning.dieDensity,
      radius: Tuning.dieBevel,
      restitution: Tuning.dieRestitution,
      friction: Tuning.dieFriction,
    );
  }

  /// Drops the dice in from random positions and orientations, mid-depth so
  /// they have room to fall.
  void scatter() {
    final double margin = Tuning.dieSize;
    for (int i = 0; i < dice.length; i++) {
      final RigidBox die = dice[i];
      // Spread across the width, high up, so they fall and tumble on landing
      // rather than appearing already at rest.
      final double slot = (i + 0.5) / dice.length;
      die.position = Vector3(
        (slot - 0.5) * (width - 2 * margin),
        height / 2 - margin - _random.nextDouble() * margin,
        -depth / 2,
      );
      die.orientation = _randomOrientation();
      die.velocity.setZero();
      die.angularVelocity.setValues(
        _random.nextDouble() * 8 - 4,
        _random.nextDouble() * 8 - 4,
        _random.nextDouble() * 8 - 4,
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

  /// The pip value showing on top, where "up" is opposite the current field.
  ///
  /// Reading the die off its actual orientation rather than choosing a number
  /// and animating towards it is the whole point of simulating in 3D: the face
  /// you see is the face the physics landed on.
  int faceUp(RigidBox die) {
    final Vector3 up =
        world.gravity.length2 > 1e-6
            ? -world.gravity.normalized()
            : Vector3(0, 0, 1);
    int best = 1;
    double bestDot = -2.0;
    for (int k = 0; k < 3; k++) {
      final Vector3 axis = die.axis(k);
      final double d = axis.dot(up);
      if (d > bestDot) {
        bestDot = d;
        best = faceValue(k, 1);
      }
      if (-d > bestDot) {
        bestDot = -d;
        best = faceValue(k, -1);
      }
    }
    return best;
  }
}

/// Pip value of the face whose outward local normal is [sign] on axis [axis].
///
/// +x is 1, +y is 2, +z is 3 and opposite faces sum to seven, which is the
/// standard right-handed western die: looking in at the corner where 1, 2 and 3
/// meet, they read anticlockwise.
int faceValue(int axis, int sign) {
  const List<int> positive = <int>[1, 2, 3];
  final int value = positive[axis];
  return sign > 0 ? value : 7 - value;
}
