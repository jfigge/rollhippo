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
import 'settings.dart';
import 'slide_confirm.dart';

/// How long after a card is dealt before a shake can deal another.
///
/// A shake is not an instant: [ManualMotionSource.shake] runs for the better
/// part of a second and a real wrist does much the same, so without a wait one
/// flick would deal a fistful of cards before the hand had stopped. Longer than
/// the shake, so one shake is one card however hard it was.
const double _kDrawCooldown = 1.1;

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
class CardScreen extends StatefulWidget {
  const CardScreen({
    super.key,
    required this.dice,
    required this.decks,
    required this.reshuffleAt,
    this.colours = const <int>[],
  });

  /// How many dice a card stands for.
  final int dice;

  /// How many full sets are shuffled together.
  final int decks;

  /// The percentage of the shoe left at which it is reshuffled.
  final int reshuffleAt;

  /// What colour each die printed on a card is, one per die, in the order they
  /// are laid out down the card. Short — empty, for a screen that was opened
  /// without an opinion about it — and the rest are ivory.
  final List<int> colours;

  @override
  State<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends State<CardScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final MotionSource _motion;

  CardTable? _table;

  Duration _last = Duration.zero;

  /// Counts up from the last card dealt. See [_kDrawCooldown].
  double _since = _kDrawCooldown;

  /// Seconds since a card was last put on the glass, or null while there is
  /// none there.
  ///
  /// Not [_since], which starts a cooldown's worth ahead so that the first
  /// card is dealt on the first shake rather than a second later — this one
  /// has to be able to say that nothing has been dealt at all, and a bare
  /// glass is exactly what a reshuffle leaves behind as well as what a table
  /// opens on.
  double? _sinceDeal;

  /// The same in whole seconds, for the clock along the top. See
  /// [ElapsedTimer], which is where the reason it is whole is written down.
  final ValueNotifier<int?> _clock = ValueNotifier<int?>(null);

  /// Bumped when the turn runs out. See [TimeUpAlert].
  final ValueNotifier<int> _alert = ValueNotifier<int>(0);

  /// Whether this card has already run its turn out, so the alert fires once
  /// and not on every frame past the limit.
  bool _alerted = false;

  final FocusNode _focus = FocusNode();

  /// Ticked on every frame a card is in the air, and on no other. Nothing on
  /// this table moves by itself, so this is the whole of what the painter has
  /// to watch. See [CardPainter.repaint].
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

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

  void _onTick(Duration elapsed) {
    double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    dt = math.min(dt, 1 / 30);
    _since += dt;

    // The clock, which runs on real seconds and on nothing else — there is no
    // simulation here for it to be part of. Null until a card is on the glass,
    // and back to null when a reshuffle sweeps it off, because with nothing
    // dealt there is nothing for it to be counting since.
    final double? dealt = _sinceDeal;
    if (dealt != null) {
      final double now = dealt + dt;
      _sinceDeal = now;
      _clock.value = now.floor();
      final int limit = settings.timer ? settings.limit : 0;
      if (limit > 0 && !_alerted && now >= limit) {
        _alerted = true;
        _alert.value++;
      }
    }

    // The whole of what the sensors are for here. Sampled every frame whether
    // or not it is wanted, because the source averages over the interval since
    // it was last asked and skipping frames would hand it one enormous one.
    //
    // No test of the setting: by the time a frame gets here the answer is in
    // the source. A table nobody asked the shake for is being handed
    // [MotionFrame.still] sixty times a second, and a still phone is never a
    // shake.
    final MotionFrame motion = _motion.sample(dt);
    if (isShake(motion) && _since >= _kDrawCooldown) _draw();

    // And the only things on this table that move: the card arriving and the
    // card it is replacing, which leaves at the same time. `busy` is both of
    // them, and it has to be both — a reshuffle sweeps a card away with
    // nothing following it, and ticking on the flight alone would leave that
    // one hanging half off the bottom of the box for ever.
    //
    // The test is before the advance rather than after it, so the frame the
    // card lands on is painted too — asking afterwards would leave it drawn a
    // frame short of the glass and nothing would come along to finish it.
    final CardTable? table = _table;
    if (table != null && table.deal.busy) {
      table.advance(dt);
      _frame.value++;
    }
  }

