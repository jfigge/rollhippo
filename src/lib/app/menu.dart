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
      onSelected: (_MenuItem item) => unawaited(_run(item)),
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

/// The settings panel: what the phone does, in three switches and a slider.
///
/// The first two are a pair rather than two entries in a list. Motion control
/// is the larger — whether the phone's own movement plays at all — and Shake
/// to deal is drawn underneath and inside it, because it only means anything
/// while the first is on and because it is the one control here that is off
/// until asked for. See [Settings.shakeToDraw].
Future<void> showSettingsSheet(
  BuildContext context,
) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Colors.transparent,
  barrierColor: const Color(0xB3000000),
  constraints: const BoxConstraints(maxWidth: kSheetWidth),
  // Otherwise a sheet is capped at nine sixteenths of the screen, and the
  // paragraph explaining what the slider does is the part that goes missing.
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

  void _setGain(double value) {
    settings.hapticGain = value;
    _engine.gain = settings.hapticGain;
    // The whole point of the control. A multiplier is not a sensation, and
    // nobody can set this one by reading it — so every notch answers in the
    // currency it is denominated in, at the strength an ordinary throw would
    // produce. Dragging the slider is a side-by-side comparison.
    _engine.demo();
  }

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: 'Settings',
      child: ListenableBuilder(
        listenable: settings,
        builder: (BuildContext context, _) {
          final double gain = settings.hapticGain;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // First, because it is the larger of the two: one of these
              // settings is how hard the app taps back, and the other is
              // whether the phone's own movement plays at all.
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Motion control',
                      style: TextStyle(
                        color: Color(0xFFE8EEF6),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Switch(
                    value: settings.motion,
                    activeThumbColor: const Color(0xFF6E9AD0),
                    activeTrackColor: const Color(0xFF3F6FA8),
                    inactiveThumbColor: const Color(0xAABFD0E4),
                    inactiveTrackColor: const Color(0x14FFFFFF),
                    onChanged: (bool on) => settings.motion = on,
                  ),
                ],
              ),
              Text(
                settings.motion
                    ? 'Tilt to pour the dice down the screen, shake to throw '
                        'them. Turn this off and the tray is handed a phone '
                        'held perfectly still: down is down the screen and '
                        'stays there, and Throw is the only way to roll.'
                    : 'Off. The tray ignores the phone: down is down the '
                        'screen and stays there, and a shake does nothing. '
                        'Throw is the only way to roll, and it works exactly '
                        'as it always did.',
                style: const TextStyle(
                  color: Color(0x99BFD0E4),
                  fontSize: 13,
                  height: 1.45,
                ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Expanded(
                              child: Text(
                                'Shake to deal a card',
                                style: TextStyle(
                                  color: Color(0xFFE8EEF6),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Switch(
                              value: settings.shakeToDraw,
                              activeThumbColor: const Color(0xFF6E9AD0),
                              activeTrackColor: const Color(0xFF3F6FA8),
                              inactiveThumbColor: const Color(0xAABFD0E4),
                              inactiveTrackColor: const Color(0x14FFFFFF),
                              onChanged: (bool on) => settings.shakeToDraw = on,
                            ),
                          ],
                        ),
                        const Text(
                          // What it costs, said plainly, because this is the
                          // one switch in the app whose downside is not
                          // obvious from the label. Everything else here is
                          // undone by doing it again.
                          'Off, and worth leaving off. A shake throws the '
                          'dice, and a throw you did not mean is undone by '
                          'throwing again — but a dealt card is gone until '
                          'the shoe is cut, and a phone handed across a table '
                          'is a shake. Draw turns the next card over either '
                          'way.',
                          style: TextStyle(
                            color: Color(0x99BFD0E4),
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Impact strength',
                      style: TextStyle(
                        color: Color(0xFFE8EEF6),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    gain <= 0 ? 'Off' : '${(gain * 100).round()}%',
                    style: const TextStyle(
                      color: Color(0xAABFD0E4),
                      fontSize: 14,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFF3F6FA8),
                  inactiveTrackColor: const Color(0x1AFFFFFF),
                  thumbColor: const Color(0xFF6E9AD0),
                  overlayColor: const Color(0x223F6FA8),
                  valueIndicatorColor: const Color(0xFF3F6FA8),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: gain.clamp(0.0, _kMaxGain),
                  max: _kMaxGain,
                  divisions: _kGainSteps,
                  onChanged: _setGain,
                ),
              ),
              const Text(
                'How hard the tray taps back when a die hits the side. The tap '
                'follows the impact, so a D20 slamming into a wall is felt and '
                'a die nudging its neighbour is not — this only sets how much '
                'of that reaches your hand. Drag the slider to feel it.',
                style: TextStyle(
                  color: Color(0x99BFD0E4),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              if (!onDevice) ...<Widget>[
                const SizedBox(height: 10),
                const Text(
                  'Nothing to feel here — this is the desktop harness, and it '
                  'has no actuator to tap with.',
                  style: TextStyle(
                    color: Color(0x66BFD0E4),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          );
        },
      ),
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
