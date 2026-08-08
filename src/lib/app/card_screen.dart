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
/// thing the accelerometer is asked for is whether the phone was shaken. With
/// motion control off it is not asked even that, and Draw is the whole of the
/// interface. See [Settings.motion].
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
  Size _size = Size.zero;

  Duration _last = Duration.zero;

  /// Counts up from the last card dealt. See [_kDrawCooldown].
  double _since = _kDrawCooldown;

  final FocusNode _focus = FocusNode();

  /// Ticked on every frame a card is in the air, and on no other. Nothing on
  /// this table moves by itself, so this is the whole of what the painter has
  /// to watch. See [CardPainter.repaint].
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _motion = motionSourceFor(device: onDevice, motion: settings.motion);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _focus.dispose();
    _frame.dispose();
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

    // The whole of what the sensors are for here. Sampled every frame whether
    // or not it is wanted, because the source averages over the interval since
    // it was last asked and skipping frames would hand it one enormous one.
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

  void _ensureTable(Size size) {
    if (_table != null && size == _size) return;
    _size = size;
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
    _since = 0;
    table.draw();
    _frame.value++;
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
    return Scaffold(
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
                                onTap: () => Navigator.of(context).pop(),
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
