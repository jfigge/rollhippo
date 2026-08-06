import 'package:flutter/material.dart';

import 'configs.dart';

/// Which configuration to open, asked once, before anything has been drawn.
///
/// Only when there is something to ask about. A first run has no saves, so
/// there is no question and no dialog: you arrive at a fresh configuration,
/// which is what the app has always started with.
///
/// Comes back with the save that was chosen, or null for a new configuration —
/// which is also what a dismissed dialog means, because the picker underneath
/// is already sitting at its defaults and that is exactly what "new" is.
Future<SavedConfig?> showOpenConfigDialog(BuildContext context) {
  return showDialog<SavedConfig>(
    context: context,
    // Darker than a sheet's barrier. There is a whole picker behind this that
    // is not to be used yet, where a sheet is drawn over a screen you have
    // already been working on and can go back to by tapping past it.
    barrierColor: const Color(0xCC000000),
    // The way out is the button. A stray tap on the way to a save should not
    // land you in a configuration you did not ask for — the back gesture still
    // works, and means the same thing the button does.
    barrierDismissible: false,
    builder: (BuildContext context) => const _OpenDialog(key: kOpenConfig),
  );
}

/// The chooser itself. Named because the saves are listed in two places at
/// once while it is up — here, and in the row of pills on the picker behind it
/// — so anything reaching for one has to say which list it means.
const Key kOpenConfig = ValueKey<String>('open-config');

class _OpenDialog extends StatelessWidget {
  const _OpenDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    return Dialog(
      backgroundColor: const Color(0xFF0B0E13),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0x14FFFFFF)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Roll Hippo',
                  style: TextStyle(
                    color: Color(0xFFE8EEF6),
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Text(
                  'Choose a configuration to open.',
                  style: TextStyle(color: Color(0x99BFD0E4), fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
              // Enough saves and the list runs past the bottom of the screen.
              // Flexible rather than Expanded: three of them should make a
              // dialog three rows tall, not one the height of the phone.
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final SavedConfig save in configs.saves)
                      _Row(
                        save: save,
                        now: now,
                        onTap: () => Navigator.of(context).pop(save),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3F6FA8),
                  foregroundColor: const Color(0xFFF2F7FF),
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  '+ New Configuration',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One save, as a row you open by tapping anywhere on it.
class _Row extends StatelessWidget {
  const _Row({required this.save, required this.now, required this.onTap});

  final SavedConfig save;

  /// Passed in rather than read here, so every row in one dialog is measured
  /// against the same instant — otherwise two saves used seconds apart could
  /// come out on either side of a boundary and read as an hour apart.
  final DateTime now;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 13),
          decoration: BoxDecoration(
            color: const Color(0xFF141A23),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x14FFFFFF)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      save.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE8EEF6),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      save.subtitle(now),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0x99BFD0E4),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 22,
                color: Color(0xFF6E9AD0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
