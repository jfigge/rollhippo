import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/card_screen.dart';
import 'package:rollhippo/app/chrome.dart';
import 'package:rollhippo/app/picker_screen.dart';
import 'package:rollhippo/app/page_dots.dart';
import 'package:rollhippo/cards/deck.dart';
import 'package:rollhippo/render/card_painter.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/tray/tray.dart';

/// Two of the palette, named so that a test reads as what it is doing.
const int green = 0xFF4A8A55;
const int violet = 0xFF7B5AA6;

/// The dice showing in one mode's rack.
List<DieSpec> specsOf(WidgetTester tester, Key page) => <DieSpec>[
  for (final DiePreview preview in tester.widgetList<DiePreview>(
    find.descendant(of: find.byKey(page), matching: find.byType(DiePreview)),
  ))
    preview.spec,
];

/// How many of them there are, and what colours they came out.
int rackOf(WidgetTester tester, Key page) => specsOf(tester, page).length;

List<int> coloursOf(WidgetTester tester, Key page) => <int>[
  for (final DieSpec spec in specsOf(tester, page)) spec.colour,
];

/// The dice in one mode's rack, which in card mode is where you say which die
/// the swatches are about.
Finder dieOf(Key page) =>
    find.descendant(of: find.byKey(page), matching: find.byType(DiePreview));

/// The palette swatch for one colour, in one mode's panel. Both modes have the
/// whole palette and both are built at once, so a swatch has to say which.
Finder swatchOf(Key page, int colour) => find.descendant(
  of: find.byKey(page),
  matching: find.byWidgetPredicate((Widget widget) {
    if (widget is! Container) return false;
    final Decoration? decoration = widget.decoration;
    return decoration is BoxDecoration &&
        decoration.shape == BoxShape.circle &&
        decoration.color == Color(colour);
  }),
);

PageDots dotsOf(WidgetTester tester, Key key) =>
    tester.widget<PageDots>(find.byKey(key));

