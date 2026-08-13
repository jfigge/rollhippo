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

/// Throw, and the dots that count the boxes — named so the tutorial can point
/// at them. They are the two things on this screen that a page of it is about,
/// and neither has a label anywhere else that says what it does.
const Key kTrayThrow = ValueKey<String>('tray-throw');
const Key kTrayDots = ValueKey<String>('tray-dots');

/// How hard a flick has to be to carry the box to the next group on its own,
/// in screens per second. Below this the box goes wherever it is nearest to.
const double _kFlingPages = 0.9;

/// How far a box has to be pushed before letting go sends it the rest of the
/// way rather than back where it came from.
const double _kSwipeThreshold = 0.25;

/// The step [_TrayScreenState._settle] runs at, and how many of them it will
/// run before giving up. A sixtieth is the frame the tuning was settled
/// against, and 600 of them are ten seconds.
const double _kSettleStep = 1 / 60;
const int _kSettleSteps = 600;

/// The tray itself: a box per group of dice, side by side.
///
/// **Nothing is thrown on the way in.** Every group is sitting there, dice on
/// the floor, waiting to be shaken or thrown — the one you arrived on exactly
/// like the ones you have not swiped to yet. A roll is a thing somebody asks
/// for, and a tray that rolled itself as it opened would spend the throw
/// before its owner had the phone level, on a screen they had not looked at.
/// It is also what the card table has always done: a shoe opens with a bare
/// glass and waits for Draw, and there was never a reason for the dice to be
/// the odd one out.
///
/// Once thrown, a box you are not looking at is not simulated at all, so
/// nothing that happens to another group can bump its numbers.
class TrayScreen extends StatefulWidget {
  const TrayScreen({super.key, required this.groups, this.initial = 0});

  /// One box per group, in the order they were set up. Never empty.
  final List<List<DieSpec>> groups;

  /// Which box you arrive on. It arrives unthrown, like every other one.
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

  /// Whole seconds since the box on screen was thrown, or null if nobody has
  /// thrown it yet. Its own notifier for the same reason [_frames] is one: the
  /// clock changes once a second and everything else up here changes never, so
  /// this rebuilds a `Text` sixty times a minute rather than sixty times a
  /// second. See [ElapsedTimer].
  final ValueNotifier<int?> _clock = ValueNotifier<int?>(null);

  /// Bumped when the box on screen runs out of time. See [TimeUpAlert], which
  /// is what watches it — a counter rather than a flag so that two turns
  /// running out one after another are two alerts.
  final ValueNotifier<int> _alert = ValueNotifier<int>(0);

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
    _clock.dispose();
    _alert.dispose();
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

    // Wall-clock, and every box, including the ones frozen under a swipe and
    // the ones nobody is looking at. How long ago a group was thrown is a fact
    // about the room rather than about the simulation, so it does not stop
    // while a finger is on the glass and it does not pause for a box that is
    // off the side of the screen — swipe back to a group after two minutes and
    // it says two minutes, which is the only answer that could be true.
    final int limit = settings.timer ? settings.limit : 0;
    for (int i = 0; i < _boxes.length; i++) {
      final _Box box = _boxes[i];
      if (!box.thrown) continue;
      box.sinceThrow += dt;
      // Marked on every box, so a group that ran out while you were looking
      // at another one is already red when you swipe back to it. Only the box
      // on screen gets the alert: a flash is for somebody watching, and three
      // taps about a tray nobody can see is the phone shouting into a pocket.
      if (limit > 0 && !box.alerted && box.sinceThrow >= limit) {
        box.alerted = true;
        if (i == _at) _alert.value++;
      }
    }

    // The hardest knock the box on screen took this frame, in newton-seconds.
    // Only that box: the unthrown ones below are putting their dice down on a
    // floor nobody is looking at, and a phone that buzzed for those would be
    // buzzing about a tray that is not there.
    double impulse = 0;

