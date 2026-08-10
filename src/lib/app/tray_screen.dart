import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../motion/motion.dart';
import '../render/tray_painter.dart';
import '../tray/tray.dart';
import 'chrome.dart';
import 'haptics.dart';
import 'page_dots.dart';
import 'settings.dart';

// Everything that imports the tray screen has always got `onDevice` and
// `kHarnessScreen` from it. They live next door now, so that the card table can
// have them too, but this is still where they are reached from.
export 'chrome.dart';

/// How hard a flick has to be to carry the box to the next group on its own,
/// in screens per second. Below this the box goes wherever it is nearest to.
const double _kFlingPages = 0.9;

/// How far a box has to be pushed before letting go sends it the rest of the
/// way rather than back where it came from.
const double _kSwipeThreshold = 0.25;

/// The tray itself: a box per group of dice, side by side.
///
/// The group you pressed Roll from arrives thrown. The others are sitting
/// there, dice on the floor, waiting to be shaken — because a group is a
/// separate roll rather than a separate view of the same one, and throwing all
/// three the moment you arrive would spend two of them before you had looked at
/// the first. Once thrown, a box you are not looking at is not simulated at
/// all, so nothing that happens to another group can bump its numbers.
class TrayScreen extends StatefulWidget {
  const TrayScreen({super.key, required this.groups, this.initial = 0});

  /// One box per group, in the order they were set up. Never empty.
  final List<List<DieSpec>> groups;

  /// Which box you arrive on, and the only one that arrives thrown.
  final int initial;

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

  /// Where the row of boxes has got to, in pages. Dragging writes to this and
  /// the painter reads it, which is the same bargain [_frames] makes: a finger
  /// moving across the glass repaints without rebuilding anything.
  final ValueNotifier<double> _page = ValueNotifier<double>(0);

  late final Listenable _repaint = Listenable.merge(<Listenable>[
    _frames,
    _page,
  ]);

  final List<_Box> _boxes = <_Box>[];
  Size _size = Size.zero;

  /// Which box is on screen and being simulated. Changes when a slide lands,
  /// not when it starts — the box you are leaving is the box that still has
  /// your finger on it.
  int _at = 0;

  bool _dragging = false;
  _Slide? _slide;

  Duration _last = Duration.zero;

  double _roll = 0;
  double _pitch = 0;

  final FocusNode _focus = FocusNode();

  /// Turns the wall impacts of the box on screen into taps you can feel.
  late final HapticEngine _haptics;

  @override
  void initState() {
    super.initState();
    _motion = motionSourceFor(device: onDevice, motion: settings.motion);
    _haptics = HapticEngine(
      driver: hapticsFor(device: onDevice),
      gain: settings.hapticGain,
    );
    // The calibration slider lives a screen away, under the picker this was
    // pushed from, so it cannot change while the tray is up. Listening anyway
    // costs nothing and means it does not matter if that stops being true.
    settings.addListener(_onSettingsChanged);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    _focus.dispose();
    _ticker.dispose();
    _motion.dispose();
    _frames.dispose();
    _page.dispose();
    super.dispose();
  }

  void _onSettingsChanged() => _haptics.gain = settings.hapticGain;

  ManualMotionSource? get _manual {
    final MotionSource source = _motion;
    return source is ManualMotionSource ? source : null;
  }

  DiceTray? get _tray => _boxes.isEmpty ? null : _boxes[_at].tray;

  /// True while a swipe is in flight, either under a finger or coasting.
  ///
  /// Nothing is simulated while it is: the box arriving and the box leaving
  /// both hold exactly the numbers they had. Advancing them through a swipe
  /// would let the accelerometer noise of the hand doing the swiping nudge a
  /// die over — and the whole reason for keeping groups apart is that a result
  /// you have already rolled stays rolled.
  bool get _frozen => _dragging || _slide != null;

  /// Whether the box will move at all right now.
  ///
  /// Only once everything has stopped. Freezing a die in mid-flight would
  /// leave it hanging in the air, and letting go of a swipe halfway through a
  /// roll would decide the roll.
  bool get _canSwipe {
    if (_boxes.length < 2) return false;
    for (final _Box box in _boxes) {
      if (!box.tray.world.asleep || box.tray.readout.moving) return false;
    }
    return true;
  }

  /// A screen plus the dark between two boxes: how far the row moves per page.
  double get _pagePitch =>
      _size.width + Tuning.trayPageGap * Tuning.logicalPixelsPerMetre;

