import 'dart:async';
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import 'configs.dart';

/// How tall the row of pills is, and how tall one pill is inside it.
///
/// The band is the pill plus the air above and below it. Named because the
/// picker hangs it under the mode dots and a row that changed height as saves
/// came and went would move the Roll button while a thumb was on its way to it.
const double kPillBand = 46;
const double kPillHeight = 32;

/// The row itself, and the pill that makes another — named so a thumb, or a
/// test, can say which one it means.
const Key kConfigPills = ValueKey<String>('config-pills');
const Key kNewConfigPill = ValueKey<String>('new-config');

/// The saved configurations, worn as pills, with the way to make another at the
/// end of the row.
///
/// A pill is the whole of a save's interface. A tap opens it; a long press —
/// or a right click, which is what the desktop harness has instead — asks what
/// else you meant by it, and that menu is where saving is done.
///
/// Nothing is written on its own. Editing the dice under an open pill changes
/// the screen and not the save, until you hold a pill down and choose Save —
/// which puts what is on screen into *that* pill, whichever one it is. So the
/// way to keep a change is the same gesture as the way to keep it somewhere
/// else, and neither of them can happen by accident.
class ConfigPills extends StatelessWidget {
  const ConfigPills({
    super.key,
    required this.open,
    required this.onOpen,
    required this.onSave,
    required this.onNew,
  });

  /// The id of the save the picker is currently showing, or null when what is
  /// on screen has never been named. Nothing is lit in that case, which is the
  /// truth: none of these is what you are looking at.
  final int? open;

  final ValueChanged<SavedConfig> onOpen;

  /// Save, from a pill's own menu: put what is on screen into this save. The
  /// screen handles it, because it is the screen being asked for.
  final ValueChanged<SavedConfig> onSave;

  /// The + New pill. The screen handles it rather than this widget, because
  /// making a save means capturing what the screen is set to.
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: kConfigPills,
      height: kPillBand,
      child: ListenableBuilder(
        listenable: configs,
        builder: (BuildContext context, _) {
          return ListView(
            scrollDirection: Axis.horizontal,
            // Enough saves and the row runs off the side, which is the one
            // place in the app that scrolls. The padding is the rack's, so the
            // first pill starts where the dice above it do.
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            children: <Widget>[
              for (final SavedConfig save in configs.saves)
                _Pill(
                  key: ValueKey<int>(save.id),
                  label: save.name,
                  selected: save.id == open,
                  onTap: () => onOpen(save),
                  onSave: () => onSave(save),
                  save: save,
                ),
              _NewPill(key: kNewConfigPill, onTap: onNew),
            ],
          );
        },
      ),
    );
  }
}

/// One save.
class _Pill extends StatefulWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onSave,
    required this.save,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSave;
  final SavedConfig save;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(covariant _Pill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) _reveal();
  }

  /// Brings the open save into the row.
  ///
  /// Because a save is not always opened from the row. The chooser at launch
  /// opens one by name, and with a few saves the pill that lights up as a
  /// result can be off the end of a row nobody has scrolled — a highlight you
  /// cannot see is the same as no highlight at all.
  ///
  /// After the frame, because it is the frame this pill is being laid out in
  /// that decides where it has ended up.
  void _reveal() {
    if (!widget.selected) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool selected = widget.selected;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: widget.onTap,
        // Both, because both mean "what else can I do with this one". A phone
        // has the long press; the desktop harness has the second button, and a
        // right click that did nothing would read as a bug rather than as a
        // gesture this app has never heard of.
        onLongPress: () => unawaited(_menu(context)),
        onSecondaryTap: () => unawaited(_menu(context)),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: kPillHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF3F6FA8) : const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(kPillHeight / 2),
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color:
                  selected ? const Color(0xFFF2F7FF) : const Color(0xAABFD0E4),
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context) async {
    final _PillAction? action = await _showPillMenu(context);
    if (action == null || !context.mounted) return;
    final SavedConfig save = widget.save;
    switch (action) {
      case _PillAction.save:
        widget.onSave();
      case _PillAction.rename:
        final String? name = await showConfigNameDialog(
          context,
          name: save.name,
        );
        if (name != null) configs.rename(save.id, name);
      case _PillAction.delete:
        final bool go = await showDeleteConfigDialog(context, save.name);
        if (go) configs.remove(save.id);
    }
  }
}

