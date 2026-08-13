import 'dart:async';
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import 'chrome.dart';
import 'haptics.dart';
import 'profiles.dart';

/// How tall one profile is, and the air between one and the next.
///
/// The gap is the same across and down, so a block of them reads as a block
/// rather than as rows.
const double kProfileHeight = 32;
const double kProfileGap = 8;

/// The row itself, and the profile that makes another — named so a thumb, or a
/// test, can say which one it means.
const Key kProfileRow = ValueKey<String>('profile-row');
const Key kNewProfile = ValueKey<String>('new-profile');

/// How far in the block starts, which is [kRackEdge] written out.
///
/// Written out because the two cannot see each other: `picker_screen.dart`
/// imports this file, so this file cannot import it back. Both are 16, and the
/// point of it is that the heading, the first profile and the leftmost slot of
/// the rack all start on the same line down the screen.
const double _kProfileEdge = 16;

/// The saved profiles, with the way to make another at the end of them.
///
/// They wrap rather than run off the side. A row that scrolled sideways would
/// hide saves behind an edge with nothing to say they were there, and the one
/// it hides first is the oldest — which is exactly the one whose name you have
/// stopped remembering. Wrapped, every profile you have is on the screen at once.
///
/// What they are not allowed to do is push the Roll button off the bottom, so
/// the block is given the space between the mode dots and that button and no
/// more: it grows downwards into it, and once it has filled it, it scrolls.
///
/// A profile is the whole of a save's interface. A tap opens it; a long press —
/// or a right click, which is what the desktop harness has instead — asks what
/// else you meant by it, and that menu is where saving and sharing are both
/// done. The heading says so, because nothing else on the screen can: the tap
/// teaches itself and the hold does not.
///
/// The dashed one at the end answers to both gestures too, and means the same
/// thing by them: a tap keeps what is on screen as a profile of its own, and a
/// hold asks what else — which for that one is Reset, the way back to the
/// set-up the app opens at, and a Share of what is on screen. So the hold is
/// worth trying on anything in the row, which is the only way a gesture with
/// nothing to advertise it gets found.
///
/// Share is on every profile in the row rather than up in the app menu,
/// because a share code *is* a profile and the row is where profiles are. What
/// it hands over is whatever the profile you held down is: a save sends what
/// that save holds, under its own name, the way Rename and Delete act on the
/// save rather than on the screen — so an edit you have not kept does not go
/// out under a name that does not describe it. The dashed one has no save
/// behind it, so it sends what is on screen, unnamed, which is exactly what it
/// has always meant.
///
/// Nothing is written on its own. Editing the dice under an open profile changes
/// the screen and not the save, until you hold a profile down and choose Save —
/// which puts what is on screen into *that* profile, whichever one it is. So the
/// way to keep a change is the same gesture as the way to keep it somewhere
/// else, and neither of them can happen by accident.
class ProfileRow extends StatelessWidget {
  const ProfileRow({
    super.key,
    required this.open,
    required this.onOpen,
    required this.onSave,
    required this.onShare,
    required this.onNew,
    required this.onReset,
    required this.onShareCurrent,
  });

  /// The id of the save the picker is currently showing, or null when what is
  /// on screen has never been named. Nothing is lit in that case, which is the
  /// truth: none of these is what you are looking at.
  final int? open;

  final ValueChanged<SavedProfile> onOpen;

  /// Save, from a profile's own menu: put what is on screen into this save. The
  /// screen handles it, because it is the screen being asked for.
  final ValueChanged<SavedProfile> onSave;

  /// Share, from that same menu: this save, as a code. The screen handles it
  /// for the reason every other entry here is handled there — the sheet is put
  /// up over the whole picker, not inside the row — and it is handed the save
  /// rather than reading the picker, because what a save shares is what it
  /// holds.
  final ValueChanged<SavedProfile> onShare;

  /// The + New profile. The screen handles it rather than this widget, because
  /// making a save means capturing what the screen is set to.
  final VoidCallback onNew;

  /// Reset, off that same profile's menu: put the picker back to the set-up the
  /// app opens with. The screen handles it for the same reason — the thing
  /// being reset is the screen, and this row is only where the gesture lands.
  final VoidCallback onReset;

  /// Share, off the dashed profile's menu: what is on screen, as a code, under
  /// no name at all. The one thing in the row that shares the picker rather
  /// than a save, because it is the one thing in the row that is not one.
  final VoidCallback onShareCurrent;