  void _onTick(Duration elapsed) {
    if (_boxes.isEmpty) {
      _last = elapsed;
      return;
    }

    double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    // A frame that took longer than this was a hitch, not a slow frame. Feeding
    // the real number in would teleport the dice.
    if (dt <= 0) return;
    dt = math.min(dt, 1 / 30);

    // Sampled even while frozen, and thrown away. The sensor averages over the
    // interval since it was last asked and smooths gravity across it; skipping
    // a second of that would hand the tray one enormous frame when the swipe
    // ended, which the dice would feel as a jolt.
    final MotionFrame motion = _motion.sample(dt);

    if (_slide != null) _advanceSlide(dt);

    // The hardest knock the box on screen took this frame, in newton-seconds.
    // Only that box: the unthrown ones below are putting their dice down on a
    // floor nobody is looking at, and a phone that buzzed for those would be
    // buzzing about a tray that is not there.
    double impulse = 0;

    if (!_frozen) {
      final _Box box = _boxes[_at];
      // A group that has not been thrown yet is waiting for exactly this.
      if (!box.thrown && isShake(motion)) {
        _throwCurrent();
      }
      box.tray.update(motion, dt);
      impulse = box.tray.world.lastWallImpulse;
    }

    // The groups you have not reached yet put their dice down off-screen, under
    // a phone that is holding perfectly still whatever the real one is doing.
    // That is what makes an unthrown box look like a tray of dice sitting there
    // rather than a tray of dice frozen in mid-air, and it costs nothing: they
    // are asleep within a second or so of arriving, and never stepped again.
    if (!_frozen) {
      for (int i = 0; i < _boxes.length; i++) {
        final _Box box = _boxes[i];
        if (i == _at || box.thrown || box.tray.world.asleep) continue;
        box.tray.update(MotionFrame.still, dt);
      }
    }

    // Every frame, including the frozen ones and the silent ones: the engine
    // keeps its own clock off this [dt], and a gap that only advanced on
    // frames that had an impact in them would never close.
    _haptics.impact(impulse, dt);

    _frames.tick();
  }

  void _advanceSlide(double dt) {
    final _Slide slide = _slide!;
    slide.elapsed += dt;
    final double t = (slide.elapsed / Tuning.traySlideDuration).clamp(0.0, 1.0);
    _page.value =
        slide.from + (slide.to - slide.from) * Curves.easeOutCubic.transform(t);
    if (t < 1) return;

    _page.value = slide.to.toDouble();
    _slide = null;
    if (slide.to == _at) return;
    // The dots and the prompt are widgets, and this is the one moment in a
    // swipe when either of them has anything new to say.
    setState(() => _at = slide.to);
  }

  /// Builds the boxes, the first time there is a screen to build them for.
  ///
  /// The size is taken every time — paging and hit testing are against the
  /// widget as it is now — but the boxes are built once and never rebuilt.
  /// They used to be rebuilt whenever the size changed, and a `DiceTray`'s
  /// constructor throws the dice: an Android phone dropped into split screen,
  /// or a foldable opened, would silently re-roll every group and lose
  /// whatever had been kept. A roll that a swipe cannot shake is a roll a
  /// window cannot shake either. What happens instead is that the box stays
  /// the size it was and [cameraFor] fits it into whatever room there now is.
  void _ensureBoxes(Size size) {
    _size = size;
    // A degenerate first layout would otherwise be the size the tray keeps.
    if (_boxes.isNotEmpty || size.isEmpty) return;
    _at = widget.initial.clamp(0, widget.groups.length - 1);
    _boxes
      ..clear()
      ..addAll(<_Box>[
        for (int i = 0; i < widget.groups.length; i++)
          _Box(
            tray: DiceTray(
              width: size.width / Tuning.logicalPixelsPerMetre,
              height: size.height / Tuning.logicalPixelsPerMetre,
              dice: widget.groups[i],
              // A group nobody has thrown yet has no result to present, so the
              // readout stays off until it does. It comes on with the throw.
              readout: i == _at,
            ),
            thrown: i == _at,
          ),
      ]);
    _page.value = _at.toDouble();
    _slide = null;
    _dragging = false;
  }

  /// Throws the group on screen, whether or not it has been thrown before.
  void _throwCurrent() {
    final _Box box = _boxes[_at];
    box.tray.throwDice();
    if (box.thrown) return;
    box.tray.readout.enabled = true;
    setState(() => box.thrown = true);
  }