  /// Builds the table, the first time there is a screen to build it for.
  ///
  /// Once, like the tray's boxes and for a sharper version of their reason: a
  /// new [CardTable] is a new [Deck], and a new Deck is a shuffle. A phone put
  /// into split screen mid-game would have swept the card off the glass and
  /// put the whole shoe back together, which is the one thing a shoe must only
  /// ever do when it is asked to. The table keeps the size it was built at and
  /// [cameraFor] fits it into the room there is.
  void _ensureTable(Size size) {
    if (_table != null || size.isEmpty) return;
    _table = CardTable(
      width: size.width / Tuning.logicalPixelsPerMetre,
      height: size.height / Tuning.logicalPixelsPerMetre,
      deck: Deck(
        dice: widget.dice,
        decks: widget.decks,
        reshuffleAt: widget.reshuffleAt,
      ),
      colours: widget.colours,
    );
  }

  /// Turns the top card over, or reshuffles if the shoe is down to the cut.
  ///
  /// A repaint rather than a rebuild: nothing above the painter has anything
  /// to say about which card is showing, and the flight that follows is a
  /// repaint a frame anyway. The card itself is dealt here and now — the
  /// animation is it arriving, not it being chosen.
  void _draw() {
    final CardTable? table = _table;
    if (table == null) return;
    final bool was = table.deck.dealt;
    _since = 0;
    table.draw();
    // A reshuffle is a draw that deals no card: the pile goes back together
    // and the glass is left bare. So the clock is not restarted, it is put
    // away — see [Deck.draw], which is where that being a state worth seeing
    // is argued.
    final bool onGlass = table.deck.shown != null;
    _sinceDeal = onGlass ? 0 : null;
    _clock.value = onGlass ? 0 : null;
    _alerted = false;
    _frame.value++;
    // The one thing on this screen a card can change above the painter: a
    // played shoe is a shoe you are asked about before it is closed, and
    // [PopScope.canPop] is read at build time rather than at the moment of
    // the gesture. So the first card of a shoe — and the reshuffle that ends
    // one — costs a rebuild, and every card in between costs nothing.
    if (table.deck.dealt != was) setState(() {});
  }

  /// Whether closing now would throw anything away. See [Deck.dealt].
  bool get _dealt => _table?.deck.dealt ?? false;

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
    final bool go = await showSlideConfirmDialog(
      context,
      title: 'Close the cards?',
      message:
          'The shoe goes back in the box. What has been dealt will be '
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

  @override
  Widget build(BuildContext context) {
    // The back gesture is the other way out of here, and it is the *easier*
    // one to make by accident — a thumb on the left edge of a phone being
    // handed across a table. So it goes through the same question, and
    // `canPop` is what decides whether there is one to ask: false once the
    // shoe has been played, which hands the pop to [_close] instead. Before
    // that it is true, deliberately, because a screen that intercepts every
    // pop is a screen whose swipe-back stops animating for no reason.
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
                _ensureTable(constraints.biggest);
                final CardTable table = _table!;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      CustomPaint(
                        painter: CardPainter(table: table, repaint: _frame),
                      ),
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
                                  onTap: () => unawaited(_close()),
                                ),
                                // Between them, and only if it was asked for.
                                // Read at build rather than obeyed further
                                // down: the setting is behind the picker, two
                                // screens away, and cannot change while a
                                // table is open. Left out entirely when it is
                                // off, which lays the row out exactly as the
                                // two buttons on their own always were.
                                if (settings.timer)
                                  ElapsedTimer(
                                    key: kElapsedTimer,
                                    seconds: _clock,
                                    limit: settings.limit,
                                  ),
                                // Draw, not Throw: there is nothing in the box
                                // that could be thrown.
                                TrayButton(
                                  label: 'Draw',
                                  onTap: _draw,
                                  emphasis: true,
                                ),
                              ],
                            ),
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
