import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/card_screen.dart';
import 'package:rollhippo/app/chrome.dart';
import 'package:rollhippo/app/page_dots.dart';
import 'package:rollhippo/app/picker_screen.dart';
import 'package:rollhippo/app/profiles.dart';
import 'package:rollhippo/render/card_painter.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The card page's three shoes, tested the way `groups_test.dart` tests the
/// dice page's three sets — because they are the same feature on the other
/// page, and the point of it is that the two behave alike.

/// The dice one shoe's rack is showing, scoped to that shoe: a page view keeps
/// its neighbours built, so counting across the tree would pick up the cards
/// of a shoe you had swiped away from.
List<DieSpec> cardRackOf(WidgetTester tester, int shoe) => <DieSpec>[
  for (final DiePreview preview in tester.widgetList<DiePreview>(
    find.descendant(
      of: find.byKey(ValueKey<String>('shoe-$shoe')),
      matching: find.byType(DiePreview),
    ),
  ))
    preview.spec,
];

PageDots shoeDotsOf(WidgetTester tester) =>
    tester.widget<PageDots>(find.byKey(kShoeDots));

/// The table's own dots, which say which shoe you are looking at.
PageDots tableDotsOf(WidgetTester tester) =>
    tester.widget<PageDots>(find.byKey(kCardDots));

CardPagesPainter tablesOf(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (Widget w) => w is CustomPaint && w.painter is CardPagesPainter,
              ),
            )
            .painter!
        as CardPagesPainter;

