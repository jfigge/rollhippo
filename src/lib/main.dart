import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import 'motion/motion.dart';
import 'physics/body.dart';
import 'render/tray_painter.dart';
import 'tray/tray.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Belt and braces with the Info.plist: the tray's walls are fixed to the
  // screen while gravity comes from the accelerometer, so letting the screen
  // re-orient as the phone tips would rotate the tray out from under the dice
  // while down carried on pointing the same way.
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  runApp(const RollHippoApp());
}

class RollHippoApp extends StatelessWidget {
  const RollHippoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roll Hippo — tray',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const TrayScreen(),
    );
  }
}

/// True when a real accelerometer is expected to be present.
bool get _onDevice =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

/// The tray the desktop harness pretends to be — an iPhone 15 Pro, in logical
/// pixels.
///
/// The harness letterboxes to this rather than filling its window, so the tray
/// it simulates is 64 × 140 mm whatever size the window happens to be. A tray
/// that changes size with the window is a tray whose feel you cannot compare
/// against the device.
const Size kHarnessScreen = Size(393, 852);

class TrayScreen extends StatefulWidget {
  const TrayScreen({super.key});

  @override
  State<TrayScreen> createState() => _TrayScreenState();
}

class _TrayScreenState extends State<TrayScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final MotionSource _motion;

  /// Repaints are driven straight off the ticker rather than off setState, so
  /// the simulation is not paying for a widget rebuild sixty times a second.
  final _FrameNotifier _frames = _FrameNotifier();

  DiceTray? _tray;
  Size _size = Size.zero;

  Duration _last = Duration.zero;
  double _fps = 0;
  double _physicsMs = 0;
  MotionFrame _lastFrame = MotionFrame.still;

  double _roll = 0;
  double _pitch = 0;

  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _motion = _onDevice ? SensorMotionSource() : ManualMotionSource();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _focus.dispose();
    _ticker.dispose();
    _motion.dispose();
    _frames.dispose();
    super.dispose();
  }

  ManualMotionSource? get _manual {
    final MotionSource source = _motion;
    return source is ManualMotionSource ? source : null;
  }

  void _onTick(Duration elapsed) {
    final DiceTray? tray = _tray;
    if (tray == null) {
      _last = elapsed;
      return;
    }

    double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    // A frame that took longer than this was a hitch, not a slow frame. Feeding
    // the real number in would teleport the dice.
    if (dt <= 0) return;
    dt = math.min(dt, 1 / 30);

    _fps = _fps == 0 ? 1 / dt : _fps * 0.9 + (1 / dt) * 0.1;

    final MotionFrame frame = _motion.sample(dt);
    _lastFrame = frame;

    final Stopwatch watch = Stopwatch()..start();
    tray.update(frame, dt);
    watch.stop();
    _physicsMs = _physicsMs * 0.9 + (watch.elapsedMicroseconds / 1000.0) * 0.1;

    _frames.tick();
  }

  void _ensureTray(Size size) {
    if (_tray != null && size == _size) return;
    _size = size;
    _tray = DiceTray(
      width: size.width / Tuning.logicalPixelsPerMetre,
      height: size.height / Tuning.logicalPixelsPerMetre,
    );
  }

  Vector3 _toMetres(Offset local) => Vector3(
    (local.dx - _size.width / 2) / Tuning.logicalPixelsPerMetre,
    (_size.height / 2 - local.dy) / Tuning.logicalPixelsPerMetre,
    0,
  );

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    final ManualMotionSource? manual = _manual;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        manual?.shake();
      case LogicalKeyboardKey.keyR:
        _tray?.scatter();
      case LogicalKeyboardKey.arrowLeft:
        _roll -= 0.12;
      case LogicalKeyboardKey.arrowRight:
        _roll += 0.12;
      case LogicalKeyboardKey.arrowUp:
        _pitch -= 0.12;
      case LogicalKeyboardKey.arrowDown:
        _pitch += 0.12;
      case LogicalKeyboardKey.keyG:
        final tray = _tray;
        if (tray != null) {
          tray.world.rotationalEffects =
              tray.world.rotationalEffects > 0 ? 0.0 : 1.0;
        }
      default:
        return;
    }
    _roll = _roll.clamp(-1.4, 1.4);
    _pitch = _pitch.clamp(-1.4, 1.4);
    manual?.tilt(roll: _roll, pitch: _pitch);
    _tray?.world.wake();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      body: KeyboardListener(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: _letterbox(
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Size size = constraints.biggest;
              _ensureTray(size);
              final DiceTray tray = _tray!;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (DragStartDetails d) {
                  _manual?.pointerTo(_toMetres(d.localPosition));
                  tray.world.wake();
                },
                onPanUpdate: (DragUpdateDetails d) {
                  _manual?.pointerTo(_toMetres(d.localPosition));
                },
                onPanEnd: (_) => _manual?.pointerUp(),
                onDoubleTap: tray.scatter,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CustomPaint(
                      painter: TrayPainter(tray: tray, repaint: _frames),
                    ),
                    _Hud(
                      tray: tray,
                      repaint: _frames,
                      fps: () => _fps,
                      physicsMs: () => _physicsMs,
                      motion: () => _lastFrame,
                    ),
                    // Top right, deliberately: the dice settle along the bottom
                    // edge, which is exactly where a control bar would sit on top
                    // of the thing you are trying to look at.
                    Positioned(
                      right: 14,
                      top: 48,
                      child: _Controls(
                        onScatter: tray.scatter,
                        onShake:
                            _manual == null ? null : () => _manual!.shake(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// On a device the tray *is* the screen. Everywhere else it is pinned to
  /// [kHarnessScreen] and scaled to fit, so the harness and the phone are
  /// showing the same tray.
  Widget _letterbox(Widget child) {
    if (_onDevice) return child;
    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: kHarnessScreen.width,
          height: kHarnessScreen.height,
          child: child,
        ),
      ),
    );
  }
}

/// Ticks once per simulated frame; the painter listens to it.
class _FrameNotifier extends ChangeNotifier {
  void tick() => notifyListeners();
}

class _Hud extends StatelessWidget {
  const _Hud({
    required this.tray,
    required this.repaint,
    required this.fps,
    required this.physicsMs,
    required this.motion,
  });

  final DiceTray tray;
  final Listenable repaint;
  final double Function() fps;
  final double Function() physicsMs;
  final MotionFrame Function() motion;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 14,
      top: 54,
      child: AnimatedBuilder(
        animation: repaint,
        builder: (BuildContext context, Widget? child) {
          final List<int> faces =
              tray.dice.map((RigidBox d) => tray.faceUp(d)).toList();
          final double g = motion().properAcceleration.length / 9.81;
          return DefaultTextStyle(
            style: const TextStyle(
              fontFamily: 'Menlo',
              fontSize: 11,
              height: 1.5,
              color: Color(0xCCBFD0E4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${fps().toStringAsFixed(0)} fps  '
                  'physics ${physicsMs().toStringAsFixed(2)} ms',
                ),
                Text(
                  'field ${g.toStringAsFixed(2)} g'
                  '${tray.world.asleep ? '   · settled' : ''}',
                ),
                Text('faces ${faces.join(' · ')}'),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.onScatter, this.onShake});

  final VoidCallback onScatter;
  final VoidCallback? onShake;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        if (onShake != null) ...<Widget>[
          _button('Shake', onShake!),
          const SizedBox(height: 8),
        ],
        _button('Throw', onScatter),
      ],
    );
  }

  Widget _button(String label, VoidCallback onTap) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      backgroundColor: const Color(0x33FFFFFF),
      foregroundColor: const Color(0xFFE8EEF6),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    ),
    child: Text(label),
  );
}
