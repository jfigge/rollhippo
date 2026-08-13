import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/chrome.dart';
import 'package:rollhippo/app/haptics.dart';
import 'package:rollhippo/app/menu.dart';
import 'package:rollhippo/app/page_dots.dart';
import 'package:rollhippo/app/picker_screen.dart';
import 'package:rollhippo/app/profile_row.dart';
import 'package:rollhippo/app/profiles.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A profile with [dice] six-sided dice in its first set and nothing in
/// the other two, which is the shape of nearly every save anybody makes.
Profile diceProfile(int dice, {int decks = 2, int cut = 5}) => Profile(
  mode: ProfileMode.dice,
  groups: <List<DieSpec>>[
    <DieSpec>[
      for (int i = 0; i < dice; i++)
        const DieSpec(kind: DieKind.d6, colour: kDiceWhite),
    ],
    <DieSpec>[],
    <DieSpec>[],
  ],
  cards: <CardSet>[
    CardSet(
      colours: <int>[kDiceWhite, kDiceWhite],
      decks: decks,
      reshuffleAt: cut,
    ),
    kEmptyShoe,
    kEmptyShoe,
  ],
);

/// The dice the rack is showing. The card page is built at the same time, one
/// screen to the side, and it has dice of its own in it.
List<DieSpec> rack(WidgetTester tester) => <DieSpec>[
  for (final DiePreview preview in tester.widgetList<DiePreview>(
    find.descendant(
      of: find.byKey(kDicePage),
      matching: find.byType(DiePreview),
    ),
  ))
    preview.spec,
];

/// One of the profiles under the picker, by name. Scoped, because a rename
/// dialog puts the same name into a text field over the top of it.
Finder profile(String name) =>
    find.descendant(of: find.byKey(kProfileRow), matching: find.text(name));

/// Which mode the picker is in, straight off the dots that say so.
int modeOf(WidgetTester tester) =>
    tester.widget<PageDots>(find.byKey(kModeDots)).current;

/// Over to one of the two modes, by tapping its dot — which is where a swipe
/// on the panel gets you, and a great deal easier to aim at from a test.
Future<void> goToMode(WidgetTester tester, int mode) async {
  await tester.tap(
    find
        .descendant(
          of: find.byKey(kModeDots),
          matching: find.byType(GestureDetector),
        )
        .at(mode),
  );
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// The picker, on a phone-shaped screen.
///
/// Not the 800 × 600 a widget test starts with. The picker is a phone screen —
/// the rack, the panel and the profiles are laid out against its height, and the
/// row of saves is given whatever is left between the mode dots and the Roll
/// button. On a window two thirds as tall as a phone there is barely any, and
/// every test here would be measuring that rather than what it came to look at.
Future<void> pumpPicker(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(kHarnessScreen);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
  await tester.pumpAndSettle();
}

/// Hands the picker a profile off somebody else's screen.
///
/// The scanner itself needs a camera, so what is driven here is the seam it
/// pops back through — which is where every decision about the name is made.
Future<void> scan(
  WidgetTester tester,
  Profile profile, {
  String name = '',
}) async {
  tester
      .widget<AppMenuButton>(find.byType(AppMenuButton))
      .onScanned(ScannedProfile(name: name, profile: profile));
  await tester.pumpAndSettle();
}

/// Adds one die to the first set, which is the quickest way to make the screen
/// differ from the save it came from.
Future<void> addDie(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey<int>(0)),
      matching: find.byKey(kAddDie),
    ),
  );
  await tester.pumpAndSettle();
}

/// Puts what is on screen into the profile called [name], the way a thumb would:
/// hold it down, and take the first thing the menu offers.
Future<void> saveProfile(WidgetTester tester, String name) async {
  await tester.longPress(profile(name));
  await tester.pumpAndSettle();
  await tapText(tester, 'Save');
}

/// Puts up the Share sheet for the profile called [name], the way a thumb
/// would: hold it down, and take Share off the menu.
Future<void> shareProfile(WidgetTester tester, String name) async {
  await tester.longPress(profile(name));
  await tester.pumpAndSettle();
  await tapText(tester, 'Share');
}

/// What is actually in the square the sheet is showing.
///
/// [ShareCodeView] is the only way to ask: `QrImageView` keeps the string it
/// was handed to itself.
ScannedProfile sharedCode(WidgetTester tester) =>
    decodeProfile(
      tester.widget<ShareCodeView>(find.byType(ShareCodeView)).code,
    )!;

/// Puts a recorder in front of the phone's actuator for one test, and hands it
/// back. The row's taps do not go through a [HapticEngine]; see [uiHaptic].
RecordedHaptics recordHaptics() {
  final RecordedHaptics driver = RecordedHaptics();
  debugUiHaptics = driver;
  addTearDown(() => debugUiHaptics = null);
  return driver;
}

