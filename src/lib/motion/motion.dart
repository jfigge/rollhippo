import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math_64.dart';

/// One instant of how the phone is moving, in device axes: x right, y towards
/// the top of the screen, z out through the glass.
class MotionFrame {
  MotionFrame({
    required this.properAcceleration,
    required this.gravityReading,
    required this.angularVelocity,
    required this.angularAcceleration,
  });

  /// What the accelerometer reads — proper acceleration, gravity included. A
  /// phone lying still reads 9.81 on whichever axis points at the sky.
  final Vector3 properAcceleration;

  /// The part of [properAcceleration] that is gravity rather than movement —
  /// what the accelerometer would read if the phone were held still in this
  /// attitude.
  ///
  /// Split out so gravity can be tuned without touching the shake. The sensor
  /// delivers the two added together, but they are not the same thing: on a
  /// smaller planet a shake would still hit exactly as hard as it does here.
  final Vector3 gravityReading;

  /// Movement only — [properAcceleration] with gravity taken back out.
  Vector3 get linearAcceleration => properAcceleration - gravityReading;

  final Vector3 angularVelocity;
  final Vector3 angularAcceleration;

  /// Held upright and perfectly still.
  static MotionFrame get still => MotionFrame(
    properAcceleration: Vector3(0, 9.81, 0),
    gravityReading: Vector3(0, 9.81, 0),
    angularVelocity: Vector3.zero(),
    angularAcceleration: Vector3.zero(),
  );
}

abstract class MotionSource {
  /// The motion since the previous call, averaged over that interval.
  MotionFrame sample(double dt);
  void dispose() {}
}

/// A phone that is not moving, and never will be.
///
/// What the app runs on when motion control is turned off — see
/// `Settings.motion`. Every frame is [MotionFrame.still], so gravity points
/// down the screen and stays there, nothing is ever a shake, and the buttons
/// along the top of the tray are the only way to roll or deal.
///
/// A source rather than a flag tested at the point of use, because "the phone
/// is not moving" is a complete and honest answer to what the sensors are for.
/// The tray needs to know nothing about the setting: it asks how the phone is
/// moving and is told the truth, which is that it is sitting on a table.
class StillMotionSource implements MotionSource {
  const StillMotionSource();

  @override
  MotionFrame sample(double dt) => MotionFrame.still;

  @override
  void dispose() {}
}

/// The source a screen should be driven by.
///
/// Three answers: the sensors when there is a phone under them, the synthetic
/// phone when there is not — that is the desktop harness, where dragging and
/// the arrow keys stand in for a hand — and [StillMotionSource] when the
/// player has said they do not want the phone's own movement in it at all.
///
/// The setting wins over both. Motion control off on the harness means the
/// keyboard shake and tilt stop working too, which is the point: it is the
/// same app with the same control taken away, and a harness that still tilted
/// would be no use for judging what the phone now does.
MotionSource motionSourceFor({required bool device, required bool motion}) {
  if (!motion) return const StillMotionSource();
  return device ? SensorMotionSource() : ManualMotionSource();
}

/// The real thing: the phone's own accelerometer and gyroscope.
///
/// **Not every phone has all three of these**, and the ones it lacks are not a
/// stream that stays quiet — `sensors_plus` completes the subscription with a
/// `PlatformException(NO_SENSOR)` instead. An unhandled stream error is an
/// unhandled exception in whatever zone the app is running in, so each `listen`
/// below carries an `onError`. Found on a BLU B1660V, which has an
/// accelerometer and nothing else: no gyroscope, no fused linear acceleration,
/// no magnetometer. That is an entire class of budget Android hardware, and a
/// dice tray that throws twice on launch there is a dice tray that is broken
/// there.
///
/// What each absence costs is already handled downstream, and deliberately —
/// see [sample]. Without a gyroscope the angular terms stay zero, which is
/// exactly the state the desktop harness's **G** key toggles: the dice still
/// slide and settle under gravity, and a wrist flick no longer adds tumble.
/// Without the user-acceleration stream the gravity estimate falls back to the
/// raw reading, which drags "down" around during a hard shake — worse, and
/// still a working tray. So the errors are swallowed rather than surfaced:
/// there is nothing to tell the player that they could act on, and the app
/// they get is the app that hardware can run.
class SensorMotionSource implements MotionSource {
  SensorMotionSource() {
    // 200 Hz requested. A hand shake has real content up to about 15 Hz, and
    // the impacts it causes are shorter than that again; sampling at frame rate
    // aliases the shake into something slower and mushier than it was, which is
    // a large part of what makes a naive shake-to-roll feel wrong.
    const Duration period = Duration(milliseconds: 5);
    _accelerometer = accelerometerEventStream(samplingPeriod: period).listen((
      AccelerometerEvent e,
    ) {
      _sum.setValues(_sum.x + e.x, _sum.y + e.y, _sum.z + e.z);
      _count++;
    }, onError: _ignoreMissingSensor);
    _gyroscope = gyroscopeEventStream(samplingPeriod: period).listen((
      GyroscopeEvent e,
    ) {
      _gyroSum.setValues(_gyroSum.x + e.x, _gyroSum.y + e.y, _gyroSum.z + e.z);
      _gyroCount++;
    }, onError: _ignoreMissingSensor);
    // Movement with gravity already taken out. On iOS this is CoreMotion's
    // sensor-fused figure, which is a far better split than low-pass filtering
    // the raw accelerometer — a low pass cannot tell a slow shake from a tilt.
    //
    // On Android it is TYPE_LINEAR_ACCELERATION, which the platform derives by
    // sensor fusion — so a phone with no gyroscope to fuse with generally has
    // no such sensor either, and this is the second stream to error rather than
    // the one that saves the first.
    _userAccelerometer = userAccelerometerEventStream(
      samplingPeriod: period,
    ).listen((UserAccelerometerEvent e) {
      _userSum.setValues(_userSum.x + e.x, _userSum.y + e.y, _userSum.z + e.z);
      _userCount++;
    }, onError: _ignoreMissingSensor);
  }

