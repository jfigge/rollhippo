import 'package:flutter/material.dart';

import '../tray/tray.dart';
import 'tray_screen.dart';

/// The most dice the tray will take.
///
/// Not an arbitrary round number: the spawn grid drops them in from the top of
/// the tray without any two starting inside each other, and past ten that stops
/// being possible in a tray this size.
const int kMaxDice = 10;

/// What you get before you have chosen anything.
const List<DieSpec> kDefaultDice = <DieSpec>[
  DieSpec(kind: DieKind.d6, colour: kDiceWhite),
  DieSpec(kind: DieKind.d6, colour: kDiceWhite),
];

/// Choose what is in the tray, then throw it.
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final List<DieSpec> _dice = List<DieSpec>.of(kDefaultDice);

  void _add() {
    if (_dice.length >= kMaxDice) return;
    // A new die matches the one before it, because the common thing to want is
    // another of what you already have.
    setState(() => _dice.add(_dice.isEmpty ? kDefaultDice.first : _dice.last));
  }

  void _remove(int index) => setState(() => _dice.removeAt(index));

  void _set(int index, DieSpec spec) => setState(() => _dice[index] = spec);

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
        child: Column(
          children: <Widget>[
            _header(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: _dice.length + 1,
                itemBuilder: (BuildContext context, int index) {
                  if (index == _dice.length) return _addButton();
                  return _DieCard(
                    key: ValueKey<int>(index),
                    index: index,
                    spec: _dice[index],
                    onChanged: (DieSpec spec) => _set(index, spec),
                    onRemove: _dice.length > 1 ? () => _remove(index) : null,
                  );
                },
              ),
            ),
            _rollButton(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
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
                  'Fill the tray, then throw it.',
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

  Widget _addButton() {
    final bool enabled = _dice.length < kMaxDice;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TextButton.icon(
        onPressed: enabled ? _add : null,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Add a die'),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFBFD0E4),
          disabledForegroundColor: const Color(0x44BFD0E4),
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color:
                  enabled ? const Color(0x22FFFFFF) : const Color(0x11FFFFFF),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rollButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
    );
  }
}

/// One die's row: what colour it is, and how many sides it has.
class _DieCard extends StatelessWidget {
  const _DieCard({
    super.key,
    required this.index,
    required this.spec,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final DieSpec spec;
  final ValueChanged<DieSpec> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 14),
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
                child: Wrap(
                  spacing: 5,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final int colour in kDicePalette)
                      _Swatch(
                        colour: colour,
                        selected: colour == spec.colour,
                        onTap: () => onChanged(spec.copyWith(colour: colour)),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
                color: const Color(0x88BFD0E4),
                disabledColor: const Color(0x22BFD0E4),
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: <Widget>[
                for (final DieKind kind in DieKind.values)
                  Expanded(
                    child: _KindChip(
                      kind: kind,
                      selected: kind == spec.kind,
                      onTap: () => onChanged(spec.copyWith(kind: kind)),
                    ),
                  ),
              ],
            ),
          ),
        ],
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
