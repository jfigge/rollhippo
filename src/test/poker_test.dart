import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/render/poker.dart';
import 'package:rollhippo/render/tray_painter.dart';
import 'package:rollhippo/tray/tray.dart';

void main() {
  test('every face of the poker die has a card, and every card a face', () {
    expect(
      kPokerFaces.keys.toList()..sort(),
      DieKind.poker.numbers,
      reason: 'the cards and the die must agree about what it can read',
    );

    // The ranks, in the order the numbers put them in. A die that read its
    // ace as anything but its highest number would sort wrong everywhere.
    expect(
      <String>[for (final int v in DieKind.poker.numbers) kPokerFaces[v]!.rank],
      <String>['9', '10', 'J', 'Q', 'K', 'A'],
    );

    // The pips are the rank, which is the whole of what makes a nine of
    // hearts a nine rather than a picture of some hearts.
    expect(kPokerFaces[9]!.pips, 9);
    expect(kPokerFaces[10]!.pips, 10);
    expect(kPokerFaces[14]!.pips, 1);
    for (final int value in <int>[11, 12, 13]) {
      expect(kPokerFaces[value]!.court, isTrue, reason: '$value is a court');
    }

    expect(kPokerFaces[14]!.suit, PokerSuit.spade, reason: 'an ace of spades');
    expect(
      <PokerSuit>{for (final PokerFace f in kPokerFaces.values) f.suit},
      PokerSuit.values.toSet(),
      reason: 'all four suits appear somewhere on the die',
    );
  });

  test('the poker die prints something other than its numbers', () {
    expect(printingFor(DieKind.poker), DiePrinting.cards);
    expect(printingFor(DieKind.hippo), DiePrinting.hippo);
    for (final DieKind kind in <DieKind>[
      DieKind.d4,
      DieKind.d6,
      DieKind.d8,
      DieKind.d10,
      DieKind.d12,
      DieKind.d20,
    ]) {
      expect(printingFor(kind), DiePrinting.numerals, reason: kind.label);
    }
  });

  test('a red suit stands off every body a die can be painted', () {
    // Held to [DieStyle.luminance] rather than to `Color.computeLuminance`,
    // because that is the measure the inks were chosen by — see `_redOn`. The
    // palette's red die is the case this exists for: a red diamond printed on
    // it in a card's own red would not be a diamond.
    for (final int colour in kDicePalette) {
      final DieStyle style = DieStyle.of(colour);
      final double body = DieStyle.luminance(Color(colour));
      expect(
        (DieStyle.luminance(style.red) - body).abs(),
        greaterThanOrEqualTo(0.30),
        reason: 'a red suit on ${colour.toRadixString(16)} must be readable',
      );
      expect(style.red, isNot(style.body), reason: 'and never the body itself');
    }
  });
}
