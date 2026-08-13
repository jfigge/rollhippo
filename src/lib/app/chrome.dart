import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'haptics.dart';

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

/// On a device the tray *is* the screen. Everywhere else it is pinned to
/// [kHarnessScreen] and scaled to fit, so the harness and the phone are
/// showing the same tray.
Widget letterbox(Widget child) {
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

/// One of the two controls along the top of a tray.
class TrayButton extends StatelessWidget {
  const TrayButton({
    super.key,
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

/// The clock along the top, named so a test can find it whichever screen it is
/// on. It is the one thing up there that says nothing about the dice.
const Key kElapsedTimer = ValueKey<String>('elapsed-timer');

/// How long since the last Throw or Draw, as `m:ss`.
///
/// Between Close and the button that resets it, on both screens, and off
/// unless somebody asked for it — see [Settings.timer]. It counts up and it
/// never counts down, even with a [limit] set: what a limit changes is the
/// colour, and the clock goes on saying how long it has actually been rather
/// than how much is left. A turn that has overrun by ninety seconds is a fact
/// worth reading, and `-1:30` is a worse way to say it.
///
/// It takes whole seconds rather than the running total, and that is the whole
/// of why it is cheap. A `ValueNotifier<int>` handed the same second sixty
/// times over notifies nobody, so a clock that changes once a second rebuilds
/// once a second — where a `double` ticking off the frame clock would rebuild
/// this subtree on every frame of a simulation that is deliberately not
/// rebuilding anything.
class ElapsedTimer extends StatelessWidget {
  const ElapsedTimer({super.key, required this.seconds, this.limit = 0});

  /// Whole seconds since the last throw or deal, or null if there has not been
  /// one — a group nobody has shaken yet, and a table whose glass is still
  /// bare, are both timing nothing.
  ///
  /// Both draw **0:00** rather than nothing. The clock used to be absent until
  /// there was something to count, on the argument that a zero would be a lie
  /// about a throw nobody had made. What that cost was worse than the lie: a
  /// setting you had just switched on showed you nothing at all until you
  /// threw, which reads as a setting that did not work. A clock reading zero
  /// is a clock that has not started, which is what everybody already takes a
  /// stopped clock to mean.
  ///
  /// The distinction is kept above this line rather than thrown away, because
  /// two other things still turn on it: nothing that has not been thrown can
  /// be past its limit, and nothing that has not been thrown fires an alert.
  final ValueListenable<int?> seconds;

  /// The turn limit in seconds, or zero for none. See [Settings.limit]. At or
  /// past it the clock is drawn in [kTimeUpInk] and stays there until the
  /// count starts again.
  final int limit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: seconds,
      builder: (BuildContext context, int? value, _) {
        // A clock nobody has started reads zero, and is never over its limit:
        // no time has passed for it to be past anything.
        final int elapsed = value ?? 0;
        final bool over = value != null && limit > 0 && elapsed >= limit;
        return Text(
          formatElapsed(elapsed),
          style: TextStyle(
            // The muted grey everything that is not asking to be pressed is
            // drawn in. A clock beside two buttons must not read as a third —
            // until the time is up, which is the one moment it is allowed to
            // be the loudest thing on a screen full of dice.
            color: over ? kTimeUpInk : const Color(0x99BFD0E4),
            fontSize: 15,
            fontWeight: FontWeight.w600,
            // Without these the 1 is narrower than every other figure, so the
            // whole clock shuffles sideways as the seconds turn over — which
            // is movement in the corner of your eye, once a second, for as
            // long as the screen is up.
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }
}

/// The colour of a turn that has run out: the clock's ink, and the wash the
/// screen flashes with as it happens.
///
/// A soft red rather than a pure one. Everything else on these screens is a
/// muted blue-grey, so this is already the only warm thing on the screen and
/// does not need to be a fire alarm as well — and it is drawn over dice that
/// somebody still has to read.
const Color kTimeUpInk = Color(0xFFE0685E);

/// How many times the screen flashes, how long the three of them take
/// together, and how far the wash gets.
///
/// Three, because it is the count somebody can take in without counting. 660
/// ms for all three is quick enough to read as one event rather than three.
/// And 0.22 is the ceiling on purpose: this goes over a tray of dice that is
/// still being read, so it has to be impossible to miss and impossible to hide
/// behind.
const int _kFlashes = 3;
const Duration _kAlertLength = Duration(milliseconds: 660);
const double _kWashPeak = 0.22;

/// The alert a turn running out gets: three flashes of the screen, with three
/// taps in step with them.
///
/// Both, rather than either. A phone face up on a table between four people is
/// seen and not felt; a phone in somebody's hand at the far end of the table is
/// felt long before it is looked at. Neither one on its own reaches both, and
/// they are the same event, which is why the taps come off the same controller
/// as the flashes rather than off a timer of their own that could drift out of
/// step with them.
///
/// Sound is the obvious third and is deliberately missing: this app has no
/// audio at all, and a beep would be the first thing it ever played — through a
/// dependency it does not have, over whatever the room is already listening to,
/// and out of a phone that may well be on silent. The taps are what a silent
/// phone can still do.
///
/// Driven by a counter rather than a flag. [trigger] is incremented to fire
/// it, so two turns running out one after another are two alerts, where a bool
/// going true a second time while already true would be none.
class TimeUpAlert extends StatefulWidget {
  const TimeUpAlert({super.key, required this.trigger});

  /// Bumped to fire the alert. Its value means nothing; its changing is the
  /// whole signal.
  final ValueListenable<int> trigger;

  @override
  State<TimeUpAlert> createState() => _TimeUpAlertState();
}

class _TimeUpAlertState extends State<TimeUpAlert>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kAlertLength,
  );

  /// How many of the three taps this run has already fired, so each flash gets
  /// one and a frame that lands twice inside the same flash gets none.
  int _tapped = 0;

  @override
  void initState() {
    super.initState();
    widget.trigger.addListener(_fire);
    _controller.addListener(_tap);
  }

  @override
  void didUpdateWidget(TimeUpAlert oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger == widget.trigger) return;
    oldWidget.trigger.removeListener(_fire);
    widget.trigger.addListener(_fire);
  }

  @override
  void dispose() {
    widget.trigger.removeListener(_fire);
    _controller.dispose();
    super.dispose();
  }

  void _fire() {
    _tapped = 0;
    _controller.forward(from: 0);
  }

  void _tap() {
    // Which flash the controller is inside. Each one taps as it begins, so the
    // tap and the light arrive together rather than the tap chasing it.
    final int flash = (_controller.value * _kFlashes).floor();
    if (flash >= _kFlashes || flash < _tapped) return;
    _tapped = flash + 1;
    // Heavier than anything the interface fires for a press, and deliberately.
    // See [uiHaptic]: those two strengths are both acknowledgements of
    // something you did. This is the app saying something you did not ask
    // about, which is the one case that has to arrive on its own.
    uiHaptic(HapticLevel.heavy);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          final double t = _controller.value;
          // Three humps: |sin| over three half-turns, which starts and ends at
          // nothing and needs no special case at either end.
          final double alpha =
              t <= 0 || t >= 1
                  ? 0
                  : math.sin(t * _kFlashes * math.pi).abs() * _kWashPeak;
          if (alpha <= 0) return const SizedBox.shrink();
          return ColoredBox(color: kTimeUpInk.withValues(alpha: alpha));
        },
      ),
    );
  }
}

