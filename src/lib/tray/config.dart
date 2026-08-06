import '../cards/deck.dart';
import 'dice.dart';

/// Which of the two things the picker is setting up.
///
/// They are pages of the same screen rather than two screens, because they are
/// alternatives: whichever one you are looking at is what Roll will do, and a
/// mode you have to go somewhere else to find is a mode nobody finds.
enum ConfigMode { dice, cards }

/// Everything the picker is set to, in both of its modes at once.
///
/// Both modes, always — a configuration is the whole screen rather than the
/// page of it you happen to be on, so saving one in card mode does not throw
/// away the dice you had set up behind it.
///
/// Down here rather than in `app/` because two quite different things need it
/// and neither is a widget: the store writes it into the preferences file, and
/// [encodeConfig] puts it in a QR code. It knows nothing about Flutter, which
/// is what lets both of those be tested without a frame.
class Config {
  const Config({
    required this.mode,
    required this.groups,
    required this.colours,
    required this.decks,
    required this.reshuffleAt,
  });

  /// Which page this configuration is about: the mode the picker was on when
  /// it was saved, and so the mode opening it puts you back on.
  final ConfigMode mode;

  /// The three sets of dice, empties and all. An empty group is a set you never
  /// started rather than one you forgot to fill in, and it is worth keeping:
  /// opening a save should give you back the two sets you had, not three.
  final List<List<DieSpec>> groups;

  /// One colour per die printed on a card, in the order they are laid down it.
  /// The list *is* the dice — see `ConfigScreen._cardColours`.
  final List<int> colours;

  final int decks;
  final int reshuffleAt;

  /// What this configuration comes to, in the fewest words that are still true.
  ///
  /// One line for a list row to hang under a name — see `SavedConfig.subtitle`
  /// — and for the Share sheet to print under its code. It describes the mode
  /// the configuration was saved in, because that is the half of it that would
  /// happen if you opened it and pressed the button.
  String get summary {
    if (mode == ConfigMode.cards) {
      final int size = Deck.sizeOf(colours.length, decks);
      return '$decks ${decks == 1 ? 'deck' : 'decks'}, $size cards';
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

  /// Two configurations are the same when they would put the same thing on
  /// screen — which is the question a scanned code asks about a save you
  /// already have, and the difference between opening it silently and stopping
  /// to ask what you meant.
  @override
  bool operator ==(Object other) =>
      other is Config &&
      other.mode == mode &&
      other.decks == decks &&
      other.reshuffleAt == reshuffleAt &&
      _sameInts(other.colours, colours) &&
      _sameGroups(other.groups, groups);

  @override
  int get hashCode => Object.hash(
    mode,
    decks,
    reshuffleAt,
    Object.hashAll(colours),
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
