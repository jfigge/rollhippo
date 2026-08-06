import 'package:flutter/material.dart';

import '../cards/deck.dart';
import '../render/die_preview.dart';
import '../tray/tray.dart';
import 'card_screen.dart';
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
/// Which of the two things the picker is setting up.
///
/// They are pages of the same screen rather than two screens, because they are
/// alternatives: whichever one you are looking at is what Roll will do, and a
/// mode you have to go somewhere else to find is a mode nobody finds.
enum ConfigMode { dice, cards }

/// The most dice a card can stand for.
///
/// Three, because a card carries every outcome of the dice it replaces and
/// there are six to the power of them: two dice is thirty-six cards, three is
/// two hundred and sixteen, and four would be a shoe of over a thousand that
/// nobody would get to the bottom of.
const int kMaxCardDice = 3;

/// The most copies of the full set that can be shuffled together.
const int kMaxDecks = 3;

/// The highest cut the shoe can be given, as a percentage left.
const int kMaxReshuffleAt = 20;

/// What a card-mode die is before it has been coloured in.
///
/// The *kind* is not a choice: a deck of every outcome only makes sense for
/// dice that all have the same faces, and the six-sided one is the die
/// everybody means. The colour is one, per die — see
/// [_ConfigScreenState._cardColours] — and this is where every one of them
/// starts.
const DieSpec kCardDie = DieSpec(kind: DieKind.d6, colour: kDiceWhite);

/// The band the page dots sit in, kept the same in both modes so that the
/// panel underneath does not jump as one slides in over the other.
const double kDotsBand = 26;

/// The two page controls on the picker, named so that a finger — or a test —
/// can tell which one it has hold of. One counts the sets of dice, the other
/// counts the modes.
const Key kGroupDots = ValueKey<String>('group-dots');
const Key kModeDots = ValueKey<String>('mode-dots');

/// The two modes' pages. Both are built at all times — the block takes the
/// taller of them, so neither the panel nor anything under it jumps when a
/// swipe lands — which means anything looking for a die, or a slider, has to
/// say which mode's it means.
const Key kDicePage = ValueKey<String>('dice-page');
const Key kCardPage = ValueKey<String>('card-page');

/// The cut slider in the card panel. Named because the settings sheet has a
/// slider too, and the picker is still built underneath it.
const Key kReshuffleSlider = ValueKey<String>('reshuffle');

/// The empty slot that takes the next die: the large plus drawn where that die
/// would land, which is where adding one is done now that no button does it.
///
/// Every rack with room in it has one — both modes are built at once and the
/// page view keeps more than one group built — so anything reaching for it has
/// to say whose rack it means.
const Key kAddDie = ValueKey<String>('add-die');

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