  /// A sensor this phone does not have. There is nothing to do about it and
  /// nothing to say about it — the counters simply stay at zero, and every
  /// reader of them in [sample] is already written to expect that.
  static void _ignoreMissingSensor(Object error, StackTrace stack) {}

  StreamSubscription<AccelerometerEvent>? _accelerometer;
  StreamSubscription<GyroscopeEvent>? _gyroscope;
  StreamSubscription<UserAccelerometerEvent>? _userAccelerometer;

  final Vector3 _sum = Vector3.zero();
  int _count = 0;
  final Vector3 _gyroSum = Vector3.zero();
  int _gyroCount = 0;
  final Vector3 _userSum = Vector3.zero();
  int _userCount = 0;
  bool _hasUserStream = false;

  final Vector3 _acceleration = Vector3(0, 9.81, 0);
  final Vector3 _gravityReading = Vector3(0, 9.81, 0);
  final Vector3 _angularVelocity = Vector3.zero();
  final Vector3 _angularAcceleration = Vector3.zero();

  @override
  MotionFrame sample(double dt) {
    // The *mean* of the samples in the interval, not the latest one. Velocity
    // is the integral of acceleration, so the mean is the reading that carries
    // the right impulse into the step; the latest sample is just whichever
    // point of the shake happened to land nearest the vsync.
    if (_count > 0) {
      _acceleration.setFrom(_sum / _count.toDouble());
      _sum.setZero();
      _count = 0;
    }

    // Gravity is whatever is left when movement is taken out. Smoothed,
    // because the two streams are separate sensors and their samples do not
    // land at quite the same instants — and because which way is down is a
    // slow fact that has no business changing at sensor noise speed.
    Vector3? estimate;
    if (_userCount > 0) {
      _hasUserStream = true;
      estimate = _acceleration - (_userSum / _userCount.toDouble());
      _userSum.setZero();
      _userCount = 0;
    } else if (_hasUserStream) {
      // The stream exists but had nothing to say this frame. Keep the estimate
      // we have rather than falling back and jerking "down" sideways.
      estimate = null;
    } else {
      // No user-acceleration stream on this platform. Falling back to the raw
      // reading means a hard shake will drag "down" around with it, which is
      // wrong but survivable; iOS and Android both supply the good one.
      estimate = _acceleration;
    }
    if (estimate != null) {
      _gravityReading.scale(0.85);
      _gravityReading.addScaled(estimate, 0.15);
    }

    if (_gyroCount > 0) {
      final Vector3 next = _gyroSum / _gyroCount.toDouble();
      if (dt > 0) {
        // Differentiating a noisy signal amplifies the noise, so the result is
        // smoothed hard. Euler forces only need the shape of the twist.
        final Vector3 raw = (next - _angularVelocity) / dt;
        _angularAcceleration.scale(0.7);
        _angularAcceleration.addScaled(raw, 0.3);
      }
      _angularVelocity.setFrom(next);
      _gyroSum.setZero();
      _gyroCount = 0;
    }

    return MotionFrame(
      properAcceleration: _acceleration.clone(),
      gravityReading: _gravityReading.clone(),
      angularVelocity: _angularVelocity.clone(),
      angularAcceleration: _angularAcceleration.clone(),
    );
  }

  @override
  void dispose() {
    _accelerometer?.cancel();
    _gyroscope?.cancel();
    _userAccelerometer?.cancel();
  }
}

/// A stand-in for a phone, for the desktop harness.
///
/// It exists so the feel of the physics can be judged — and regression-checked
/// — without a hand and a device in the loop. It manufactures the same
/// [MotionFrame] a real phone would produce: a gravity direction you can tilt,
/// plus an acceleration you can drive by dragging or by running a synthetic
/// shake.
class ManualMotionSource implements MotionSource {
  /// Which way gravity points in device axes. Upright by default.
  final Vector3 down = Vector3(0, -1, 0);

