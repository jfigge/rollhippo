import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/card_screen.dart';
import 'package:rollhippo/app/chrome.dart';
import 'package:rollhippo/app/config_screen.dart';
import 'package:rollhippo/app/page_dots.dart';
import 'package:rollhippo/cards/deck.dart';
import 'package:rollhippo/render/card_painter.dart';
import 'package:rollhippo/render/die_preview.dart';

/// The dice showing in one mode's rack.
int rackOf(WidgetTester tester, Key page) =>
    find
        .descendant(of: find.byKey(page), matching: find.byType(DiePreview))
        .evaluate()
        .length;

PageDots dotsOf(WidgetTester tester, Key key) =>
    tester.widget<PageDots>(find.byKey(key));

/// Drags the panel — the one thing on the picker that switches modes.
Future<void> swipePanel(WidgetTester tester, Finder onPanel, double dx) async {
  await tester.drag(onPanel, Offset(dx, 0));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The table the card screen is painting, read back out of its painter.
CardTable tableOf(WidgetTester tester) =>
    (tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (Widget w) => w is CustomPaint && w.painter is CardPainter,
                  ),
                )
                .painter!
            as CardPainter)
        .table;

void main() {
  group('a deck of rolls', () {
    test('is every ordered outcome, once per deck', () {
      expect(Deck.build(1, 1).length, 6);
      expect(Deck.build(2, 1).length, 36);
      expect(Deck.build(3, 1).length, 216);
      expect(Deck.build(2, 3).length, 108);

      // Ordered, not combined: 1-2 and 2-1 are two ways for a pair of dice to
      // land and the deck has to hold both, or snake eyes gets rarer than it
      // is by the act of dealing it.
      final Set<String> seen = <String>{
        for (final PlayingCard card in Deck.build(2, 1)) card.toString(),
      };
      expect(seen.length, 36);
      expect(seen.contains('1-2'), isTrue);
      expect(seen.contains('2-1'), isTrue);

      // And every face is a real one.
      for (final PlayingCard card in Deck.build(3, 1)) {
        expect(card.faces.length, 3);
        for (final int face in card.faces) {
          expect(face, inInclusiveRange(1, 6));
        }
      }
    });

    test('twice over is every outcome exactly twice', () {
      final Map<String, int> counts = <String, int>{};
      for (final PlayingCard card in Deck.build(2, 2)) {
        counts[card.toString()] = (counts[card.toString()] ?? 0) + 1;
      }
      expect(counts.length, 36);
      expect(counts.values.every((int n) => n == 2), isTrue);
    });

    test('starts full, face down, with nothing on the glass', () {
      final Deck deck = Deck(
        dice: 2,
        decks: 2,
        reshuffleAt: 5,
        random: math.Random(1),
      );
      expect(deck.size, 72);
      expect(deck.remaining, 72);
      expect(deck.shown, isNull);
    });

    test('is shuffled, not dealt in the order it was built', () {
      final List<String> built = <String>[
        for (final PlayingCard card in Deck.build(2, 1)) card.toString(),
      ];
      final Deck deck = Deck(
        dice: 2,
        decks: 1,
        reshuffleAt: 0,
        random: math.Random(9),
      );
      final List<String> dealt = <String>[];
      while (!deck.spent) {
        deck.draw();
        dealt.add(deck.shown.toString());
      }
      expect(dealt.length, 36);
      expect(dealt, isNot(built));
      expect(dealt.toSet(), built.toSet(), reason: 'a card went missing');
    });

    test('deals one card off the top at a time', () {
      final Deck deck = Deck(
        dice: 2,
        decks: 1,
        reshuffleAt: 0,
        random: math.Random(2),
      );
      deck.draw();
      expect(deck.remaining, 35);
      final PlayingCard first = deck.shown!;

      deck.draw();
      expect(deck.remaining, 34);
      expect(deck.shown, isNot(same(first)));
    });

    test('cuts where it was told to', () {
      // 20% of 72 is 14.4, and you cannot cut a card in half.
      expect(
        Deck(dice: 2, decks: 2, reshuffleAt: 20, random: math.Random(1)).cut,
        14,
      );
      expect(
        Deck(dice: 2, decks: 2, reshuffleAt: 5, random: math.Random(1)).cut,
        3,
      );
      expect(
        Deck(dice: 2, decks: 2, reshuffleAt: 0, random: math.Random(1)).cut,
        0,
      );
    });

    test('reshuffles at the cut, and comes back full and face down', () {
      final Deck deck = Deck(
        dice: 2,
        decks: 1,
        reshuffleAt: 20,
        random: math.Random(5),
      );
      expect(deck.cut, 7);

      while (!deck.spent) {
        deck.draw();
      }
      expect(deck.remaining, 7, reason: 'it dealt past its own cut');
      expect(deck.shown, isNotNull);

      // The next ask is the reshuffle itself, and what you get for it is the
      // position the shoe started in.
      deck.draw();
      expect(deck.remaining, 36);
      expect(deck.shown, isNull, reason: 'the glass should have been cleared');

      // And then it deals again.
      deck.draw();
      expect(deck.remaining, 35);
      expect(deck.shown, isNotNull);
    });

    test('at nought per cent it runs to the very last card', () {
      final Deck deck = Deck(
        dice: 1,
        decks: 1,
        reshuffleAt: 0,
        random: math.Random(3),
      );
      for (int i = 0; i < 6; i++) {
        deck.draw();
        expect(deck.shown, isNotNull);
      }
      expect(deck.remaining, 0);

      deck.draw();
      expect(deck.remaining, 6);
      expect(deck.shown, isNull);
    });
  });

  group('the picker in two modes', () {
    testWidgets('starts on dice, with both modes there to swipe to', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));

      expect(dotsOf(tester, kModeDots).current, 0);
      expect(dotsOf(tester, kModeDots).filled, <bool>[true, true]);
      expect(rackOf(tester, kDicePage), kDefaultDice.length);
      expect(find.text('Cards'), findsOneWidget, reason: 'card mode is built');
    });

    testWidgets('a swipe on the panel changes mode', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await swipePanel(tester, find.text('Die 1 — D6'), -300);

      expect(dotsOf(tester, kModeDots).current, 1);
      // Two dice by default, and only three places for them.
      expect(rackOf(tester, kCardPage), 2);
      expect(find.text('2 / $kMaxCardDice'), findsOneWidget);
      // Thirty-six outcomes of two dice, and two decks of them by default.
      expect(find.text('(72 in the shoe)'), findsOneWidget);

      await swipePanel(tester, find.text('Cards'), 300);
      expect(dotsOf(tester, kModeDots).current, 0);
    });

    testWidgets('a swipe on the rack changes set, not mode', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(dotsOf(tester, kGroupDots).current, 1);
      expect(dotsOf(tester, kModeDots).current, 0, reason: 'the mode moved');
    });

    testWidgets('card mode counts dice between one and three', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await swipePanel(tester, find.text('Die 1 — D6'), -300);

      await tester.tap(find.text('Add a die'));
      await tester.pump();
      expect(rackOf(tester, kCardPage), 3);
      expect(find.text('(432 in the shoe)'), findsOneWidget);

      // And it stops there, however many times it is asked.
      await tester.tap(find.text('Add a die'));
      await tester.pump();
      expect(rackOf(tester, kCardPage), kMaxCardDice);

      // Remove takes them off again, the same control dice mode uses.
      final Finder remove = find.descendant(
        of: find.byKey(kCardPage),
        matching: find.text('Remove'),
      );
      await tester.tap(remove);
      await tester.pump();
      await tester.tap(remove);
      await tester.pump();
      expect(rackOf(tester, kCardPage), 1);
      expect(find.text('(12 in the shoe)'), findsOneWidget);

      // And it stops at one: a shoe with no dice in it is not a shoe.
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.ancestor(
                of: remove,
                matching: find.byWidgetPredicate(
                  (Widget widget) => widget is ButtonStyleButton,
                ),
              ),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('the deck count is a choice of three', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await swipePanel(tester, find.text('Die 1 — D6'), -300);

      expect(find.text('(72 in the shoe)'), findsOneWidget);
      await tester.tap(find.text('3'));
      await tester.pump();
      expect(find.text('(108 in the shoe)'), findsOneWidget);
    });

    testWidgets('the big button shuffles rather than rolls', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      expect(find.text('Roll'), findsOneWidget);
      expect(find.text('Shuffle'), findsNothing);

      await swipePanel(tester, find.text('Die 1 — D6'), -300);
      expect(find.text('Roll'), findsNothing);

      await tester.tap(find.text('Shuffle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(CardScreen), findsOneWidget);
      expect(find.text('Draw'), findsOneWidget);
      expect(find.text('Throw'), findsNothing);
    });
  });

  group('the card table', () {
    final TargetPlatformVariant harness = TargetPlatformVariant.only(
      TargetPlatform.macOS,
    );

    Future<CardTable> open(
      WidgetTester tester, {
      int dice = 2,
      int decks = 1,
      int reshuffleAt = 0,
    }) async {
      await tester.binding.setSurfaceSize(kHarnessScreen);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: CardScreen(dice: dice, decks: decks, reshuffleAt: reshuffleAt),
        ),
      );
      await tester.pump();
      return tableOf(tester);
    }

    testWidgets('starts with a full pile and an empty glass', (
      WidgetTester tester,
    ) async {
      final CardTable table = await open(tester);
      expect(table.deck.remaining, 36);
      expect(table.deck.shown, isNull);
    }, variant: harness);

    testWidgets('Draw turns the top card over', (WidgetTester tester) async {
      final CardTable table = await open(tester);

      await tester.tap(find.text('Draw'));
      await tester.pump();
      expect(table.deck.shown, isNotNull);
      expect(table.deck.remaining, 35);
      expect(table.deck.shown!.faces.length, 2);

      // And it stays there until the next one is asked for.
      final PlayingCard first = table.deck.shown!;
      await tester.pump(const Duration(seconds: 2));
      expect(table.deck.shown, same(first));
    }, variant: harness);

    testWidgets('a shake deals one card, not a fistful', (
      WidgetTester tester,
    ) async {
      final CardTable table = await open(tester);

      // Space is the harness's shake, and it runs for the better part of a
      // second — every frame of which would be a card without the wait.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      for (int i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(table.deck.remaining, 35, reason: 'one shake, one card');
      expect(table.deck.shown, isNotNull);
    }, variant: harness);

    testWidgets('dealing out the shoe puts it back together', (
      WidgetTester tester,
    ) async {
      final CardTable table = await open(tester, dice: 1, reshuffleAt: 0);

      for (int i = 0; i < 6; i++) {
        await tester.tap(find.text('Draw'));
        await tester.pump();
      }
      expect(table.deck.remaining, 0);

      await tester.tap(find.text('Draw'));
      await tester.pump();
      expect(table.deck.remaining, 6);
      expect(table.deck.shown, isNull, reason: 'back to the starting position');
    }, variant: harness);
  });
}
