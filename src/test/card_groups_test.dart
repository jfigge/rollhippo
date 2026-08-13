import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/card_screen.dart';
import 'package:rollhippo/app/chrome.dart';
import 'package:rollhippo/app/menu.dart';
import 'package:rollhippo/app/page_dots.dart';
import 'package:rollhippo/app/picker_screen.dart';
import 'package:rollhippo/app/profiles.dart';
import 'package:rollhippo/render/card_painter.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The card page's shoes, tested the way `groups_test.dart` tests the dice
/// page's sets — because they are the same feature on the other page, and the
/// point of it is that the two behave alike, growing a page at a time
/// included.

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

/// Remove, on a press that may put a question up and may animate a shoe out.
Future<void> tapCardRemove(WidgetTester tester) async {
  await tester.tap(cardRemove);
  await tester.pumpAndSettle();
}

/// Answers the question a shoe's last die gets.
Future<void> answerDrop(WidgetTester tester, String button) async {
  expect(find.byKey(kDropSetDialog), findsOneWidget);
  await tester.tap(
    find.descendant(
      of: find.byKey(kDropSetDialog),
      matching: find.text(button),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('the shoes', () {
    testWidgets('start as one shoe and one nobody has started', (
      WidgetTester tester,
    ) async {
      await openCards(tester);

      // The dice page's rule, on this page: what you are shown is the shoes
      // you have started and one empty one after them.
      expect(shoeDotsOf(tester).filled, <bool>[true, false]);
      expect(shoeDotsOf(tester).current, 0);
      expect(cardRackOf(tester, 0).length, 2);
      expect(cardRackOf(tester, 1), isEmpty);
    });

    testWidgets('grow a page at a time, and stop at kMaxCardSets', (
      WidgetTester tester,
    ) async {
      await openCards(tester);

      for (int shoe = 1; shoe < kMaxCardSets; shoe++) {
        expect(shoeDotsOf(tester).filled.length, shoe + 1);
        await swipeShoe(tester, -300);
        expect(shoeDotsOf(tester).current, shoe);
        await tester.tap(addInShoe(shoe));
        await tester.pump();
      }
      expect(shoeDotsOf(tester).filled, List<bool>.filled(kMaxCardSets, true));

      await swipeShoe(tester, -300);
      expect(shoeDotsOf(tester).current, kMaxCardSets - 1);
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

    testWidgets('the only shoe there is keeps a die', (
      WidgetTester tester,
    ) async {
      await openCards(tester);

      await tapCardRemove(tester);
      await tapCardRemove(tester);
      expect(cardRackOf(tester, 0).length, 1);
      expect(find.byKey(kDropSetDialog), findsNothing);
    });

    testWidgets('the last shoe in the row empties without being asked about', (
      WidgetTester tester,
    ) async {
      await openCards(tester);
      await swipeShoe(tester, -300);
      await tester.tap(addInShoe(1));
      await tester.pump();

      // Shoe two is where the row ends, so emptying it takes nothing away: it
      // goes back to being the empty page the rack finishes with.
      await tapCardRemove(tester);

      expect(find.byKey(kDropSetDialog), findsNothing);
      expect(cardRackOf(tester, 1), isEmpty);
      expect(shoeDotsOf(tester).filled, <bool>[true, false]);
      expect(shoeDotsOf(tester).current, 1);
    });

    testWidgets('any other shoe asks, and OK takes it away entirely', (
      WidgetTester tester,
    ) async {
      await openCards(tester);
      // Three shoes, the third with two dice on its card and three decks
      // behind it — enough that it is recognisable once it has moved.
      await swipeShoe(tester, -300);
      await tester.tap(addInShoe(1));
      await tester.pump();
      await swipeShoe(tester, -300);
      await tester.tap(addInShoe(2));
      await tester.pump();
      await tester.tap(addInShoe(2));
      await tester.pump();
      await tester.tap(
        find.descendant(of: find.byKey(kCardPage), matching: find.text('3')),
      );
      await tester.pump();

      // Back to the middle one, whose last die is now the whole shoe.
      await swipeShoe(tester, 300);
      await tapCardRemove(tester);
      await answerDrop(tester, 'Cancel');
      expect(cardRackOf(tester, 1).length, 1, reason: 'cancel moved nothing');

      await tapCardRemove(tester);
      await answerDrop(tester, 'Remove');

      // The third shoe has come forward a page — its dice, its decks and its
      // cut all still its own.
      expect(shoeDotsOf(tester).filled, <bool>[true, true, false]);
      expect(shoeDotsOf(tester).current, 1);
      expect(cardRackOf(tester, 1).length, 2);
      // Three decks of two dice is 108 cards, and it is the second of two.
      expect(
        find.descendant(
          of: find.byKey(kCardPage),
          matching: find.text('Shoe 2/2 · 108 cards'),
        ),
        findsOneWidget,
      );
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

    testWidgets('opening a profile puts you back on the first shoe', (
      WidgetTester tester,
    ) async {
      await openCards(tester);
      await swipeShoe(tester, -300);
      await tester.tap(addInShoe(1));
      await tester.pumpAndSettle();
      expect(shoeDotsOf(tester).current, 1);

      // A profile with one shoe, arriving while the rack is on the second.
      // The page it is sitting on is one the picker no longer offers, so the
      // controller has to be sent home along with the field that counts it.
      final AppMenuButton menu = tester.widget<AppMenuButton>(
        find.byType(AppMenuButton),
      );
      menu.onScanned(
        const ScannedProfile(
          name: '',
          profile: Profile(
            mode: ProfileMode.cards,
            groups: <List<DieSpec>>[kDefaultDice],
            cards: <CardSet>[
              CardSet(colours: <int>[kDiceWhite], decks: 1, reshuffleAt: 0),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(shoeDotsOf(tester).filled, <bool>[true, false]);
      expect(shoeDotsOf(tester).current, 0);
      expect(cardRackOf(tester, 0).length, 1);
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

  group('the shoes, kept', () {
    test('there are exactly as many of them as there are sets of dice', () {
      // The two pages of one picker. A build where these disagreed would be
      // two apps — see [kMaxCardSets], which says so and has nothing to hold
      // it to it but this.
      expect(kMaxCardSets, kMaxGroups);
    });

    test('a profile carries all of them, and their own numbers with them', () {
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
        reason: 'the ones it has no room for arrive unstarted',
      );
    });
  });
}
