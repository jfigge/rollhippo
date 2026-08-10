import 'dart:async';

import 'package:flutter/material.dart';

import '../cards/deck.dart';
import '../render/die_preview.dart';
import '../tray/tray.dart';
import 'card_screen.dart';
import 'menu.dart';
import 'page_dots.dart';
import 'profile_row.dart';
import 'profiles.dart';
import 'tray_screen.dart';
import 'tutorial.dart';

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
/// [_PickerScreenState._cardColours] — and this is where every one of them
/// starts.
const DieSpec kCardDie = DieSpec(kind: DieKind.d6, colour: kDiceWhite);

/// The band the group dots sit in, between the rack and the editor. Card mode
/// has no dots there — one shoe, not three sets — and no band either: what it
/// has instead is a rack with a row spare, which is where its taller panel is
/// hung from.
const double kDotsBand = 26;

/// The two page controls on the picker, named so that a finger — or a test —
/// can tell which one it has hold of. One counts the sets of dice, the other
/// counts the modes.
const Key kGroupDots = ValueKey<String>('group-dots');
const Key kModeDots = ValueKey<String>('mode-dots');

/// The two modes' pages. Both are built at all times — the dice page sets the
/// block's height and the card page is laid into it, so neither the panels nor
/// anything under them jumps when a swipe lands — which means anything looking
/// for a die, or a slider, has to say which mode's it means.
const Key kDicePage = ValueKey<String>('dice-page');
const Key kCardPage = ValueKey<String>('card-page');

/// The cut slider in the card panel. Named because the settings sheet has a
/// slider too, and the picker is still built underneath it.
const Key kReshuffleSlider = ValueKey<String>('reshuffle');

/// The empty slot that takes the next die: the large plus, which is where
/// adding one is done now that no button does it.
///
/// It is drawn in the *last* slot of the rack and stays there, rather than
/// walking along behind the dice as they are added — a button that moves out
/// from under the finger pressing it is a button that has to be chased. The
/// die still lands in the first free slot; the plus says *add one*, not
/// *here*. The last die is the one exception, because the only slot left for
/// it is the plus's own: it arrives, the plus goes, and the plus is back the
/// moment a die is taken off again.
///
/// Every rack with room in it has one — both modes are built at once and the
/// page view keeps more than one group built — so anything reaching for it has
/// to say whose rack it means.
const Key kAddDie = ValueKey<String>('add-die');

/// The name that lets the hippopotamus out.
///
/// Name a profile this and the rack offers a seventh kind of die — see
/// [DieKind.hippo], which is a D6 with an animal carved out of it. Matched
/// against the name of the profile you have *open*, trimmed and
/// case-folded, so it is a thing you keep rather than a thing you type: it
/// comes back every time you open that save, travels in a share code with it,
/// and is gone the moment you open something else.
const String kHippoProfile = 'hippo';

/// What you get before you have chosen anything.
const List<DieSpec> kDefaultDice = <DieSpec>[
  DieSpec(kind: DieKind.d6, colour: kDiceWhite),
  DieSpec(kind: DieKind.d6, colour: kDiceWhite),
];

/// An empty desk: the whole picker as the app opens it, both modes and all.
///
/// The state below starts here and [_PickerScreenState._reset] comes back to
/// it. One constant for both, so that starting again by hand and starting
/// again by launching the app land on the same set-up.
const Profile kDefaultProfile = Profile(
  mode: ProfileMode.dice,
  groups: <List<DieSpec>>[kDefaultDice, <DieSpec>[], <DieSpec>[]],
  colours: <int>[kDiceWhite, kDiceWhite],
  decks: 2,
  reshuffleAt: 5,
);

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
///
/// Under all of it is a row of profiles, which is every profile you have
/// kept, and one of them is lit: the one you opened. Nothing here writes to it
/// — an edit is to the picker, not to the save — so keeping a change means
/// holding a profile down and choosing Save. See [ProfileRow] and [_saveTo].
class PickerScreen extends StatefulWidget {
  const PickerScreen({
    super.key,
    this.tutorial = false,
    this.initial = kDefaultProfile,
  });

