import 'package:flutter/material.dart';

/// Which of several pages you are on, and which of them have anything in them.
///
/// The dots iOS puts under a paged view, carrying one extra piece of
/// information: a group of dice can exist and be empty, and the difference
/// matters before you swipe rather than after. So the two states are drawn on
/// different axes — *shape* says whether the group has dice in it, a filled
/// disc against a hollow ring, and *colour* says which one you are looking at.
/// Read either one without having to decode the other.
///
/// The first dot is always filled, because the first group is the set and
/// cannot be emptied. That is not enforced here; it falls out of the picker
/// refusing to remove the last die.
class PageDots extends StatelessWidget {
  const PageDots({
    super.key,
    required this.current,
    required this.filled,
    this.onTap,
  });

  /// Which page is on screen. One dot is drawn per entry in [filled].
  final int current;

  /// Whether each page has anything in it — a filled disc if so.
  final List<bool> filled;

  /// Where a tapped dot goes. Null leaves them as an indicator only, which is
  /// what the tray wants: there the dots say where you are, and the box itself
  /// is the thing you move.
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final ValueChanged<int>? onTap = this.onTap;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < filled.length; i++)
          GestureDetector(
            onTap: onTap == null ? null : () => onTap(i),
            behavior: HitTestBehavior.opaque,
            // The dot is 7 across and the target is bigger than it, because
            // a dot big enough to hit comfortably is a dot too big to be
            // punctuation. The target is wider than the dot by 11 rather than
            // the 17 it started at: three dots set that far apart read as one
            // piece of punctuation instead of three, and the full 24 of height
            // is still there to be hit.
            child: SizedBox(
              width: 18,
              height: 24,
              child: Center(
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        filled[i]
                            ? _colour(i == current)
                            : const Color(0x00000000),
                    border:
                        filled[i]
                            ? null
                            : Border.all(color: _colour(i == current)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Lit for the page you are on, and the muted grey the rest of the chrome
  /// uses for everything you are not being asked to look at.
  Color _colour(bool here) =>
      here ? const Color(0xFF6E9AD0) : const Color(0x44BFD0E4);
}
