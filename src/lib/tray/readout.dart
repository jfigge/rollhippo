import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../physics/body.dart';
import 'reading.dart';
import 'tuning.dart';

/// What the dice do once they have stopped.
///
/// Held upright, a phone puts "up" along the top of the screen, so a die that
/// has settled is showing its number to the ceiling and its edge to you. The
/// number is genuinely there and genuinely unreadable. So once the world goes
/// to sleep the dice are lifted off the floor of the tray, turned until the
/// face they landed on is square to the glass, and laid out on a grid.
///
/// This is not the thing the README warns against. Nothing is *chosen* here:
/// the face is read off the orientation the physics arrived at, exactly as
/// [DiceTray.faceUp] reads it, and only then is the die turned so you can see
/// what it already says. The numbers are captured once, at the moment the
/// formation is laid out, and held — recomputing them afterwards would read a
/// die that has since been turned, against a gravity that no longer points at
/// the floor it was resting on.
///
/// Anything that wakes the world hands the dice straight back to the solver
/// from wherever they had got to. Their velocities are already zero, so they
/// simply drop out of formation, which is what a tray of dice being picked up
/// mid-read would do.
class Readout {
  Readout({
    required this.dice,
    required this.width,
    required this.height,
    required this.depth,
    this.enabled = true,
  });

  /// The bodies this poses, in tray order. The same list [DiceTray] holds.
  final List<RigidBody> dice;

  final double width;
  final double height;
  final double depth;

  /// Whether settled dice tidy themselves up at all. Off leaves them where
  /// they landed, which is the right answer for a phone lying flat — there,
  /// "up" is already out through the glass and the dice can be read as they
  /// lie.
  bool enabled;

  _Phase _phase = _Phase.idle;
  double _elapsed = 0;

  final List<_Move> _moves = <_Move>[];
  List<int>? _values;

  /// True once the dice have started moving into formation, and until they are
  /// back down.
  bool get active =>
      _phase == _Phase.moving ||
      _phase == _Phase.showing ||
      _phase == _Phase.returning;

  /// True only while the dice are actually travelling, either way.
  ///
  /// Narrower than [active], and for a different question: [active] asks
  /// whether the formation is what you are looking at, this asks whether it is
  /// safe to stop advancing the tray. Freezing a die halfway between where it
  /// landed and where it is going leaves it hanging in mid-air, and that is as
  /// true of the journey home as of the journey out.
  bool get moving => _phase == _Phase.moving || _phase == _Phase.returning;

  /// True once the dice have been put back down and are being left alone.
  bool get down => _phase == _Phase.down;

  /// The numbers, captured when the formation was laid out. Null until then,
  /// which is [DiceTray]'s signal to read the dice live instead.
  List<int>? get values => _values;

  /// How far into the presentation this is, 0 to 1 — what the painter dims the
  /// tray by, so the walls fade at exactly the rate the dice come forward.
  double get progress {
    switch (_phase) {
      case _Phase.idle:
      case _Phase.waiting:
        return 0;
      case _Phase.moving:
      case _Phase.returning:
        return _ease((_elapsed / Tuning.readoutDuration).clamp(0.0, 1.0));
      case _Phase.showing:
        return 1;
      case _Phase.down:
        return 0;
    }
  }

  /// Drives the readout for one frame, in *real* seconds.
  ///
  /// [Tuning.timeScale] slows the simulation; it has no business slowing a
  /// presentation, which is not part of the physics and is not pretending to
  /// be. [reading] hands back the index of the face each die is read off, and
  /// is asked exactly once — at the instant the formation is laid out.
  void advance(
    double dt, {
    required bool atRest,
    required List<int> Function() reading,
  }) {
    if (!atRest || !enabled) {
      release();
      return;
    }

    switch (_phase) {
      case _Phase.idle:
        _phase = _Phase.waiting;
        _elapsed = 0;
      case _Phase.waiting:
        _elapsed += dt;
        if (_elapsed < Tuning.readoutDelay) return;
        _lay(reading());
        _phase = _Phase.moving;
        _elapsed = 0;
      case _Phase.moving:
        _elapsed += dt;
        if (_elapsed >= Tuning.readoutDuration) {
          _elapsed = Tuning.readoutDuration;
          _phase = _Phase.showing;
        }
        _pose(_ease(_elapsed / Tuning.readoutDuration));
      case _Phase.showing:
        return;
      case _Phase.returning:
        // The same journey, run backwards through the same easing, so the dice
        // come home along the line they went out on. Quicker, because going
        // out is the part worth watching.
        _elapsed -= dt * Tuning.readoutDuration / Tuning.readoutReturn;
        if (_elapsed <= 0) {
          _restore();
          _phase = _Phase.down;
          _elapsed = 0;
          _values = null;
          _moves.clear();
          return;
        }
        _pose(_ease(_elapsed / Tuning.readoutDuration));
      case _Phase.down:
        return;
    }
  }

