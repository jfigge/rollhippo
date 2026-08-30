import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/cards/deck.dart';
import 'package:rollhippo/motion/entropy.dart';

/// A clock that does not move.
///
/// The whole reason [EntropyPool] takes one: with the real clock every seed
/// differs whether or not a reading ever reached the pool, so a stopped clock
/// is the only way to ask whether stirring does anything at all.
int _stopped() => 1735689600000000;

/// How many of the sixty-four bits two seeds disagree about.
int _hamming(int a, int b) {
  final int difference = a ^ b;
  int bits = 0;
  for (int i = 0; i < 64; i++) {
    bits += (difference >>> i) & 1;
  }
  return bits;
}

/// Deals a shoe right down to the cut and says what order it came out in.
List<String> _dealAll(Deck deck) {
  final List<String> dealt = <String>[];
  while (!deck.spent) {
    deck.draw();
    dealt.add(deck.shown.toString());
  }
  return dealt;
}

void main() {
  group('EntropyPool', () {
    test('is a function of what went into it', () {
      // Two pools, one instant, the same three readings: the mixing is
      // arithmetic and nothing else, which is what makes the rest of these
      // tests worth believing.
      final EntropyPool one =
          EntropyPool(clock: _stopped)
            ..stir(9.8066)
            ..stir(-0.0213)
            ..stir(0.4471);
      final EntropyPool two =
          EntropyPool(clock: _stopped)
            ..stir(9.8066)
            ..stir(-0.0213)
            ..stir(0.4471);
      expect(one.seed(), two.seed());
    });

    test('one reading changes everything about the seed', () {
      // A unit in the last place apart — which is about what two accelerometer
      // samples of a phone lying still on a table differ by. Without an
      // avalanche two seeds that close would start two very similar streams,
      // and a shoe would be nearly the same shoe.
      final int near =
          (EntropyPool(clock: _stopped)..stir(9.806650161743164)).seed();
      final int far =
          (EntropyPool(clock: _stopped)..stir(9.806650161743166)).seed();
      expect(near, isNot(far));
      expect(_hamming(near, far), greaterThan(16));
    });

    test('four shoes built in the same microsecond do not share a seed', () {
      // What the picker does: up to four tables, all of them shuffled inside
      // one layout pass. The clock cannot tell them apart, so the draw count
      // has to.
      final EntropyPool pool = EntropyPool(clock: _stopped)..stir(9.81);
      final List<int> seeds = <int>[for (int i = 0; i < 4; i++) pool.seed()];
      expect(seeds.toSet().length, 4);
    });

    test('a pool nobody stirred still moves, because the clock does', () {
      // The desktop harness, a phone whose accelerometer errored, every test in
      // this suite. Nothing physical has gone in and the seeds must still be
      // spread over the whole word rather than counting.
      final EntropyPool pool = EntropyPool();
      final Set<int> seeds = <int>{};
      int anySet = 0;
      int anyClear = 0;
      for (int i = 0; i < 1000; i++) {
        final int seed = pool.seed();
        seeds.add(seed);
        anySet |= seed;
        anyClear |= ~seed;
      }
      expect(seeds.length, 1000, reason: 'a seed came round twice');
      expect(anySet, -1, reason: 'a bit was never set');
      expect(anyClear, -1, reason: 'a bit was never clear');
    });
  });

  group('a shoe seeded from it', () {
    test('deals a different order every time it is built', () {
      final List<String> first = _dealAll(
        Deck(dice: 2, decks: 1, reshuffleAt: 0),
      );
      final List<String> second = _dealAll(
        Deck(dice: 2, decks: 1, reshuffleAt: 0),
      );
      expect(first.length, 36);
      expect(first, isNot(second));
      expect(first.toSet(), second.toSet(), reason: 'a card went missing');
    });

    test('deals the same order when it is given a generator', () {
      // The seam the tools and the tests hold on to. A deck told which stream
      // to draw from must not go anywhere near the pool.
      expect(
        _dealAll(
          Deck(dice: 2, decks: 1, reshuffleAt: 0, random: math.Random(9)),
        ),
        _dealAll(
          Deck(dice: 2, decks: 1, reshuffleAt: 0, random: math.Random(9)),
        ),
      );
    });
  });
}