  /// A tap at [local] on [tray]: keep the die under it, or put the roll down.
  void _tap(DiceTray tray, Offset local) {
    if (tray.canHold) {
      final int? die = dieAt(tray, _size, local);
      if (die != null) {
        // No setState: the glow is painted, and the painter is already being
        // told to repaint every frame the tray ticks.
        tray.toggleHold(die);
        return;
      }
    }
    tray.readout.down ? tray.readout.pickUp() : tray.readout.putDown();
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
        if (_boxes.isNotEmpty) _throwCurrent();
      case LogicalKeyboardKey.arrowLeft:
        _roll -= 0.12;
      case LogicalKeyboardKey.arrowRight:
        _roll += 0.12;
      case LogicalKeyboardKey.arrowUp:
        _pitch -= 0.12;
      case LogicalKeyboardKey.arrowDown:
        _pitch += 0.12;
      case LogicalKeyboardKey.keyG:
        // Every box, so that swiping does not quietly undo the A/B.
        for (final _Box box in _boxes) {
          box.tray.world.rotationalEffects =
              box.tray.world.rotationalEffects > 0 ? 0.0 : 1.0;
        }
      default:
        return;
    }
    _roll = _roll.clamp(-1.4, 1.4);
    _pitch = _pitch.clamp(-1.4, 1.4);
    manual?.tilt(roll: _roll, pitch: _pitch);
    _tray?.world.wake();
  }

  void _dragStart(DragStartDetails details) {
    if (!_canSwipe) return;
    _slide = null;
    setState(() => _dragging = true);
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    _page.value = (_page.value - details.delta.dx / _pagePitch).clamp(
      0.0,
      (_boxes.length - 1).toDouble(),
    );
  }

  void _dragEnd(DragEndDetails details) {
    if (!_dragging) return;
    // A flick carries the box on its own; otherwise a quarter of the way over
    // is far enough to mean it, and anything less springs back.
    final double fling = -details.velocity.pixelsPerSecond.dx / _pagePitch;
    final double moved = _page.value - _at;
    int to = _at;
    if (fling.abs() > _kFlingPages) {
      to = _at + (fling > 0 ? 1 : -1);
    } else if (moved.abs() > _kSwipeThreshold) {
      to = _at + (moved > 0 ? 1 : -1);
    }
    setState(() {
      _dragging = false;
      _slide = _Slide(from: _page.value, to: to.clamp(0, _boxes.length - 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      body: KeyboardListener(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: letterbox(
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Size size = constraints.biggest;
              _ensureBoxes(size);
              final _Box box = _boxes[_at];
              final bool paged = _boxes.length > 1;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (DragStartDetails d) {
                  _manual?.pointerTo(_toMetres(d.localPosition));
                  box.tray.world.wake();
                },
                onPanUpdate: (DragUpdateDetails d) {
                  _manual?.pointerTo(_toMetres(d.localPosition));
                },
                onPanEnd: (_) => _manual?.pointerUp(),
                // Only wired up when there is somewhere to go, so a single
                // group behaves exactly as it did before there were groups.
                // With both recognisers in the arena a sideways drag pages and
                // anything else goes to the finger above, which is the split
                // every scrolling app already makes.
                onHorizontalDragStart: paged ? _dragStart : null,
                onHorizontalDragUpdate: paged ? _dragUpdate : null,
                onHorizontalDragEnd: paged ? _dragEnd : null,
                // A tap does one of two things, depending on what is under
                // it. On a die, while the roll is being presented, it keeps
                // that die for the next throw. Anywhere else it puts the dice
                // back down where they landed — the formation is a fine place
                // to leave a roll, but not if you wanted to look at where it
                // actually fell — and a second tap lifts them again.
                //
                // No `onDoubleTap`: with one registered, every single tap waits
                // three hundred milliseconds to find out whether a second is
                // coming, and picking dice out of a formation is not a gesture
                // that can afford to feel like that. Throw and a shake are both
                // still there.
                onTapUp: (TapUpDetails d) => _tap(box.tray, d.localPosition),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CustomPaint(
                      painter: TrayPagesPainter(
                        trays: <DiceTray>[
                          for (final _Box box in _boxes) box.tray,
                        ],
                        page: _page,
                        repaint: _repaint,
                      ),
                    ),
                    if (!box.thrown && !_frozen) const _RollPrompt(),
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
                              TrayButton(
                                label: 'Close',
                                onTap: () => Navigator.of(context).pop(),
                              ),
                              if (paged)
                                PageDots(
                                  current: _at,
                                  filled: List<bool>.filled(
                                    _boxes.length,
                                    true,
                                  ),
                                ),
                              TrayButton(
                                label: 'Throw',
                                onTap: _throwCurrent,
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
}

/// One group's box, and whether anyone has thrown it yet.
class _Box {
  _Box({required this.tray, required this.thrown});

  final DiceTray tray;

  /// False for a group you have swiped to and not yet shaken. Its dice have
  /// been put down by the solver, but they are not a result.
  bool thrown;
}

/// A swipe coasting to a stop.
class _Slide {
  _Slide({required this.from, required this.to});

  final double from;
  final int to;
  double elapsed = 0;
}

/// What an unthrown group says for itself.
///
/// The dice are lying on the floor of the box, which on its own is ambiguous —
/// it looks like a roll that came out badly. One line says it is not a roll at
/// all yet, and goes away the instant it stops being true.
///
/// It names the gesture that actually works. With motion control off a shake
/// does nothing, and a prompt that asked for one would be the app telling you
/// to do something it has been told to ignore. Read rather than passed in, and
/// not rebuilt: the setting lives behind the picker, a screen away, and cannot
/// change while a tray is up.
class _RollPrompt extends StatelessWidget {
  const _RollPrompt();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Text(
          settings.motion ? 'Shake to roll' : 'Tap Throw to roll',
          style: const TextStyle(
            color: Color(0x66BFD0E4),
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

/// Ticks once per simulated frame; the painter listens to it.
class _FrameNotifier extends ChangeNotifier {
  void tick() => notifyListeners();
}
