import '../cards/deck.dart';
import 'dice.dart';

/// Which of the two things the picker is setting up.
///
/// They are pages of the same screen rather than two screens, because they are
/// alternatives: whichever one you are looking at is what Roll will do, and a
/// mode you have to go somewhere else to find is a mode nobody finds.
enum ProfileMode { dice, cards }

/// How many shoes a table can hold.
///
/// Four, and the same four as `kMaxGroups`: the card table is the tray's other
/// page, and a picker whose two halves disagreed about how many sets you may
/// have would be two apps. Named here rather than beside that one because
/// this is where a shoe is defined and because [encodeProfile] — which is
/// below the widgets and cannot see the picker — has to know it to read an
/// older code that carries only one.
///
/// It is a ceiling rather than a count. The picker never shows four at once
/// unless you have filled them: it shows the shoes you have started and one
/// empty one after them, so the number of pages grows as you fill them and
/// this is only where that growing stops.
const int kMaxCardSets = 4;

/// One shoe, as the picker sets it up: what is printed on a card, how many
/// decks are shuffled together, and how deep it is cut.
///
/// The card side's answer to a group of dice, and deliberately the same shape
/// of thing. A tray holds several sets of dice and you swipe between them; a
/// table holds as many shoes and you swipe between those. Which means a shoe
/// carries its own set-up rather than sharing one — two shoes with the same
/// dice, the same decks and the same cut are the same shoe twice, and the
/// point of having more than one is that one can be a blackjack shoe and
/// another a single deck you cut to the last card.
///
/// [colours] *is* the dice: a card with two dice printed on it is a card with
/// two colours on it, and there is no separate count that could disagree. An
/// empty one is a shoe nobody started — see [Profile.cards].
class CardSet {
  const CardSet({
    required this.colours,
    required this.decks,
    required this.reshuffleAt,
  });

  /// One colour per die printed on a card, in the order they are laid down it.
  final List<int> colours;

  final int decks;
  final int reshuffleAt;

  /// How many dice a card of this shoe stands for.
  int get dice => colours.length;

  /// True of a shoe nobody has started. Not one you emptied by accident:
  /// the picker will not let the last shoe there is get here.
  bool get isEmpty => colours.isEmpty;

  bool get isNotEmpty => colours.isNotEmpty;

  /// How many cards it comes to.
  int get size => Deck.sizeOf(colours.length, decks);

  CardSet copyWith({List<int>? colours, int? decks, int? reshuffleAt}) =>
      CardSet(
        colours: colours ?? this.colours,
        decks: decks ?? this.decks,
        reshuffleAt: reshuffleAt ?? this.reshuffleAt,
      );

  /// Value equality, for the reason [DieSpec] has it: "do I already have this
  /// one" is the question a scanned code asks, and it asks it of the whole
  /// profile.
  @override
  bool operator ==(Object other) =>
      other is CardSet &&
      other.decks == decks &&
      other.reshuffleAt == reshuffleAt &&
      _sameInts(other.colours, colours);

  @override
  int get hashCode => Object.hash(decks, reshuffleAt, Object.hashAll(colours));
}

/// A shoe nobody has started, which is what the one waiting past the last
/// started shoe is until somebody puts a die on it.
///
/// Its numbers are the ones a first die finds waiting, and they are the same
/// two the app's own opening shoe is set up with — see `kDefaultProfile`. A
/// blank shoe used to start at one deck cut to nothing, on the argument that a
/// shoe with no cards in it has no decks to speak of; what that missed is that
/// these numbers are not a description of an empty shoe but the starting point
/// of the next one. Somebody adding a second shoe is adding *another* of what
/// they already have, and finding it set up unlike the first is two rows to
/// put back before the shoe is what they meant.
///
/// Down here rather than beside the picker's other defaults because
/// `tutorial.dart` needs one too and must not import the picker: the picker
/// opens the tutorial, so that edge already runs the other way.
const CardSet kEmptyShoe = CardSet(colours: <int>[], decks: 2, reshuffleAt: 5);

/// Everything the picker is set to, in both of its modes at once.
///
/// Both modes, always — a profile is the whole screen rather than the
/// page of it you happen to be on, so saving one in card mode does not throw
/// away the dice you had set up behind it.
///
/// Down here rather than in `app/` because two quite different things need it
/// and neither is a widget: the store writes it into the preferences file, and
/// [encodeProfile] puts it in a QR code. It knows nothing about Flutter, which
/// is what lets both of those be tested without a frame.
class Profile {
  const Profile({
    required this.mode,
    required this.groups,
    required this.cards,
  });

  /// Which page this profile is about: the mode the picker was on when
  /// it was saved, and so the mode opening it puts you back on.
  final ProfileMode mode;

  /// The sets of dice, empties and all — `kMaxGroups` of them, since that is
  /// what the picker captures. An empty group is a set you never started
  /// rather than one you forgot to fill in, and it is worth keeping: opening a
  /// save should give you back the two sets you had, not four.
  final List<List<DieSpec>> groups;

  /// The shoes, empties and all, for the same reason [groups] keeps its
  /// empties: a shoe with no dice on its card is one you never started, and
  /// opening a save should give you back the two you had rather than four.
  /// At least one of them has a card on it, though it need not be the first.
  final List<CardSet> cards;

  /// What this profile comes to, in the fewest words that are still true.
  ///
  /// One line for the Share sheet to print under its code. It describes the mode
  /// the profile was saved in, because that is the half of it that would
  /// happen if you opened it and pressed the button.
  String get summary {
    if (mode == ProfileMode.cards) {
      final List<CardSet> shoes = <CardSet>[
        for (final CardSet shoe in cards)
          if (shoe.isNotEmpty) shoe,
      ];
      if (shoes.isEmpty) return 'no cards';
      final int total = shoes.fold(0, (int sum, CardSet s) => sum + s.size);
      // More than one and the decks are no longer one number to quote, so the
      // count of shoes takes that half of the line — which is the shape the
      // dice summary already uses for more than one set.
      if (shoes.length > 1) return '${shoes.length} shoes, $total cards';
      final int decks = shoes.first.decks;
      return '$decks ${decks == 1 ? 'deck' : 'decks'}, $total cards';
    }
    final List<int> counts = <int>[
      for (final List<DieSpec> group in groups)
        if (group.isNotEmpty) group.length,
    ];
    final int total = counts.fold(0, (int sum, int n) => sum + n);
    if (total == 0) return 'no dice';
    final String dice = '$total ${total == 1 ? 'die' : 'dice'}';
    return counts.length > 1 ? '${counts.length} sets, $dice' : dice;
  }

  /// Two profiles are the same when they would put the same thing on
  /// screen — which is the question a scanned code asks about a save you
  /// already have, and the difference between opening it silently and stopping
  /// to ask what you meant.
  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.mode == mode &&
      _sameCards(other.cards, cards) &&
      _sameGroups(other.groups, groups);

  @override
  int get hashCode => Object.hash(
    mode,
    Object.hashAll(cards),
    Object.hashAll(<int>[
      for (final List<DieSpec> group in groups) Object.hashAll(group),
    ]),
  );
}

bool _sameInts(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameCards(List<CardSet> a, List<CardSet> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameGroups(List<List<DieSpec>> a, List<List<DieSpec>> b) {
  if (a.length != b.length) return false;
  for (int g = 0; g < a.length; g++) {
    if (a[g].length != b[g].length) return false;
    for (int d = 0; d < a[g].length; d++) {
      if (a[g][d] != b[g][d]) return false;
    }
  }
  return true;
}
