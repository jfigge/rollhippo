import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../tray/tray.dart';
import 'haptics.dart';
import 'scan_screen.dart';
import 'settings.dart';
import 'tray_screen.dart';

/// How wide a sheet is allowed to get.
///
/// The same number as the picker's rack, for the same reason rather than by
/// coincidence: a phone is narrower than this and fills it, and on a desktop
/// window an unconstrained sheet is a line of text you read across a foot of
/// screen, or a QR code the size of a beer mat.
const double _kSheetWidth = 440;

/// How many steps the calibration slider has between off and [_kMaxGain].
///
/// Notched rather than continuous. The underlying value is a multiplier and
/// changing it by a hundredth changes nothing anyone can feel, so a smooth
/// slider would be a control that mostly does not respond — and each notch is
/// one tap played back, which makes dragging it an actual comparison.
const int _kGainSteps = 12;

/// The top of the slider. See [Tuning.hapticMaxGain].
const double _kMaxGain = Tuning.hapticMaxGain;

/// The menu button's tap target, and the icon centred inside it.
///
/// 48 is the accessibility minimum for something a thumb has to find, and what
/// [IconButton] gives you by default; 26 is the size that matches the title it
/// sits beside.
const double _kMenuTarget = 48;
const double _kMenuIcon = 26;

/// How far into [AppMenuButton] its three strokes actually begin.
///
/// The visible part of this button is a good deal smaller than the box it
/// needs for a thumb, which matters to anything trying to line it up with
/// something else. The icon floats in the middle of a tap target nearly twice
/// its size, and Material insets `Icons.menu` by a further eighth of the icon
/// at each end — its bars run from 3 to 21 of a 24-point grid. Fourteen and a
/// quarter points, all told.
///
/// Read off the rendered pixels rather than worked out on paper, because it is
/// easy to be wrong here and hard to notice: `flutter test` substitutes a font
/// with no glyphs in it, so an unwary measurement returns the notdef box —
/// which is a different size, and centred differently.
const double kAppMenuInset =
    (_kMenuTarget - _kMenuIcon) / 2 + _kMenuIcon * 3 / 24;

/// Quits.
///
/// [SystemNavigator.pop] is the polite way out and is what Android wants: it
/// finishes the activity and lets the framework tidy up first. On iOS it is
/// deliberately a no-op, because Apple's guidelines say an application should
/// never terminate itself and App Review has read a visible Quit as grounds
/// for rejection before now — which leaves [exit] as the only line here that
/// actually does anything on a phone, and the line to delete if that bites.
Future<void> quitApp() async {
  await SystemNavigator.pop();
  exit(0);
}

/// The app menu: three lines, top left.
///
/// Everything in it is about the app rather than about the dice in front of
/// you, which is why it is a menu and not four more buttons on a screen that
/// already has enough.
class AppMenuButton extends StatefulWidget {
  const AppMenuButton({
    super.key,
    required this.groups,
    required this.onScanned,
    this.onExit = quitApp,
  });

  /// The sets as they stand, for the Share sheet to turn into a code.
  final List<List<DieSpec>> groups;

  /// Handed the sets a scanned code described. Not called if the scanner was
  /// closed without finding one.
  final ValueChanged<List<List<DieSpec>>> onScanned;

  /// What Exit does.
  ///
  /// Overridable for exactly one reason: [quitApp] ends the process, and a
  /// widget test that walked into it would take the test runner with it.
  final Future<void> Function() onExit;

  @override
  State<AppMenuButton> createState() => _AppMenuButtonState();
}

enum _MenuItem { settings, scan, share, exit }

class _AppMenuButtonState extends State<AppMenuButton> {
  Future<void> _run(_MenuItem item) async {
    switch (item) {
      case _MenuItem.settings:
        await showSettingsSheet(context);
      case _MenuItem.scan:
        await _scan();
      case _MenuItem.share:
        await showShareSheet(context, widget.groups);
      case _MenuItem.exit:
        await widget.onExit();
    }
  }

  Future<void> _scan() async {
    final List<List<DieSpec>>? groups = await Navigator.of(context).push(
      MaterialPageRoute<List<List<DieSpec>>>(
        builder: (BuildContext context) => const ScanScreen(),
      ),
    );
    if (groups == null || !mounted) return;
    widget.onScanned(groups);
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
      icon: const Icon(Icons.menu, color: Color(0xFFBFD0E4), size: _kMenuIcon),
      onSelected: (_MenuItem item) => unawaited(_run(item)),
      itemBuilder:
          (BuildContext context) => <PopupMenuEntry<_MenuItem>>[
            _entry(_MenuItem.settings, Icons.tune, 'Settings'),
            _entry(_MenuItem.scan, Icons.qr_code_scanner, 'Scan'),
            _entry(_MenuItem.share, Icons.qr_code_2, 'Share'),
            _entry(_MenuItem.exit, Icons.logout, 'Exit'),
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

/// The settings panel.
Future<void> showSettingsSheet(
  BuildContext context,
) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Colors.transparent,
  barrierColor: const Color(0xB3000000),
  constraints: const BoxConstraints(maxWidth: _kSheetWidth),
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

/// The Share sheet: these dice, as a square somebody else can point a phone at.
Future<void> showShareSheet(BuildContext context, List<List<DieSpec>> groups) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xB3000000),
      constraints: const BoxConstraints(maxWidth: _kSheetWidth),
      isScrollControlled: true,
      builder: (BuildContext context) => _ShareSheet(groups: groups),
    );

class _ShareSheet extends StatelessWidget {
  const _ShareSheet({required this.groups});

  final List<List<DieSpec>> groups;

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: 'Share',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(child: ShareCodeView(code: encodeGroups(groups))),
          const SizedBox(height: 16),
          Text(
            _summary(groups),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFE8EEF6),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Every set, every die, its kind and its colour. Scan it from '
            'another phone to set that one up the same way.',
            textAlign: TextAlign.center,
            style: TextStyle(
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

  /// The payload, from [encodeGroups].
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

/// What the code says, in words, for someone who cannot read a QR code.
String _summary(List<List<DieSpec>> groups) {
  final List<int> counts = <int>[
    for (final List<DieSpec> group in groups)
      if (group.isNotEmpty) group.length,
  ];
  if (counts.isEmpty) return 'No dice';
  final String sets = counts.length == 1 ? 'set' : 'sets';
  return '${counts.length} $sets · ${counts.join(' + ')} dice';
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