  /// Set by dragging; decays on its own so a flick is a flick and not a shove.
  final Vector3 _dragAcceleration = Vector3.zero();

  final Vector3 _dragVelocity = Vector3.zero();

  final Vector3 _angularVelocity = Vector3.zero();
  final Vector3 _previousAngularVelocity = Vector3.zero();
  final Vector3 _angularAcceleration = Vector3.zero();

  _SyntheticShake? _shake;

  double _elapsed = 0.0;

  /// Where the pointer is, in metres in the plane of the glass. Setting it
  /// drags the whole phone: the harness treats a pointer path as the path the
  /// device took, differentiates it twice, and feeds the result in as the
  /// acceleration a hand would have produced.
  final Vector3 _pointerTarget = Vector3.zero();
  final Vector3 _pointer = Vector3.zero();
  bool _pointerDown = false;

  void pointerTo(Vector3 metres) {
    if (!_pointerDown) {
      _pointerDown = true;
      _pointer.setFrom(metres);
    }
    _pointerTarget.setFrom(metres);
  }

  void pointerUp() {
    _pointerDown = false;
    _dragVelocity.setZero();
  }

  void _drag(Vector3 velocity, double dt) {
    final Vector3 acceleration = (velocity - _dragVelocity) / dt;
    _dragVelocity.setFrom(velocity);
    // One-pole smoothing: a mouse delivers position in steps, and raw
    // differences between them are spikes no hand could produce.
    _dragAcceleration.scale(0.6);
    _dragAcceleration.addScaled(acceleration, 0.4);
  }

  /// Rolls and pitches the phone, in radians.
  void tilt({double roll = 0, double pitch = 0}) {
    final Quaternion q = Quaternion.euler(0, pitch, roll);
    down.setFrom(q.rotated(Vector3(0, -1, 0)));
  }

  /// Runs [seconds] of a hand shake: a few hertz, a few centimetres, with the
  /// wrist rotation that comes with it.
  void shake({
    double seconds = 0.9,
    double frequency = 4.5,
    double amplitude = 0.045,
    double twist = 7.0,
  }) {
    _shake = _SyntheticShake(
      until: _elapsed + seconds,
      frequency: frequency,
      amplitude: amplitude,
      twist: twist,
    );
  }

  bool get shaking => _shake != null;

  @override
  MotionFrame sample(double dt) {
    _elapsed += dt;

    if (_pointerDown && dt > 0) {
      _drag((_pointerTarget - _pointer) / dt, dt);
      _pointer.setFrom(_pointerTarget);
    }

    final Vector3 acceleration = _dragAcceleration.clone();
    _angularVelocity.setZero();

    final _SyntheticShake? shake = _shake;
    if (shake != null) {
      if (_elapsed >= shake.until) {
        _shake = null;
      } else {
        acceleration.add(shake.accelerationAt(_elapsed));
        _angularVelocity.add(shake.angularVelocityAt(_elapsed));
      }
    }

    if (dt > 0) {
      _angularAcceleration.setFrom(
        (_angularVelocity - _previousAngularVelocity) / dt,
      );
    }
    _previousAngularVelocity.setFrom(_angularVelocity);

    // Drag acceleration bleeds away so a held pointer is not a rocket motor.
    _dragAcceleration.scale(math.exp(-dt * 12));

    // a_proper = a_device − g, and g is `down × 9.81`. The harness knows which
    // half is which exactly, with none of the sensor's guesswork.
    final Vector3 gravityReading = -down * 9.81;
    return MotionFrame(
      properAcceleration: acceleration + gravityReading,
      gravityReading: gravityReading,
      angularVelocity: _angularVelocity.clone(),
      angularAcceleration: _angularAcceleration.clone(),
    );
  }

  @override
  void dispose() {}
}

/// A shake with the numbers a real hand produces: 3–6 Hz over a few
/// centimetres, which peaks around 3 g, plus the wrist rotation nobody can
/// avoid adding.
class _SyntheticShake {
  _SyntheticShake({
    required this.until,
    required this.frequency,
    required this.amplitude,
    required this.twist,
  });

  final double until;
  final double frequency;
  final double amplitude;
  final double twist;

  Vector3 accelerationAt(double t) {
    final double w = 2 * math.pi * frequency;
    final double peak = amplitude * w * w;
    // Mostly along the long axis of the phone, with a smaller cross component
    // so the dice are not driven back and forth along one line.
    return Vector3(
      0.45 * peak * math.sin(w * 0.83 * t + 1.1),
      peak * math.sin(w * t),
      0.3 * peak * math.sin(w * 1.31 * t + 2.2),
    );
  }

  Vector3 angularVelocityAt(double t) {
    final double w = 2 * math.pi * frequency;
    return Vector3(
      twist * 0.6 * math.sin(w * t + 0.4),
      twist * 0.3 * math.sin(w * 1.17 * t),
      twist * math.sin(w * 0.91 * t + 2.0),
    );
  }
}