    if (!_frozen) {
      final _Box box = _boxes[_at];
      final bool shaken = isShake(motion);
      // A group that has not been thrown yet is waiting for exactly this.
      if (!box.thrown && shaken) {
        _throwCurrent();
      } else if (shaken) {
        // And a group that *has* been thrown is rolled by the shake itself.
        // There is no second call to `throwDice` here and there must not be:
        // [DiceTray.update] wakes the world and the accelerometer scatters
        // the dice, which is the simulation being the throw rather than
        // standing in for one. The clock measures rolls and not button
        // presses, so this counts — otherwise a tray shaken into a fresh
        // result would go on reporting how long ago the last tap was.
        //
        // A shake is true for as long as the wrist is moving, so this is
        // zeroed on every frame of it and the count starts where the shaking
        // stopped, which is where the roll it produced actually began.
        box.sinceThrow = 0;
        box.alerted = false;
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

    // Last, so that a shake landing this frame is already in it.
    _updateClock();

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
              // Nobody has thrown any of these, so none of them has a result
              // to present. Every readout comes on with its own throw.
              readout: false,
            ),
            thrown: false,
          ),
      ]);
    // The box you are about to be looking at, put down before you look at it.
    // The others settle off-screen over the next second, which is what they
    // have always done — but this one has no next second to hide in.
    _settle(_boxes[_at].tray);
    _page.value = _at.toDouble();
    _slide = null;
    _dragging = false;
  }

  /// Runs a box forward under a phone lying perfectly still, until its dice
  /// have stopped.
  ///
  /// A [DiceTray]'s constructor throws — that is how the dice get anywhere at
  /// all — so a tray nobody has rolled is a tray in mid-air until something
  /// steps it. This is what turns that into a tray of dice lying on the floor,
  /// and it runs before the first frame is painted rather than across the
  /// first second of them, because the whole point is that opening the screen
  /// does not look like a roll. Watching the spawn formation tumble into a
  /// heap is exactly the thing this change was asked to remove.
  ///
  /// [MotionFrame.still] and not the real sensor: whatever the phone happens
  /// to be doing while a screen opens is not a throw anybody asked for.
  ///
  /// Bounded, because this is inside a layout pass. The worst set the picker
  /// can build — ten D20s, which are the slowest to stop — is asleep in 81
  /// steps, so the 600 of [_kSettleSteps] are a backstop against a set that
  /// somehow never settles rather than a number any real tray goes near. A box
  /// that did reach the cap would be left to the still-motion loop in
  /// `_onTick` like any other, and would simply finish settling on screen.
  ///
  /// Those 81 steps cost about 100 ms under the debug VM and a small fraction
  /// of that in the profile and release builds this ships as, which is what
  /// makes doing it here rather than across the first second of frames
  /// affordable at all. It is spent inside the route transition onto this
  /// screen. If a set is ever allowed to be much larger than ten, measure this
  /// again before assuming it is still free.
  static void _settle(DiceTray tray) {
    for (int step = 0; step < _kSettleSteps; step++) {
      if (tray.world.asleep) return;
      tray.update(MotionFrame.still, _kSettleStep);
    }
  }

  /// Hands the clock the whole second the box on screen is at.
  ///
  /// Called every frame and cheap every time: a [ValueNotifier] given the
  /// value it already holds tells nobody, so this is a comparison of two ints
  /// on fifty-nine frames out of sixty.
  void _updateClock() {
    final _Box box = _boxes[_at];
    _clock.value = box.thrown ? box.sinceThrow.floor() : null;
  }

  /// Throws the group on screen, whether or not it has been thrown before.
  void _throwCurrent() {
    final _Box box = _boxes[_at];
    box.tray.throwDice();
    // Zeroed here rather than left to the next frame, so the clock goes back
    // to 0:00 under the thumb that threw rather than a frame after it. This
    // covers the button, R on the harness, and the shake that throws a group
    // nobody had thrown yet — but not a shake on one already thrown, which
    // never comes through here at all. See `_onTick`.
    box.sinceThrow = 0;
    box.alerted = false;
    if (!box.thrown) {
      box.tray.readout.enabled = true;
      setState(() => box.thrown = true);
    }
    // After the flag and not before it. [_updateClock] reads `thrown` to
    // decide whether this box is timing anything at all, so on a group's
    // *first* throw — which, now that nothing is thrown on the way in, is
    // every group's first throw — asking before it is set would leave the
    // clock blank until the next frame put it right.
    _updateClock();
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
                        // The clock rides *in* the row, between the two
                        // buttons; the dots go under the whole of it. Both
                        // were children of one column in the middle of the
                        // row once, and that is a row whose height is the
                        // taller of them: turning the timer on with more than
                        // one box moved Close and Throw down the screen by
                        // half the height of a dot. A row that changes height
                        // when something optional appears inside it is a row
                        // that moves everything it contains.
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  TrayButton(
                                    label: 'Close',
                                    onTap: () => Navigator.of(context).pop(),
                                  ),
                                  // Read here rather than obeyed lower down.
                                  // The setting lives behind the picker, a
                                  // screen away, so it cannot change while a
                                  // tray is up — the same bargain
                                  // [_RollPrompt] makes with `motion`. Left
                                  // out entirely when it is off, which lays
                                  // the row out exactly as the two buttons on
                                  // their own always were.
                                  if (settings.timer)
                                    ElapsedTimer(
                                      key: kElapsedTimer,
                                      seconds: _clock,
                                      limit: settings.limit,
                                    ),
                                  TrayButton(
                                    key: kTrayThrow,
                                    label: 'Throw',
                                    onTap: _throwCurrent,
                                    emphasis: true,
                                  ),
                                ],
                              ),
                            ),
                            // Under the row rather than in it, and centred on
                            // the screen rather than on wherever `spaceBetween`
                            // would have put a middle child.
                            if (paged)
                              PageDots(
                                key: kTrayDots,
                                current: _at,
                                filled: List<bool>.filled(_boxes.length, true),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Last, so the flash is over the buttons as well as the
                    // dice. It is telling you about the screen rather than
                    // about anything on it.
                    TimeUpAlert(trigger: _alert),
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

  /// Whether this group has already run its turn out, so that the alert fires
  /// once rather than on every frame past the limit. Cleared by the next
  /// throw, which is also what clears [sinceThrow].
  bool alerted = false;

  /// Seconds since this group was last thrown, and meaningless until [thrown]
  /// — which is what the clock draws as a stopped `0:00` rather than as a
  /// count, and what keeps an unthrown group from ever running out of time.
  /// Per box rather than one for the screen, because a group is its own roll:
  /// throwing the set beside this one says nothing about how long ago this one
  /// was thrown.
  double sinceThrow = 0;
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
