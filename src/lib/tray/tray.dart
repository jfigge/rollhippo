import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../motion/motion.dart';
import '../physics/body.dart';
import '../physics/collision.dart';
import '../physics/world.dart';
import 'dice.dart';
import 'reading.dart';
import 'readout.dart';
import 'tuning.dart';

export 'dice.dart';
export 'profile.dart';
export 'reading.dart';
export 'readout.dart';
export 'share_code.dart';
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

/// True when a motion frame is a deliberate shake rather than a hand doing its
/// best to hold the phone still.
///
/// Either test on its own misses half of what people actually do: a shake down
/// the length of the phone shows up in the accelerometer, and a flick of the
/// wrist barely moves the phone's centre at all but spins it hard. A tray of
/// dice should wake for both.
bool isShake(MotionFrame motion) =>
    motion.properAcceleration.length > Tuning.wakeAcceleration ||
    motion.angularVelocity.length > 3.0;

/// A tray of dice: the world, the dice in it, and the wiring from a
/// [MotionSource] to the forces inside.
class DiceTray {
  DiceTray({
    required this.width,
    required this.height,
    this.depth = Tuning.trayDepth,
    List<DieSpec>? dice,
    int diceCount = 2,
    bool readout = false,
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
    this.readout = Readout(
      dice: world.bodies,
      width: width,
      height: height,
      depth: depth,
      enabled: readout,
    );
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

  /// What the dice do once they have stopped: see [Readout].
  ///
  /// Off unless asked for. A bare [DiceTray] is a box with dice in it, and
  /// anything measuring where they came to rest — which is most of the test
  /// suite — is measuring a tray that does not tidy itself up afterwards. The
  /// app turns it on; so do the tools, which are showing the app.
  late final Readout readout;

  List<RigidBody> get dice => world.bodies;

  /// The dice the player has pinned, by index, each mapped to the face index
  /// it is holding.
  ///
  /// The index rather than the number, because putting a die back into the
  /// pose that shows that number needs [readMarking], and that works from the
  /// index. Keeping it at all is the same argument [Readout] makes for
  /// capturing its numbers once: a held die cannot fall over to re-read
  /// itself, so a live reading of one is a reading against a gravity that has
  /// nothing to do with the face it is resting on.
  final Map<int, int> held = <int, int>{};

  /// Whether the dice can be picked out right now.
  ///
  /// Only while the roll is being presented. Before that there is no result to
  /// keep, and the numbers a die would be held at do not exist yet.
  bool get canHold => readout.reading != null;

  /// Pins the die at [index], or lets it go again.
  ///
  /// Does nothing unless the roll is being presented — see [canHold].
  void toggleHold(int index) {
    if (index < 0 || index >= dice.length) return;
    if (held.remove(index) != null) {
      dice[index].held = false;
      return;
    }
    final List<int>? reading = readout.reading;
    if (reading == null) return;
    held[index] = reading[index];
    dice[index].held = true;
  }

  /// Lets every die go.
  void releaseHolds() {
    for (final int index in held.keys) {
      dice[index].held = false;
    }
    held.clear();
  }

  /// The face index each die is read off — the held one for a die that has
  /// been pinned, and a live reading for everything else.
  List<int> get readings => <int>[
    for (int i = 0; i < dice.length; i++) held[i] ?? readFace(dice[i], up),
  ];

  /// Throws the dice in from the top of the tray.
  ///
  /// They start along the top edge on a grid spaced by their own width, so any
  /// mixture of shapes packs without starting inside each other, and they leave
  /// with enough downward speed to reach the floor at between 2.2 and 2.8
  /// metres a second — hard enough to bounce back a visible fraction of the
  /// tray before they settle.
  ///
  /// A range rather than a figure, because a throw is not one number:
  /// [Tuning.throwSpeed] is the floor of it and the spread added below is what
  /// makes two throws in a row different, with the fall from the top of the
  /// tray on top of both. The constant's own comment quotes 2.3 m/s, which is
  /// the bottom of this range and is the right answer to a different
  /// question — what that number alone comes to, before anything is added to
  /// it. `dice_test.dart` measures the range so neither can drift again.
  void throwDice() {
    // Put every die back on the spot it landed on before anything else. The
    // ones about to be thrown are leaving that spot immediately and will never
    // know; the held ones are not being thrown at all, and this is how they end
    // up sitting where the roll left them rather than hanging in the middle of
    // the tray where the formation had lifted them to.
    readout.release();

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

    // Held dice take up no room on the spawn grid: the slot counter only
    // advances for a die that is actually being thrown, so keeping four of them
    // does not leave four gaps and bunch the rest into a corner.
    int slot = 0;
    for (int i = 0; i < dice.length; i++) {
      if (held.containsKey(i)) continue;
      final RigidBody die = dice[i];
      final int column = slot % columns;
      final int layer = (slot ~/ columns) % layers;
      final int row = slot ~/ (columns * layers);
      slot++;

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

    if (isShake(motion)) world.wake();

    // Anything at all that wakes the world takes the dice back off the
    // readout: the shake test just above, a throw, a key, a finger on the
    // glass. Catching it here rather than at each of those means there is one
    // place it can be got wrong instead of five.
    readout.advance(dt, atRest: world.asleep, reading: () => readings);

    // Real time goes to the sensors — angular acceleration is a physical rate
    // and has no business being scaled. Only the simulation is slowed.
    world.advance(dt * Tuning.timeScale);
  }

  /// Which way the sky is, inside the tray. Opposite the effective field, which
  /// is where "up" has to come from in a box that is only ever accelerating.
  Vector3 get up =>
      world.gravity.length2 > 1e-6
          ? -world.gravity.normalized()
          : Vector3(0, 0, 1);

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
  int faceUp(RigidBody die) => die.shape.faces[readFace(die, up)].value;

  /// What every die is showing, in tray order.
  ///
  /// Once the readout has laid the dice out these are the numbers it captured,
  /// not what the dice would read now. It has turned them since, and it turned
  /// them to show exactly these.
  List<int> get faces =>
      readout.values ??
      <int>[
        for (int i = 0; i < dice.length; i++)
          dice[i].shape.faces[readings[i]].value,
      ];
}
