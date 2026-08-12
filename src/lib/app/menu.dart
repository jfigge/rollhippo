import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../tray/tray.dart';
import 'chrome.dart';
import 'haptics.dart';
import 'scan_screen.dart';
import 'settings.dart';
import 'tray_screen.dart';

/// How many steps the calibration slider has between off and [_kMaxGain].
///
/// Notched rather than continuous. The underlying value is a multiplier and
/// changing it by a hundredth changes nothing anyone can feel, so a smooth
/// slider would be a control that mostly does not respond — and each notch is
/// one tap played back, which makes dragging it an actual comparison.
const int _kGainSteps = 12;

/// The top of the slider. See [Tuning.hapticMaxGain].
const double _kMaxGain = Tuning.hapticMaxGain;

/// The menu button's tap target, the icon centred inside it, and how thick a
/// stroke the three lines are drawn with.
///
/// 48 is the accessibility minimum for something a thumb has to find, and what
/// [IconButton] gives you by default; 26 is the size that matches the title it
/// sits beside.
///
/// The stroke is why the lines are drawn here rather than set in `Icons.menu`.
/// Every Material glyph is 2 points thick on a 24-point grid whatever size it
/// is used at, which beside a 26-point title puts a heavier mark on the screen
/// than the capital R it is level with. There is no lighter hamburger in the
/// font — the weight is in the outlines — so the only way to a thinner one is
/// to stop asking the font for it.
const double _kMenuTarget = 48;
const double _kMenuIcon = 26;
const double _kMenuStroke = 1.5;

/// Where the three lines sit inside the icon's own box, as fractions of it.
///
/// Material's own grid, kept to the point: `Icons.menu` runs its bars from 3
/// to 21 across a 24-point square, centred on 7, 12 and 17 down it. Drawing
/// them somewhere else would move the button out from under everything that
/// lines up against [kAppMenuInset].
const double _kMenuBarInset = 3 / 24;
const List<double> _kMenuBarRows = <double>[7 / 24, 12 / 24, 17 / 24];

/// How far into [AppMenuButton] its three strokes actually begin.
///
/// The visible part of this button is a good deal smaller than the box it
/// needs for a thumb, which matters to anything trying to line it up with
/// something else. The icon floats in the middle of a tap target nearly twice
/// its size, and the lines begin an eighth of the icon in from that. Fourteen
/// and a quarter points, all told.
const double kAppMenuInset =
    (_kMenuTarget - _kMenuIcon) / 2 + _kMenuIcon * _kMenuBarInset;

/// The two sliders on this sheet, so a test can drag the one it means. Neither
/// has a label a finder could reach it by, and "the slider in the sheet"
/// stopped being one thing the moment there were two.
const Key kGainSlider = ValueKey<String>('gain-slider');
const Key kLimitSlider = ValueKey<String>('limit-slider');

/// The menu button itself, so the tutorial can point at it. The one thing on
/// the picker that is about the app rather than about the dice, and the only
/// way to Settings — which makes it worth a page of its own.
const Key kAppMenu = ValueKey<String>('app-menu');

/// The app menu: three lines, top left.
///
/// Everything in it is about the app rather than about the dice in front of
/// you, which is why it is a menu and not four more buttons on a screen that
/// already has enough. Settings is about the phone, Scan is about somebody
/// else's, and How to use is about the app itself — none of the three is about
/// the set of dice you are looking at, which is the whole of the test.
///
/// How to use is last, and last is where it belongs: it is the entry a first
/// run has already shown you and the only one you reach for when something
/// else has not worked. The two above it are the ones somebody comes here
/// meaning to press.
///
/// Sharing used to be the third, and is not, because it is the one thing here
/// that was never about the app. A code *is* a profile, so it belongs to a
/// profile — the menu a save gives you when you hold it down, beside the Save
/// and the Rename and the Delete that already act on that same save. See
/// `profile_row.dart`. What is left up here needs no profile at all, which is
/// why this button no longer takes one.
class AppMenuButton extends StatefulWidget {
  const AppMenuButton({
    super.key,
    required this.onScanned,
    required this.onTutorial,
  });

  /// Handed the profile a scanned code described, and the name that came
  /// with it. Not called if the scanner was closed without finding one.
  final ValueChanged<ScannedProfile> onScanned;

  /// What **How to use** does. A callback rather than a call, because the
  /// tutorial draws a picker behind itself and the picker is what builds this
  /// button — so a menu that opened the tutorial itself would put a cycle
  /// through three files. See `PickerScreen._tutorial`.
  final VoidCallback onTutorial;