/// The one that is not a save: a dashed outline where the next pill would go.
///
/// Dashed rather than filled, and it is the whole of the distinction. Every
/// other pill in the row is a thing that exists and can be opened; this one is
/// the space for one that does not exist yet, drawn the way the rack draws the
/// slot the next die lands in.
class _NewPill extends StatelessWidget {
  const _NewPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Save this configuration',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: CustomPaint(
          painter: const _DashedPill(),
          child: Container(
            height: kPillHeight,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: const Text(
              '+ New',
              style: TextStyle(
                color: Color(0xFF6E9AD0),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dashed outline. Flutter draws borders solid and nothing else, so the
/// only way to a dashed one is to walk the rounded rectangle's own path and
/// draw every other stretch of it.
class _DashedPill extends CustomPainter {
  const _DashedPill();

  /// The mark, and the gap after it. Both a little under three points, which is
  /// dense enough to read as an outline at pill size rather than as a row of
  /// ticks — and it divides into the perimeter closely enough that the seam at
  /// the top left is not worth chasing.
  static const double _dash = 4;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final Path outline =
        Path()..addRRect(
          RRect.fromRectAndRadius(
            // Half a stroke in, so the dashes sit inside the pill's box rather
            // than half outside it and clipped by the scrolling row.
            Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
            Radius.circular(size.height / 2),
          ),
        );
    final Paint paint =
        Paint()
          ..color = const Color(0x55BFD0E4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    for (final PathMetric metric in outline.computeMetrics()) {
      for (double at = 0; at < metric.length; at += _dash + _gap) {
        canvas.drawPath(
          metric.extractPath(at, (at + _dash).clamp(0.0, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPill oldDelegate) => false;
}

/// What a long press on a pill can lead to.
///
/// Save first, because it is the one of the three anybody does twice in an
/// evening — and because it is the only way anything is ever written, so a
/// menu that buried it would be a menu that hid the point of the row.
///
/// Not opening it, though. A tap does that, and a menu whose first entry
/// repeats the gesture that opened it has misunderstood what it is for.
enum _PillAction { save, rename, delete }

/// Puts the menu over the pill it was asked from.
Future<_PillAction?> _showPillMenu(BuildContext context) {
  final RenderBox pill = context.findRenderObject()! as RenderBox;
  final RenderBox overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  return showMenu<_PillAction>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(
        pill.localToGlobal(Offset.zero, ancestor: overlay),
        pill.localToGlobal(
          pill.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    ),
    // The app menu's card, because it is the same kind of object: a short list
    // of things to do, lifted off a screen too dark to cast a shadow onto.
    color: const Color(0xFF141A23),
    elevation: 6,
    shadowColor: const Color(0x66000000),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0x14FFFFFF)),
    ),
    items: <PopupMenuEntry<_PillAction>>[
      _entry(_PillAction.save, Icons.save_outlined, 'Save'),
      _entry(_PillAction.rename, Icons.edit_outlined, 'Rename'),
      _entry(_PillAction.delete, Icons.delete_outline, 'Delete'),
    ],
  );
}

PopupMenuItem<_PillAction> _entry(
  _PillAction action,
  IconData icon,
  String label,
) {
  final bool destructive = action == _PillAction.delete;
  return PopupMenuItem<_PillAction>(
    value: action,
    height: 46,
    child: Row(
      children: <Widget>[
        Icon(
          icon,
          size: 18,
          color:
              destructive ? const Color(0xFFB3453F) : const Color(0xAABFD0E4),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color:
                destructive ? const Color(0xFFD4756E) : const Color(0xFFE8EEF6),
            fontSize: 15,
          ),
        ),
      ],
    ),
  );
}

/// Asks what to call it: the new-save dialog, and the rename dialog, which are
/// the same dialog with a different word on the button.
///
/// Comes back with a name, or null if it was cancelled. Never with an empty
/// one — the button is dead until there is something to press it about.
Future<String?> showConfigNameDialog(BuildContext context, {String? name}) {
  return showDialog<String>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (BuildContext context) => _NameDialog(name: name),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({this.name});

  /// The name it already has, when this is a rename.
  final String? name;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _field = TextEditingController(
    text: widget.name ?? '',
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  String get _name => _field.text.trim();

  void _submit() {
    if (_name.isEmpty) return;
    Navigator.of(context).pop(_name);
  }

  @override
  Widget build(BuildContext context) {
    final bool renaming = widget.name != null;
    return _Dialog(
      title: renaming ? 'Rename configuration' : 'New configuration',
      children: <Widget>[
        TextField(
          controller: _field,
          autofocus: true,
          maxLength: kMaxConfigName,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          // The name is redrawn on every keystroke, which is what keeps the
          // button in step with whether there is anything to save under.
          onChanged: (_) => setState(() {}),
          cursorColor: const Color(0xFF6E9AD0),
          style: const TextStyle(color: Color(0xFFE8EEF6), fontSize: 20),
          decoration: InputDecoration(
            // The limit is a limit, not a score. A counter under the field
            // would be the largest thing in a dialog with one question in it.
            counterText: '',
            hintText: 'Yahtzee',
            hintStyle: const TextStyle(color: Color(0x44BFD0E4), fontSize: 20),
            filled: true,
            fillColor: const Color(0xFF0B0E13),
            contentPadding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 18),
        _Actions(
          confirm: renaming ? 'Update' : 'Create',
          onConfirm: _name.isEmpty ? null : _submit,
        ),
      ],
    );
  }
}

/// Are you sure. Asked because a save is the only thing in this app that took
/// any setting up, and deleting one is the only action here that cannot be
/// undone by doing it again.
Future<bool> showDeleteConfigDialog(BuildContext context, String name) async {
  final bool? go = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder:
        (BuildContext context) => _Dialog(
          title: 'Delete "$name"?',
          children: <Widget>[
            const Text(
              'The dice and cards it holds go with it. Nothing else changes — '
              'what is on screen stays where it is.',
              style: TextStyle(
                color: Color(0x99BFD0E4),
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            _Actions(
              confirm: 'Delete',
              destructive: true,
              onConfirm: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
  );
  return go ?? false;
}

/// What to do with a configuration somebody else's code arrived with.
///
/// [ScannedChoice.load] is the answer that changes nothing you have kept: the
/// configuration goes on screen as an unnamed one, the way a code with no name
/// on it always has. [ScannedChoice.keep] is the one that writes — a new pill,
/// or the contents of the pill that already has this name.
enum ScannedChoice { cancel, load, keep }

/// Asks what was meant by a code with a name on it.
///
/// Two questions, one dialog, because they are the same question with a
/// different thing at stake: whether to keep a configuration you have not seen
/// before, and whether to let one you *have* seen overwrite the one you have.
/// [replaces] says which — it is true when a save of this name already exists,
/// in which case keeping means losing what is there now, and the button says
/// so.
///
/// A code whose name you already have and whose contents match is never asked
/// about at all. See `ConfigScreen._scanned`: there is nothing to decide.
Future<ScannedChoice> showScannedConfigDialog(
  BuildContext context, {
  required String name,
  required bool replaces,
}) async {
  final ScannedChoice? choice = await showDialog<ScannedChoice>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder:
        (BuildContext context) => _Dialog(
          title: replaces ? 'Replace "$name"?' : 'Save "$name"?',
          children: <Widget>[
            Text(
              replaces
                  ? 'You already have a configuration called "$name", and this '
                      'code is not it. Load it to use it now and keep yours as '
                      'it is, or replace yours with what was scanned.'
                  : 'This code came from a configuration called "$name". Load '
                      'it to use it now, or save it to keep it as a pill of '
                      'your own.',
              style: const TextStyle(
                color: Color(0x99BFD0E4),
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            _Actions(
              middle: 'Load',
              onMiddle: () => Navigator.of(context).pop(ScannedChoice.load),
              confirm: replaces ? 'Replace' : 'Save',
              destructive: replaces,
              onConfirm: () => Navigator.of(context).pop(ScannedChoice.keep),
            ),
          ],
        ),
  );
  return choice ?? ScannedChoice.cancel;
}

/// The card both dialogs are drawn on.
class _Dialog extends StatelessWidget {
  const _Dialog({required this.title, required this.children});

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

/// Cancel, and the one that does the thing.
///
/// Cancel is a word rather than a button, because it is what happens if you
/// tap outside the dialog anyway — it is there to be found, not to be aimed at.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.confirm,
    required this.onConfirm,
    this.middle,
    this.onMiddle,
    this.destructive = false,
  });

  final String confirm;

  /// Null when there is nothing to confirm — an empty name.
  final VoidCallback? onConfirm;

  /// A second thing you might have meant, between Cancel and the button that
  /// does the thing. Only the scanned-code dialogs have one: taking somebody
  /// else's configuration and *keeping* it are different answers, and a dialog
  /// that made you choose between keeping it and losing it would get the wrong
  /// one pressed.
  final String? middle;
  final VoidCallback? onMiddle;

  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final String? middle = this.middle;
    // An [OverflowBar] rather than a [Row], for the three-button case: Cancel,
    // Load and Replace side by side is most of the width of a narrow phone
    // already, and one notch of larger text would push the last of them off
    // the edge. This puts them in a column when they stop fitting, which is
    // what an alert dialog has always done.
    return OverflowBar(
      alignment: MainAxisAlignment.end,
      overflowAlignment: OverflowBarAlignment.end,
      spacing: 2,
      overflowSpacing: 4,
      children: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xAABFD0E4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
          ),
          child: const Text('Cancel'),
        ),
        if (middle != null)
          TextButton(
            onPressed: onMiddle,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6E9AD0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(middle),
          ),
        FilledButton(
          onPressed: onConfirm,
          style: FilledButton.styleFrom(
            backgroundColor:
                destructive ? const Color(0xFFB3453F) : const Color(0xFF3F6FA8),
            foregroundColor: const Color(0xFFF2F7FF),
            disabledBackgroundColor: const Color(0x223F6FA8),
            disabledForegroundColor: const Color(0x55F2F7FF),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(confirm),
        ),
      ],
    );
  }
}
