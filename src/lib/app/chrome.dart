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
