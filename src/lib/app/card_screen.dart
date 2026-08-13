import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../cards/deck.dart';
import '../motion/motion.dart';
import '../render/card_painter.dart';
import '../tray/tray.dart';
import 'chrome.dart';
import 'page_dots.dart';
import 'settings.dart';
import 'slide_confirm.dart';

/// The dots that count the shoes — named so the tutorial and the tests can
/// point at them, exactly as `kTrayDots` is on the other screen.
const Key kCardDots = ValueKey<String>('card-dots');

/// How long after a card is dealt before a shake can deal another.
///
/// A shake is not an instant: [ManualMotionSource.shake] runs for the better
/// part of a second and a real wrist does much the same, so without a wait one
/// flick would deal a fistful of cards before the hand had stopped. Longer than
/// the shake, so one shake is one card however hard it was.
const double _kDrawCooldown = 1.1;

/// How hard a flick has to be to carry the table to the next shoe on its own,
/// in screens per second. Below this the table goes wherever it is nearest to.
const double _kFlingPages = 0.9;

/// How far a table has to be pushed before letting go sends it the rest of the
/// way rather than back where it came from.
const double _kSwipeThreshold = 0.25;

/// The card table: the same box, with a shoe of cards in it instead of dice.
///
/// Nothing here is simulated. A card is not a rigid body and there is nothing
/// to throw — the shoe is shuffled, the top card is turned over, and the only
/// thing the accelerometer is ever asked for is whether the phone was shaken.
///
/// And by default it is not asked even that: **Draw is the whole of the
/// interface here unless somebody has asked for the shake**, which the tray
/// never requires anybody to do. The two gestures are not the same act. A
/// shake on the tray *is* the simulation and an unwanted throw is undone by
/// throwing again; a shake here is a trigger, and what it triggers takes a
/// card off the shoe for good. See [Settings.shakeToDraw], which is where the
/// rest of that argument is written down.
///
/// **One table per shoe, side by side**, and swiped between exactly as the
/// tray's boxes are. What a shoe knows is what has already gone out of it, so
/// two of them side by side are two independent memories — and keeping them
/// apart is the same promise the tray makes about a roll you have already
/// thrown. Nothing that happens to one shoe touches another: they are shuffled
/// separately, dealt separately, and the cut card falls where each one's own
/// cut says.
class CardScreen extends StatefulWidget {
  const CardScreen({super.key, required this.shoes, this.initial = 0});

  /// One table per shoe, in the order they were set up. Never empty.
  final List<CardSet> shoes;

  /// Which table you arrive on. It arrives on a bare glass, like every other.
  final int initial;

  @override
  State<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends State<CardScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final MotionSource _motion;

  final List<_Shoe> _shoes = <_Shoe>[];
  Size _size = Size.zero;

  Duration _last = Duration.zero;

  /// Counts up from the last card dealt. See [_kDrawCooldown].
  ///
  /// One for the screen rather than one per shoe, because what it is measuring
  /// is the hand: a wrist that has just finished a shake is still moving
  /// whichever table happens to be in front of it.
  double _since = _kDrawCooldown;

  /// Which table is on screen. Changes when a slide lands, not when it starts.
  int _at = 0;

  bool _dragging = false;
  _Slide? _slide;

  /// Where the row of tables has got to, in pages. Dragging writes to this and
  /// the painter reads it, so a finger moving across the glass repaints
  /// without rebuilding anything.
  final ValueNotifier<double> _page = ValueNotifier<double>(0);

  /// The same in whole seconds, for the clock along the top. See
  /// [ElapsedTimer], which is where the reason it is whole is written down.
  final ValueNotifier<int?> _clock = ValueNotifier<int?>(null);

  /// Bumped when the turn runs out. See [TimeUpAlert].
  final ValueNotifier<int> _alert = ValueNotifier<int>(0);

  final FocusNode _focus = FocusNode();

  /// Ticked on every frame a card is in the air, and on no other. Nothing on
  /// these tables moves by itself, so this is the whole of what the painter
  /// has to watch. See [CardPainter.repaint].
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  late final Listenable _repaint = Listenable.merge(<Listenable>[
    _frame,
    _page,
  ]);

  @override
  void initState() {
    super.initState();
    // Two settings, one source, and no new flag anywhere below this line. The
    // rule the tray keeps — motion off is a *source*, not something the screen
    // tests — is the rule that makes this a one-line change: a table that has
    // not been asked for the shake is handed a phone lying perfectly still, so
    // `isShake` is never true and nothing under here has to know why.
    _motion = motionSourceFor(
      device: onDevice,
      motion: settings.motion && settings.shakeToDraw,
    );
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _focus.dispose();
    _frame.dispose();
    _page.dispose();
    _clock.dispose();
    _alert.dispose();
    _ticker.dispose();
    _motion.dispose();
    super.dispose();
  }

