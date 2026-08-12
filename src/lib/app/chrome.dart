import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