  @override
  State<AppMenuButton> createState() => _AppMenuButtonState();
}

enum _MenuItem { settings, scan, tutorial }

class _AppMenuButtonState extends State<AppMenuButton> {
  Future<void> _run(_MenuItem item) async {
    switch (item) {
      case _MenuItem.settings:
        await showSettingsSheet(context);
      case _MenuItem.scan:
        await _scan();
      case _MenuItem.tutorial:
        widget.onTutorial();
    }
  }

  Future<void> _scan() async {
    final ScannedProfile? scanned = await Navigator.of(context).push(
      MaterialPageRoute<ScannedProfile>(
        builder: (BuildContext context) => const ScanScreen(),
      ),
    );
    if (scanned == null || !mounted) return;
    widget.onScanned(scanned);
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuItem>(
      tooltip: 'Menu',
      position: PopupMenuPosition.under,
      color: const Color(0xFF141A23),
      // Enough to lift the card off the picker, and no more. The default
      // shadow against a screen this dark is a hard black ring rather than a
      // shadow, because there is nothing under it for the light to fall on.
      elevation: 6,
      shadowColor: const Color(0x66000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0x14FFFFFF)),
      ),
      padding: EdgeInsets.zero,
      icon: const _MenuBars(),
      // The card arriving is the moment worth confirming, and it is the
      // firmer of the two taps — see [uiHaptic], which is where the pair is
      // explained. The entry you then pick out of it is the lighter one,
      // because taking it does something you can see.
      onOpened: () => uiHaptic(HapticLevel.medium),
      onSelected: (_MenuItem item) {
        uiHaptic(HapticLevel.light);
        unawaited(_run(item));
      },
      itemBuilder:
          (BuildContext context) => <PopupMenuEntry<_MenuItem>>[
            _entry(_MenuItem.settings, Icons.tune, 'Settings'),
            _entry(_MenuItem.scan, Icons.qr_code_scanner, 'Scan'),
            _entry(_MenuItem.tutorial, Icons.help_outline, 'How to use'),
          ],
    );
  }

  PopupMenuItem<_MenuItem> _entry(_MenuItem item, IconData icon, String label) {
    return PopupMenuItem<_MenuItem>(
      value: item,
      height: 46,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: const Color(0xAABFD0E4)),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: Color(0xFFE8EEF6), fontSize: 15),
          ),
        ],
      ),
    );
  }
}

/// Three lines, thinner than the font draws them. See [_kMenuStroke].
class _MenuBars extends StatelessWidget {
  const _MenuBars();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    // The size the glyph was, so the button keeps the tap target it had and
    // [kAppMenuInset] keeps meaning what it says.
    dimension: _kMenuIcon,
    child: CustomPaint(painter: _MenuBarsPainter()),
  );
}

class _MenuBarsPainter extends CustomPainter {
  const _MenuBarsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint =
        Paint()
          ..color = const Color(0xFFBFD0E4)
          ..strokeWidth = _kMenuStroke;
    final double left = size.width * _kMenuBarInset;
    final double right = size.width - left;
    for (final double row in _kMenuBarRows) {
      final double y = size.height * row;
      // Butt ends, not round: a rounded cap hangs half a stroke past each end,
      // and the left one is the edge the subtitle and the rack line up with.
      canvas.drawLine(Offset(left, y), Offset(right, y), paint);
    }
  }

  @override
  bool shouldRepaint(_MenuBarsPainter oldDelegate) => false;
}

/// How long a disclosure takes to open, and how long the arrow takes to turn.
///
/// Short. This is a panel opening under a thumb that is still on it, not a
/// transition between screens — anything slower reads as the sheet thinking
/// about it.
const Duration _kExpand = Duration(milliseconds: 180);

/// The three voices on this sheet: what a setting is called, what it does, and
/// why it is the way it is.
///
/// The summary is a shade brighter than the argument under it, because it is
/// the line that is always on the screen and the argument is the one you asked
/// for.
const TextStyle _kSettingTitle = TextStyle(
  color: Color(0xFFE8EEF6),
  fontSize: 15,
  fontWeight: FontWeight.w600,
);
const TextStyle _kSettingSummary = TextStyle(
  color: Color(0xBBBFD0E4),
  fontSize: 13,
  height: 1.45,
);
const TextStyle _kSettingDetail = TextStyle(
  color: Color(0x99BFD0E4),
  fontSize: 13,
  height: 1.45,
);