class _ConfigScreenState extends State<ConfigScreen>
    with SingleTickerProviderStateMixin {
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

  /// Where the two modes have got to, dice at 0 and cards at 1. Driven by a
  /// finger on the panel, and left to coast when the finger lets go.
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// The mode Roll will act on. Set the moment a swipe is committed to rather
  /// than when it lands, so the button and the dots agree with the box that is
  /// on its way in.
  ConfigMode _mode = ConfigMode.dice;

  bool get _cards => _mode == ConfigMode.cards;

  /// What is printed on a card: one colour per die, in the order they are laid
  /// out down the card.
  ///
  /// The list *is* the dice — there is no separate count, because a card with
  /// two dice on it is a card with two colours on it and two numbers that
  /// would have to be kept in step. Only the colours vary: every one of them
  /// is a D6, since a deck of every outcome only makes sense for dice that all
  /// have the same faces.
  final List<int> _cardColours = <int>[kCardDie.colour, kCardDie.colour];

  /// Which of them the swatches are pointed at, exactly as [_selectedIn] does
  /// for a group of real dice. Card mode always has at least one die, so this
  /// always names a real one.
  int _cardSelected = 0;

  /// What the shoe is made of.
  int _decks = 2;
  int _reshuffleAt = 5;

  /// How many dice a card stands for.
  int get _cardDice => _cardColours.length;

  /// The die in slot [i] of the card: a D6 in whatever colour it was given.
  DieSpec _cardSpec(int i) => kCardDie.copyWith(colour: _cardColours[i]);

  /// The group on screen. Everything below the rack is about this one.
  List<DieSpec> get _dice => _groups[_group];

  int get _selected => _selectedIn[_group];

  /// The first group is the set, and cannot be taken away entirely. The others
  /// can: emptying group two is the only way to say you have finished with it.
  int get _floor => _group == 0 ? 1 : 0;

  @override
  void dispose() {
    _slide.dispose();
    _racks.dispose();
    super.dispose();
  }

  /// Adds a die to the card, matching the one before it and arriving selected.
  ///
  /// The same bargain [_addTo] makes in dice mode, for the same two reasons: the
  /// common thing to want is another of what you already have, and the other
  /// common thing is for it to be different.
  void _addCardDie() {
    if (_cardDice >= kMaxCardDice) return;
    setState(() {
      _cardColours.add(_cardColours.last);
      _cardSelected = _cardColours.length - 1;
    });
  }

  /// Takes the selected die off the card.
  ///
  /// The selected one rather than the last one, now that there is a selection
  /// to honour: taking away die two of three has to leave the other two the
  /// colours they were, not shuffle the third one's colour up into its place.
  /// One die always stays — a shoe with no dice in it is not a shoe.
  void _removeCardDie() {
    if (_cardDice <= 1) return;
    setState(() {
      _cardColours.removeAt(_cardSelected);
      _cardSelected = _cardSelected.clamp(0, _cardColours.length - 1);
    });
  }

  void _selectCardDie(int index) => setState(() => _cardSelected = index);

  /// Paints the selected die of the card.
  ///
  /// No guard, where [_set] needs one: a group of real dice can be emptied and
  /// leave its editor talking about nothing, and card mode cannot — the last
  /// die always stays — so there is always a die here for a swatch to land on.
  void _setCardColour(int colour) =>
      setState(() => _cardColours[_cardSelected] = colour);

  /// Commits to a mode and lets the block coast the rest of the way there.
  void _goToMode(int index) {
    setState(() => _mode = index == 0 ? ConfigMode.dice : ConfigMode.cards);
    _slide.animateTo(
      index.toDouble(),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _modeDrag(double delta, double width) =>
      _slide.value = (_slide.value - delta / width).clamp(0.0, 1.0);

  void _modeDragEnd(double velocity, double width) {
    // A flick carries it; otherwise a quarter of the way over is far enough to
    // have meant it. The same bargain the tray's boxes make.
    final double fling = -velocity / width;
    final int from = _cards ? 1 : 0;
    final double moved = _slide.value - from;
    int to = from;
    if (fling.abs() > 0.9) {
      to = from + (fling > 0 ? 1 : -1);
    } else if (moved.abs() > 0.25) {
      to = from + (moved > 0 ? 1 : -1);
    }
    _goToMode(to.clamp(0, 1));
  }

  /// Adds a die to [group] — the set whose rack was tapped, rather than
  /// whichever one happens to be on screen.
  ///
  /// The two are the same except mid-swipe, where the page view has two racks
  /// built and the one under your finger is not yet the one the editor is
  /// about. A plus belongs to the rack it is drawn in.
  void _addTo(int group) {
    final List<DieSpec> dice = _groups[group];
    if (dice.length >= kMaxDice) return;
    setState(() {
      // A new die matches the one before it, because the common thing to want
      // is another of what you already have — and it arrives selected, since
      // the other common thing is to want it different. The first die of an
      // empty group has nothing to match, so it is what the app starts with.
      dice.add(dice.isEmpty ? kDefaultDice.first : dice.last);
      _selectedIn[group] = dice.length - 1;
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

  /// Points the editor at die [index] of [group], and takes the group for the
  /// same reason [_addTo] does: a tap lands on the rack it was drawn in.
  void _select(int group, int index) =>
      setState(() => _selectedIn[group] = index);

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
    if (_cards) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (BuildContext context) => CardScreen(
                dice: _cardDice,
                decks: _decks,
                reshuffleAt: _reshuffleAt,
                colours: List<int>.of(_cardColours),
              ),
        ),
      );
      return;
    }
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
                // The rack and the panel below it move together, because they
                // are one thing: a set of dice and what you do to it, or a
                // shoe of cards and what it is made of.
                _block(),
                _modeDots(),
                const Spacer(),
                _rollButton(),
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
                Expanded(
                  child: Text(
                    _cards
                        ? 'A card for every roll. Swipe back for dice.'
                        : 'Tap a die to change it. Swipe for another set.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0x99BFD0E4),
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  _cards
                      ? '$_cardDice / $kMaxCardDice'
                      : '${_dice.length} / $kMaxDice',
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

  /// The two modes, side by side, one of them on screen.
  ///
  /// A [Stack] rather than another [PageView]: the two pages are different
  /// heights — one has a row of page dots in it and a card of swatches, the
  /// other has neither — and a stack takes the taller of them without anyone
  /// having to work out in advance which that is. What slides is a transform,
  /// which costs no layout at all.
  ///
  /// The gesture is on the panel and nowhere else. The rack has a page view of
  /// its own for the three sets, and a sideways drag that starts there belongs
  /// to that; one that starts on the panel belongs to this.
  Widget _block() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        return ClipRect(
          child: AnimatedBuilder(
            animation: _slide,
            builder:
                (BuildContext context, Widget? child) => Stack(
                  children: <Widget>[
                    for (int page = 0; page < 2; page++)
                      Transform.translate(
                        offset: Offset((page - _slide.value) * width, 0),
                        child: SizedBox(
                          key: page == 0 ? kDicePage : kCardPage,
                          width: width,
                          child:
                              page == 0 ? _dicePage(width) : _cardsPage(width),
                        ),
                      ),
                  ],
                ),
          ),
        );
      },
    );
  }

  Widget _dicePage(double width) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _racksView(),
      _dots(),
      // Directly under the rack, so the colours and the shapes read as
      // belonging to the die you just tapped rather than to the set.
      _swipeable(_editor(), width),
    ],
  );

  Widget _cardsPage(double width) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _cardRack(),
      // Empty, but exactly as tall as the dots the other mode has there, so
      // the two panels sit at the same height as one slides over the other.
      const SizedBox(height: kDotsBand),
      _swipeable(_cardPanel(), width),
    ],
  );

  /// Arms [child] as the handle the two modes are dragged by.
  Widget _swipeable(Widget child, double width) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onHorizontalDragUpdate:
        (DragUpdateDetails d) => _modeDrag(d.delta.dx, width),
    onHorizontalDragEnd:
        (DragEndDetails d) =>
            _modeDragEnd(d.velocity.pixelsPerSecond.dx, width),
    child: child,
  );

  /// Which mode you are in, under the block that holds it.
  ///
  /// Outside the block rather than in it, because it is the one thing on the
  /// screen that is about both modes and so the one thing that should not
  /// slide when they do.
  Widget _modeDots() => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Center(
      child: PageDots(
        key: kModeDots,
        current: _cards ? 1 : 0,
        filled: const <bool>[true, true],
        onTap: _goToMode,
      ),
    ),
  );

  /// The rack, in card mode: three slots where there were ten.
  ///
  /// The other seven are not drawn, but their space is still there — the rack
  /// is the same size in both modes, so swapping between them moves nothing
  /// but the slots themselves.
  Widget _cardRack() {
    return Padding(
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
                          child:
                              i < kMaxCardDice
                                  ? _RackSlot(
                                    key: i == _cardDice ? kAddDie : null,
                                    spec: i < _cardDice ? _cardSpec(i) : null,
                                    selected: i == _cardSelected,
                                    adds: i == _cardDice,
                                    // Tappable, and selected the same way the
                                    // dice rack is: the swatches below are
                                    // about one die of the card, and this is
                                    // where you say which. There is still no
                                    // kind to choose — every card-mode die is
                                    // a D6 — so colour is all a tap can lead
                                    // to here. The slot past the last die is
                                    // the plus, and takes another; past three
                                    // there is no slot at all.
                                    onTap:
                                        i < _cardDice
                                            ? () => _selectCardDie(i)
                                            : i == _cardDice
                                            ? _addCardDie
                                            : null,
                                  )
                                  : const SizedBox.shrink(),
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

  /// What the shoe is made of: how many decks are in it, and how deep it is
  /// cut before it goes back together.
  Widget _cardPanel() {
    final int size = Deck.build(_cardDice, _decks).length;
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
              // The title sits in the label column and the count starts where
              // the first deck button does, so the panel reads as two columns
              // rather than as three rows that happen to be stacked.
              const SizedBox(
                width: _kFieldLabel,
                child: Text(
                  'Cards',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFFE8EEF6),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: _kChipMargin),
                  child: Text(
                    '($size in the shoe)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xAABFD0E4),
                      fontSize: 13,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              _RemoveButton(onPressed: _cardDice > 1 ? _removeCardDie : null),
            ],
          ),
          const SizedBox(height: 8),
          // The same swatches the die editor has, in the same place under the
          // panel's title, doing the same thing to the die the rack above has
          // a ring round.
          //
          // Across the whole panel rather than in the label column the two
          // rows below keep to: eight of them do not fit beside a label on a
          // narrow phone, and a swatch row that wrapped there would make this
          // panel a different height on different handsets.
          Wrap(
            spacing: 5,
            runSpacing: 6,
            children: <Widget>[
              for (final int colour in kDicePalette)
                _Swatch(
                  colour: colour,
                  selected: colour == _cardColours[_cardSelected],
                  onTap: () => _setCardColour(colour),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const SizedBox(width: _kFieldLabel, child: _FieldLabel('Decks')),
              for (int n = 1; n <= kMaxDecks; n++)
                Expanded(
                  child: _Chip(
                    label: '$n',
                    selected: n == _decks,
                    onTap: () => setState(() => _decks = n),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const SizedBox(
                width: _kFieldLabel,
                child: _FieldLabel('Reshuffle'),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                  ),
                  child: Slider(
                    key: kReshuffleSlider,
                    value: _reshuffleAt.toDouble(),
                    max: kMaxReshuffleAt.toDouble(),
                    divisions: kMaxReshuffleAt,
                    activeColor: const Color(0xFF3F6FA8),
                    inactiveColor: const Color(0x22FFFFFF),
                    onChanged:
                        (double v) => setState(() => _reshuffleAt = v.round()),
                  ),
                ),
              ),
              SizedBox(
                // Wide enough for the longest it gets, which is "<20%".
                width: 46,
                child: Text(
                  // Below this much left, not above it: the shoe goes back
                  // together when it is nearly out, and a bare number does not
                  // say which way round that is.
                  '<$_reshuffleAt%',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Color(0xFFE8EEF6),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
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
                            // The first empty slot is where another die would
                            // go, so it is where you ask for one. A full rack
                            // has no such slot, and that is the whole of the
                            // limit: nothing to tap, and nothing greyed out
                            // to explain why not.
                            key: i == dice.length ? kAddDie : null,
                            spec: i < dice.length ? dice[i] : null,
                            selected: i == selected,
                            adds: i == dice.length,
                            onTap:
                                i < dice.length
                                    ? () => _select(group, i)
                                    : i == dice.length
                                    ? () => _addTo(group)
                                    : null,
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
    return SizedBox(
      height: kDotsBand,
      child: Center(
        child: PageDots(
          key: kGroupDots,
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
              _RemoveButton(
                onPressed: _dice.length > _floor ? _removeSelected : null,
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
                          child: _Chip(
                            label: kind.label,
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

  /// Roll, across the whole width, with nothing beside it.
  ///
  /// Adding a die is done in the rack now, in the slot the die will land in,
  /// which is both where you are already looking and the only place that can
  /// say — by having no slot left — that there is no room for another. So the
  /// bottom of the screen is one button about the whole set, rather than a
  /// button about the set sharing a row with one about a die.
  Widget _rollButton() {
    final bool anything =
        _cards || _groups.any((List<DieSpec> g) => g.isNotEmpty);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
        // Card mode does not throw anything. What the button does there is put
        // a shoe together and hand it to you face down, which is a shuffle and
        // reads as one.
        child: Text(
          _cards ? 'Shuffle' : 'Roll',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// One place in the rack: a die you can select, the space the next die goes in,
/// or a slot the set has not reached yet.
class _RackSlot extends StatelessWidget {
  const _RackSlot({
    super.key,
    required this.spec,
    required this.selected,
    required this.onTap,
    this.adds = false,
  });

  /// Null for a slot with no die in it.
  final DieSpec? spec;
  final bool selected;
  final VoidCallback? onTap;

  /// Whether this is the slot another die would land in — drawn as a plus the
  /// size of the die that is about to be there, and the only empty slot in the
  /// rack a tap does anything to. Never true of a slot that has a [spec].
  final bool adds;

  @override
  Widget build(BuildContext context) {
    final DieSpec? spec = this.spec;
    // Only a filled slot can be selected; an empty one never draws the ring.
    final bool lit = selected && spec != null;
    // Three weights of edge, because there are three kinds of slot. The one
    // that adds is brighter than the empty ones past it: it is worth aiming
    // at, and they are only there to say how much room is left.
    final Color edge =
        lit
            ? const Color(0xFF6E9AD0)
            : spec != null
            ? const Color(0x14FFFFFF)
            : adds
            ? const Color(0x22FFFFFF)
            : const Color(0x0CFFFFFF);
    final Widget slot = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: lit ? const Color(0x223F6FA8) : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: edge, width: lit ? 2 : 1),
        ),
        // The die is inset from the ring so a selected one does not touch it.
        padding: const EdgeInsets.all(4),
        child:
            adds
                ? const FractionallySizedBox(
                  // Half the slot: a mark saying where the next die goes,
                  // rather than a thing pretending to be one. A fraction and
                  // not a point size, so it stays half of whatever the slot
                  // turns out to be — the same bargain [DiePreview] makes by
                  // filling one.
                  widthFactor: 0.5,
                  heightFactor: 0.5,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Icon(Icons.add, size: 24, color: Color(0x99BFD0E4)),
                  ),
                )
                : spec == null
                ? null
                : DiePreview(spec: spec),
      ),
    );
    // The plus used to be a button with a word on it. Losing the word to the
    // rack should not lose it to a screen reader as well.
    return adds
        ? Semantics(button: true, label: 'Add a die', child: slot)
        : slot;
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

/// How wide a field's name is in the card panel. One column, so the decks and
/// the cut line up with each other rather than each starting where its own
/// label happens to end.
const double _kFieldLabel = 74;

/// The gutter each chip keeps to either side of itself.
const double _kChipMargin = 2;

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    // One line whatever happens. A label that wraps takes the field beside it
    // down the screen with it, and the two fields would stop lining up.
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: Color(0xAABFD0E4), fontSize: 13),
  );
}

/// Takes one die away. The same control in both modes, because taking a die
/// out of a set and taking one off a card are the same thing to look at.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  /// Null when there is nothing left to remove.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.close, size: 16),
    label: const Text('Remove'),
    style: TextButton.styleFrom(
      foregroundColor: const Color(0xAABFD0E4),
      disabledForegroundColor: const Color(0x33BFD0E4),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(fontSize: 13),
    ),
  );
}

/// One of a row of choices — a kind of die, or a number of decks.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: _kChipMargin),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF3F6FA8) : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
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