/// Makes a save called [name] out of whatever is on screen, the way a thumb
/// would: the dashed profile, the dialog, the name, Create.
Future<void> createSave(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(kNewProfile));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), name);
  await tester.pumpAndSettle();
  await tapText(tester, 'Create');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // The store is one object for the whole app, so every test starts by
    // putting an empty preferences file behind it and reading that back —
    // which is also the only way to clear what the last test left in it.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await profiles.load();
  });

  group('a profile', () {
    test('goes out and comes back exactly as it was', () {
      final Profile profile = Profile(
        mode: ProfileMode.cards,
        groups: <List<DieSpec>>[
          <DieSpec>[
            const DieSpec(kind: DieKind.d20, colour: 0xFFB3453F),
            const DieSpec(kind: DieKind.d4, colour: 0xFF4A8A55),
          ],
          <DieSpec>[],
          <DieSpec>[const DieSpec(kind: DieKind.d8, colour: kDiceWhite)],
        ],
        cards: <CardSet>[
          CardSet(
            colours: <int>[0xFF3F6FA8, 0xFFD8B23A, kDiceWhite],
            decks: 3,
            reshuffleAt: 17,
          ),
          kEmptyShoe,
          kEmptyShoe,
        ],
      );

      final Profile back = profileFromJson(profileToJson(profile))!;

      expect(back.mode, ProfileMode.cards);
      expect(back.cards.first.decks, 3);
      expect(back.cards.first.reshuffleAt, 17);
      expect(back.cards, profile.cards);
      // The empty set in the middle survives: it is a set nobody started, not
      // a gap to be closed up.
      expect(back.groups.length, 3);
      expect(back.groups[1], isEmpty);
      expect(back.groups[0][0].kind, DieKind.d20);
      expect(back.groups[0][0].colour, 0xFFB3453F);
      expect(back.groups[2][0].kind, DieKind.d8);
    });

    test('is dropped rather than repaired when it cannot be read', () {
      expect(profileFromJson(null), isNull);
      expect(profileFromJson('RH1:AwIAAA=='), isNull);
      final Map<String, Object?> good = profileToJson(diceProfile(2));
      expect(
        profileFromJson(Map<String, Object?>.of(good)..remove('dice')),
        isNull,
        reason: 'without dice',
      );
      // The three single-shoe fields are a *fallback*, so taking `cards` away
      // is not damage: it is what every save written before there were three
      // shoes looks like, and it still opens — as one shoe, with two nobody
      // started. Taking one of the three away as well leaves nothing to fall
      // back to, and that is the save that gets dropped.
      final Map<String, Object?> old = Map<String, Object?>.of(good)
        ..remove('cards');
      final Profile? legacy = profileFromJson(old);
      expect(legacy, isNotNull, reason: 'a save from before there were shoes');
      expect(legacy!.cards.length, kMaxCardSets);
      expect(legacy.cards.first.colours, good['colours']);
      expect(legacy.cards[1].isEmpty, isTrue);
      for (final String key in <String>['colours', 'decks', 'cut']) {
        final Map<String, Object?> broken = Map<String, Object?>.of(old)
          ..remove(key);
        expect(profileFromJson(broken), isNull, reason: 'without $key');
      }
      // And a shoe list this build could not put on screen: the first shoe is
      // the one the picker will not let you empty.
      expect(
        profileFromJson(
          Map<String, Object?>.of(good)
            ..['cards'] = <Object?>[
              <String, Object?>{'colours': <int>[], 'decks': 1, 'cut': 0},
            ],
        ),
        isNull,
        reason: 'a first shoe with no card',
      );
      // A code that is not one of ours is not a profile either.
      expect(
        profileFromJson(Map<String, Object?>.of(good)..['dice'] = 'hello'),
        isNull,
      );
    });

    test('says what it comes to in as few words as are true', () {
      expect(diceProfile(5).summary, '5 dice');
      expect(diceProfile(1).summary, '1 die');

      final Profile sets = Profile(
        mode: ProfileMode.dice,
        groups: <List<DieSpec>>[
          <DieSpec>[for (int i = 0; i < 5; i++) kCardDie],
          <DieSpec>[for (int i = 0; i < 2; i++) kCardDie],
          <DieSpec>[],
        ],
        cards: <CardSet>[
          CardSet(colours: const <int>[kDiceWhite], decks: 1, reshuffleAt: 0),
          kEmptyShoe,
          kEmptyShoe,
        ],
      );
      expect(sets.summary, '2 sets, 7 dice');

      // Card mode counts the shoe, which is what it would deal from.
      expect(
        Profile(
          mode: ProfileMode.cards,
          groups: const <List<DieSpec>>[],
          cards: <CardSet>[
            CardSet(
              colours: const <int>[kDiceWhite, kDiceWhite],
              decks: 2,
              reshuffleAt: 5,
            ),
            kEmptyShoe,
            kEmptyShoe,
          ],
        ).summary,
        '2 decks, 72 cards',
      );
      expect(
        Profile(
          mode: ProfileMode.cards,
          groups: const <List<DieSpec>>[],
          cards: <CardSet>[
            CardSet(colours: const <int>[kDiceWhite], decks: 1, reshuffleAt: 5),
            kEmptyShoe,
            kEmptyShoe,
          ],
        ).summary,
        '1 deck, 6 cards',
      );
    });
  });

  group('the store', () {
    test('puts the newest save at the front', () {
      profiles.add('First', diceProfile(1));
      profiles.add('Second', diceProfile(2));
      expect(
        <String>[for (final SavedProfile s in profiles.saves) s.name],
        <String>['Second', 'First'],
      );
    });

    test('writes a changed profile back under the same name', () {
      final SavedProfile save = profiles.add('Yahtzee', diceProfile(5));
      profiles.write(save.id, diceProfile(6));

      expect(profiles.saves.single.name, 'Yahtzee');
      expect(profiles.saves.single.id, save.id);
      expect(profiles.saves.single.profile.groups[0].length, 6);
    });

    test('writes nothing for a save that is no longer there', () {
      final SavedProfile save = profiles.add('Yahtzee', diceProfile(5));
      profiles.remove(save.id);
      profiles.write(save.id, diceProfile(6));
      expect(profiles.saves, isEmpty);
    });

    test('renames, deletes and marks as used', () {
      final SavedProfile save = profiles.add('Yahtzee', diceProfile(5));
      final DateTime made = save.usedAt;

      profiles.rename(save.id, 'D&D');
      expect(profiles.byId(save.id)!.name, 'D&D');
      expect(profiles.byId(save.id)!.profile.groups[0].length, 5);

      profiles.touch(save.id);
      expect(
        profiles.byId(save.id)!.usedAt.isBefore(made),
        isFalse,
        reason: 'opening a save moves it forwards, not back',
      );

      profiles.remove(save.id);
      expect(profiles.byId(save.id), isNull);
      expect(profiles.isEmpty, isTrue);
    });

    test('is still there after the app has been put down', () async {
      profiles.add('Yahtzee', diceProfile(5));
      profiles.add(
        'Cards',
        Profile(
          mode: ProfileMode.cards,
          groups: const <List<DieSpec>>[],
          cards: <CardSet>[
            CardSet(
              colours: const <int>[0xFFB3453F],
              decks: 3,
              reshuffleAt: 12,
            ),
            kEmptyShoe,
            kEmptyShoe,
          ],
        ),
      );
      await pumpEventQueue();

      // Which is all a fresh launch does.
      await profiles.load();

      expect(profiles.saves.length, 2);
      expect(profiles.saves[0].name, 'Cards');
      expect(profiles.saves[0].profile.mode, ProfileMode.cards);
      expect(profiles.saves[0].profile.cards.first.decks, 3);
      expect(profiles.saves[0].profile.cards.first.reshuffleAt, 12);
      expect(profiles.saves[0].profile.cards.first.colours, <int>[0xFFB3453F]);
      expect(profiles.saves[1].name, 'Yahtzee');
      expect(profiles.saves[1].profile.groups[0].length, 5);
    });

    test('drops a save it cannot read and keeps the rest', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'configs.saved':
            '[{"id":1,"name":"Fine","used":0,'
            '"config":{"mode":"dice","dice":"RH1:AwIQEAAA","colours":[1],'
            '"decks":1,"cut":0}},'
            '{"id":2,"name":"Broken","used":0,"config":{"mode":"dice"}}]',
      });
      await profiles.load();
      expect(
        <String>[for (final SavedProfile s in profiles.saves) s.name],
        <String>['Fine'],
      );
    });

    test(
      'a preferences file full of nonsense costs the saves and no more',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'configs.saved': 'not json at all',
        });
        await profiles.load();
        expect(profiles.isEmpty, isTrue);
      },
    );
  });

  group('the profiles', () {
    testWidgets('are just the one, until something is saved', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      expect(find.byKey(kNewProfile), findsOneWidget);
      expect(find.text('+ New'), findsOneWidget);
    });

    testWidgets('keep what is on screen, under a name', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await addDie(tester);
      await tester.tap(find.byKey(kNewProfile));
      await tester.pumpAndSettle();

      expect(find.text('New profile'), findsOneWidget);
      // Nothing to create until there is something to call it.
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'))
            .onPressed,
        isNull,
      );

      await tester.enterText(find.byType(TextField), 'Yahtzee');
      await tester.pumpAndSettle();
      await tapText(tester, 'Create');

      expect(profile('Yahtzee'), findsOneWidget);
      expect(profiles.saves.single.name, 'Yahtzee');
      // The die that was added on the way here went in with it: what is kept is
      // the screen, and the screen is not left behind either.
      expect(
        profiles.saves.single.profile.groups[0].length,
        kDefaultDice.length + 1,
      );
      expect(rack(tester).length, kDefaultDice.length + 1);
    });

    testWidgets('cancelling keeps nothing', (WidgetTester tester) async {
      await pumpPicker(tester);
      await tester.tap(find.byKey(kNewProfile));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Yahtzee');
      await tapText(tester, 'Cancel');

      expect(profiles.isEmpty, isTrue);
      expect(profile('Yahtzee'), findsNothing);
    });

    testWidgets('start again, from the menu the dashed one gives you', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      // A save made of three dice, and then a screen taken further away from
      // the defaults still — in the other mode, so that both halves of the
      // picker have something to put back.
      await addDie(tester);
      await createSave(tester, 'Yahtzee');
      await goToMode(tester, 1);
      await tester.tap(
        find.descendant(of: find.byKey(kCardPage), matching: find.text('3')),
      );
      await tester.pumpAndSettle();
      expect(find.text('(108 in the shoe)'), findsOneWidget);

      await tester.longPress(find.byKey(kNewProfile));
      await tester.pumpAndSettle();

      // Two things to do to a profile that does not exist yet, and Reset is
      // the one that belongs only here — so it goes first. Save, Rename and
      // Delete all need a save, and there is no save here to do them to.
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Reset')).dy,
        lessThan(tester.getTopLeft(find.text('Share')).dy),
      );
      expect(find.text('Save'), findsNothing);
      expect(find.text('Rename'), findsNothing);
      expect(find.text('Delete'), findsNothing);

      await tapText(tester, 'Reset');

      // Back to what the app opens at, both modes and the page it starts on.
      expect(modeOf(tester), 0);
      expect(rack(tester).length, kDefaultDice.length);
      await goToMode(tester, 1);
      expect(find.text('(72 in the shoe)'), findsOneWidget);
      expect(find.text('<5%'), findsOneWidget);

      // The save it was made from is untouched, and nothing is lit any more:
      // what is on screen has come from no profile, which is what a first run
      // looks like too.
      expect(
        profiles.saves.single.profile.groups[0].length,
        kDefaultDice.length + 1,
      );
      expect(find.text('Roll Hippo'), findsOneWidget);
      expect(find.text('Roll Hippo - Yahtzee'), findsNothing);
    });

    testWidgets('and leave the row alone if you think better of it', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await addDie(tester);

      await tester.longPress(find.byKey(kNewProfile));
      await tester.pumpAndSettle();
      // Out through the barrier, which is the way out of any of these menus.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text('Reset'), findsNothing);
      expect(rack(tester).length, kDefaultDice.length + 1);
      expect(profiles.isEmpty, isTrue);
    });

    testWidgets('wrap rather than run off the side', (
      WidgetTester tester,
    ) async {
      for (int i = 0; i < 6; i++) {
        profiles.add('Game ${i + 1}', diceProfile(2));
      }
      await pumpPicker(tester);

      final Set<double> rows = <double>{};
      for (final SavedProfile save in profiles.saves) {
        final Rect box = tester.getRect(profile(save.name));
        expect(
          box.left,
          greaterThanOrEqualTo(0),
          reason: '${save.name} has run off the left',
        );
        expect(
          box.right,
          lessThanOrEqualTo(kHarnessScreen.width),
          reason: '${save.name} has run off the right',
        );
        rows.add(box.top);
      }
      expect(rows.length, greaterThan(1), reason: 'they never wrapped');
    });

    testWidgets('scroll rather than push the Roll button off the bottom', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      final double button = tester.getTopLeft(find.text('Roll')).dy;

      // Far more than anybody would keep, which is the point: the block has
      // to stop growing somewhere, and where it stops is the button.
      for (int i = 0; i < 40; i++) {
        profiles.add('Game ${i + 1}', diceProfile(2));
      }
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Roll')).dy,
        button,
        reason: 'the profiles pushed the button down the screen',
      );
      final ScrollableState scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(kProfileRow),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        scroll.position.maxScrollExtent,
        greaterThan(0),
        reason: 'they filled the space without becoming scrollable',
      );
      // And the bottom of the block is still above the button.
      expect(
        tester.getRect(find.byKey(kProfileRow)).bottom,
        lessThanOrEqualTo(button),
      );
    });

    testWidgets('take a name of no more than the limit', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await tester.tap(find.byKey(kNewProfile));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).maxLength,
        kMaxProfileName,
      );
    });

    testWidgets('do not follow the screen until they are told to', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await createSave(tester, 'Yahtzee');

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<int>(0)),
          matching: find.byKey(kAddDie),
        ),
      );
      await tester.pumpAndSettle();

      // The die is on the rack and nowhere else. A save is a photograph, and
      // this one was taken before the die arrived.
      expect(rack(tester).length, kDefaultDice.length + 1);
      expect(
        profiles.saves.single.profile.groups[0].length,
        kDefaultDice.length,
      );

      await saveProfile(tester, 'Yahtzee');

      expect(
        profiles.saves.single.profile.groups[0].length,
        kDefaultDice.length + 1,
      );
      // And it stays put across a reload, which is the whole point of asking.
      await profiles.load();
      expect(
        profiles.saves.single.profile.groups[0].length,
        kDefaultDice.length + 1,
      );
    });

    testWidgets('take what is on screen onto whichever one is held down', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await createSave(tester, 'Yahtzee');
      await createSave(tester, 'D&D');

      // Open the first one, change it, and put the change on the other.
      await tester.tap(profile('Yahtzee'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<int>(0)),
          matching: find.byKey(kAddDie),
        ),
      );
      await tester.pumpAndSettle();
      await saveProfile(tester, 'D&D');

      expect(find.text('Saved to "D&D".'), findsOneWidget);
      expect(
        profiles.saves
            .firstWhere((SavedProfile save) => save.name == 'D&D')
            .profile
            .groups[0]
            .length,
        kDefaultDice.length + 1,
      );

      // Yahtzee, which was open a moment ago, is untouched.
      expect(
        profiles.saves
            .firstWhere((SavedProfile s) => s.name == 'Yahtzee')
            .profile
            .groups[0]
            .length,
        kDefaultDice.length,
      );
    });

    testWidgets('keep both modes, whichever one you are looking at', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      // Over to cards, and change something only that mode has.
      await tester.tap(
        find
            .descendant(
              of: find.byKey(kModeDots),
              matching: find.byType(GestureDetector),
            )
            .at(1),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byKey(kCardPage), matching: find.text('3')),
      );
      await tester.pumpAndSettle();
      await createSave(tester, 'Poker Night');

      final Profile kept = profiles.saves.single.profile;
      expect(kept.mode, ProfileMode.cards);
      expect(kept.cards.first.decks, 3);
      // And the dice behind it went along too, untouched.
      expect(kept.groups[0].length, kDefaultDice.length);
    });

    testWidgets('open one, and it replaces what was there', (
      WidgetTester tester,
    ) async {
      profiles.add(
        'Twenty',
        Profile(
          mode: ProfileMode.dice,
          groups: <List<DieSpec>>[
            <DieSpec>[const DieSpec(kind: DieKind.d20, colour: 0xFFB3453F)],
            <DieSpec>[],
            <DieSpec>[],
          ],
          cards: <CardSet>[
            CardSet(colours: const <int>[kDiceWhite], decks: 1, reshuffleAt: 0),
            kEmptyShoe,
            kEmptyShoe,
          ],
        ),
      );
      await pumpPicker(tester);

      // A save exists and none of it is on screen: the launch is the picker,
      // at its defaults, with the row underneath offering that save.
      expect(rack(tester).length, kDefaultDice.length);

      await tester.tap(profile('Twenty'));
      await tester.pumpAndSettle();

      expect(rack(tester).length, 1);
      expect(rack(tester).single.kind, DieKind.d20);
      expect(rack(tester).single.colour, 0xFFB3453F);
    });

    testWidgets('come back to the mode they were made in', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      await goToMode(tester, 1);
      await createSave(tester, 'Poker');
      expect(profiles.saves.single.profile.mode, ProfileMode.cards);

      // Going to look at the dice is not a change to the save — nothing is,
      // until Save. The mode is the page it was saved on.
      await goToMode(tester, 0);
      expect(profiles.saves.single.profile.mode, ProfileMode.cards);

      await tester.tap(profile('Poker'));
      await tester.pumpAndSettle();
      expect(modeOf(tester), 1);
      expect(find.text('Deal'), findsOneWidget);
    });

    testWidgets('a dice save opened from card mode lands on the dice', (
      WidgetTester tester,
    ) async {
      profiles.add('Yahtzee', diceProfile(5));
      await pumpPicker(tester);

      await goToMode(tester, 1);
      expect(modeOf(tester), 1);

      await tester.tap(profile('Yahtzee'));
      await tester.pumpAndSettle();

      expect(modeOf(tester), 0);
      expect(find.text('Roll'), findsOneWidget);
      expect(rack(tester).length, 5);
    });

    testWidgets('put the open profile in the title', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      expect(find.text('Roll Hippo'), findsOneWidget);

      await createSave(tester, 'Yahtzee');
      expect(find.text('Roll Hippo - Yahtzee'), findsOneWidget);
      expect(find.text('Roll Hippo'), findsNothing);

      // A rename is a rename of the thing you are in, so it lands up here too.
      await tester.longPress(profile('Yahtzee'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Rename');
      await tester.enterText(find.byType(TextField), 'D&D');
      await tester.pumpAndSettle();
      await tapText(tester, 'Update');
      expect(find.text('Roll Hippo - D&D'), findsOneWidget);

      // Deleting it leaves the dice where they are and the plain title back.
      await tester.longPress(profile('D&D'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Delete');
      await tapText(tester, 'Delete');
      expect(find.text('Roll Hippo'), findsOneWidget);
    });

    testWidgets('title one that was opened rather than made', (
      WidgetTester tester,
    ) async {
      // Straight into the store rather than through the naming dialog, so
      // that nothing has opened it: a save you have not touched is not the
      // profile you are in, and the title has to say the plain thing until
      // you tap it.
      profiles.add('Yahtzee', diceProfile(5));
      await pumpPicker(tester);
      expect(find.text('Roll Hippo'), findsOneWidget);
      expect(find.text('Roll Hippo - Yahtzee'), findsNothing);

      await tester.tap(profile('Yahtzee'));
      await tester.pumpAndSettle();
      expect(find.text('Roll Hippo - Yahtzee'), findsOneWidget);
    });

    testWidgets('a long press asks what else you meant', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await createSave(tester, 'Yahtzee');

      await tester.longPress(profile('Yahtzee'));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      // Save first: it is the only way anything is ever written. Delete last:
      // it is the only one that cannot be undone by doing it again, and Share
      // — which touches nothing at all — has no business below it.
      double top(String label) => tester.getTopLeft(find.text(label)).dy;
      expect(top('Save'), lessThan(top('Rename')));
      expect(top('Rename'), lessThan(top('Share')));
      expect(top('Share'), lessThan(top('Delete')));

      await tapText(tester, 'Rename');
      expect(find.text('Rename profile'), findsOneWidget);
      // The same dialog, with the other word on it.
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Create'), findsNothing);

      await tester.enterText(find.byType(TextField), 'D&D');
      await tester.pumpAndSettle();
      await tapText(tester, 'Update');

      expect(profile('D&D'), findsOneWidget);
      expect(profile('Yahtzee'), findsNothing);
      // Renaming is about the name and nothing else.
      expect(
        profiles.saves.single.profile.groups[0].length,
        kDefaultDice.length,
      );
    });

    testWidgets('answer a tap and a hold in the hand as well', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await createSave(tester, 'Yahtzee');
      final RecordedHaptics taps = recordHaptics();

      // Opening one replaces everything above it, so it says so.
      await tester.tap(profile('Yahtzee'));
      await tester.pumpAndSettle();
      expect(taps.fired, <HapticLevel>[HapticLevel.light]);

      // The hold is the firmer tap, and on this row it is the only sign the
      // press was long enough — there is no moment of contact to feel.
      taps.clear();
      await tester.longPress(profile('Yahtzee'));
      await tester.pumpAndSettle();
      expect(taps.fired, <HapticLevel>[HapticLevel.medium]);

      // A menu tapped away from rather than chosen out of confirms nothing.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(taps.fired, <HapticLevel>[HapticLevel.medium]);

      taps.clear();
      await tester.longPress(profile('Yahtzee'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Save');
      expect(taps.fired, <HapticLevel>[HapticLevel.medium, HapticLevel.light]);
    });

    testWidgets('and so does the dashed one, which is one of them', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      final RecordedHaptics taps = recordHaptics();

      // A tap on it is the naming dialog rather than a save being opened, and
      // it is still a chip in the row being pressed.
      await tester.tap(find.byKey(kNewProfile));
      await tester.pumpAndSettle();
      expect(taps.fired, <HapticLevel>[HapticLevel.light]);
      await tapText(tester, 'Cancel');

      taps.clear();
      await tester.longPress(find.byKey(kNewProfile));
      await tester.pumpAndSettle();
      await tapText(tester, 'Reset');
      expect(taps.fired, <HapticLevel>[HapticLevel.medium, HapticLevel.light]);
    });

    testWidgets('deleting is asked about first, and can be called off', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await createSave(tester, 'Yahtzee');

      await tester.longPress(profile('Yahtzee'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Delete');
      expect(find.text('Delete "Yahtzee"?'), findsOneWidget);

      await tapText(tester, 'Cancel');
      expect(profile('Yahtzee'), findsOneWidget);

      await tester.longPress(profile('Yahtzee'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Delete');
      await tapText(tester, 'Delete');

      expect(profile('Yahtzee'), findsNothing);
      expect(profiles.isEmpty, isTrue);
      // What was on screen is still on screen — deleting a save is a statement
      // about the row of profiles, not about the dice.
      expect(rack(tester).length, kDefaultDice.length);
    });

    testWidgets('open one the app has been put down and picked up on', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await goToMode(tester, 1);
      await tester.tap(
        find.descendant(of: find.byKey(kCardPage), matching: find.text('3')),
      );
      await tester.pumpAndSettle();
      await createSave(tester, 'Catan');

      // Put the app down, and read the file back the way `main` does.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      await profiles.load();
      expect(profiles.saves.single.profile.mode, ProfileMode.cards);

      await pumpPicker(tester);
      await tester.tap(profile('Catan'));
      await tester.pumpAndSettle();

      expect(modeOf(tester), 1);
      expect(find.text('Deal'), findsOneWidget);
      expect(find.text('(108 in the shoe)'), findsOneWidget);
    });
  });

  group('a scanned code', () {
    testWidgets('with no name on it changes the screen and keeps nothing', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      await scan(tester, diceProfile(4));

      expect(rack(tester).length, 4);
      expect(
        profiles.isEmpty,
        isTrue,
        reason: 'nothing was named, so nothing is kept',
      );
      expect(find.text('Roll Hippo'), findsOneWidget);
      expect(find.text('Set up from a shared code.'), findsOneWidget);
    });

    testWidgets('carries the mode, and the shoe with it', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      await scan(
        tester,
        Profile(
          mode: ProfileMode.cards,
          groups: <List<DieSpec>>[
            <DieSpec>[kCardDie],
            <DieSpec>[],
            <DieSpec>[],
          ],
          cards: <CardSet>[
            CardSet(
              colours: const <int>[kDiceWhite, 0xFFB3453F],
              decks: 3,
              reshuffleAt: 12,
            ),
            kEmptyShoe,
            kEmptyShoe,
          ],
        ),
      );

      expect(modeOf(tester), 1, reason: 'a card code opens on the card page');
      expect(find.text('Deal'), findsOneWidget);
      expect(find.text('(108 in the shoe)'), findsOneWidget);
      expect(find.text('<12%'), findsOneWidget);
      expect(find.text('2 / $kMaxCardDice'), findsOneWidget);
    });

    testWidgets('you already have, to the die, opens without a word', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await createSave(tester, 'Yahtzee');
      final Profile kept = profiles.saves.single.profile;
      // Something on screen that is not what was saved, so that opening it is
      // a change you can see.
      await addDie(tester);
      expect(rack(tester).length, kDefaultDice.length + 1);

      await scan(tester, kept, name: 'Yahtzee');

      expect(find.text('Save "Yahtzee"?'), findsNothing);
      expect(find.text('Replace "Yahtzee"?'), findsNothing);
      expect(rack(tester).length, kDefaultDice.length);
      expect(find.text('Roll Hippo - Yahtzee'), findsOneWidget);
    });

    testWidgets('you already have but is different asks, and Load keeps yours', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await createSave(tester, 'Yahtzee');

      await scan(tester, diceProfile(5), name: 'Yahtzee');
      expect(find.text('Replace "Yahtzee"?'), findsOneWidget);

      await tapText(tester, 'Load');

      expect(rack(tester).length, 5, reason: 'the scanned one is on screen');
      expect(
        profiles.saves.single.profile.groups[0].length,
        kDefaultDice.length,
        reason: 'and the save it is not is untouched',
      );
      // It is nobody's save, so nothing is lit and the title is the plain one.
      expect(find.text('Roll Hippo'), findsOneWidget);
      expect(find.text('Set up from "Yahtzee".'), findsOneWidget);
    });

    testWidgets('replaces the one you have when you say so', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await createSave(tester, 'Yahtzee');

      await scan(tester, diceProfile(5), name: 'Yahtzee');
      await tapText(tester, 'Replace');

      expect(rack(tester).length, 5);
      expect(profiles.saves.length, 1, reason: 'replaced, not added beside');
      expect(profiles.saves.single.profile.groups[0].length, 5);
      expect(find.text('Roll Hippo - Yahtzee'), findsOneWidget);
      // And it is on the file, not just in the row.
      await profiles.load();
      expect(profiles.saves.single.profile.groups[0].length, 5);
    });

    testWidgets('cancelled, leaves the screen and the save alone', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await createSave(tester, 'Yahtzee');

      await scan(tester, diceProfile(5), name: 'Yahtzee');
      await tapText(tester, 'Cancel');

      expect(rack(tester).length, kDefaultDice.length);
      expect(
        profiles.saves.single.profile.groups[0].length,
        kDefaultDice.length,
      );
      expect(find.text('Roll Hippo - Yahtzee'), findsOneWidget);
    });

    testWidgets('with a name you have not got offers to keep it', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      await scan(tester, diceProfile(7), name: 'Catan');
      expect(find.text('Save "Catan"?'), findsOneWidget);

      await tapText(tester, 'Save');

      expect(profile('Catan'), findsOneWidget);
      expect(profiles.saves.single.profile.groups[0].length, 7);
      expect(rack(tester).length, 7);
      expect(find.text('Roll Hippo - Catan'), findsOneWidget);
    });

    testWidgets('or to be tried without being kept', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      await scan(tester, diceProfile(7), name: 'Catan');
      await tapText(tester, 'Load');

      expect(rack(tester).length, 7);
      expect(profiles.isEmpty, isTrue);
      expect(profile('Catan'), findsNothing);
      expect(find.text('Roll Hippo'), findsOneWidget);
    });

    testWidgets('is cut down to what the picker has room for', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      // A code from some later build: four sets, twelve dice in the first, and
      // four dice on the card.
      await scan(
        tester,
        Profile(
          mode: ProfileMode.dice,
          groups: <List<DieSpec>>[
            <DieSpec>[for (int i = 0; i < 12; i++) kCardDie],
            <DieSpec>[],
            <DieSpec>[],
            <DieSpec>[kCardDie],
          ],
          cards: <CardSet>[
            CardSet(
              colours: const <int>[
                kDiceWhite,
                kDiceWhite,
                kDiceWhite,
                kDiceWhite,
              ],
              decks: 9,
              reshuffleAt: 99,
            ),
            kEmptyShoe,
            kEmptyShoe,
          ],
        ),
      );

      expect(rack(tester).length, kMaxDice);
      await goToMode(tester, 1);
      expect(find.text('$kMaxCardDice / $kMaxCardDice'), findsOneWidget);
      expect(find.text('3'), findsWidgets, reason: 'the decks are clamped too');
      expect(find.text('<$kMaxReshuffleAt%'), findsOneWidget);
    });

    testWidgets('and what is kept is cut down with it', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      // The same later-build code, saved rather than merely tried. What lands
      // on the file has to be what the screen took: a save written from the
      // code itself would hold four sets and nine decks behind a picker
      // showing three of each, and would say so in the row — under a shoe size
      // of nought, because six to the fourth by nine is not a number this app
      // can produce and Dart's integer power wraps rather than complaining.
      await scan(
        tester,
        Profile(
          mode: ProfileMode.cards,
          groups: <List<DieSpec>>[
            <DieSpec>[for (int i = 0; i < 12; i++) kCardDie],
            <DieSpec>[],
            <DieSpec>[],
            <DieSpec>[kCardDie],
          ],
          cards: <CardSet>[
            CardSet(
              colours: const <int>[
                kDiceWhite,
                kDiceWhite,
                kDiceWhite,
                kDiceWhite,
              ],
              decks: 9,
              reshuffleAt: 99,
            ),
            kEmptyShoe,
            kEmptyShoe,
          ],
        ),
        name: 'Later',
      );
      await tapText(tester, 'Save');

      final Profile kept = profiles.saves.single.profile;
      expect(kept.groups.length, kMaxGroups);
      expect(kept.groups[0].length, kMaxDice);
      expect(kept.cards.first.colours.length, kMaxCardDice);
      expect(kept.cards.first.decks, kMaxDecks);
      expect(kept.cards.first.reshuffleAt, kMaxReshuffleAt);
      expect(
        kept.summary,
        '$kMaxDecks decks, 648 cards',
        reason: 'the row has to describe a shoe the app could build',
      );

      // And on the file, not merely in the row.
      await profiles.load();
      expect(profiles.saves.single.profile, kept);
    });

    testWidgets('the code a save offers carries the name it is saved under', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await createSave(tester, 'Yahtzee');

      await shareProfile(tester, 'Yahtzee');

      final ScannedProfile code = sharedCode(tester);
      expect(code.name, 'Yahtzee');
      expect(code.profile, profiles.saves.single.profile);
      // And it says as much in words, under the square.
      expect(find.text('Yahtzee · 2 dice'), findsOneWidget);
    });

    testWidgets('a save shares what it holds, not what is on screen', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await createSave(tester, 'Yahtzee');
      // The screen is now a die further along than the save it came from, and
      // nothing has written that die anywhere.
      await addDie(tester);
      expect(rack(tester).length, kDefaultDice.length + 1);

      await shareProfile(tester, 'Yahtzee');

      final ScannedProfile code = sharedCode(tester);
      expect(code.name, 'Yahtzee');
      expect(
        code.profile.groups[0].length,
        kDefaultDice.length,
        reason:
            'the code is named Yahtzee, so it has to be the Yahtzee that was '
            'kept — Rename and Delete on the same menu mean that save too',
      );
      expect(code.profile, profiles.saves.single.profile);
      expect(find.text('Yahtzee · 2 dice'), findsOneWidget);
    });

    testWidgets('the dashed one shares the screen, under no name at all', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await createSave(tester, 'Yahtzee');
      await addDie(tester);

      await tester.longPress(find.byKey(kNewProfile));
      await tester.pumpAndSettle();
      await tapText(tester, 'Share');

      final ScannedProfile code = sharedCode(tester);
      // Unnamed even though Yahtzee is lit, because what is on screen is not
      // Yahtzee — a code labelled with a name it does not contain is the one
      // thing the receiving phone cannot be told the truth about.
      expect(code.name, isEmpty);
      expect(code.profile.groups[0].length, kDefaultDice.length + 1);
      expect(find.text('3 dice'), findsOneWidget);
    });
  });
}