/// The plus in one mode's rack — the empty slot that takes another die. Both
/// modes are built at once and both have one, so it has to say which.
Finder addOf(Key page) =>
    find.descendant(of: find.byKey(page), matching: find.byKey(kAddDie));

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

  group('a card being dealt', () {
    CardTable table({int dice = 2, int decks = 1, int reshuffleAt = 0}) =>
        CardTable(
          width: kHarnessScreen.width / Tuning.logicalPixelsPerMetre,
          height: kHarnessScreen.height / Tuning.logicalPixelsPerMetre,
          deck: Deck(
            dice: dice,
            decks: decks,
            reshuffleAt: reshuffleAt,
            random: math.Random(7),
          ),
        );

    /// Runs [seconds] of table time past it, in frame-sized steps that add up
    /// to exactly that — the deal is eased, so it is steepest in the middle
    /// and half a frame of overshoot there is a fifth of a radian of turn.
    void run(CardTable table, double seconds) {
      const int steps = 24;
      for (int i = 0; i < steps; i++) {
        table.advance(seconds / steps);
      }
    }

    test('is off the pile at once, and only then flies', () {
      final CardTable deal = table();
      deal.draw();

      // The card is dealt the instant it is asked for. Only the arrival is
      // animated, which is why interrupting it cannot cost a card.
      expect(deal.deck.remaining, 35);
      expect(deal.deck.shown, isNotNull);
      expect(deal.deal.flying, isTrue);
      expect(deal.deal.card, same(deal.deck.shown));
      expect(deal.deal.under, isNull, reason: 'the glass was empty');
      expect(deal.deal.travel, 0);

      run(deal, Tuning.dealDuration / 2);
      expect(deal.deal.travel, closeTo(0.5, 0.02), reason: 'eased both ends');
      expect(deal.deal.flying, isTrue);

      run(deal, Tuning.dealDuration / 2);
      expect(deal.deal.flying, isFalse);
      expect(deal.deck.shown, isNotNull, reason: 'and it is lying there now');
    });

    test('turns from its back to its face, and is over before it lands', () {
      final CardTable deal = table();
      deal.draw();
      expect(deal.deal.turn, 0, reason: 'face down, off the top of the pile');

      // Halfway through the turn's own clock is the card exactly edge on,
      // which is where the painter swaps one side of it for the other.
      run(deal, Tuning.dealDuration * Tuning.dealTurn / 2);
      expect(deal.deal.turn, closeTo(math.pi / 2, 0.05));
      expect(deal.deal.travel, lessThan(0.5), reason: 'still on its way');

      // And by the end of that clock it is face up, with the last fifth of the
      // journey left to lie down in.
      run(deal, Tuning.dealDuration * Tuning.dealTurn / 2);
      expect(deal.deal.turn, closeTo(math.pi, 0.02));
      expect(deal.deal.flying, isTrue, reason: 'over, but not landed');
    });

    test('a second ask lands the first card and deals onto it', () {
      final CardTable deal = table();
      deal.draw();
      final PlayingCard first = deal.deck.shown!;
      run(deal, Tuning.dealDuration / 3);

      deal.draw();
      expect(deal.deal.under, same(first), reason: 'it is covering that one');
      expect(deal.deal.card, same(deal.deck.shown));
      expect(deal.deal.travel, 0, reason: 'the new one starts at the pile');
      expect(deal.deck.remaining, 34, reason: 'and both were really dealt');
    });

    test('a reshuffle clears the air rather than dealing into it', () {
      final CardTable deal = table(dice: 1);
      for (int i = 0; i < 6; i++) {
        deal.draw();
      }
      expect(deal.deck.remaining, 0);

      deal.draw();
      expect(deal.deck.shown, isNull);
      expect(deal.deal.flying, isFalse, reason: 'there is no card to fly');
      expect(deal.deal.under, isNull, reason: 'and none left on the glass');
    });
  });

  group('the picker in two modes', () {
    testWidgets('starts on dice, with both modes there to swipe to', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));

      expect(dotsOf(tester, kModeDots).current, 0);
      expect(dotsOf(tester, kModeDots).filled, <bool>[true, true]);
      expect(rackOf(tester, kDicePage), kDefaultDice.length);
      expect(find.text('Cards'), findsOneWidget, reason: 'card mode is built');
    });

    testWidgets('a swipe on the panel changes mode', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
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
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(dotsOf(tester, kGroupDots).current, 1);
      expect(dotsOf(tester, kModeDots).current, 0, reason: 'the mode moved');
    });

    testWidgets('card mode counts dice between one and three', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await swipePanel(tester, find.text('Die 1 — D6'), -300);

      await tester.tap(addOf(kCardPage));
      await tester.pump();
      expect(rackOf(tester, kCardPage), 3);
      expect(find.text('(432 in the shoe)'), findsOneWidget);

      // And it stops there, because there is nothing left to ask with: three
      // is every slot the card has, so the plus has nowhere to be.
      expect(rackOf(tester, kCardPage), kMaxCardDice);
      expect(addOf(kCardPage), findsNothing);

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
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await swipePanel(tester, find.text('Die 1 — D6'), -300);

      expect(find.text('(72 in the shoe)'), findsOneWidget);
      await tester.tap(find.text('3'));
      await tester.pump();
      expect(find.text('(108 in the shoe)'), findsOneWidget);
    });

    testWidgets('a colour lands on the selected die and nowhere else', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await swipePanel(tester, find.text('Die 1 — D6'), -300);

      // DieSpec is compared field by field: it has no `==` of its own, and a
      // spec built fresh every build would never be the same instance twice.
      for (final DieSpec spec in specsOf(tester, kCardPage)) {
        expect(spec.kind, kCardDie.kind);
        expect(spec.colour, kCardDie.colour);
      }

      // The second die of the card, tapped exactly as the rack next door is.
      await tester.tap(dieOf(kCardPage).at(1));
      await tester.pump();
      await tester.tap(swatchOf(kCardPage, green));
      await tester.pump();
      expect(coloursOf(tester, kCardPage), <int>[kDiceWhite, green]);

      // And the dice next door are still the dice next door.
      expect(coloursOf(tester, kDicePage), everyElement(kDiceWhite));
    });

    testWidgets('a die takes its colour with it when it goes', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await swipePanel(tester, find.text('Die 1 — D6'), -300);

      await tester.tap(dieOf(kCardPage).at(1));
      await tester.pump();
      await tester.tap(swatchOf(kCardPage, green));
      await tester.pump();
      // A third, which arrives matching the one before it and selected.
      await tester.tap(addOf(kCardPage));
      await tester.pump();
      await tester.tap(swatchOf(kCardPage, violet));
      await tester.pump();
      expect(coloursOf(tester, kCardPage), <int>[kDiceWhite, green, violet]);

      // Now take the green one out. The violet die moves up a place rather
      // than handing its colour back to the slot it left.
      await tester.tap(dieOf(kCardPage).at(1));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byKey(kCardPage),
          matching: find.text('Remove'),
        ),
      );
      await tester.pump();
      expect(coloursOf(tester, kCardPage), <int>[kDiceWhite, violet]);
    });

    testWidgets('the colours chosen are the colours the cards are printed in', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await swipePanel(tester, find.text('Die 1 — D6'), -300);

      await tester.tap(swatchOf(kCardPage, violet));
      await tester.pump();
      await tester.tap(dieOf(kCardPage).at(1));
      await tester.pump();
      await tester.tap(swatchOf(kCardPage, green));
      await tester.pump();

      await tester.tap(find.text('Shuffle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final CardTable table = tableOf(tester);
      expect(table.colours, <int>[violet, green]);
      expect(table.colourOf(0), violet);
      expect(table.colourOf(1), green);
      // And a die nobody said anything about is ivory, which is how a table
      // built without any colours at all comes out.
      expect(table.colourOf(2), kDiceWhite);
    });

    testWidgets('the big button shuffles rather than rolls', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
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

    testWidgets('a drawn card flies out of the pile and lands', (
      WidgetTester tester,
    ) async {
      final CardTable table = await open(tester);

      await tester.tap(find.text('Draw'));
      await tester.pump();
      expect(table.deal.flying, isTrue);

      // A few frames in, on its way — the screen's own ticker is what carries
      // it, so this is also the test that the ticker is wired to the table.
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(table.deal.flying, isTrue);
      expect(table.deal.travel, greaterThan(0));

      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(table.deal.flying, isFalse);
      expect(table.deck.shown, isNotNull);
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
