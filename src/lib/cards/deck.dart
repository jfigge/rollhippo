import 'dart:math' as math;

import '../motion/entropy.dart';
import '../tray/dice.dart';
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
  }) : _random = random ?? math.Random(entropy.seed()) {
    shuffle();
  }

  /// How many dice a card stands for, 1 to 3.
  final int dice;

  /// How many copies of the full set are shuffled together.
  final int decks;

  /// The percentage of the shoe left at which it is reshuffled rather than
  /// dealt from, 0 to 20. At zero it runs to the last card.
  final int reshuffleAt;

  /// What the shuffle draws its indices from.
  ///
  /// Given one, this deck deals the same shoe every time it is built — which
  /// is what the tests and the tools want, and the only reason the parameter
  /// exists. Given nothing, it seeds its own from [entropy]: the clock, and
  /// whatever the phone's own sensors have been stirring into the pool since
  /// launch.
  ///
  /// Seeded rather than left to `math.Random()`, because a shoe is a claim
  /// that nobody knows what is left in it and a default seed is a fact about
  /// the millisecond an object was made. See [EntropyPool], which is where the
  /// argument and the limits of it are written down. It is drawn once, here,
  /// and [shuffle] goes on using the same stream afterwards — a reshuffle is
  /// the next hand of the same deal, not a new pool.
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
  int get size => sizeOf(dice, decks);

  /// The same count, for a shoe nobody has built yet.
  ///
  /// The picker draws it under the card panel and the saved-profile list
  /// says it out loud — "2 decks, 72 cards" — and neither of them wants two
  /// hundred [PlayingCard]s made and thrown away to find out what the number is.
  static int sizeOf(int dice, int decks) => math.pow(6, dice).toInt() * decks;

  /// How many are left to deal.
  int get remaining => _pile.length;

  /// The card lying face up on the glass, or null before the first draw and
  /// again after a reshuffle.
  PlayingCard? get shown => _shown;

  /// The count at or below which the shoe is reshuffled instead of dealt from.
  int get cut => size * reshuffleAt ~/ 100;

  /// True when the next [draw] will reshuffle rather than deal a card.
  bool get spent => remaining <= cut;

  /// True once this shoe has been played — a card is on the glass, or cards
  /// have gone from the pile, or both.
  ///
  /// What it really answers is "would shutting this down throw anything away",
  /// and on a shoe that is a question about the *pile* rather than about the
  /// glass. Drawing without replacement is the whole of what makes this mode
  /// different from throwing dice, so what a closed table loses is not the
  /// card you were looking at, it is everything the cards already gone say
  /// about the ones that are left.
  ///
  /// Which is why a reshuffle puts it back to false. [shuffle] empties the
  /// glass and refills the pile, and what is left behind is a full shoe nobody
  /// has drawn from — the state a table opens in, with nothing to lose by
  /// closing it.
  bool get dealt => _shown != null || remaining < size;

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

/// A card on its way from the top of the pile to the glass, turning over as it
/// goes.
///
/// Time, and nothing else. Where the pile stands and where a dealt card lies
/// are the painter's business — it works both out from the tray's own
/// measurements, and a second copy of them in here would be a second thing to
/// get wrong. What this holds is how far through the journey the card is, how
/// far over it has turned, and which card it is landing on top of.
///
/// The deal is not the draw. [Deck.draw] happens at once and the card is off
/// the pile the instant it is asked for — this is only the card arriving, and
/// interrupting it costs nothing but the sight of it.
class Deal {
  PlayingCard? _card;
  PlayingCard? _under;
  double _elapsed = 0;

  /// The card in the air, or null when nothing is being dealt.
  PlayingCard? get card => _card;

  /// The card being replaced: whatever was lying on the glass when this one
  /// was asked for, and null once it has left.
  ///
  /// It leaves rather than waits to be covered. A card that simply vanished
  /// the moment the next one lifted off would read as one being snatched away,
  /// which is why this was kept in the first place; a card that lay there and
  /// was buried never looked like it had been played. So it is dealt with the
  /// same way a hand deals with it — swept off the table — and [discard] is
  /// how far through that it is.
  PlayingCard? get under => _under;

  /// True while a card is in the air.
  bool get flying => _card != null;

  /// True while the card being replaced is still on its way out.
  ///
  /// Not the same question as [flying], and neither implies the other: a
  /// reshuffle sends a card away with nothing following it, and a deal onto an
  /// empty glass has nothing to send.
  bool get discarding => _under != null;