  ManualMotionSource? get _manual {
    final MotionSource source = _motion;
    return source is ManualMotionSource ? source : null;
  }

  _Shoe? get _shoe => _shoes.isEmpty ? null : _shoes[_at];

  /// True while a swipe is in flight, either under a finger or coasting.
  ///
  /// A shake landing during one deals nothing. Unlike the tray there is no
  /// simulation to disturb, but there is a hand moving across the glass, and a
  /// card off the shoe for good is exactly what that hand did not ask for.
  bool get _frozen => _dragging || _slide != null;

  /// Whether the table will move at all right now.
  ///
  /// Only once every card has landed. The tray's rule, for a softer reason:
  /// a card mid-flight is already dealt and could be swiped away from safely,
  /// but a table sliding sideways while a card flies across it reads as two
  /// animations arguing.
  bool get _canSwipe {
    if (_shoes.length < 2) return false;
    for (final _Shoe shoe in _shoes) {
      if (shoe.table.deal.busy) return false;
    }
    return true;
  }

  /// A screen plus the dark between two tables: how far the row moves per page.
  double get _pagePitch =>
      _size.width + Tuning.trayPageGap * Tuning.logicalPixelsPerMetre;

  void _onTick(Duration elapsed) {
    if (_shoes.isEmpty) {
      _last = elapsed;
      return;
    }

    double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    dt = math.min(dt, 1 / 30);
    _since += dt;

    if (_slide != null) _advanceSlide(dt);

    // The clocks, which run on real seconds and on nothing else — there is no
    // simulation here for them to be part of. Every shoe, including the ones
    // off the side of the screen, for the reason the tray advances every box's:
    // how long ago a card was dealt is a fact about the room. Null until a card
    // is on the glass, and back to null when a reshuffle sweeps it off, because
    // with nothing dealt there is nothing to be counting since.
    final int limit = settings.timer ? settings.limit : 0;
    for (int i = 0; i < _shoes.length; i++) {
      final _Shoe shoe = _shoes[i];
      final double? dealt = shoe.sinceDeal;
      if (dealt == null) continue;
      final double now = dealt + dt;
      shoe.sinceDeal = now;
      // Marked on every shoe, so one that ran out while you were looking at
      // another is already red when you swipe back to it. Only the shoe on
      // screen gets the alert: a flash is for somebody watching, and three
      // taps about a table nobody can see is the phone shouting into a pocket.
      if (limit > 0 && !shoe.alerted && now >= limit) {
        shoe.alerted = true;
        if (i == _at) _alert.value++;
      }
    }
    _updateClock();

    // The whole of what the sensors are for here. Sampled every frame whether
    // or not it is wanted, because the source averages over the interval since
    // it was last asked and skipping frames would hand it one enormous one.
    //
    // No test of the setting: by the time a frame gets here the answer is in
    // the source. A table nobody asked the shake for is being handed
    // [MotionFrame.still] sixty times a second, and a still phone is never a
    // shake.
    final MotionFrame motion = _motion.sample(dt);
    if (!_frozen && isShake(motion) && _since >= _kDrawCooldown) _draw();

    // And the only things on these tables that move: the card arriving and the
    // card it is replacing, which leaves at the same time. `busy` is both of
    // them, and it has to be both — a reshuffle sweeps a card away with
    // nothing following it, and ticking on the flight alone would leave that
    // one hanging half off the bottom of the box for ever.
    //
    // Every table and not only the one on screen, which is where this parts
    // company with the tray. A box you are not looking at is not simulated,
    // because stepping it could change what its dice are showing. A card is
    // already dealt before it has arrived — see [CardTable.draw] — so all that
    // is left in flight is its journey, and freezing that would only mean
    // swiping back to a card stopped in mid-air.
    //
    // The test is before the advance rather than after it, so the frame the
    // card lands on is painted too — asking afterwards would leave it drawn a
    // frame short of the glass and nothing would come along to finish it.
    bool moved = false;
    for (final _Shoe shoe in _shoes) {
      if (!shoe.table.deal.busy) continue;
      shoe.table.advance(dt);
      moved = true;
    }
    if (moved) _frame.value++;
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
    // The dots are a widget, and this is the one moment in a swipe when they
    // have anything new to say. So is `canPop`: which shoe is in front of you
    // decides nothing about it, but the rebuild is free here and the dots need
    // one anyway.
    setState(() => _at = slide.to);
  }