/// Opens the picker on its card page — a drag on the *dice* panel, which is
/// the handle the two modes are dragged by.
/// Pumps a fixed number of frames. Never [WidgetTester.pumpAndSettle] once the
/// table is up: that screen holds a `Ticker` that runs whether or not anything
/// is moving, so settling waits for a frame that is never the last one.
Future<void> frames(WidgetTester tester, [int count = 30]) async {
  for (int i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

Future<void> openCards(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(kHarnessScreen);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
  await tester.drag(find.text('Dice - Set 1/1'), const Offset(-300, 0));
  await tester.pumpAndSettle();
}

/// Swipes the card rack one shoe to the left, and lets it land.
Future<void> swipeShoe(WidgetTester tester, double by) async {
  await tester.drag(find.byKey(kCardRack), Offset(by, 0));
  await tester.pumpAndSettle();
}

Finder addInShoe(int shoe) => find.descendant(
  of: find.byKey(ValueKey<String>('shoe-$shoe')),
  matching: find.byKey(kAddDie),
);

final Finder cardRemove = find.descendant(
  of: find.byKey(kCardPage),
  matching: find.text('Remove'),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('three shoes', () {
    testWidgets('start as one shoe and two nobody has started', (
      WidgetTester tester,
    ) async {
      await openCards(tester);

      expect(shoeDotsOf(tester).filled, <bool>[true, false, false]);
      expect(shoeDotsOf(tester).current, 0);
      expect(cardRackOf(tester, 0).length, 2);
      expect(cardRackOf(tester, 1), isEmpty);
    });

    testWidgets('a swipe on the card rack changes shoe, not mode', (
      WidgetTester tester,
    ) async {
      await openCards(tester);
      await swipeShoe(tester, -300);

      expect(shoeDotsOf(tester).current, 1);
      expect(
        tester.widget<PageDots>(find.byKey(kModeDots)).current,
        1,
        reason: 'still on the card page',
      );
    });

    testWidgets('the first shoe keeps a die and the others need not', (
      WidgetTester tester,
    ) async {
      await openCards(tester);
      // Down to one on the first shoe, and no further: a shoe with nothing
      // printed on its card is not a shoe.
      await tester.tap(cardRemove);
      await tester.pump();
      expect(cardRackOf(tester, 0).length, 1);
      await tester.tap(cardRemove);
      await tester.pump();
      expect(cardRackOf(tester, 0).length, 1);

      // The second starts empty, takes a die, and can go back to none.
      await swipeShoe(tester, -300);
      expect(cardRackOf(tester, 1), isEmpty);
      await tester.tap(addInShoe(1));
      await tester.pump();
      expect(cardRackOf(tester, 1).length, 1);
      expect(shoeDotsOf(tester).filled, <bool>[true, true, false]);
      await tester.tap(cardRemove);
      await tester.pump();
      expect(cardRackOf(tester, 1), isEmpty);
      expect(shoeDotsOf(tester).filled, <bool>[true, false, false]);
    });

    testWidgets('each shoe keeps its own decks and its own cut', (
      WidgetTester tester,
    ) async {
      await openCards(tester);
      // The first shoe opens on two decks; make the second one three.
      await swipeShoe(tester, -300);
      await tester.tap(addInShoe(1));
      await tester.pump();
      await tester.tap(
        find.descendant(of: find.byKey(kCardPage), matching: find.text('3')),
      );
      await tester.pump();

      await swipeShoe(tester, 300);
      // Two decks of two dice is seventy-two cards, and the heading counts the
      // shoes now that there is more than one of them.
      expect(
        find.descendant(
          of: find.byKey(kCardPage),
          matching: find.text('Shoe 1/2 · 72 cards'),
        ),
        findsOneWidget,
        reason: 'the first shoe kept its own two decks',
      );

      await swipeShoe(tester, -300);
      expect(
        find.descendant(
          of: find.byKey(kCardPage),
          matching: find.text('Shoe 2/2 · 18 cards'),
        ),
        findsOneWidget,
        reason: 'and the second one has three decks of a single die',
      );
    });

    testWidgets('a table is opened per shoe, and dealing from one leaves the '
        'others alone', (WidgetTester tester) async {
      await openCards(tester);
      await swipeShoe(tester, -300);
      await tester.tap(addInShoe(1));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deal'));
      await frames(tester);

      final CardPagesPainter tables = tablesOf(tester);
      expect(tables.tables.length, 2, reason: 'one table per started shoe');
      expect(
        tableDotsOf(tester).current,
        1,
        reason: 'you arrive on the shoe you were setting up',
      );

      final int before = tables.tables[0].deck.remaining;
      await tester.tap(find.text('Draw'));
      await frames(tester);

      expect(tables.tables[1].deck.dealt, isTrue);
      expect(
        tables.tables[0].deck.remaining,
        before,
        reason: 'the shoe next door has not been touched',
      );
      expect(tables.tables[0].deck.dealt, isFalse);
    });

    testWidgets('an empty shoe is not a table to swipe to', (
      WidgetTester tester,
    ) async {
      await openCards(tester);
      await tester.tap(find.text('Deal'));
      await frames(tester);

      expect(tablesOf(tester).tables.length, 1);
      expect(
        find.byKey(kCardDots),
        findsNothing,
        reason: 'one table has nothing to page between',
      );
    });
  });

  group('three shoes, kept', () {
    test('a profile carries all three, and their own numbers with them', () {
      const Profile profile = Profile(
        mode: ProfileMode.cards,
        groups: <List<DieSpec>>[kDefaultDice, <DieSpec>[], <DieSpec>[]],
        cards: <CardSet>[
          CardSet(colours: <int>[kDiceWhite], decks: 1, reshuffleAt: 0),
          CardSet(
            colours: <int>[kDiceWhite, kDiceWhite],
            decks: 3,
            reshuffleAt: 20,
          ),
          kEmptyShoe,
        ],
      );

      final Profile? back = profileFromJson(profileToJson(profile));
      expect(back, isNotNull);
      expect(back!.cards.length, 3);
      expect(back.cards[1].decks, 3);
      expect(back.cards[1].reshuffleAt, 20);
      expect(back.cards[2].isEmpty, isTrue);
      expect(back, profile, reason: 'the same profile, not two thirds of it');

      // And round the other way, through a QR code.
      final ScannedProfile? scanned = decodeProfile(
        encodeProfile(profile, name: 'Shoes'),
      );
      expect(scanned, isNotNull);
      expect(scanned!.name, 'Shoes');
      expect(scanned.profile, profile);
    });

    test('a code from before there were shoes still opens, as one shoe', () {
      // An `RH2:` code, built here byte by byte because nothing writes them
      // any more: the mode, then the two numbers the one shoe was made of and
      // its dice as palette indices — which is the header this app wrote until
      // there were three shoes — then one set of one D6, then an empty name.
      final String code =
          kProfileCodeV2Prefix +
          base64Url.encode(<int>[
            ProfileMode.cards.index,
            2, // decks
            5, // cut
            1, // one die on the card
            0, // ivory, the first of the palette
            1, // one set of dice
            1, // with one die in it
            DieKind.d6.index << 4, // a D6, ivory
            0, // no name
          ]);
      final ScannedProfile? back = decodeProfile(code);
      expect(back, isNotNull, reason: 'an older code is still one of ours');
      expect(back!.profile.mode, ProfileMode.cards);
      expect(back.profile.cards.length, kMaxCardSets);
      expect(back.profile.cards.first.decks, 2);
      expect(back.profile.cards.first.reshuffleAt, 5);
      expect(back.profile.cards.first.colours, <int>[kDiceWhite]);
      expect(
        back.profile.cards[1].isEmpty,
        isTrue,
        reason: 'the two it has no room for arrive unstarted',
      );
    });
  });
}
