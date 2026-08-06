import 'package:flutter/material.dart';

import '../render/die_preview.dart';
import '../tray/tray.dart';
import 'menu.dart';
import 'page_dots.dart';
import 'tray_screen.dart';

/// The most dice the tray will take.
///
/// Not an arbitrary round number: the spawn grid drops them in from the top of
/// the tray without any two starting inside each other, and past ten that stops
/// being possible in a tray this size. The rack below is two rows of five for
/// the same reason — ten is the shape of the thing, not a limit imposed on it.
const int kMaxDice = 10;

/// How many separate sets of dice you can set up.
///
/// Three because a roll that needs more than three readings kept apart is a
/// roll you are going to write down anyway, and because three dots under the
/// rack are countable at a glance where five are a row you have to read.
const int kMaxGroups = 3;

/// How wide the rack is. Five slots a row, filled left to right: 1–5 along the
/// top, 6–10 along the bottom.
const int kRackColumns = 5;

/// The rack's margin, the gutter that separates one slot from the next, and
/// the gap between its two rows.
///
/// Named rather than written out because four things have to agree about them:
/// [_rack] lays the slots out with them, [_rackHeight] works out how tall that
/// comes to, and the header lines the subtitle up against [kRackEdge]. They
/// were three literals in two places and a comment asking the next person to
/// keep them in step, which is the sort of request nobody remembers.
const double kRackMargin = 12;
const double kRackGutter = 4;
const double kRackRowGap = 6;

/// Where the leftmost slot of the rack begins, and so where everything that is
/// *about* the rack begins.
const double kRackEdge = kRackMargin + kRackGutter;

/// How wide the picker is allowed to get.
///
/// A phone is narrower than this and simply fills it. A desktop window is not,
/// and without the cap the rack would grow with it until the dice were the size
/// of coasters — the same reason [kHarnessScreen] pins the tray.
const double kPickerWidth = 440;

/// Where the menu button's box starts, so that its three strokes land on
/// [kRackEdge] along with the subtitle and the rack below them.
///
/// Not [kRackEdge] itself. Most of that button is tap target with nothing
/// drawn in it — see [kAppMenuInset], which is how much. `menu_test.dart`
/// measures the two against the rack and holds them there.
const double _kMenuEdge = kRackEdge - kAppMenuInset;

/// What you get before you have chosen anything.
const List<DieSpec> kDefaultDice = <DieSpec>[
  DieSpec(kind: DieKind.d6, colour: kDiceWhite),
  DieSpec(kind: DieKind.d6, colour: kDiceWhite),
];

/// The groups worth throwing, deep-copied, in the order they were set up.
///
/// An empty group is not a set you forgot to fill in, it is one you never
/// started — so it is not a box on the tray either, and swiping past it there
/// would be swiping past nothing. The first group can never be emptied, so
/// this never comes back with nothing in it.
List<List<DieSpec>> rollableGroups(List<List<DieSpec>> groups) =>
    <List<DieSpec>>[
      for (final List<DieSpec> group in groups)
        if (group.isNotEmpty) List<DieSpec>.of(group),
    ];

/// Where [group] ends up once the empty groups have been dropped.
///
/// A group that is itself empty has no answer, and comes back as the count of
/// what came before it — which the caller clamps onto the last real group, so
/// pressing Roll from an empty page lands you on the nearest one that has dice
/// in it rather than back at the beginning.
int rollableIndex(List<List<DieSpec>> groups, int group) {
  int index = 0;
  for (int i = 0; i < group && i < groups.length; i++) {
    if (groups[i].isNotEmpty) index++;
  }
  return index;
}