  /// Hands the clock the whole second the shoe on screen is at.
  void _updateClock() {
    final _Shoe shoe = _shoes[_at];
    _clock.value = shoe.sinceDeal?.floor();
  }

  /// Builds the tables, the first time there is a screen to build them for.
  ///
  /// Once, like the tray's boxes and for a sharper version of their reason: a
  /// new [CardTable] is a new [Deck], and a new Deck is a shuffle. A phone put
  /// into split screen mid-game would have swept the card off the glass and
  /// put the whole shoe back together, which is the one thing a shoe must only
  /// ever do when it is asked to. The tables keep the size they were built at
  /// and [cameraFor] fits them into the room there is.
  void _ensureTables(Size size) {
    _size = size;
    if (_shoes.isNotEmpty || size.isEmpty) return;
    _at = widget.initial.clamp(0, widget.shoes.length - 1);
    _shoes
      ..clear()
      ..addAll(<_Shoe>[
        for (final CardSet shoe in widget.shoes)
          _Shoe(
            table: CardTable(
              width: size.width / Tuning.logicalPixelsPerMetre,
              height: size.height / Tuning.logicalPixelsPerMetre,
              deck: Deck(
                dice: shoe.dice,
                decks: shoe.decks,
                reshuffleAt: shoe.reshuffleAt,
              ),
              colours: shoe.colours,
            ),
          ),
      ]);
    _page.value = _at.toDouble();
    _slide = null;
    _dragging = false;
  }

  /// Turns the top card of the shoe on screen over, or reshuffles it if it is
  /// down to the cut.
  ///
  /// A repaint rather than a rebuild: nothing above the painter has anything
  /// to say about which card is showing, and the flight that follows is a
  /// repaint a frame anyway. The card itself is dealt here and now — the
  /// animation is it arriving, not it being chosen.
  void _draw() {
    final _Shoe? shoe = _shoe;
    if (shoe == null) return;
    final bool was = _dealt;
    _since = 0;
    shoe.table.draw();
    // A reshuffle is a draw that deals no card: the pile goes back together
    // and the glass is left bare. So the clock is not restarted, it is put
    // away — see [Deck.draw], which is where that being a state worth seeing
    // is argued.
    final bool onGlass = shoe.table.deck.shown != null;
    shoe.sinceDeal = onGlass ? 0 : null;
    shoe.alerted = false;
    _updateClock();
    _frame.value++;
    // The one thing on this screen a card can change above the painter: a
    // played table is one you are asked about before it is closed, and
    // [PopScope.canPop] is read at build time rather than at the moment of
    // the gesture. So the first card dealt on the table — and the reshuffle
    // that leaves every shoe unplayed again — costs a rebuild, and every card
    // in between costs nothing.
    if (_dealt != was) setState(() {});
  }

  /// Whether closing now would throw anything away. See [Deck.dealt].
  ///
  /// Any shoe, not the one in front of you: closing takes all three away, and
  /// a table that asked about the shoe on screen while quietly dropping the
  /// two beside it would be asking the wrong question.
  bool get _dealt {
    for (final _Shoe shoe in _shoes) {
      if (shoe.table.deck.dealt) return true;
    }
    return false;
  }