  /// What the picker opens showing.
  ///
  /// [kDefaultProfile] everywhere a person is looking at it, because that is
  /// what an empty desk is. It is a parameter because the tutorial builds a
  /// picker of its own to stand behind itself — see [tutorialBackdrop] — and
  /// that one has to be showing the page it is currently talking about rather
  /// than whatever the real screen underneath happens to be set to.
  ///
  /// Read once, in [State.initState]. Handing a different profile to a picker
  /// that is already up does nothing: opening a profile is [_apply]'s job and
  /// it goes through the store.
  final Profile initial;

  /// Whether to put the tutorial up over this screen on the way in.
  ///
  /// Passed in rather than read off `settings`, because "is this a first run"
  /// is a fact about the *launch* and this widget is built by three other
  /// things that are not launches: the tools in `tool/` render it into PNGs
  /// for the store listing and the website, and the tests pump it a hundred
  /// times a run. `main` is the one place that knows, so `main` is the one
  /// place that answers — and the default is false, so everything else carries
  /// on exactly as it did.
  ///
  /// It is only ever read once, in [State.initState]. Changing it afterwards
  /// does nothing, which is the truth of the thing: a run cannot become a
  /// first run.
  final bool tutorial;

  @override
  State<PickerScreen> createState() => _PickerScreenState();
}