  /// Sends the dice back down to where they landed, and leaves them there.
  ///
  /// The formation is a fine place to leave a roll, but it is not where the
  /// roll happened — so putting the dice down puts them back on the exact spot
  /// and the exact orientation the physics left them in, not merely somewhere
  /// underneath the formation. They are still asleep when they arrive, and the
  /// readout does not pick them up again of its own accord: [pickUp] or a
  /// shake, and nothing else.
  void putDown() {
    if (_phase != _Phase.moving && _phase != _Phase.showing) return;
    if (_moves.isEmpty) {
      _phase = _Phase.down;
      return;
    }
    _phase = _Phase.returning;
  }

  /// Brings them back up again, if they have been put down.
  void pickUp() {
    if (_phase != _Phase.down) return;
    _phase = _Phase.idle;
    _elapsed = 0;
  }

  /// Hands the dice back to the solver, at the spot they landed on.
  ///
  /// Instant, where [putDown] travels: this is what a shake gets, and a shake
  /// is a request for the physics *now*. Spending a third of a second flying
  /// the dice home first would eat the front of the very impulse that asked
  /// for them. They still land back where they were before they are scattered
  /// from it, which is the whole point of having remembered.
  void release() {
    _restore();
    _phase = _Phase.idle;
    _elapsed = 0;
    _values = null;
    _moves.clear();
  }

  /// Drops the formation without moving anything.
  ///
  /// For [DiceTray.throwDice], which has already put every die somewhere new:
  /// restoring them to where the last roll finished would undo the throw.
  void forget() {
    _phase = _Phase.idle;
    _elapsed = 0;
    _values = null;
    _moves.clear();
  }

  /// Puts every die back exactly where it was picked up from.
  void _restore() {
    for (int i = 0; i < _moves.length && i < dice.length; i++) {
      final RigidBody die = dice[i];
      dice[i].position.setFrom(_moves[i].from);
      die.orientation = _moves[i].fromOrientation.clone();
      die.syncDerived();
    }
  }