/// Choose what is in the tray, then throw it.
///
/// The whole set is on screen at once, drawn as the dice it actually is, and
/// exactly one of them is selected: the colours and the shapes underneath are
/// that die's, and change it. Picking another die drops the first — which is
/// the same bargain a paint palette makes, and needs no explaining.
///
/// Sideways are two more sets, empty until you put something in them. They are
/// pages rather than a list because they are alternatives rather than parts of
/// a whole: you are never choosing between all thirty dice at once, you are
/// choosing what is in *this* box.
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  /// The three sets. The first is the one the app starts with and always has at
  /// least one die in it; the other two begin with none, and are allowed to go
  /// back to none, because an empty group is how you say you only wanted one.
  final List<List<DieSpec>> _groups = <List<DieSpec>>[
    List<DieSpec>.of(kDefaultDice),
    <DieSpec>[],
    <DieSpec>[],
  ];

  /// Which die the editor is pointed at, per group — so swiping away and back
  /// puts you on the die you were working on rather than the first one.
  final List<int> _selectedIn = List<int>.filled(kMaxGroups, 0);

  /// Which group is on screen.
  int _group = 0;

  final PageController _racks = PageController();

  /// The group on screen. Everything below the rack is about this one.
  List<DieSpec> get _dice => _groups[_group];

  int get _selected => _selectedIn[_group];

  /// The first group is the set, and cannot be taken away entirely. The others
  /// can: emptying group two is the only way to say you have finished with it.
  int get _floor => _group == 0 ? 1 : 0;

  @override
  void dispose() {
    _racks.dispose();
    super.dispose();
  }

  void _add() {
    if (_dice.length >= kMaxDice) return;
    setState(() {
      // A new die matches the one before it, because the common thing to want
      // is another of what you already have — and it arrives selected, since
      // the other common thing is to want it different. The first die of an
      // empty group has nothing to match, so it is what the app starts with.
      _dice.add(_dice.isEmpty ? kDefaultDice.first : _dice.last);
      _selectedIn[_group] = _dice.length - 1;
    });
  }

  void _removeSelected() {
    if (_dice.length <= _floor) return;
    setState(() {
      _dice.removeAt(_selected);
      // Emptied, there is no die to be pointed at and no range to clamp into.
      // The zero it goes back to is where the first die you add will land.
      _selectedIn[_group] =
          _dice.isEmpty ? 0 : _selected.clamp(0, _dice.length - 1);
    });
  }

  void _select(int index) => setState(() => _selectedIn[_group] = index);

  /// The guard is for an empty group, where there is no die for the editor to
  /// be talking about. Nothing can reach this — the controls are behind an
  /// [IgnorePointer] — but the editor is built against a stand-in spec there,
  /// and a stand-in that could be written back would be a trap.
  void _set(DieSpec spec) {
    if (_dice.isEmpty) return;
    setState(() => _dice[_selected] = spec);
  }

  /// Replaces every set with the ones a scanned code described.
  ///
  /// All three at once, and not a merge. A share code is somebody's whole
  /// setup — the sets are alternatives to each other, so taking two of theirs
  /// and keeping one of yours would produce a arrangement neither of you has
  /// ever seen. Swapping the lot is the only reading of "scan this" that gives
  /// you what you were looking at when you scanned it.
  ///
  /// The picker's own limits are applied here rather than in [decodeGroups],
  /// which knows the wire format and not how much room this screen has. A code
  /// from some later build with four sets or twelve dice in one loses the
  /// excess and works; it does not fail.
  void _applyScanned(List<List<DieSpec>> scanned) {
    setState(() {
      for (int group = 0; group < kMaxGroups; group++) {
        final List<DieSpec> from =
            group < scanned.length ? scanned[group] : const <DieSpec>[];
        _groups[group] = <DieSpec>[...from.take(kMaxDice)];
        _selectedIn[group] = 0;
      }
      // The same floor [_floor] holds everywhere else: the first set is *the*
      // set and the picker has nothing to show you if it is empty. A code that
      // says otherwise was not made by this screen.
      if (_groups[0].isEmpty) _groups[0] = List<DieSpec>.of(kDefaultDice);
    });
    _goTo(0);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dice set up from a shared code.'),
        backgroundColor: Color(0xFF1B2430),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _goTo(int group) => _racks.animateToPage(
    group,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
  );

  void _roll() {
    final List<List<DieSpec>> groups = rollableGroups(_groups);
    if (groups.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (BuildContext context) => TrayScreen(
              groups: groups,
              initial: rollableIndex(
                _groups,
                _group,
              ).clamp(0, groups.length - 1),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kPickerWidth),
            child: Column(
              children: <Widget>[
                _header(),
                _racksView(),
                _dots(),
                // Directly under the rack, so the colours and the shapes read
                // as belonging to the die you just tapped rather than to the
                // set. What is left over goes at the bottom, which is where a
                // gap is worth having: it keeps Roll under your thumb.
                _editor(),
                const Spacer(),
                _buttons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The name, the menu, and how full the rack is.
  ///
  /// Two lines rather than one. The menu button sits on the title's own line
  /// and centred against it, because three horizontal lines beside a capital R
  /// read as one object where a button hung off the bottom of a two-line block
  /// reads as a third thing loose in the corner.
  ///
  /// Everything on the second line starts at [kRackEdge], which is where the
  /// leftmost slot of the rack starts: the subtitle is a sentence about the
  /// rack, so it begins where the rack begins. Only the title and the button
  /// it belongs to are allowed further out than that.
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(width: _kMenuEdge),
              AppMenuButton(groups: _groups, onScanned: _applyScanned),
              const Text(
                'Roll Hippo',
                style: TextStyle(
                  color: Color(0xFFE8EEF6),
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: kRackEdge),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Tap a die to change it. Swipe for another set.',
                    style: TextStyle(color: Color(0x99BFD0E4), fontSize: 13),
                  ),
                ),
                Text(
                  '${_dice.length} / $kMaxDice',
                  style: const TextStyle(
                    color: Color(0x99BFD0E4),
                    fontSize: 13,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The three racks, one swipe apart.
  ///
  /// A [PageView] has to be told how tall it is, and the rack's height is not a
  /// number anyone chose — it falls out of five square slots across whatever
  /// width there is. So it is worked out here rather than pinned, and the two
  /// stay in step by construction: change the padding in [_rack] and change it
  /// in [_rackHeight].
  Widget _racksView() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SizedBox(
          height: _rackHeight(constraints.maxWidth),
          child: PageView(
            controller: _racks,
            onPageChanged: (int page) => setState(() => _group = page),
            children: <Widget>[
              for (int group = 0; group < kMaxGroups; group++) _rack(group),
            ],
          ),
        );
      },
    );
  }

  /// Two rows of square slots, each inset by [kRackGutter], inside a
  /// [kRackMargin] margin — so a slot is a fifth of what is left, and the rack
  /// is two of those plus the [kRackRowGap] that separates the rows.
  double _rackHeight(double width) => (2 *
          ((width - 2 * kRackMargin) / kRackColumns -
              2 * kRackGutter +
              kRackRowGap))
      .clamp(0.0, double.infinity);

  /// One set, two rows of five.
  ///
  /// The empty slots stay in the layout rather than collapsing to the dice you
  /// have: they say how many more the tray will take, and — more usefully —
  /// they stop a die moving under your finger when you add another one. On an
  /// untouched group they are all there is, which is what an empty group ought
  /// to look like: room for ten, and nothing in it.
  Widget _rack(int group) {
    final List<DieSpec> dice = _groups[group];
    final int selected = _selectedIn[group];
    return Padding(
      // The one key in the app. A page view is entitled to know which of its
      // children is which, and so is anything looking for a particular group's
      // dice rather than for whichever ones happen to be built.
      key: ValueKey<int>(group),
      padding: const EdgeInsets.symmetric(horizontal: kRackMargin),
      child: Column(
        children: <Widget>[
          for (int row = 0; row * kRackColumns < kMaxDice; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: kRackRowGap),
              child: Row(
                children: <Widget>[
                  for (
                    int i = row * kRackColumns;
                    i < (row + 1) * kRackColumns;
                    i++
                  )
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: kRackGutter,
                        ),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: _RackSlot(
                            spec: i < dice.length ? dice[i] : null,
                            selected: i == selected,
                            onTap: i < dice.length ? () => _select(i) : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Where you are among the three sets, and which of them have dice in them.
  ///
  /// Between the rack and the editor because that is the seam: everything above
  /// it belongs to the group you are on and swipes with it, everything below is
  /// about one die and stays put.
  Widget _dots() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Center(
        child: PageDots(
          current: _group,
          filled: <bool>[
            for (final List<DieSpec> group in _groups) group.isNotEmpty,
          ],
          onTap: _goTo,
        ),
      ),
    );
  }

  /// What the selected die is: its colour, and how many sides it has.
  ///
  /// An empty group has no selected die, and the card goes quiet rather than
  /// away: it keeps its exact size, and the swatches and the shapes stay in
  /// the places you last saw them. A card that vanished would take the dots,
  /// the switch and the buttons a hundred points up the screen with it, and it
  /// would do that under a finger that is in the middle of a swipe.
  Widget _editor() {
    final bool empty = _dice.isEmpty;
    // Something to draw the disabled card against. Nothing is selected, so
    // nothing it says is true — which is what the fading is for.
    final DieSpec spec = empty ? kDefaultDice.first : _dice[_selected];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF141A23),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  empty
                      ? 'No dice yet'
                      : 'Die ${_selected + 1} — ${spec.kind.label}',
                  // Short, and held to one line come what may: this title is
                  // the one thing in the card whose length changes, and a
                  // second line of it would push everything below the card
                  // down the screen under a finger mid-swipe.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        empty
                            ? const Color(0x66BFD0E4)
                            : const Color(0xFFE8EEF6),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _dice.length > _floor ? _removeSelected : null,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xAABFD0E4),
                  disabledForegroundColor: const Color(0x33BFD0E4),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // The controls themselves fade together and stop taking taps, rather
          // than each being told separately that it is disabled — there is one
          // reason they are all off, and it is not about any of them.
          IgnorePointer(
            ignoring: empty,
            child: Opacity(
              opacity: empty ? 0.38 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 5,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final int colour in kDicePalette)
                        _Swatch(
                          colour: colour,
                          selected: !empty && colour == spec.colour,
                          onTap: () => _set(spec.copyWith(colour: colour)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      for (final DieKind kind in DieKind.values)
                        Expanded(
                          child: _KindChip(
                            kind: kind,
                            selected: !empty && kind == spec.kind,
                            onTap: () => _set(spec.copyWith(kind: kind)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buttons() {
    final bool room = _dice.length < kMaxDice;
    final bool anything = _groups.any((List<DieSpec> g) => g.isNotEmpty);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: TextButton.icon(
              onPressed: room ? _add : null,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add a die'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFBFD0E4),
                disabledForegroundColor: const Color(0x44BFD0E4),
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color:
                        room
                            ? const Color(0x22FFFFFF)
                            : const Color(0x11FFFFFF),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: FilledButton(
              onPressed: anything ? _roll : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3F6FA8),
                foregroundColor: const Color(0xFFF2F7FF),
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Roll',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One place in the rack: a die you can select, or the space where one would go.
class _RackSlot extends StatelessWidget {
  const _RackSlot({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  /// Null for a slot the set has not reached yet.
  final DieSpec? spec;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final DieSpec? spec = this.spec;
    // Only a filled slot can be selected; an empty one never draws the ring.
    final bool lit = selected && spec != null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: lit ? const Color(0x223F6FA8) : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                lit
                    ? const Color(0xFF6E9AD0)
                    : spec != null
                    ? const Color(0x14FFFFFF)
                    : const Color(0x0CFFFFFF),
            width: lit ? 2 : 1,
          ),
        ),
        // The die is inset from the ring so a selected one does not touch it.
        padding: const EdgeInsets.all(4),
        child: spec == null ? null : DiePreview(spec: spec),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.colour,
    required this.selected,
    required this.onTap,
  });

  final int colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 27,
        height: 30,
        child: Center(
          child: Container(
            width: selected ? 26 : 22,
            height: selected ? 26 : 22,
            decoration: BoxDecoration(
              color: Color(colour),
              shape: BoxShape.circle,
              border: Border.all(
                color:
                    selected
                        ? const Color(0xFFE8EEF6)
                        : const Color(0x33FFFFFF),
                width: selected ? 2 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final DieKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF3F6FA8) : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          kind.label,
          style: TextStyle(
            color: selected ? const Color(0xFFF2F7FF) : const Color(0xAABFD0E4),
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