  @override
  Widget build(BuildContext context) {
    // A heading, and then the block itself. The scroll view fills whatever the
    // picker gives it that the heading has not taken and lays the profiles out
    // at the top of that, which is what puts them under the mode dots with the
    // slack below them. Too many to fit and it scrolls, which is the only thing
    // in this app that does.
    return Column(
      key: kProfileRow,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          // The space above it is the space the profiles used to keep over
          // themselves, moved up here: the heading takes the top of the block
          // rather than being added to it, so nothing below has moved.
          padding: EdgeInsets.fromLTRB(_kProfileEdge, 7, _kProfileEdge, 5),
          // Two weights on one line: the heading, and then in the lighter of the
          // two the picker already uses for its subtitles, what holding a
          // profile down is for. That gesture is the whole of a save's second
          // interface, and a menu that only opens on a gesture is a menu nobody
          // finds unless something says so.
          //
          // One line is not a preference. The block below is given the space
          // between the mode dots and the Roll button and no more, so a heading
          // that took a second line would take it out of the profiles. At 13 the
          // label fits the narrowest phone with room over; at a large text scale
          // it will not, and there it is to lose its tail rather than the row.
          child: Text.rich(
            TextSpan(
              children: <TextSpan>[
                TextSpan(
                  text: 'Profiles',
                  style: TextStyle(
                    color: Color(0xAABFD0E4),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: ' (press and hold for options)',
                  style: TextStyle(color: Color(0x99BFD0E4)),
                ),
              ],
            ),
            style: TextStyle(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(child: _block()),
      ],
    );
  }

  /// The saves themselves, wrapped, and scrolling once they have filled the
  /// space the picker allowed them.
  Widget _block() {
    return SingleChildScrollView(
      // The padding is the rack's, so the first profile starts where the dice
      // above it do — and where the heading over them does.
      padding: const EdgeInsets.fromLTRB(_kProfileEdge, 0, _kProfileEdge, 7),
      child: SizedBox(
        // A [Wrap] is as wide as its widest run, and the column above centres
        // what it is given. Without this the block would drift left and right
        // as profiles were added, instead of starting where the rack starts.
        width: double.infinity,
        child: ListenableBuilder(
          listenable: profiles,
          builder: (BuildContext context, _) {
            return Wrap(
              spacing: kProfileGap,
              runSpacing: kProfileGap,
              children: <Widget>[
                for (final SavedProfile save in profiles.saves)
                  _Profile(
                    key: ValueKey<int>(save.id),
                    label: save.name,
                    selected: save.id == open,
                    onTap: () => onOpen(save),
                    onSave: () => onSave(save),
                    onShare: () => onShare(save),
                    save: save,
                  ),
                _NewProfile(
                  key: kNewProfile,
                  onTap: onNew,
                  onReset: onReset,
                  onShare: onShareCurrent,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One save.
class _Profile extends StatefulWidget {
  const _Profile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onSave,
    required this.onShare,
    required this.save,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final SavedProfile save;

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(covariant _Profile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) _reveal();
  }

  /// Brings the open save into view.
  ///
  /// Because a save is not always opened from the block. A scanned code opens
  /// one by name, and with enough saves the profile that lights up as a result
  /// can be below the fold of a block nobody has scrolled — a highlight you
  /// cannot see is the same as no highlight at all.
  ///
  /// After the frame, because it is the frame this profile is being laid out in
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
    return GestureDetector(
      // A profile is the one control on this screen that replaces everything
      // above it in a single tap, so it says so in the hand as well.
      onTap: () {
        uiHaptic(HapticLevel.light);
        widget.onTap();
      },
      // Both, because both mean "what else can I do with this one". A phone
      // has the long press; the desktop harness has the second button, and a
      // right click that did nothing would read as a bug rather than as a
      // gesture this app has never heard of.
      onLongPress: () => unawaited(_menu(context)),
      onSecondaryTap: () => unawaited(_menu(context)),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: kProfileHeight,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF3F6FA8) : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(kProfileHeight / 2),
        ),
        // A [Center] with both factors, rather than the container's own
        // `alignment`: that one is an [Align] with no factors, which fills
        // whatever width it is offered. In a row that scrolled sideways it was
        // offered no width at all and hugged its label; in a [Wrap] it is
        // offered the whole line, and every profile would be a full-width bar.
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
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
    final _ProfileAction? action = await _showProfileMenu(context);
    if (action == null || !context.mounted) return;
    final SavedProfile save = widget.save;
    switch (action) {
      case _ProfileAction.save:
        widget.onSave();
      case _ProfileAction.rename:
        final String? name = await showProfileNameDialog(
          context,
          name: save.name,
        );
        if (name != null) profiles.rename(save.id, name);
      case _ProfileAction.share:
        widget.onShare();
      case _ProfileAction.delete:
        final bool go = await showDeleteProfileDialog(context, save.name);
        if (go) profiles.remove(save.id);
    }
  }
}

/// The one that is not a save: a dashed outline where the next profile would go.
///
/// Dashed rather than filled, and it is the whole of the distinction. Every
/// other profile in the row is a thing that exists and can be opened; this one is
/// the space for one that does not exist yet, drawn the way the rack draws the
/// slot the next die lands in.
///
/// It carries the same pair of gestures as the profiles beside it, because it
/// sits in their row and a hold that did nothing on one chip out of seven would
/// read as the gesture having failed. A tap keeps what is on screen under a
/// name; the hold has Reset, which puts the picker back to what the app opens
/// with and is the one thing in this row that belongs to no save at all, and a
/// Share, which here hands the screen over as a code with no name on it.
class _NewProfile extends StatelessWidget {
  const _NewProfile({
    super.key,
    required this.onTap,
    required this.onReset,
    required this.onShare,
  });

  final VoidCallback onTap;

  final VoidCallback onReset;

  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Save this profile',
      child: GestureDetector(
        // Answered exactly as the profiles beside it are, which is the whole
        // bargain this one makes: it sits in their row and carries their
        // gestures.
        onTap: () {
          uiHaptic(HapticLevel.light);
          onTap();
        },
        // The hold and the right click, both, exactly as a save answers them.
        onLongPress: () => unawaited(_menu(context)),
        onSecondaryTap: () => unawaited(_menu(context)),
        behavior: HitTestBehavior.opaque,
        child: CustomPaint(
          painter: const _DashedProfile(),
          child: Container(
            height: kProfileHeight,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            // Hugs its own label, for the reason the profile beside it does.
            child: const Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
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
      ),
    );
  }

  /// A menu of two, and only one of them is peculiar to this profile.
  ///
  /// Reset first, because it is the one that belongs *only* here: every profile
  /// in the row has a Share and none of them has a Reset, so the entry that
  /// makes this menu worth opening is the entry that goes at the top of it. A
  /// menu rather than a second tap for both, because the row has taught the
  /// gesture already and starting over is not something to hand to a finger
  /// that slipped.
  Future<void> _menu(BuildContext context) async {
    final _NewAction? action =
        await _showChipMenu<_NewAction>(context, <PopupMenuEntry<_NewAction>>[
          _entry(_NewAction.reset, Icons.restart_alt, 'Reset'),
          _entry(_NewAction.share, Icons.qr_code_2, 'Share'),
        ]);
    if (action == null) return;
    switch (action) {
      case _NewAction.reset:
        onReset();
      case _NewAction.share:
        onShare();
    }
  }
}

/// The dashed outline. Flutter draws borders solid and nothing else, so the
/// only way to a dashed one is to walk the rounded rectangle's own path and
/// draw every other stretch of it.
class _DashedProfile extends CustomPainter {
  const _DashedProfile();

  /// The mark, and the gap after it. Both a little under three points, which is
  /// dense enough to read as an outline at profile size rather than as a row of
  /// ticks — and it divides into the perimeter closely enough that the seam at
  /// the top left is not worth chasing.
  static const double _dash = 4;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final Path outline =
        Path()..addRRect(
          RRect.fromRectAndRadius(
            // Half a stroke in, so the dashes sit inside the profile's box rather
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
  bool shouldRepaint(_DashedProfile oldDelegate) => false;
}

/// What a long press on a profile can lead to.
///
/// Save first, because it is the one of the four anybody does twice in an
/// evening — and because it is the only way anything is ever written, so a
/// menu that buried it would be a menu that hid the point of the row.
///
/// Delete last, because it is the one entry drawn in a colour of its own and
/// the only one that cannot be undone by doing it again. Share goes above it
/// rather than below for that reason alone: an entry that changes nothing at
/// all has no business sitting under the one that ends the save.
///
/// Not opening it, though. A tap does that, and a menu whose first entry
/// repeats the gesture that opened it has misunderstood what it is for.
enum _ProfileAction { save, rename, share, delete }

/// The dashed profile's pair, which is the same list with everything that
/// needs a save taken out of it and Reset put in.
enum _NewAction { reset, share }

/// What a hold on a save offers.
Future<_ProfileAction?> _showProfileMenu(BuildContext context) {
  return _showChipMenu<_ProfileAction>(
    context,
    <PopupMenuEntry<_ProfileAction>>[
      _entry(_ProfileAction.save, Icons.save_outlined, 'Save'),
      _entry(_ProfileAction.rename, Icons.edit_outlined, 'Rename'),
      _entry(_ProfileAction.share, Icons.qr_code_2, 'Share'),
      _entry(_ProfileAction.delete, Icons.delete_outline, 'Delete'),
    ],
  );
}

/// Puts a menu over the profile it was asked from, whichever profile that is.
///
/// One presenter for both, so that the dashed profile's menu cannot arrive as a
/// different object to the one every other profile in the row puts up.
Future<T?> _showChipMenu<T>(
  BuildContext context,
  List<PopupMenuEntry<T>> items,
) async {
  final RenderBox profile = context.findRenderObject()! as RenderBox;
  final RenderBox overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  // Both taps are fired from here rather than from the two callers, for the
  // reason this function exists at all: the dashed profile's menu must not
  // arrive as a different object to every other profile's, and it must not
  // arrive feeling different either. The firmer one is the menu opening,
  // which on this row is the answer to a long press and so the only sign the
  // press was long enough. See [uiHaptic].
  uiHaptic(HapticLevel.medium);
  final T? action = await showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(
        profile.localToGlobal(Offset.zero, ancestor: overlay),
        profile.localToGlobal(
          profile.size.bottomRight(Offset.zero),
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
    items: items,
  );
  // Only for a choice. A menu dismissed by tapping the screen beside it is a
  // menu nobody took anything out of, and a tap for that would be the app
  // confirming a decision that was not made.
  if (action != null) uiHaptic(HapticLevel.light);
  return action;
}

/// One line of it. Delete is the only entry that is red, and it is the only one
/// that takes something away that cannot be got back — Reset drops what is on
/// screen, which was either kept in a profile of its own or was never named.
PopupMenuItem<T> _entry<T>(T action, IconData icon, String label) {
  final bool destructive = action == _ProfileAction.delete;
  return PopupMenuItem<T>(
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
Future<String?> showProfileNameDialog(BuildContext context, {String? name}) {
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
    return AppDialog(
      title: renaming ? 'Rename profile' : 'New profile',
      children: <Widget>[
        TextField(
          controller: _field,
          autofocus: true,
          maxLength: kMaxProfileName,
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
        DialogActions(
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
Future<bool> showDeleteProfileDialog(BuildContext context, String name) async {
  final bool? go = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder:
        (BuildContext context) => AppDialog(
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
            DialogActions(
              confirm: 'Delete',
              destructive: true,
              onConfirm: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
  );
  return go ?? false;
}

/// What to do with a profile somebody else's code arrived with.
///
/// [ScannedChoice.load] is the answer that changes nothing you have kept: the
/// profile goes on screen as an unnamed one, the way a code with no name
/// on it always has. [ScannedChoice.keep] is the one that writes — a new profile,
/// or the contents of the profile that already has this name.
enum ScannedChoice { cancel, load, keep }

/// Asks what was meant by a code with a name on it.
///
/// Two questions, one dialog, because they are the same question with a
/// different thing at stake: whether to keep a profile you have not seen
/// before, and whether to let one you *have* seen overwrite the one you have.
/// [replaces] says which — it is true when a save of this name already exists,
/// in which case keeping means losing what is there now, and the button says
/// so.
///
/// A code whose name you already have and whose contents match is never asked
/// about at all. See `PickerScreen._scanned`: there is nothing to decide.
Future<ScannedChoice> showScannedProfileDialog(
  BuildContext context, {
  required String name,
  required bool replaces,
}) async {
  final ScannedChoice? choice = await showDialog<ScannedChoice>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder:
        (BuildContext context) => AppDialog(
          title: replaces ? 'Replace "$name"?' : 'Save "$name"?',
          children: <Widget>[
            Text(
              replaces
                  ? 'You already have a profile called "$name", and this '
                      'code is not it. Load it to use it now and keep yours as '
                      'it is, or replace yours with what was scanned.'
                  : 'This code came from a profile called "$name". Load '
                      'it to use it now, or save it to keep it as one of your own.',
              style: const TextStyle(
                color: Color(0x99BFD0E4),
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            DialogActions(
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