  /// Leaves the table, asking first if there is a shoe to lose.
  ///
  /// The question is a slide rather than a button, because what it is guarding
  /// against is not a decision but a stray thumb: Close sits an inch from
  /// Draw, and the two get pressed by the same hand doing the same thing. A
  /// second button under the first is a second thing to hit by accident; a
  /// drag from one side of the dialog to the other is not.
  /// A second tap on Close while the question is up needs no guard here, and
  /// there is deliberately not one: the dialog is modal, so the tap that would
  /// have asked twice lands on its barrier instead and takes the question away
  /// again. Which leaves the table open, which is the safe end of the mistake
  /// — see the double tap in `cards_test.dart`.
  Future<void> _close() async {
    final NavigatorState navigator = Navigator.of(context);
    if (!_dealt) {
      navigator.pop();
      return;
    }
    // The message says how many shoes are going, because closing takes all of
    // them and somebody who has only dealt from the one in front of them has
    // no reason to expect that.
    final bool many = _shoes.length > 1;
    final bool go = await showSlideConfirmDialog(
      context,
      title: 'Close the cards?',
      message:
          many
              ? 'All ${_shoes.length} shoes go back in the box, not just this one. '
                  'What has been dealt will be forgotten, and the next table '
                  'starts from a full shuffle.'
              : 'The shoe goes back in the box. What has been dealt will be '
                  'forgotten, and the next table starts from a full shuffle.',
      slide: 'Slide to close',
    );
    if (go && mounted) navigator.pop();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        _manual?.shake();
      case LogicalKeyboardKey.keyR:
        _draw();
      default:
        return;
    }
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
      (_shoes.length - 1).toDouble(),
    );
  }

  void _dragEnd(DragEndDetails details) {
    if (!_dragging) return;
    // A flick carries the table on its own; otherwise a quarter of the way
    // over is far enough to mean it, and anything less springs back.
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
      _slide = _Slide(from: _page.value, to: to.clamp(0, _shoes.length - 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    // The back gesture is the other way out of here, and it is the *easier*
    // one to make by accident — a thumb on the left edge of a phone being
    // handed across a table. So it goes through the same question, and
    // `canPop` is what decides whether there is one to ask: false once a shoe
    // has been played, which hands the pop to [_close] instead. Before that it
    // is true, deliberately, because a screen that intercepts every pop is a
    // screen whose swipe-back stops animating for no reason.
    return PopScope<Object?>(
      canPop: !_dealt,
      onPopInvokedWithResult: (bool popped, Object? result) {
        if (!popped) unawaited(_close());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0E13),
        body: KeyboardListener(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _handleKey,
          child: letterbox(
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                _ensureTables(constraints.biggest);
                final bool paged = _shoes.length > 1;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Only wired up when there is somewhere to go, so a single
                  // shoe behaves exactly as it did before there were shoes.
                  onHorizontalDragStart: paged ? _dragStart : null,
                  onHorizontalDragUpdate: paged ? _dragUpdate : null,
                  onHorizontalDragEnd: paged ? _dragEnd : null,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      CustomPaint(
                        painter: CardPagesPainter(
                          tables: <CardTable>[
                            for (final _Shoe shoe in _shoes) shoe.table,
                          ],
                          page: _page,
                          repaint: _repaint,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: SafeArea(
                          bottom: false,
                          minimum: const EdgeInsets.only(top: 44),
                          // The clock rides *in* the row, between the two
                          // buttons; the dots go under the whole of it. The
                          // tray does the same, and the reason is written
                          // there: a row whose middle child is a column of
                          // both is a row that grows when the timer is
                          // switched on, and a taller row moves Close and
                          // Draw down the screen with it.
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
                                      onTap: () => unawaited(_close()),
                                    ),
                                    // Read at build rather than obeyed further
                                    // down: the setting is behind the picker,
                                    // two screens away, and cannot change
                                    // while a table is open. Left out entirely
                                    // when it is off, which lays the row out
                                    // exactly as the two buttons on their own
                                    // always were.
                                    if (settings.timer)
                                      ElapsedTimer(
                                        key: kElapsedTimer,
                                        seconds: _clock,
                                        limit: settings.limit,
                                      ),
                                    // Draw, not Throw: there is nothing in the
                                    // box that could be thrown.
                                    TrayButton(
                                      label: 'Draw',
                                      onTap: _draw,
                                      emphasis: true,
                                    ),
                                  ],
                                ),
                              ),
                              if (paged)
                                PageDots(
                                  key: kCardDots,
                                  current: _at,
                                  filled: List<bool>.filled(
                                    _shoes.length,
                                    true,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      // Last, so the flash is over the buttons as well as the
                      // card.
                      TimeUpAlert(trigger: _alert),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// One shoe's table, and what its own clock is at.
///
/// The card side's `_Box`, and per shoe for the same reason: a shoe is its own
/// memory, so dealing from the one beside this one says nothing about how long
/// ago this one was dealt from.
class _Shoe {
  _Shoe({required this.table});

  final CardTable table;

  /// Seconds since a card was last put on this glass, or null while there is
  /// none there.
  ///
  /// Null is a real answer and not a zero, even though [ElapsedTimer] draws
  /// both as `0:00`: a bare glass is what a table opens on and what a
  /// reshuffle leaves behind, and it is the difference between a clock that is
  /// stopped and one that has just been started. Nothing null can be past its
  /// limit, and nothing null fires an alert.
  double? sinceDeal;

  /// Whether this shoe has already run its turn out, so the alert fires once
  /// and not on every frame past the limit.
  bool alerted = false;
}

/// A swipe coasting to a stop.
class _Slide {
  _Slide({required this.from, required this.to});

  final double from;
  final int to;
  double elapsed = 0;
}
