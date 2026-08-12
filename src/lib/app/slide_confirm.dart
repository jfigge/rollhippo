import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chrome.dart';
import 'haptics.dart';

/// The track, and the thumb that runs along it.
const double _kTrackHeight = 56;
const double _kInset = 4;
const double _kKnob = _kTrackHeight - _kInset * 2;

/// How far along counts as all the way.
///
/// Not 1.0. A thumb dragged to the far end of a track stops when it meets the
/// end of the track, and the last few pixels are the ones a hand cannot feel
/// itself failing to reach — asking for the literal end would leave a slide
/// that visibly finished springing back. Short of the end and it latches; the
/// animation covers the rest.
const double _kLatch = 0.94;

/// A slider you have to take all the way across before it answers.
///
/// This is a confirmation for the one kind of mistake a button cannot guard
/// against: not "did you mean it", which a second tap answers, but "was that a
/// tap at all". A dialog whose confirm button sits where the button you just
/// pressed was is a dialog a double tap walks straight through, and the thing
/// on the other side of this one cannot be undone by doing it again. A drag
/// across the whole width of the dialog is not something a thumb does by
/// accident.
///
/// It commits on release rather than on arrival, so a slide that overshoots
/// and comes back is still a slide you can abandon — let go anywhere short of
/// [_kLatch] and it springs home having done nothing.
class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirm,
  });

  /// What the track says before the thumb has covered it up.
  final String label;

  /// Called once, when the slide has been taken all the way and let go.
  final VoidCallback onConfirm;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm>
    with SingleTickerProviderStateMixin {
  /// How far across, 0 to 1. An animation rather than a plain field because
  /// the two ends of a drag are both animated — home again, or the last of the
  /// way to the end — and dragging is just setting it by hand in between.
  late final AnimationController _at = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  /// How many pixels the thumb has to cover, measured in the last layout.
  ///
  /// A drag arrives in pixels and this is what turns them into a fraction. It
  /// is written in `build` because it is a fact about the width the dialog
  /// gave us, and a dialog that is rebuilt narrower is one whose next drag has
  /// less ground to cover.
  double _travel = 1;

  /// True once the slide has been taken and answered, so that a second release
  /// against a latched track cannot fire [SlideToConfirm.onConfirm] twice.
  bool _done = false;

  @override
  void dispose() {
    _at.dispose();
    super.dispose();
  }

  void _drag(DragUpdateDetails details) {
    if (_done) return;
    _at.value = (_at.value + details.primaryDelta! / _travel).clamp(0.0, 1.0);
  }

  Future<void> _release() async {
    if (_done) return;
    if (_at.value < _kLatch) {
      // Short of the end: home, and nothing happened.
      await _at.animateBack(0, curve: Curves.easeOut);
      return;
    }
    await _confirm();
  }

  /// Takes the thumb the rest of the way and answers.
  ///
  /// [HapticLevel.medium], which is the strength this app keeps for a gesture
  /// nothing else confirms — the same argument as a long press. A drag has no
  /// moment of contact of its own, and the screen behind the dialog does not
  /// answer until the dialog has gone, so the tap under the thumb is what says
  /// it got there.
  Future<void> _confirm() async {
    _done = true;
    uiHaptic(HapticLevel.medium);
    await _at.animateTo(1, curve: Curves.easeOut);
    if (!mounted) return;
    widget.onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _travel = math.max(1, constraints.maxWidth - _kInset * 2 - _kKnob);
        return Semantics(
          // A slide is a gesture a screen reader cannot make. The semantic tap
          // is the same commitment by the only route a voice control has, and
          // it is deliberately not a real one: nothing here answers a pointer
          // tap, which is the whole point of the control.
          button: true,
          label: widget.label,
          onTap: () => unawaited(_confirm()),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _drag,
            onHorizontalDragEnd:
                (DragEndDetails details) => unawaited(_release()),
            onHorizontalDragCancel: () => unawaited(_release()),
            child: AnimatedBuilder(
              animation: _at,
              builder: (BuildContext context, Widget? child) {
                final double at = _at.value;
                return Container(
                  height: _kTrackHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0E13),
                    borderRadius: BorderRadius.circular(_kTrackHeight / 2),
                    border: const Border.fromBorderSide(
                      BorderSide(color: Color(0x14FFFFFF)),
                    ),
                  ),
                  child: Stack(
                    children: <Widget>[
                      // The words, fading as the thumb comes across them —
                      // gone before it reaches them rather than read through
                      // it.
                      Center(
                        child: Opacity(
                          opacity: (1 - at * 2).clamp(0.0, 1.0),
                          child: Text(
                            widget.label,
                            style: const TextStyle(
                              color: Color(0x99BFD0E4),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: _kInset + at * _travel,
                        top: _kInset,
                        child: Container(
                          width: _kKnob,
                          height: _kKnob,
                          decoration: const BoxDecoration(
                            color: Color(0xFF3F6FA8),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 22,
                            color: Color(0xFFF2F7FF),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Asks a question that only a slide answers.
///
/// Comes back true if the track was taken all the way across, and false for
/// every other way out of the dialog — Cancel, the barrier, the back gesture.
/// The default is therefore "no", which is what makes this worth putting in
/// front of something: everything that is not the deliberate gesture leaves
/// the screen behind it exactly as it was.
Future<bool> showSlideConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String slide,
}) async {
  final bool? go = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder:
        (BuildContext context) => AppDialog(
          title: title,
          children: <Widget>[
            Text(
              message,
              style: const TextStyle(
                color: Color(0x99BFD0E4),
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            SlideToConfirm(
              label: slide,
              onConfirm: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 4),
            // Cancel as a word rather than as a button, the way every other
            // dialog here has it: it is what tapping outside does anyway, and
            // the thing it is next to is the one you are meant to have to aim
            // at.
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xAABFD0E4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
  );
  return go ?? false;
}