  /// Works out where every die is going, and how it has to be turned to get
  /// its number to the glass.
  void _lay(List<int> reading) {
    _values = List<int>.unmodifiable(<int>[
      for (int i = 0; i < dice.length; i++)
        dice[i].shape.faces[reading[i]].value,
    ]);
    _moves.clear();

    final int count = dice.length;
    if (count == 0) return;

    double reach = 0;
    for (final RigidBody die in dice) {
      reach = math.max(reach, die.circumradius);
    }
    // The spawn grid's pitch, for the spawn grid's reason: it is the spacing at
    // which no two dice of any mixture can overlap. That matters twice over
    // here, because the formation is also where the dice are standing when a
    // shake hands them back to the solver.
    final double pitch = 2.05 * reach;

    final double roomAcross = width;
    final double roomDown = height - Tuning.readoutTopClearance;

    // Whatever number of columns leaves the dice biggest. Ten dice on a phone
    // come out two across and five down; two dice come out side by side.
    int columns = 1;
    double fit = 0;
    for (int c = 1; c <= count; c++) {
      final int r = (count + c - 1) ~/ c;
      final double candidate = math.min(
        1.0,
        math.min(roomAcross / (c * pitch), roomDown / (r * pitch)),
      );
      if (candidate > fit) {
        fit = candidate;
        columns = c;
      }
    }
    final int rows = (count + columns - 1) ~/ columns;

    // Depth does the fitting, not scale. A die is 16 mm and stays 16 mm; if the
    // grid is too big for the tray the whole formation stands further from the
    // eye, which is what the camera already does to everything else in the box.
    // `scaleAt` of this z is exactly `fit`, which is the shrink that was asked
    // for. The near clamp keeps a die wholly behind the glass, so releasing the
    // formation does not start it inside a wall.
    final double z = (Tuning.eyeDistance * (1 - 1 / fit)).clamp(
      -depth + reach,
      -reach,
    );

    // The band left below the buttons, centred — but divided back through the
    // shrink, because the projection scales positions about the middle of the
    // screen as well as sizes. A formation centred here in metres would draw
    // itself centred `fit` of the way there.
    final double centreY = -Tuning.readoutTopClearance / (2 * fit);

    for (int i = 0; i < count; i++) {
      final RigidBody die = dice[i];
      final int row = i ~/ columns;
      final int column = i % columns;
      // The last row is usually short. Centring it looks laid out; leaving it
      // ragged looks like a bug.
      final int across = math.min(columns, count - row * columns);

      final DieMarking marking = readMarking(die.shape, reading[i]);

      _moves.add(
        _Move(
          from: die.position.clone(),
          to: Vector3(
            (column - (across - 1) / 2) * pitch,
            centreY + ((rows - 1) / 2 - row) * pitch,
            z,
          ),
          fromOrientation: die.orientation.clone(),
          toOrientation: markingToScreenTilted(
            die.shape,
            marking,
            Tuning.readoutTilt,
          ),
        ),
      );
    }
  }

  void _pose(double t) {
    for (int i = 0; i < dice.length; i++) {
      final RigidBody die = dice[i];
      final _Move move = _moves[i];
      die.position
        ..setFrom(move.from)
        ..addScaled(move.travel, t);
      die.orientation = slerp(move.fromOrientation, move.toOrientation, t);
      // The painter reads the cached world-space normals and vertices, so a
      // die posed without this is a die drawn where it used to be.
      die.syncDerived();
    }
  }
}

enum _Phase { idle, waiting, moving, showing, returning, down }

class _Move {
  _Move({
    required this.from,
    required this.to,
    required this.fromOrientation,
    required this.toOrientation,
  }) : travel = to - from;

  final Vector3 from;
  final Vector3 to;
  final Vector3 travel;
  final Quaternion fromOrientation;
  final Quaternion toOrientation;
}

/// Cubic ease in and out — Flutter's `Curves.easeInOutCubic`, written out
/// because nothing below the widgets may import it, and because the readout has
/// to run headless in the tools and the tests.
double _ease(double t) =>
    t < 0.5
        ? 4 * t * t * t
        : 1 - (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) / 2;

/// Spherical linear interpolation between two orientations.
///
/// vector_math has none, and lerping quaternions instead would swing a die
/// through a visibly wrong arc over the half-turns the readout routinely has to
/// make. The negation is the short way round: `q` and `-q` are the same
/// orientation, and without it half of all turns take the long way.
Quaternion slerp(Quaternion a, Quaternion b, double t) {
  double dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
  double bx = b.x, by = b.y, bz = b.z, bw = b.w;
  if (dot < 0) {
    dot = -dot;
    bx = -bx;
    by = -by;
    bz = -bz;
    bw = -bw;
  }

  double wa = 1 - t;
  double wb = t;
  // Near-parallel: the arc is shorter than a pixel and sin(theta) is on its way
  // to zero, so take the straight line and normalise rather than divide by it.
  if (dot < 0.9995) {
    final double theta = math.acos(dot.clamp(-1.0, 1.0));
    final double sine = math.sin(theta);
    wa = math.sin((1 - t) * theta) / sine;
    wb = math.sin(t * theta) / sine;
  }

  return Quaternion(
    a.x * wa + bx * wb,
    a.y * wa + by * wb,
    a.z * wa + bz * wb,
    a.w * wa + bw * wb,
  )..normalize();
}
