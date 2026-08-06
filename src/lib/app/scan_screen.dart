import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../tray/tray.dart';

/// How much of the narrower screen dimension the framing square takes.
const double _kWindowFraction = 0.68;

/// Point the camera at somebody else's Roll Hippo code.
///
/// Pops with the sets the code described, or with null if you closed it. It
/// never pops with a code it could not read — see [_onDetect]. The one thing
/// this screen must not do is come back with *something*: a scanner that
/// half-understands a QR code off a cereal box and replaces your dice with it
/// is worse than one that never worked.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    // QR only. Telling the detector what to look for is worth real frame time
    // on the phone, and every other symbology it knows about is one more thing
    // that can distract it from the square being held up in front of it.
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );

  /// Set when a QR code was read and turned out not to be ours. The camera
  /// keeps running: the answer to the wrong code is to point at another one.
  String? _complaint;

  /// One result per screen. The detector runs several times a second and will
  /// happily read the same code again while the pop is still in flight.
  bool _taken = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  /// A frame the detector found codes in.
  ///
  /// Every code in it is offered to [decodeGroups], and the first one that is a
  /// Roll Hippo code wins. Anything else only earns a line of text — a camera
  /// pointed at the world finds QR codes constantly, and a scanner that
  /// complained about each one would be unusable in a room with a poster in it.
  void _onDetect(BarcodeCapture capture) {
    if (_taken || !mounted) return;
    for (final Barcode code in capture.barcodes) {
      final String? raw = code.rawValue;
      if (raw == null) continue;
      final List<List<DieSpec>>? groups = decodeGroups(raw);
      if (groups == null) continue;
      _taken = true;
      Navigator.of(context).pop(groups);
      return;
    }
    if (capture.barcodes.isEmpty) return;
    setState(() => _complaint = 'That is a QR code, but not a Roll Hippo one.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size size = constraints.biggest;
          final double side = (size.shortestSide * _kWindowFraction).clamp(
            0.0,
            420.0,
          );
          final Rect window = Rect.fromCenter(
            center: size.center(Offset.zero),
            width: side,
            height: side,
          );
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                // Only what is inside the frame counts, which is what makes
                // the frame mean anything. Without it the square on screen is
                // decoration and the code you did not mean to scan wins.
                scanWindow: window,
                errorBuilder: _error,
              ),
              _Frame(window: window),
              _chrome(),
            ],
          );
        },
      ),
    );
  }

  Widget _chrome() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _RoundButton(
                  icon: Icons.close,
                  label: 'Close',
                  onTap: () => Navigator.of(context).pop(),
                ),
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: _controller,
                  builder:
                      (BuildContext context, MobileScannerState state, _) =>
                          _RoundButton(
                            icon:
                                state.torchState == TorchState.on
                                    ? Icons.flashlight_on
                                    : Icons.flashlight_off,
                            label: 'Torch',
                            onTap: () => unawaited(_controller.toggleTorch()),
                          ),
                ),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                _complaint ?? 'Hold a Roll Hippo code inside the square.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:
                      _complaint == null
                          ? const Color(0xCCBFD0E4)
                          : const Color(0xFFD98032),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// No camera, or no permission to use it.
  ///
  /// Both arrive here, and both are things the player has to go and fix
  /// somewhere else, so the screen says which one it is and offers the way out
  /// rather than sitting on a black rectangle.
  Widget _error(BuildContext context, MobileScannerException error) {
    final bool denied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: const Color(0xFF0B0E13),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.no_photography_outlined,
                  color: Color(0x66BFD0E4),
                  size: 40,
                ),
                const SizedBox(height: 16),
                Text(
                  denied
                      ? 'Roll Hippo has not been allowed to use the camera. '
                          'Turn it on in Settings and come back.'
                      : 'The camera is not available here.\n'
                          '${error.errorCode.message}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xAABFD0E4),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                _RoundButton(
                  icon: Icons.close,
                  label: 'Close',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Everything outside the scan window, dimmed, with a bracket on the corners.
class _Frame extends StatelessWidget {
  const _Frame({required this.window});

  final Rect window;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: CustomPaint(painter: _FramePainter(window)));
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect hole = RRect.fromRectAndRadius(
      window,
      const Radius.circular(20),
    );

    // The dim is one path with a hole in it rather than four rectangles round
    // the edge, so the rounded corners of the window are actually rounded.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(hole),
      ),
      Paint()..color = const Color(0xB30B0E13),
    );

    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x553F6FA8),
    );

    // Corner brackets, a fifth of the side each. They say which way up the
    // square is at a glance, where a plain outline reads as a viewfinder for
    // the whole picture.
    final double arm = window.width / 5;
    final Paint bracket =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF6E9AD0);
    for (final (Offset corner, double dx, double dy)
        in <(Offset, double, double)>[
          (window.topLeft, 1, 1),
          (window.topRight, -1, 1),
          (window.bottomLeft, 1, -1),
          (window.bottomRight, -1, -1),
        ]) {
      // Inset from the corner by the radius so the arms meet the curve rather
      // than crossing it.
      final Offset start = corner.translate(dx * 18, dy * 18);
      canvas.drawLine(start, start.translate(dx * arm, 0), bracket);
      canvas.drawLine(start, start.translate(0, dy * arm), bracket);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.window != window;
}

/// A pill with an icon and a word in it, for the camera's own controls.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        backgroundColor: const Color(0x66141A23),
        foregroundColor: const Color(0xFFF2F7FF),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }
}