/// Which explanation is open. See [_SettingsSheetState._open].
enum _Panel { motion, shake, impact, timer, limit }

/// The settings panel: three switches and two sliders, each one sentence tall
/// until you ask it for more.
///
/// Every entry is a title, its control, and one line saying what it does now.
/// The argument for it — which on this sheet runs to a paragraph, because the
/// arguments are real and two of them are the reason the setting exists — is
/// behind the arrow beside the control. That is the whole of how four settings
/// fit on a phone where the prose alone used to be eight hundred points tall,
/// and it is what leaves room for the fifth.
///
/// **What stays visible is the consequence, and that is not an accident.**
/// Shake to deal is the switch whose downside is not obvious from its label,
/// and "a dealt card is gone until the shoe is cut" has to be on the screen of
/// somebody reaching for it rather than one tap further in. The paragraph
/// underneath argues *why* a shake on the cards is a different act from a
/// shake on the tray, and that can wait to be asked for. Anything moved behind
/// the arrow has to pass that test: reasoning, never a cost.
///
/// One panel is open at a time. The point of the sheet is that it is short,
/// and four open panels are the sheet that was there before.
///
/// Two of the five are pairs rather than entries in a list, and they are drawn
/// the same way for the same reason: indented under the switch they depend on,
/// faded and deaf while it is off. Shake to deal is nothing without Motion
/// control, because a still phone is never shaken; Turn limit is nothing
/// without Timer, because what it does when it runs out is turn a clock red.
/// See [Settings.shakeToDraw] and [Settings.limit].
Future<void> showSettingsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xB3000000),
      constraints: const BoxConstraints(maxWidth: kSheetWidth),
      // Otherwise a sheet is capped at nine sixteenths of the screen. It is far
      // shorter than it was, but an open panel on a small phone can still reach
      // past that, and this is also what lets it grow as one opens.
      isScrollControlled: true,
      builder: (BuildContext context) => const _SettingsSheet(),
    );

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  /// The sheet's own engine, used for nothing but playing the slider back.
  ///
  /// Not the tray's. This one is never fed a tray frame, so its gap and its
  /// escalation rule are irrelevant — [HapticEngine.demo] steps round them.
  late final HapticEngine _engine = HapticEngine(
    driver: hapticsFor(device: onDevice),
    gain: settings.hapticGain,
  );

  /// Which argument is on the screen, or null for none — which is where the
  /// sheet opens every time. Nothing is remembered between openings: the
  /// question a panel answers is one you have either already read or are about
  /// to ask again, and a sheet that reopened three lines taller than it closed
  /// would have given back the space it was rewritten for.
  _Panel? _open;

  void _toggle(_Panel panel) {
    // A press the screen answers is the lighter of the two taps — see
    // [uiHaptic], where the pair is argued.
    uiHaptic(HapticLevel.light);
    setState(() => _open = _open == panel ? null : panel);
  }

  void _setGain(double value) {
    settings.hapticGain = value;
    _engine.gain = settings.hapticGain;
    // The whole point of the control. A multiplier is not a sensation, and
    // nobody can set this one by reading it — so every notch answers in the
    // currency it is denominated in, at the strength an ordinary throw would
    // produce. Dragging the slider is a side-by-side comparison.
    _engine.demo();
  }

  /// One switch, in the sheet's colours. Three of these differing only in what
  /// they are wired to is three chances for one of them to be a different blue.
  Widget _switch({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Switch(
    value: value,
    activeThumbColor: const Color(0xFF6E9AD0),
    activeTrackColor: const Color(0xFF3F6FA8),
    inactiveThumbColor: const Color(0xAABFD0E4),
    inactiveTrackColor: const Color(0x14FFFFFF),
    onChanged: onChanged,
  );

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: 'Settings',
      child: ListenableBuilder(
        listenable: settings,
        builder: (BuildContext context, _) {
          final double gain = settings.hapticGain;
          final int limit = settings.limit;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // First, because it is the larger of the two: one of these
              // settings is how hard the app taps back, and the other is
              // whether the phone's own movement plays at all.
              _Setting(
                title: 'Motion control',
                expanded: _open == _Panel.motion,
                onTap: () => _toggle(_Panel.motion),
                control: _switch(
                  value: settings.motion,
                  onChanged: (bool on) => settings.motion = on,
                ),
                summary:
                    settings.motion
                        ? 'Tilt to pour the dice down the screen, shake to '
                            'throw them.'
                        : 'Off. Down is down the screen and stays there, and a '
                            'shake does nothing.',
                detail:
                    settings.motion
                        ? 'Turn it off and the tray is handed a phone held '
                            'perfectly still: down is down the screen whatever '
                            'the real one is doing, and Throw — or Draw, on '
                            'the cards — is the whole of the interface.\n\n'
                            'It is a real setting rather than an accessibility '
                            'afterthought. A phone on a table, a hand that '
                            'cannot shake one, a game being played on a train '
                            '— all of them want the dice and none of them '
                            'wants the accelerometer.'
                        : 'The tray is being handed a phone held perfectly '
                            'still. Throw — or Draw, on the cards — is the '
                            'whole of the interface, and it works exactly as '
                            'it always did.\n\n'
                            'It is a real setting rather than an accessibility '
                            'afterthought. A phone on a table, a hand that '
                            'cannot shake one, a game being played on a train '
                            '— all of them want the dice and none of them '
                            'wants the accelerometer.',
              ),
              // Underneath the switch it depends on, and indented under it,
              // because it is a narrowing of that setting rather than a
              // setting beside it: with motion off there is no shake to deal
              // on, so the control has nothing to say and says nothing —
              // faded and deaf, which is the same bargain the picker's editor
              // makes with an empty group.
              const SizedBox(height: 16),
              IgnorePointer(
                ignoring: !settings.motion,
                child: Opacity(
                  opacity: settings.motion ? 1 : 0.38,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: _Setting(
                      title: 'Shake to deal a card',
                      expanded: _open == _Panel.shake,
                      onTap: () => _toggle(_Panel.shake),
                      control: _switch(
                        value: settings.shakeToDraw,
                        onChanged: (bool on) => settings.shakeToDraw = on,
                      ),
                      // What it costs, said plainly and said out here, because
                      // this is the one switch in the app whose downside is
                      // not obvious from the label. Everything else on this
                      // sheet is undone by doing it again.
                      summary:
                          settings.shakeToDraw
                              ? 'On. A shake takes the next card off the shoe, '
                                  'and there is no dealing it back.'
                              : 'Off, and worth leaving off. A dealt card is '
                                  'gone until the shoe is cut, and a phone '
                                  'handed across a table is a shake.',
                      detail:
                          'A shake on the tray and a shake on the card table '
                          'are not the same act. Shaking dice is the '
                          'simulation — the box moved, so the dice tumbled — '
                          'and a throw you did not mean is undone by throwing '
                          'again.\n\n'
                          'A shoe has memory, and that is the whole reason to '
                          'play with one. What has been dealt is off the shoe '
                          'until the cut comes round, so what is left to come '
                          'has genuinely changed. Draw turns the next card '
                          'over either way.',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _Setting(
                title: 'Impact strength',
                expanded: _open == _Panel.impact,
                onTap: () => _toggle(_Panel.impact),
                // The figure rather than a switch: this is the one setting
                // here that is a quantity, and the number is what says where
                // the slider under it has got to.
                control: Text(
                  gain <= 0 ? 'Off' : '${(gain * 100).round()}%',
                  style: const TextStyle(
                    color: Color(0xAABFD0E4),
                    fontSize: 14,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
                under: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF3F6FA8),
                    inactiveTrackColor: const Color(0x1AFFFFFF),
                    thumbColor: const Color(0xFF6E9AD0),
                    overlayColor: const Color(0x223F6FA8),
                    valueIndicatorColor: const Color(0xFF3F6FA8),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    key: kGainSlider,
                    value: gain.clamp(0.0, _kMaxGain),
                    max: _kMaxGain,
                    divisions: _kGainSteps,
                    onChanged: _setGain,
                  ),
                ),
                summary:
                    gain <= 0
                        ? 'Off, and off for the whole app — the tray, the '
                            'menus and the profiles.'
                        : 'How hard the tray taps back when a die hits the '
                            'side. Drag the slider to feel it.',
                detail:
                    'The tap follows the impact, so a D20 slamming into a wall '
                    'is felt and a die nudging its neighbour is not — this '
                    'only sets how much of that reaches your hand.\n\n'
                    'The interface taps too, at a fixed strength rather than '
                    'at whatever this slider says: a light one for a menu '
                    'entry or a profile you have pressed, and a firmer one as '
                    'a menu opens under your thumb, that being the only sign a '
                    'press was long enough. All the way down silences those as '
                    'well as the tray.',
                aside:
                    onDevice
                        ? null
                        : 'Nothing to feel here — this is the desktop harness, '
                            'and it has no actuator to tap with.',
              ),
              const SizedBox(height: 18),
              // Last. The three above are about what the phone does with a
              // hand — how it is moved, and how it answers back — where this
              // one only decides whether one more thing is drawn.
              _Setting(
                title: 'Timer',
                expanded: _open == _Panel.timer,
                onTap: () => _toggle(_Panel.timer),
                control: _switch(
                  value: settings.timer,
                  onChanged: (bool on) => settings.timer = on,
                ),
                summary:
                    settings.timer
                        ? 'A clock between Close and Throw, counting up from '
                            'the last roll.'
                        : 'No clock. Turn it on for one between Close and '
                            'Throw, counting up from the last roll.',
                detail:
                    'On the card table it counts from the last card instead. '
                    'Each set of dice keeps its own, so swiping to another '
                    'says how long ago that one was thrown — and a set nobody '
                    'has thrown yet shows nothing at all, because 0:00 would '
                    'be a lie about it.\n\n'
                    'It measures and does nothing else — until you give it a '
                    'limit, and even then all that runs out is the colour.',
              ),
              // Under the clock it colours, and indented under it, on exactly
              // the terms Shake to deal is under Motion control: a limit with
              // no clock to turn red is a setting that would do nothing and
              // say nothing about having done it.
              const SizedBox(height: 16),
              IgnorePointer(
                ignoring: !settings.timer,
                child: Opacity(
                  opacity: settings.timer ? 1 : 0.38,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: _Setting(
                      title: 'Turn limit',
                      expanded: _open == _Panel.limit,
                      onTap: () => _toggle(_Panel.limit),
                      control: Text(
                        // "None" rather than "Off", which is what the switches
                        // say and what the slider above says. A duration that
                        // has not been set is not a thing that has been turned
                        // off, and the two words sitting one above the other
                        // saying the same one would read as a repeat.
                        limit <= 0 ? 'None' : formatElapsed(limit),
                        style: const TextStyle(
                          color: Color(0xAABFD0E4),
                          fontSize: 14,
                          fontFeatures: <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      under: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF3F6FA8),
                          inactiveTrackColor: const Color(0x1AFFFFFF),
                          thumbColor: const Color(0xFF6E9AD0),
                          overlayColor: const Color(0x223F6FA8),
                          trackHeight: 4,
                        ),
                        child: Slider(
                          key: kLimitSlider,
                          value: stepForLimit(limit).toDouble(),
                          max: kLimitSteps.toDouble(),
                          divisions: kLimitSteps,
                          onChanged:
                              (double step) =>
                                  settings.limit = limitForStep(step.round()),
                        ),
                      ),
                      summary:
                          limit <= 0
                              ? 'No limit. Set one and the clock turns red '
                                  'when a turn runs past it.'
                              : 'At ${formatElapsed(limit)} the screen flashes '
                                  'three times, the phone taps with it, and '
                                  'the clock turns red.',
                      detail:
                          'Thirty seconds to five minutes, in quarter-minutes '
                          '— a turn limit is a thing people agree on out loud, '
                          'and it is never 47 seconds.\n\n'
                          'Nothing is prevented and nothing is scored. The '
                          'clock goes on counting up past the limit rather '
                          'than down towards it, because how far over a turn '
                          'has run is the useful number and it is still your '
                          'table\'s business what that costs. The next roll '
                          'puts it back to 0:00 and the colour with it.',
                      aside:
                          onDevice
                              ? null
                              : 'The flash is here on the harness; the taps '
                                  'need a phone.',
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One setting: what it is called, its control, what it does now, and — behind
/// the arrow — why.
///
/// The header row and the summary are both the tap that opens it, which is a
/// deliberately large target for a gesture nobody is obliged to make. The
/// control is not: a [Switch] and a [Slider] take their own presses, so the
/// thing you came for is never the thing that opens a paragraph.
class _Setting extends StatelessWidget {
  const _Setting({
    required this.title,
    required this.summary,
    required this.detail,
    required this.expanded,
    required this.onTap,
    required this.control,
    this.under,
    this.aside,
  });

  final String title;

  /// The line that is always there. What the setting is doing *now* and what
  /// that costs — never the argument for it, which is what [detail] is.
  final String summary;

  /// The argument, in paragraphs separated by a blank line. On the screen only
  /// while [expanded].
  final String detail;

  final bool expanded;
  final VoidCallback onTap;

  /// The switch, or the figure a slider is showing. On the title's own line.
  final Widget control;

  /// Anything that has to stay visible under the header whether or not the
  /// panel is open — which today is the one slider.
  final Widget? under;

  /// A footnote to [detail], drawn in italic. The harness has one; nothing
  /// else does yet.
  final String? aside;

  @override
  Widget build(BuildContext context) {
    final Widget? under = this.under;
    final String? aside = this.aside;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            children: <Widget>[
              Expanded(child: Text(title, style: _kSettingTitle)),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: _kExpand,
                curve: Curves.easeOut,
                child: const Icon(
                  Icons.expand_more,
                  size: 20,
                  color: Color(0x66BFD0E4),
                ),
              ),
              const SizedBox(width: 12),
              control,
            ],
          ),
        ),
        if (under != null) under,
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Text(summary, style: _kSettingSummary),
        ),
        // Sized rather than faded: the sheet has to grow and shrink around
        // this, and a paragraph that was always laid out and merely invisible
        // would have saved nothing at all. The empty box keeps the full width
        // so the animation is in one dimension only.
        AnimatedSize(
          duration: _kExpand,
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: double.infinity,
            child:
                !expanded
                    ? const SizedBox.shrink()
                    : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(detail, style: _kSettingDetail),
                          if (aside != null) ...<Widget>[
                            const SizedBox(height: 10),
                            Text(
                              aside,
                              style: const TextStyle(
                                color: Color(0x66BFD0E4),
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
          ),
        ),
      ],
    );
  }
}

/// The Share sheet: this profile, as a square somebody else can point a
/// phone at.
Future<void> showShareSheet(
  BuildContext context,
  Profile profile,
  String name,
) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Colors.transparent,
  barrierColor: const Color(0xB3000000),
  constraints: const BoxConstraints(maxWidth: kSheetWidth),
  isScrollControlled: true,
  builder: (BuildContext context) => _ShareSheet(profile: profile, name: name),
);

class _ShareSheet extends StatelessWidget {
  const _ShareSheet({required this.profile, required this.name});

  final Profile profile;
  final String name;

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: 'Share',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: ShareCodeView(code: encodeProfile(profile, name: name)),
          ),
          const SizedBox(height: 16),
          Text(
            name.isEmpty ? profile.summary : '$name · ${profile.summary}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFE8EEF6),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            // What is actually in the square, said plainly, because the one
            // thing a QR code cannot do is tell you what it is about to do to
            // the phone that reads it.
            'The whole set-up: which page you are on, every die, its kind and '
            'its colour, and — in card mode — the shoe you built. Scan it from '
            'another phone to set that one up the same way.'
            '${name.isEmpty ? '' : ' The name goes with it, so they can keep '
                    'it as "$name".'}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0x99BFD0E4),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// One share code, drawn.
///
/// Its own widget rather than a `QrImageView` inline, because [QrImageView]
/// keeps the string it was handed private — so this is the only way anything
/// outside the sheet, a test included, can ask what is actually in the square.
class ShareCodeView extends StatelessWidget {
  const ShareCodeView({super.key, required this.code});

  /// The payload, from [encodeProfile].
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // White, and with a margin of it. A QR code needs a light quiet zone
        // round the outside to be found at all, and this app is otherwise
        // entirely dark — so the code gets its own paper rather than being
        // asked to work against the sheet.
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: QrImageView(
        data: code,
        version: QrVersions.auto,
        // The weakest correction, deliberately. The payload is under fifty
        // characters, so even at level L the code is a coarse grid of large
        // modules — which is far easier for the other phone to find across a
        // table than a dense one carrying redundancy it does not need. This is
        // a screen being held up for ten seconds, not a label on a crate.
        errorCorrectionLevel: QrErrorCorrectLevel.L,
        size: 230,
        gapless: true,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF0B0E13),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF0B0E13),
        ),
      ),
    );
  }
}

/// The chrome both sheets share: a grab handle, a title, and the dark card.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141A23),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: SafeArea(
        top: false,
        // A sheet is as tall as what is in it, and what is in it does not
        // change — but the screen does. On a short phone the Share sheet's
        // code and its caption are taller than the space a modal sheet is
        // allowed, and the alternative to scrolling there is a caption nobody
        // can read and a yellow overflow bar in debug.
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0x33FFFFFF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFE8EEF6),
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