/// `m:ss`, counting up.
///
/// The minutes are not padded and are deliberately not wrapped at an hour.
/// This measures a turn, and a turn that has genuinely run to sixty-three
/// minutes is better said as `63:00` than as `3:00` — the second of which is
/// a different, wrong answer rather than a shorter one.
String formatElapsed(int seconds) {
  final int whole = seconds < 0 ? 0 : seconds;
  final String s = (whole % 60).toString().padLeft(2, '0');
  return '${whole ~/ 60}:$s';
}

/// How wide a modal sheet is allowed to get.
///
/// The same number as the picker's rack, for the same reason rather than by
/// coincidence: a phone is narrower than this and fills it, and on a desktop
/// window an unconstrained sheet is a line of text you read across a foot of
/// screen, or a QR code the size of a beer mat.
///
/// Here rather than in `menu.dart`, where it was, because the tutorial is a
/// sheet too and the menu is what opens it — so a constant kept over there
/// would have to travel back through an import cycle to reach it. This file is
/// the chrome every screen shares and has nothing app-local of its own to
/// import, which is what makes it the one place both can see.
const double kSheetWidth = 440;

/// The card a dialog is drawn on: a title, and whatever answers it.
///
/// Here rather than beside the profile dialogs it was written for, and for the
/// same reason [kSheetWidth] is here — the slide-to-close dialog the cards ask
/// before they shut is not about profiles, and a second copy of this card
/// would be a second set of colours to keep in step with the first.
class AppDialog extends StatelessWidget {
  const AppDialog({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF141A23),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0x14FFFFFF)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFE8EEF6),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 18),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