class _PickerScreenState extends State<PickerScreen>
    with SingleTickerProviderStateMixin {
  /// The three sets. The first is the one the app starts with and always has at
  /// least one die in it; the other two begin with none, and are allowed to go
  /// back to none, because an empty group is how you say you only wanted one.
  ///
  /// Filled from [PickerScreen.initial] in [initState], along with everything
  /// else below that a profile carries. The values written here are what a
  /// field initialiser has to be — something legal for the moment between the
  /// constructor and [initState] — and not what the picker opens showing.
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
  ProfileMode _mode = kDefaultProfile.mode;

  bool get _cards => _mode == ProfileMode.cards;

  /// What is printed on a card: one colour per die, in the order they are laid
  /// out down the card.
  ///
  /// The list *is* the dice — there is no separate count, because a card with
  /// two dice on it is a card with two colours on it and two numbers that
  /// would have to be kept in step. Only the colours vary: every one of them
  /// is a D6, since a deck of every outcome only makes sense for dice that all
  /// have the same faces.
  final List<int> _cardColours = List<int>.of(kDefaultProfile.colours);

  /// Which of them the swatches are pointed at, exactly as [_selectedIn] does
  /// for a group of real dice. Card mode always has at least one die, so this
  /// always names a real one.
  int _cardSelected = 0;

  /// What the shoe is made of.
  int _decks = kDefaultProfile.decks;
  int _reshuffleAt = kDefaultProfile.reshuffleAt;

  /// Which save the picker was last opened from or saved to, by id, or null
  /// when what is on screen has come from neither. It lights that profile; it does
  /// not promise the screen still matches it, because an edit since then is an
  /// edit nobody has saved. See [_saveTo].
  int? _saved;

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
  void initState() {
    super.initState();
    _load(widget.initial);
    // What [_apply] does after its own [_load], minus the page controller,
    // which has no clients yet and opens on page zero anyway.
    _slide.value = _cards ? 1 : 0;
    profiles.addListener(_savesChanged);
    // After the first frame rather than during it: the tutorial is a route,
    // and pushing a route from `initState` asks the navigator to rebuild the
    // tree that is in the middle of building this widget. The frame the picker
    // is drawn on is the frame the sheet slides up over, so nobody sees the
    // gap — and what is behind it is the screen the tutorial is talking about,
    // which is the whole reason this is a sheet and not a page of its own.
    if (widget.tutorial) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted) unawaited(_tutorial());
      });
    }
  }

  @override
  void dispose() {
    profiles.removeListener(_savesChanged);
    _slide.dispose();
    _racks.dispose();
    super.dispose();
  }

  /// What is on screen, as something that can be kept.
  ///
  /// Both modes, deep-copied. A profile is the whole picker rather than
  /// the page of it you are looking at — saving in card mode must not throw
  /// away the dice behind it — and the lists are copies because the store holds
  /// what it is given while this screen carries on editing its own.
  ///
  /// The mode goes with it, which is why this is only ever called where the
  /// whole picker is meant: the places that write a save — [_newSave],
  /// [_saveTo], and [_scanned] when a code is kept — and [_shareCurrent],
  /// which writes nothing and hands the same thing to another phone. A profile
  /// is saved *on* a page, and that is the page it opens on, whether it was
  /// kept here or read off a code there.
  ///
  /// Every one of those goes through here rather than writing what it happens
  /// to be holding, and a scanned code is why it matters: what this returns
  /// has been through [_apply] and is inside the picker's limits by
  /// construction, where a code is only inside them by good manners.
  Profile _capture() => Profile(
    mode: _mode,
    groups: <List<DieSpec>>[
      for (final List<DieSpec> group in _groups) List<DieSpec>.of(group),
    ],
    colours: List<int>.of(_cardColours),
    decks: _decks,
    reshuffleAt: _reshuffleAt,
  );

  /// Puts what is on screen into [save] — Save, from a profile's own menu.
  ///
  /// Whichever profile was held down, which need not be the one that is open:
  /// saving your dice *onto* another profile is the same gesture as
  /// saving them back into this one, and both are things people mean. Either
  /// way that profile is now what you are looking at, so it is the one that
  /// lights up.
  ///
  /// Nothing else in this screen writes anything. An edit changes the picker
  /// and leaves every save alone until this is called.
  void _saveTo(SavedProfile save) {
    profiles.write(save.id, _capture());
    setState(() => _saved = save.id);
    // The only sign anything happened, when the profile was already lit. Saving
    // over a profile is silent otherwise, and silence is what a control
    // that has not worked also looks like.
    _say('Saved to "${save.name}".');
  }

  /// Share, from a save's own menu: that save, as a code somebody else can
  /// point a phone at.
  ///
  /// What the *save* holds, not what is on screen — so a "Yahtzee" you have
  /// added a die to since opening still shares the Yahtzee you kept. The name
  /// on the code and the dice in it describe the same thing, which is the only
  /// version of this that a receiving phone can be told the truth about, and it
  /// is what Rename and Delete on the same menu already mean by that profile.
  void _share(SavedProfile save) =>
      unawaited(showShareSheet(context, save.profile, save.name));

  /// Share, from the dashed profile's menu: what is on screen, under no name.
  ///
  /// Blank rather than the open save's name even when one is lit, for the
  /// reason [_share] gives from the other end: this is the picker as it stands,
  /// which need not be what any save holds. A code with no name on it opens
  /// unnamed on the phone that reads it, which is what an unkept set-up is
  /// there too.
  void _shareCurrent() => unawaited(showShareSheet(context, _capture(), ''));

  /// Sets the picker to a whole profile, dropping whatever it was
  /// showing — which is what opening a save means, and why a profile needs no
  /// confirmation: what it replaces is either kept in a profile of its own or was
  /// never named.
  ///
  /// The picker's own limits are applied on the way in, for the reason
  /// [_applyScanned] gives: a profile written by some later build with
  /// four sets, or four dice on a card, loses the excess and opens.
  void _apply(Profile profile) {
    setState(() => _load(profile));
    // Both of these are where a profile begins: the first set, and the
    // mode it was saved in. Jumped to rather than animated — nothing is sliding
    // *from* anywhere, the screen has just become a different one.
    _slide.value = _cards ? 1 : 0;
    if (_racks.hasClients) _racks.jumpToPage(0);
  }

  /// Writes a profile into the fields, and nothing else.
  ///
  /// Split out of [_apply] because [initState] needs exactly this half and
  /// none of the other: there is no [setState] to call before the first build,
  /// and the two controllers it drives afterwards are either not built yet or
  /// already where this would put them.
  void _load(Profile profile) {
    _takeGroups(profile.groups);
    _cardColours
      ..clear()
      ..addAll(profile.colours.take(kMaxCardDice));
    // The last die always stays — a shoe with no dice in it is not a shoe —
    // so a profile that says otherwise gets the one card mode starts
    // with rather than a panel with nothing to point at.
    if (_cardColours.isEmpty) _cardColours.add(kCardDie.colour);
    _cardSelected = 0;
    _decks = profile.decks.clamp(1, kMaxDecks);
    _reshuffleAt = profile.reshuffleAt.clamp(0, kMaxReshuffleAt);
    _mode = profile.mode;
    _group = 0;
  }

  /// Takes a set of groups into the rack, held to the picker's limits. Call
  /// from inside a [setState], or from [initState] before there is one.
  void _takeGroups(List<List<DieSpec>> from) {
    for (int group = 0; group < kMaxGroups; group++) {
      final List<DieSpec> dice =
          group < from.length ? from[group] : const <DieSpec>[];
      _groups[group] = <DieSpec>[...dice.take(kMaxDice)];
      _selectedIn[group] = 0;
    }
    // The same floor [_floor] holds everywhere else: the first set is *the*
    // set and the picker has nothing to show you if it is empty.
    if (_groups[0].isEmpty) _groups[0] = List<DieSpec>.of(kDefaultDice);
  }

  /// Opens a save: a tap on its profile in the row, and nothing else.
  ///
  /// The app used to ask which one to open before it would show you anything,
  /// as a dialog over the picker on every launch that had a save behind it.
  /// The row underneath answers the same question in one tap without standing
  /// in front of the screen to do it, so the launch is now the picker, every
  /// time — a first run and a hundredth look the same.
  void _open(SavedProfile save) {
    _apply(save.profile);
    profiles.touch(save.id);
    setState(() => _saved = save.id);
  }

  /// Keeps what is on screen, under a name.
  Future<void> _newSave() async {
    final String? name = await showProfileNameDialog(context);
    if (name == null || !mounted) return;
    final SavedProfile save = profiles.add(name, _capture());
    setState(() => _saved = save.id);
  }

  /// Back to the beginning — Reset, from the menu the dashed profile gives you
  /// when you hold it down.
  ///
  /// [kDefaultProfile] is the set-up the app opens at, so this is the one way
  /// back to an empty desk without closing the app: two white D6s in one set,
  /// nothing in the other two, the shoe as it comes, and the dice page.
  ///
  /// Nothing is lit afterwards, and the title goes back to the plain one,
  /// because what is on screen has come from no save — which is the same thing
  /// a first run is. It asks first about nothing at all, for the reason
  /// [_apply] gives: what it replaces was either kept in a profile of its own
  /// or was never named. The saves themselves are not touched.
  void _reset() {
    _apply(kDefaultProfile);
    setState(() => _saved = null);
  }

  /// Something about the saves has changed — one renamed, one deleted.
  ///
  /// The row of profiles has a listener of its own, but the title above it does
  /// not: it reads the open save's name, so a rename has to reach up here as
  /// well as down there.
  ///
  /// A deleted save that was the open one leaves the picker with nothing lit
  /// and the plain title back. What is on screen stays where it is — you were
  /// using it a moment ago, and deleting a save is a statement about the row of
  /// profiles rather than about the dice. It is simply not kept, which is what an
  /// unnamed profile is.
  void _savesChanged() {
    setState(() {
      if (_saved != null && profiles.byId(_saved) == null) _saved = null;
    });
  }

  /// Whether the hippopotamus is out — see [kHippoProfile].
  bool get _hippoLoose {
    final SavedProfile? save = profiles.byId(_saved);
    return save != null && save.name.trim().toLowerCase() == kHippoProfile;
  }

  /// The kinds the chips offer, given the die the editor is pointed at.
  ///
  /// A secret kind is in the row once it has been let out — and also whenever
  /// the die in front of you is already one, which is what a scanned code or a
  /// save made under another name can leave you holding. A row of chips with
  /// none of them lit would be the picker declining to say what the die is.
  List<DieKind> _kinds(DieSpec spec) => <DieKind>[
    for (final DieKind kind in DieKind.values)
      if (!kind.secret || _hippoLoose || kind == spec.kind) kind,
  ];

  /// The app's name, and the profile you are in, if you are in one.
  ///
  /// The name comes from the store rather than from anything held here, so a
  /// rename lands in the title without being carried to it.
  String get _title {
    final SavedProfile? save = profiles.byId(_saved);
    return save == null ? 'Roll Hippo' : 'Roll Hippo - ${save.name}';
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
    setState(() => _mode = index == 0 ? ProfileMode.dice : ProfileMode.cards);
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

  /// Takes on a profile somebody else's phone described.
  ///
  /// All of it at once, and not a merge. A code is somebody's whole setup —
  /// the sets are alternatives to each other, and the shoe behind them is part
  /// of the same arrangement — so taking two of theirs and keeping one of
  /// yours would produce something neither of you has ever seen. Swapping the
  /// lot is the only reading of "scan this" that gives you what you were
  /// looking at when you scanned it.
  ///
  /// What is asked afterwards depends entirely on the name that came with it,
  /// and there are four cases:
  ///
  ///  * No name — the other phone had not saved it either. It goes on screen
  ///    as an unnamed profile, which is what it is, and nothing is
  ///    written. This is what every code did before names existed.
  ///  * A name you already have, holding exactly this — you have scanned a
  ///    profile you already keep. There is nothing to decide and nothing
  ///    to write, so it simply opens, the way tapping its profile would.
  ///  * A name you already have, holding something else — the interesting one,
  ///    and the only one that can lose you something. Load, Replace or Cancel.
  ///  * A name you do not have — worth offering to keep, since somebody
  ///    bothered to name it. Load, Save or Cancel.
  Future<void> _scanned(ScannedProfile scanned) async {
    final String name = scanned.name.trim();
    if (name.isEmpty) {
      _take(scanned.profile);
      _say('Set up from a shared code.');
      return;
    }

    final SavedProfile? existing = profiles.byName(name);
    if (existing != null && existing.profile == scanned.profile) {
      // Silently: the profile lights up, the title says the name, and there was
      // never a question. Asking here would be asking somebody to confirm that
      // two identical things are identical.
      _open(existing);
      return;
    }

    final ScannedChoice choice = await showScannedProfileDialog(
      context,
      name: name,
      replaces: existing != null,
    );
    if (!mounted) return;
    switch (choice) {
      case ScannedChoice.cancel:
        return;
      case ScannedChoice.load:
        _take(scanned.profile);
        _say('Set up from "$name".');
      case ScannedChoice.keep:
        // On screen first, and then keep *that* — not the code it came from.
        // [_apply] is where a profile is held to what this picker has room
        // for, so a code from some later build arrives as three sets rather
        // than four and one deck rather than nine. Keeping the code itself
        // would write a save holding dice this build will never show you,
        // under a summary that described them: "9 decks" on a row that opens
        // showing three. A save has to describe what opening it does.
        //
        // It is also what makes [_capture] the only thing a save is ever made
        // of, which is what this screen says of itself everywhere else.
        _apply(scanned.profile);
        final Profile taken = _capture();
        if (existing != null) {
          profiles.write(existing.id, taken);
          _open(profiles.byId(existing.id)!);
        } else {
          final SavedProfile made = profiles.add(name, taken);
          setState(() => _saved = made.id);
        }
    }
  }

  /// Puts a scanned profile on screen without keeping it.
  ///
  /// Nothing is lit afterwards. What is on screen came from a code rather than
  /// from a profile, and a profile that lit up here would be claiming to hold
  /// something it does not.
  void _take(Profile profile) {
    _apply(profile);
    setState(() => _saved = null);
  }

  void _say(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: const Color(0xFF1B2430),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );

  /// Puts the tutorial up. Both ways in come through here: the first launch,
  /// from [initState], and **How to use** at the bottom of the app menu.
  ///
  /// The backdrop goes with it because the tutorial cannot build one for
  /// itself. It draws the screen each page is about behind the card of text,
  /// and two of the three screens are this file — so a tutorial that reached
  /// for [PickerScreen] directly would be a file the picker imports importing
  /// the picker back. `profile_row.dart` pays for the same rule with a
  /// duplicated constant; here the cost is one function, which is cheaper.
  Future<void> _tutorial() => showTutorial(context, backdrop: tutorialBackdrop);

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
                // Under everything the two modes have, because a save is
                // about both of them at once — and given every point between
                // there and the Roll button, which is what it wraps into and,
                // once it has filled it, scrolls inside. There is no [Spacer]:
                // the slack under the profiles *is* the profiles' space, and a block
                // of them that grew past it would push the button off the
                // bottom of the screen.
                Expanded(
                  child: ProfileRow(
                    open: _saved,
                    onOpen: _open,
                    onSave: _saveTo,
                    onShare: _share,
                    onNew: () => unawaited(_newSave()),
                    onReset: _reset,
                    onShareCurrent: _shareCurrent,
                  ),
                ),
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
              AppMenuButton(
                key: kAppMenu,
                onScanned:
                    (ScannedProfile scanned) => unawaited(_scanned(scanned)),
                onTutorial: () => unawaited(_tutorial()),
              ),
              // Shrunk to fit rather than cut off. The longest name allowed
              // takes the title past the width of a phone, and an ellipsis
              // would eat the end of the one word here that is not always the
              // same — which is the word worth reading. Nothing to scale down
              // until there is a name, so the plain title is untouched.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _title,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Color(0xFFE8EEF6),
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                    ),
                  ),
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
  /// A [Stack] rather than another [PageView], and a deliberately lopsided one:
  /// the dice page is the only child that sizes it, and the card page is laid
  /// into whatever height that comes to. So the block is the same height in
  /// both modes — nothing under it moves when a swipe lands — and the card
  /// page, which is the shorter rack and the taller panel, spends the
  /// difference on the gap between the two rather than on being taller. What
  /// slides is a transform, which costs no layout at all.
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
                    Transform.translate(
                      offset: Offset(-_slide.value * width, 0),
                      child: SizedBox(
                        key: kDicePage,
                        width: width,
                        child: _dicePage(width),
                      ),
                    ),
                    // Positioned, so it takes the dice page's height as a tight
                    // constraint instead of contributing one of its own.
                    Positioned.fill(
                      child: Transform.translate(
                        offset: Offset((1 - _slide.value) * width, 0),
                        child: SizedBox(
                          key: kCardPage,
                          width: width,
                          child: _cardsPage(width),
                        ),
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

  /// The card page fills the block rather than sizing it — see [_block] — so
  /// the panel hangs off the bottom and the slack goes above it, into the row
  /// of the rack that card mode leaves empty. Its panel is the taller of the
  /// two by a slider, and this is what pays for that without either panel's
  /// bottom edge — or the mode dots under them — moving as one slides over the
  /// other.
  Widget _cardsPage(double width) => Column(
    children: <Widget>[
      _cardRack(),
      const Spacer(),
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
  /// The row they are in is the row the dice rack starts with, so swapping
  /// between the modes moves nothing but the slots themselves. What card mode
  /// does not have is the second row — three dice never reach it — and that is
  /// deliberately a row of nothing rather than a row of empty slots: it is the
  /// space [_cardsPage] spends on a panel with a slider in it.
  Widget _cardRack() {
    // The same plus the dice rack has, in the same place: the last slot of the
    // three, until the third die lands in it.
    final int adder = _cardDice < kMaxCardDice ? kMaxCardDice - 1 : -1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kRackMargin),
      child: Column(
        children: <Widget>[
          for (int row = 0; row * kRackColumns < kMaxCardDice; row++)
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
                                    key: i == adder ? kAddDie : null,
                                    spec: i < _cardDice ? _cardSpec(i) : null,
                                    selected: i == _cardSelected,
                                    adds: i == adder,
                                    // Tappable, and selected the same way the
                                    // dice rack is: the swatches below are
                                    // about one die of the card, and this is
                                    // where you say which. There is still no
                                    // kind to choose — every card-mode die is
                                    // a D6 — so colour is all a tap can lead
                                    // to here. The third slot is the plus and
                                    // takes another die, until the third die
                                    // is that slot; past three there is no
                                    // slot at all.
                                    onTap:
                                        i < _cardDice
                                            ? () => _selectCardDie(i)
                                            : i == adder
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
    final int size = Deck.sizeOf(_cardDice, _decks);
    return Container(
      // The handle the two modes are dragged by, on the page that has the
      // most to say for itself — which is why it is the thing the tutorial's
      // first page points at. See [kCardPanel].
      key: kCardPanel,
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
          key: kRack,
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
  /// to look like: room for ten, and nothing in it — with the plus at the far
  /// end of them, where it stays.
  Widget _rack(int group) {
    final List<DieSpec> dice = _groups[group];
    final int selected = _selectedIn[group];
    // Where the plus is: the last slot in the rack, for as long as the rack has
    // room for another die. A full one has no plus at all — the tenth die is
    // sitting in the slot it was drawn in — which [kAddDie] is the long form of.
    final int adder = dice.length < kMaxDice ? kMaxDice - 1 : -1;
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
                            // The last slot is where you ask for another die,
                            // and it is the same slot every time. A full rack
                            // has no plus — that slot is a die now — and that
                            // is the whole of the limit: nothing to tap, and
                            // nothing greyed out to explain why not.
                            key: i == adder ? kAddDie : null,
                            spec: i < dice.length ? dice[i] : null,
                            selected: i == selected,
                            adds: i == adder,
                            onTap:
                                i < dice.length
                                    ? () => _select(group, i)
                                    : i == adder
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
                  empty ? 'No dice yet' : 'Die ${_selected + 1}',
                  // Short, and held to one line come what may: this title is
                  // the one thing in the card whose length changes, and a
                  // second line of it would push everything below the card
                  // down the screen under a finger mid-swipe. It does not name
                  // the kind: the lit chip below already says which one it is,
                  // and saying it twice only made the line longer.
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
                      for (final DieKind kind in _kinds(spec))
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
        key: kRollButton,
        onPressed: anything ? _roll : null,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF3F6FA8),
          foregroundColor: const Color(0xFFF2F7FF),
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        // Card mode does not throw anything. The button still builds a shoe
        // and shuffles it, but that is the preparation and not the thing being
        // asked for — and the card screen has its own button for turning each
        // card over, which is "Draw". So this one is named for putting the
        // game on the table rather than for the work behind it, and the two
        // stay a pair of distinct gestures instead of two words for one.
        child: Text(
          _cards ? 'Deal' : 'Roll',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// The screen the tutorial draws behind itself, for a given page.
///
/// A real [PickerScreen] and a real [TrayScreen], not a picture of either:
/// what a page points at has to be where it actually is, and a drawing of a
/// screen is a second thing to keep in step with the first. They are built
/// from [kTutorialProfile] rather than from whatever the player has set up,
/// because the whole point is that the backdrop shows the page being
/// *discussed* — the card page while the card page is being explained, three
/// sets of dice while the three sets are.
///
/// Nothing here is touchable: the tutorial puts every one of these behind an
/// [IgnorePointer]. The tray is still fed the accelerometer, though, so a
/// shake on the page that says "shake to throw" throws it.
///
/// Handed to [showTutorial] rather than reached for from inside it — see
/// [_PickerScreenState._tutorial], which explains what the indirection buys.
Widget tutorialBackdrop(TutorialStage stage) => switch (stage) {
  TutorialStage.dice => const PickerScreen(initial: kTutorialProfile),
  TutorialStage.cards => const PickerScreen(initial: kTutorialCards),
  TutorialStage.tray => TrayScreen(
    groups: rollableGroups(kTutorialProfile.groups),
  ),
};

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

  /// Whether this is the slot the plus is drawn in — the last one in the rack,
  /// for as long as the rack has room for another die, and the only empty slot
  /// a tap does anything to. Never true of a slot that has a [spec].
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
    // The size rides on the label rather than on the `ButtonStyle`, which is
    // how [TrayButton] has always done it and is not merely a matter of taste.
    // A `textStyle` given to `styleFrom` REPLACES the button's resolved text
    // style outright instead of merging into it, so a style written there for
    // its size alone also throws the font family away — and a label with no
    // family asks the engine for whatever the platform's default happens to
    // be. On a phone that is the system face and nobody notices. Anywhere the
    // default is not a real font it is six blank boxes, which is what
    // `tool/appstore.dart` was rendering into the store listing.
    label: const Text('Remove', style: TextStyle(fontSize: 13)),
    style: TextButton.styleFrom(
      foregroundColor: const Color(0xAABFD0E4),
      disabledForegroundColor: const Color(0x33BFD0E4),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
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
        // Shrunk to fit rather than cut off, the same bargain the title makes.
        // Six chips of two or three characters fit any phone with room to
        // spare; a seventh, with a word on it, does not — and a chip whose
        // label had been ellipsed would be a chip you could not read.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color:
                  selected ? const Color(0xFFF2F7FF) : const Color(0xAABFD0E4),
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
