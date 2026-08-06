import 'package:flutter/material.dart';

import '../render/die_preview.dart';
import '../tray/tray.dart';
import 'tray_screen.dart';

/// The most dice the tray will take.
///
/// Not an arbitrary round number: the spawn grid drops them in from the top of
/// the tray without any two starting inside each other, and past ten that stops
/// being possible in a tray this size. The rack below is two rows of five for
/// the same reason — ten is the shape of the thing, not a limit imposed on it.
const int kMaxDice = 10;

/// How wide the rack is. Five slots a row, filled left to right: 1–5 along the
/// top, 6–10 along the bottom.
const int kRackColumns = 5;

/// How wide the picker is allowed to get.
///
/// A phone is narrower than this and simply fills it. A desktop window is not,
/// and without the cap the rack would grow with it until the dice were the size
/// of coasters — the same reason [kHarnessScreen] pins the tray.
const double kPickerWidth = 440;

/// What you get before you have chosen anything.
const List<DieSpec> kDefaultDice = <DieSpec>[
  DieSpec(kind: DieKind.d6, colour: kDiceWhite),
  DieSpec(kind: DieKind.d6, colour: kDiceWhite),
];

/// Choose what is in the tray, then throw it.
///
/// The whole set is on screen at once, drawn as the dice it actually is, and
/// exactly one of them is selected: the colours and the shapes underneath are
/// that die's, and change it. Picking another die drops the first — which is
/// the same bargain a paint palette makes, and needs no explaining.
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final List<DieSpec> _dice = List<DieSpec>.of(kDefaultDice);

  /// Which die the editor below the rack is pointed at. Always a real index:
  /// the last die cannot be removed, so the set is never empty.
  int _selected = 0;

  void _add() {
    if (_dice.length >= kMaxDice) return;
    setState(() {
      // A new die matches the one before it, because the common thing to want
      // is another of what you already have — and it arrives selected, since
      // the other common thing is to want it different.
      _dice.add(_dice.last);
      _selected = _dice.length - 1;
    });
  }

  void _removeSelected() {
    if (_dice.length <= 1) return;
    setState(() {
      _dice.removeAt(_selected);
      _selected = _selected.clamp(0, _dice.length - 1);
    });
  }

  void _select(int index) => setState(() => _selected = index);

  void _set(DieSpec spec) => setState(() => _dice[_selected] = spec);

  void _roll() {
    if (_dice.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (BuildContext context) => TrayScreen(dice: List<DieSpec>.of(_dice)),
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
                _rack(),
                const SizedBox(height: 16),
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

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Roll Hippo',
                  style: TextStyle(
                    color: Color(0xFFE8EEF6),
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Tap a die to change it, then throw them.',
                  style: TextStyle(color: Color(0x99BFD0E4), fontSize: 13),
                ),
              ],
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
    );
  }

  /// The set itself, two rows of five.
  ///
  /// The empty slots stay in the layout rather than collapsing to the dice you
  /// have: they say how many more the tray will take, and — more usefully —
  /// they stop a die moving under your finger when you add another one.
  Widget _rack() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: <Widget>[
          for (int row = 0; row * kRackColumns < kMaxDice; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: <Widget>[
                  for (
                    int i = row * kRackColumns;
                    i < (row + 1) * kRackColumns;
                    i++
                  )
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: _RackSlot(
                            spec: i < _dice.length ? _dice[i] : null,
                            selected: i == _selected,
                            onTap: i < _dice.length ? () => _select(i) : null,
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

  /// What the selected die is: its colour, and how many sides it has.
  Widget _editor() {
    final DieSpec spec = _dice[_selected];
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
                  'Die ${_selected + 1} — ${spec.kind.label}',
                  style: const TextStyle(
                    color: Color(0xFFE8EEF6),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _dice.length > 1 ? _removeSelected : null,
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
          Wrap(
            spacing: 5,
            runSpacing: 6,
            children: <Widget>[
              for (final int colour in kDicePalette)
                _Swatch(
                  colour: colour,
                  selected: colour == spec.colour,
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
                    selected: kind == spec.kind,
                    onTap: () => _set(spec.copyWith(kind: kind)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buttons() {
    final bool room = _dice.length < kMaxDice;
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
              onPressed: _dice.isEmpty ? null : _roll,
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
