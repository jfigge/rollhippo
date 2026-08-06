import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../motion/motion.dart';
import '../render/tray_painter.dart';
import '../tray/tray.dart';

/// True when a real accelerometer is expected to be present.
bool get onDevice =>
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

/// The tray itself: the dice you chose, thrown in and left to settle.
class TrayScreen extends StatefulWidget {
  const TrayScreen({super.key, required this.dice, this.readout = true});

  final List<DieSpec> dice;

  /// Whether settled dice turn themselves towards you to be read.
  final bool readout;

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

  double _roll = 0;
  double _pitch = 0;

  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _motion = onDevice ? SensorMotionSource() : ManualMotionSource();
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

    tray.update(_motion.sample(dt), dt);
    _frames.tick();
  }

  void _ensureTray(Size size) {
    if (_tray != null && size == _size) return;
    _size = size;
    _tray = DiceTray(
      width: size.width / Tuning.logicalPixelsPerMetre,
      height: size.height / Tuning.logicalPixelsPerMetre,
      dice: widget.dice,
      readout: widget.readout,
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
        _tray?.throwDice();
      case LogicalKeyboardKey.arrowLeft:
        _roll -= 0.12;
      case LogicalKeyboardKey.arrowRight:
        _roll += 0.12;
      case LogicalKeyboardKey.arrowUp:
        _pitch -= 0.12;
      case LogicalKeyboardKey.arrowDown:
        _pitch += 0.12;
      case LogicalKeyboardKey.keyG:
        final DiceTray? tray = _tray;
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
                // Somewhere to put the dice back down without shaking them: the
                // formation is a fine place to leave a roll, but not if you
                // wanted to look at where it actually landed.
                onTap: () {
                  if (!tray.readout.active) return;
                  tray.readout.release();
                  tray.world.wake();
                },
                onDoubleTap: tray.throwDice,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CustomPaint(
                      painter: TrayPainter(tray: tray, repaint: _frames),
                    ),
                    // Along the top, deliberately: the dice settle along the
                    // bottom edge, which is exactly where a control bar would
                    // sit on top of the thing you are trying to look at.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: SafeArea(
                        bottom: false,
                        minimum: const EdgeInsets.only(top: 44),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              _TrayButton(
                                label: 'Close',
                                onTap: () => Navigator.of(context).pop(),
                              ),
                              _TrayButton(
                                label: 'Throw',
                                onTap: tray.throwDice,
                                emphasis: true,
                              ),
                            ],
                          ),
                        ),
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
    if (onDevice) return child;
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

class _TrayButton extends StatelessWidget {
  const _TrayButton({
    required this.label,
    required this.onTap,
    this.emphasis = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor:
            emphasis ? const Color(0xE63F6FA8) : const Color(0x33FFFFFF),
        foregroundColor: const Color(0xFFF2F7FF),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }
}
