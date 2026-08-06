import 'dart:math' as math;

import '../tray/tuning.dart';

/// One card: a single possible outcome of the dice being thrown.
///
/// Not a suit and a rank. The deck this belongs to is a deck of *rolls* — every
/// combination the dice could come up with, printed one per card — so what a
/// card carries is the faces themselves.
class PlayingCard {
  const PlayingCard(this.faces);

  /// One value per die, each 1 to 6, in the order the dice are laid out.
  final List<int> faces;

  int get total => faces.fold(0, (int sum, int face) => sum + face);

  @override
  String toString() => faces.join('-');
}

/// A shoe of cards standing in for a throw of [dice] six-sided dice.
///
/// Drawing from it is the same wager as rolling them, and stays the same wager
/// only because every outcome is in here the same number of times. Which means
/// *ordered* outcomes: a pair of dice can come up 1-2 two ways and 1-1 only
/// one, so a deck holding each unordered pair once would quietly make snake
/// eyes twice as likely as it is. Six to the power of the dice, per deck.
///
/// It differs from rolling in the one way a shoe always differs: it is drawn
/// without replacement, so what has already gone tells you something about what
/// is left. That is the point of it, and it is why [reshuffleAt] exists — the
/// same cut card a casino uses, for the same reason.
class Deck {
  Deck({
    required this.dice,
    required this.decks,
    required this.reshuffleAt,
    math.Random? random,
  }) : _random = random ?? math.Random() {
    shuffle();
  }

  /// How many dice a card stands for, 1 to 3.
  final int dice;

  /// How many copies of the full set are shuffled together.
  final int decks;

  /// The percentage of the shoe left at which it is reshuffled rather than
  /// dealt from, 0 to 20. At zero it runs to the last card.
  final int reshuffleAt;

  final math.Random _random;

  /// Face down, top of the pile last — [List.removeLast] is the cheap end.
  final List<PlayingCard> _pile = <PlayingCard>[];

  PlayingCard? _shown;

  /// Every ordered outcome of [dice] dice, [decks] times over.
  ///
  /// Counting in base six: card *n* of a deck reads off as the digits of *n*,
  /// which is exactly one card per outcome and no bookkeeping to get wrong.
  static List<PlayingCard> build(int dice, int decks) {
    final int outcomes = math.pow(6, dice).toInt();
    return <PlayingCard>[
      for (int copy = 0; copy < decks; copy++)
        for (int n = 0; n < outcomes; n++)
          PlayingCard(<int>[
            for (int d = 0, rest = n; d < dice; d++, rest ~/= 6) rest % 6 + 1,
          ]),
    ];
  }

  /// How many cards a full shoe holds.
  int get size => math.pow(6, dice).toInt() * decks;

  /// How many are left to deal.
  int get remaining => _pile.length;

  /// The card lying face up on the glass, or null before the first draw and
  /// again after a reshuffle.
  PlayingCard? get shown => _shown;

  /// The count at or below which the shoe is reshuffled instead of dealt from.
  int get cut => size * reshuffleAt ~/ 100;

  /// True when the next [draw] will reshuffle rather than deal a card.
  bool get spent => remaining <= cut;

  /// Puts every card back and shuffles, and clears the glass.
  void shuffle() {
    _pile
      ..clear()
      ..addAll(build(dice, decks));
    // Fisher–Yates, back to front: after step i the tail is a uniform sample
    // and never moves again.
    for (int i = _pile.length - 1; i > 0; i--) {
      final int j = _random.nextInt(i + 1);
      final PlayingCard swap = _pile[i];
      _pile[i] = _pile[j];
      _pile[j] = swap;
    }
    _shown = null;
  }

  /// Deals the top card face up, or reshuffles if the shoe is [spent].
  ///
  /// The reshuffle is a draw of its own rather than something that happens
  /// silently underneath one: you ask for a card, the shoe is down to the cut,
  /// and what you get is a full pile and an empty glass. That is a state worth
  /// seeing, and folding it into the same action as a deal would either hide it
  /// or throw away the card you just asked for.
  void draw() {
    if (spent) {
      shuffle();
      return;
    }
    _shown = _pile.removeLast();
  }
}

/// The box, with a pile of cards in it instead of dice.
///
/// The same tray, the same walls and the same camera — what changes is what is
/// standing inside. Metres, like everything below the widgets.
class CardTable {
  CardTable({
    required this.width,
    required this.height,
    this.depth = Tuning.trayDepth,
    required this.deck,
  });

  final double width;
  final double height;
  final double depth;

  final Deck deck;
}