  /// True while anything at all on this table is moving.
  ///
  /// What the screen ticks on and what the painter asks before it draws a card
  /// lying still, because during a deal there is no such card: the one that
  /// was there is leaving and the one that is coming has not arrived.
  bool get busy => flying || discarding;

  /// How far along the journey the card is: 0 on the pile, 1 on the glass.
  double get travel => _ease(_fraction(Tuning.dealDuration));

  /// How far over it has turned, radians. Nought is face down, pi is face up,
  /// and halfway is the card edge on.
  ///
  /// On its own clock, which runs out at [Tuning.dealTurn] of the journey: the
  /// turn is finished before the landing is.
  double get turn =>
      math.pi * _ease(_fraction(Tuning.dealDuration * Tuning.dealTurn));

  /// How far the outgoing card has got: 0 lying on the glass, 1 clear of the
  /// box altogether.
  ///
  /// On its own clock, like [turn], and for the same kind of reason — it runs
  /// out at [Tuning.dealDiscard] of the journey, so the glass is empty for a
  /// beat before the new card reaches it. Where "clear of the box" is belongs
  /// to the painter, which knows where a card lies and how big the box is.
  double get discard =>
      _ease(_fraction(Tuning.dealDuration * Tuning.dealDiscard));

  double _fraction(double over) => (_elapsed / over).clamp(0.0, 1.0);

  /// Sends [card] on its way and [under] off the table. Either may be null and
  /// they are independent: a reshuffle deals no card and still has one to
  /// clear away, and the first deal onto an empty glass clears nothing.
  void start(PlayingCard? card, PlayingCard? under) {
    _card = card;
    _under = under;
    _elapsed = 0;
  }

  /// One frame, in real seconds.
  ///
  /// Two clocks off one elapsed time, and they stop at different moments: the
  /// outgoing card is gone first, the arriving one lands last. The elapsed
  /// time is only reset once both are done, because either of them still
  /// running is a reason to keep counting.
  void advance(double dt) {
    if (!busy) return;
    _elapsed += dt;
    // Off the bottom of the box, and nothing will draw it again.
    if (_elapsed >= Tuning.dealDuration * Tuning.dealDiscard) _under = null;
    // Landed. The card is the deck's [Deck.shown] now and the painter draws it
    // lying on the glass, which is where this left it.
    if (_elapsed >= Tuning.dealDuration) _card = null;
    if (!busy) _elapsed = 0;
  }
}

/// Cubic ease in and out, the same curve the readout moves the dice on and
/// written out here for the same reason: nothing below the widgets may import
/// Flutter's `Curves`, and a card has to be dealt headless in the tools and the
/// tests.
double _ease(double t) =>
    t < 0.5
        ? 4 * t * t * t
        : 1 - (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) / 2;

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
    this.colours = const <int>[],
  });

  final double width;
  final double height;
  final double depth;

  final Deck deck;

  /// What colour each die printed on a card is, packed ARGB and one per die —
  /// ints rather than `Color`s for the same reason [DieSpec] keeps one, so
  /// that nothing below the widgets has to know Flutter exists.
  ///
  /// They belong to the table rather than to the [Deck], because a deck is the
  /// combinatorics — which outcomes exist and how many of each — and what ink
  /// they happen to be printed in is not one of them.
  ///
  /// A table can be built without saying, and usually is by the tests and the
  /// harness; anything this list does not reach is ivory, which is what a die
  /// is anywhere else in the app. See [colourOf].
  final List<int> colours;

  /// What the die in position [i] on a card is printed in.
  int colourOf(int i) => i < colours.length ? colours[i] : kDiceWhite;

  /// The card presently in the air, if any. See [Deal].
  final Deal deal = Deal();

  /// Turns the top card over onto the glass, or reshuffles if the shoe is
  /// spent — and sends whatever came of that on its way across the box, while
  /// whatever was already on the glass slides out of the bottom of it.
  ///
  /// The deal is the whole of what is animated here, and it is animated after
  /// the fact: the card has already left the pile by the time this returns,
  /// and [Deck.shown] is already the new one. Nothing about which card it is
  /// waits on the flight, so a second ask arriving mid-flight simply lands the
  /// first one and starts again.
  void draw() {
    final PlayingCard? under = deck.shown;
    deck.draw();
    deal.start(deck.shown, under);
  }

  /// One frame, in real seconds.
  ///
  /// Nothing on this table is simulated — a card is not a rigid body and there
  /// is nothing in the box to throw. The only things that move are the card
  /// being dealt and the one it is replacing.
  void advance(double dt) => deal.advance(dt);
}
