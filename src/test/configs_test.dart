import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/config_pills.dart';
import 'package:rollhippo/app/config_screen.dart';
import 'package:rollhippo/app/configs.dart';
import 'package:rollhippo/app/menu.dart';
import 'package:rollhippo/app/open_dialog.dart';
import 'package:rollhippo/app/page_dots.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A configuration with [dice] six-sided dice in its first set and nothing in
/// the other two, which is the shape of nearly every save anybody makes.
Config diceConfig(int dice, {int decks = 2, int cut = 5}) => Config(
  mode: ConfigMode.dice,
  groups: <List<DieSpec>>[
    <DieSpec>[
      for (int i = 0; i < dice; i++)
        const DieSpec(kind: DieKind.d6, colour: kDiceWhite),
    ],
    <DieSpec>[],
    <DieSpec>[],
  ],
  colours: <int>[kDiceWhite, kDiceWhite],
  decks: decks,
  reshuffleAt: cut,
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

/// One of the pills under the picker, by name. Scoped, because the chooser at
/// launch lists the same names one layer up.
Finder pill(String name) =>
    find.descendant(of: find.byKey(kConfigPills), matching: find.text(name));

/// A row of the launch chooser, by name.
Finder chooserRow(String name) =>
    find.descendant(of: find.byKey(kOpenConfig), matching: find.text(name));

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

/// Hands the picker a configuration off somebody else's screen.
///
/// The scanner itself needs a camera, so what is driven here is the seam it
/// pops back through — which is where every decision about the name is made.
Future<void> scan(
  WidgetTester tester,
  Config config, {
  String name = '',
}) async {
  tester
      .widget<AppMenuButton>(find.byType(AppMenuButton))
      .onScanned(ScannedConfig(name: name, config: config));
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

/// Puts what is on screen into the pill called [name], the way a thumb would:
/// hold it down, and take the first thing the menu offers.
Future<void> savePill(WidgetTester tester, String name) async {
  await tester.longPress(pill(name));
  await tester.pumpAndSettle();
  await tapText(tester, 'Save');
}

/// Makes a save called [name] out of whatever is on screen, the way a thumb
/// would: the dashed pill, the dialog, the name, Create.
Future<void> createSave(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(kNewConfigPill));
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
    await configs.load();
  });

  group('a configuration', () {
    test('goes out and comes back exactly as it was', () {
      final Config config = Config(
        mode: ConfigMode.cards,
        groups: <List<DieSpec>>[
          <DieSpec>[
            const DieSpec(kind: DieKind.d20, colour: 0xFFB3453F),
            const DieSpec(kind: DieKind.d4, colour: 0xFF4A8A55),
          ],
          <DieSpec>[],
          <DieSpec>[const DieSpec(kind: DieKind.d8, colour: kDiceWhite)],
        ],
        colours: <int>[0xFF3F6FA8, 0xFFD8B23A, kDiceWhite],
        decks: 3,
        reshuffleAt: 17,
      );

      final Config back = configFromJson(configToJson(config))!;

      expect(back.mode, ConfigMode.cards);
      expect(back.decks, 3);
      expect(back.reshuffleAt, 17);
      expect(back.colours, config.colours);
      // The empty set in the middle survives: it is a set nobody started, not
      // a gap to be closed up.
      expect(back.groups.length, 3);
      expect(back.groups[1], isEmpty);
      expect(back.groups[0][0].kind, DieKind.d20);
      expect(back.groups[0][0].colour, 0xFFB3453F);
      expect(back.groups[2][0].kind, DieKind.d8);
    });

    test('is dropped rather than repaired when it cannot be read', () {
      expect(configFromJson(null), isNull);
      expect(configFromJson('RH1:AwIAAA=='), isNull);
      final Map<String, Object?> good = configToJson(diceConfig(2));
      for (final String key in <String>['dice', 'colours', 'decks', 'cut']) {
        final Map<String, Object?> broken = Map<String, Object?>.of(good)
          ..remove(key);
        expect(configFromJson(broken), isNull, reason: 'without $key');
      }
      // A code that is not one of ours is not a configuration either.
      expect(
        configFromJson(Map<String, Object?>.of(good)..['dice'] = 'hello'),
        isNull,
      );
    });

    test('says what it comes to in as few words as are true', () {
      expect(diceConfig(5).summary, '5 dice');
      expect(diceConfig(1).summary, '1 die');

      final Config sets = Config(
        mode: ConfigMode.dice,
        groups: <List<DieSpec>>[
          <DieSpec>[for (int i = 0; i < 5; i++) kCardDie],
          <DieSpec>[for (int i = 0; i < 2; i++) kCardDie],
          <DieSpec>[],
        ],
        colours: const <int>[kDiceWhite],
        decks: 1,
        reshuffleAt: 0,
      );
      expect(sets.summary, '2 sets, 7 dice');

      // Card mode counts the shoe, which is what it would deal from.
      expect(
        Config(
          mode: ConfigMode.cards,
          groups: const <List<DieSpec>>[],
          colours: const <int>[kDiceWhite, kDiceWhite],
          decks: 2,
          reshuffleAt: 5,
        ).summary,
        '2 decks, 72 cards',
      );
      expect(
        Config(
          mode: ConfigMode.cards,
          groups: const <List<DieSpec>>[],
          colours: const <int>[kDiceWhite],
          decks: 1,
          reshuffleAt: 5,
        ).summary,
        '1 deck, 6 cards',
      );
    });
  });

  group('how long ago', () {
    final DateTime now = DateTime(2026, 8, 6, 14, 30);
    String ago(Duration back) => agoLabel(now.subtract(back), now);

    test('is coarse, and stays true', () {
      expect(ago(const Duration(seconds: 20)), 'just now');
      expect(ago(const Duration(minutes: 5)), '5m ago');
      expect(ago(const Duration(hours: 2)), '2h ago');
      expect(ago(const Duration(hours: 30)), 'yesterday');
      expect(ago(const Duration(days: 3)), '3 days ago');
      expect(ago(const Duration(days: 9)), 'last week');
      expect(ago(const Duration(days: 30)), '4 weeks ago');
      expect(ago(const Duration(days: 200)), '6 months ago');
      expect(ago(const Duration(days: 900)), 'over a year ago');
    });

    test('survives a clock that has gone backwards', () {
      expect(agoLabel(now.add(const Duration(hours: 3)), now), 'just now');
    });
  });

  group('the store', () {
    test('puts the newest save at the front', () {
      configs.add('First', diceConfig(1));
      configs.add('Second', diceConfig(2));
      expect(
        <String>[for (final SavedConfig s in configs.saves) s.name],
        <String>['Second', 'First'],
      );
    });

    test('writes a changed configuration back under the same name', () {
      final SavedConfig save = configs.add('Yahtzee', diceConfig(5));
      configs.write(save.id, diceConfig(6));

      expect(configs.saves.single.name, 'Yahtzee');
      expect(configs.saves.single.id, save.id);
      expect(configs.saves.single.config.groups[0].length, 6);
    });

    test('writes nothing for a save that is no longer there', () {
      final SavedConfig save = configs.add('Yahtzee', diceConfig(5));
      configs.remove(save.id);
      configs.write(save.id, diceConfig(6));
      expect(configs.saves, isEmpty);
    });

    test('renames, deletes and marks as used', () {
      final SavedConfig save = configs.add('Yahtzee', diceConfig(5));
      final DateTime made = save.usedAt;

      configs.rename(save.id, 'D&D');
      expect(configs.byId(save.id)!.name, 'D&D');
      expect(configs.byId(save.id)!.config.groups[0].length, 5);

      configs.touch(save.id);
      expect(
        configs.byId(save.id)!.usedAt.isBefore(made),
        isFalse,
        reason: 'opening a save moves it forwards, not back',
      );

      configs.remove(save.id);
      expect(configs.byId(save.id), isNull);
      expect(configs.isEmpty, isTrue);
    });

    test('is still there after the app has been put down', () async {
      configs.add('Yahtzee', diceConfig(5));
      configs.add(
        'Cards',
        Config(
          mode: ConfigMode.cards,
          groups: const <List<DieSpec>>[],
          colours: const <int>[0xFFB3453F],
          decks: 3,
          reshuffleAt: 12,
        ),
      );
      await pumpEventQueue();

      // Which is all a fresh launch does.
      await configs.load();

      expect(configs.saves.length, 2);
      expect(configs.saves[0].name, 'Cards');
      expect(configs.saves[0].config.mode, ConfigMode.cards);
      expect(configs.saves[0].config.decks, 3);
      expect(configs.saves[0].config.reshuffleAt, 12);
      expect(configs.saves[0].config.colours, <int>[0xFFB3453F]);
      expect(configs.saves[1].name, 'Yahtzee');
      expect(configs.saves[1].config.groups[0].length, 5);
    });

    test('drops a save it cannot read and keeps the rest', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'configs.saved':
            '[{"id":1,"name":"Fine","used":0,'
            '"config":{"mode":"dice","dice":"RH1:AwIQEAAA","colours":[1],'
            '"decks":1,"cut":0}},'
            '{"id":2,"name":"Broken","used":0,"config":{"mode":"dice"}}]',
      });
      await configs.load();
      expect(
        <String>[for (final SavedConfig s in configs.saves) s.name],
        <String>['Fine'],
      );
    });

    test(
      'a preferences file full of nonsense costs the saves and no more',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'configs.saved': 'not json at all',
        });
        await configs.load();
        expect(configs.isEmpty, isTrue);
      },
    );
  });

  group('the pills', () {
    testWidgets('are just the one, until something is saved', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();

      // Nothing to choose between, so nothing was asked.
      expect(find.byKey(kOpenConfig), findsNothing);
      expect(find.byKey(kNewConfigPill), findsOneWidget);
      expect(find.text('+ New'), findsOneWidget);
    });

    testWidgets('keep what is on screen, under a name', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kNewConfigPill));
      await tester.pumpAndSettle();

      expect(find.text('New configuration'), findsOneWidget);
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

      expect(pill('Yahtzee'), findsOneWidget);
      expect(configs.saves.single.name, 'Yahtzee');
      expect(configs.saves.single.config.groups[0].length, kDefaultDice.length);
    });

    testWidgets('cancelling keeps nothing', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kNewConfigPill));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Yahtzee');
      await tapText(tester, 'Cancel');

      expect(configs.isEmpty, isTrue);
      expect(pill('Yahtzee'), findsNothing);
    });

    testWidgets('take a name of no more than the limit', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kNewConfigPill));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).maxLength,
        kMaxConfigName,
      );
    });

    testWidgets('do not follow the screen until they are told to', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
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
      expect(configs.saves.single.config.groups[0].length, kDefaultDice.length);

      await savePill(tester, 'Yahtzee');

      expect(
        configs.saves.single.config.groups[0].length,
        kDefaultDice.length + 1,
      );
      // And it stays put across a reload, which is the whole point of asking.
      await configs.load();
      expect(
        configs.saves.single.config.groups[0].length,
        kDefaultDice.length + 1,
      );
    });

    testWidgets('take what is on screen onto whichever one is held down', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      await createSave(tester, 'Yahtzee');
      await createSave(tester, 'D&D');

      // Open the first one, change it, and put the change on the other.
      await tester.tap(pill('Yahtzee'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<int>(0)),
          matching: find.byKey(kAddDie),
        ),
      );
      await tester.pumpAndSettle();
      await savePill(tester, 'D&D');

      expect(find.text('Saved to "D&D".'), findsOneWidget);
      expect(
        configs.saves
            .firstWhere((SavedConfig save) => save.name == 'D&D')
            .config
            .groups[0]
            .length,
        kDefaultDice.length + 1,
      );

      // Yahtzee, which was open a moment ago, is untouched.
      expect(
        configs.saves
            .firstWhere((SavedConfig s) => s.name == 'Yahtzee')
            .config
            .groups[0]
            .length,
        kDefaultDice.length,
      );
    });

    testWidgets('keep both modes, whichever one you are looking at', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();

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

      final Config kept = configs.saves.single.config;
      expect(kept.mode, ConfigMode.cards);
      expect(kept.decks, 3);
      // And the dice behind it went along too, untouched.
      expect(kept.groups[0].length, kDefaultDice.length);
    });

    testWidgets('open one, and it replaces what was there', (
      WidgetTester tester,
    ) async {
      configs.add(
        'Twenty',
        Config(
          mode: ConfigMode.dice,
          groups: <List<DieSpec>>[
            <DieSpec>[const DieSpec(kind: DieKind.d20, colour: 0xFFB3453F)],
            <DieSpec>[],
            <DieSpec>[],
          ],
          colours: const <int>[kDiceWhite],
          decks: 1,
          reshuffleAt: 0,
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      // The chooser is up, because there is a save. Take the new one.
      await tapText(tester, '+ New Configuration');

      expect(rack(tester).length, kDefaultDice.length);

      await tester.tap(pill('Twenty'));
      await tester.pumpAndSettle();

      expect(rack(tester).length, 1);
      expect(rack(tester).single.kind, DieKind.d20);
      expect(rack(tester).single.colour, 0xFFB3453F);
    });

    testWidgets('come back to the mode they were made in', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();

      await goToMode(tester, 1);
      await createSave(tester, 'Poker');
      expect(configs.saves.single.config.mode, ConfigMode.cards);

      // Going to look at the dice is not a change to the save — nothing is,
      // until Save. The mode is the page it was saved on.
      await goToMode(tester, 0);
      expect(configs.saves.single.config.mode, ConfigMode.cards);

      await tester.tap(pill('Poker'));
      await tester.pumpAndSettle();
      expect(modeOf(tester), 1);
      expect(find.text('Shuffle'), findsOneWidget);
    });

    testWidgets('a dice save opened from card mode lands on the dice', (
      WidgetTester tester,
    ) async {
      configs.add('Yahtzee', diceConfig(5));
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      await tapText(tester, '+ New Configuration');

      await goToMode(tester, 1);
      expect(modeOf(tester), 1);

      await tester.tap(pill('Yahtzee'));
      await tester.pumpAndSettle();

      expect(modeOf(tester), 0);
      expect(find.text('Roll'), findsOneWidget);
      expect(rack(tester).length, 5);
    });

    testWidgets('put the open configuration in the title', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Roll Hippo'), findsOneWidget);

      await createSave(tester, 'Yahtzee');
      expect(find.text('Roll Hippo - Yahtzee'), findsOneWidget);
      expect(find.text('Roll Hippo'), findsNothing);

      // A rename is a rename of the thing you are in, so it lands up here too.
      await tester.longPress(pill('Yahtzee'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Rename');
      await tester.enterText(find.byType(TextField), 'D&D');
      await tester.pumpAndSettle();
      await tapText(tester, 'Update');
      expect(find.text('Roll Hippo - D&D'), findsOneWidget);

      // Deleting it leaves the dice where they are and the plain title back.
      await tester.longPress(pill('D&D'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Delete');
      await tapText(tester, 'Delete');
      expect(find.text('Roll Hippo'), findsOneWidget);
    });

    testWidgets('title one opened from the chooser, before it is touched', (
      WidgetTester tester,
    ) async {
      configs.add('Yahtzee', diceConfig(5));
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();

      // The chooser has a title of its own, and it is not this one.
      expect(find.text('Roll Hippo - Yahtzee'), findsNothing);

      await tester.tap(chooserRow('Yahtzee'));
      await tester.pumpAndSettle();
      expect(find.text('Roll Hippo - Yahtzee'), findsOneWidget);
    });

    testWidgets('a long press asks what else you meant', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      await createSave(tester, 'Yahtzee');

      await tester.longPress(pill('Yahtzee'));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      // Save first: it is the only way anything is ever written.
      expect(
        tester.getTopLeft(find.text('Save')).dy,
        lessThan(tester.getTopLeft(find.text('Rename')).dy),
      );

      await tapText(tester, 'Rename');
      expect(find.text('Rename configuration'), findsOneWidget);
      // The same dialog, with the other word on it.
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Create'), findsNothing);

      await tester.enterText(find.byType(TextField), 'D&D');
      await tester.pumpAndSettle();
      await tapText(tester, 'Update');

      expect(pill('D&D'), findsOneWidget);
      expect(pill('Yahtzee'), findsNothing);
      // Renaming is about the name and nothing else.
      expect(configs.saves.single.config.groups[0].length, kDefaultDice.length);
    });

    testWidgets('deleting is asked about first, and can be called off', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      await createSave(tester, 'Yahtzee');

      await tester.longPress(pill('Yahtzee'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Delete');
      expect(find.text('Delete "Yahtzee"?'), findsOneWidget);

      await tapText(tester, 'Cancel');
      expect(pill('Yahtzee'), findsOneWidget);

      await tester.longPress(pill('Yahtzee'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Delete');
      await tapText(tester, 'Delete');

      expect(pill('Yahtzee'), findsNothing);
      expect(configs.isEmpty, isTrue);
      // What was on screen is still on screen — deleting a save is a statement
      // about the row of pills, not about the dice.
      expect(rack(tester).length, kDefaultDice.length);
    });
  });

  group('the chooser at launch', () {
    testWidgets('lists what there is, and opens the one you pick', (
      WidgetTester tester,
    ) async {
      configs.add('Yahtzee', diceConfig(5));
      configs.add('D&D', diceConfig(7));
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(kOpenConfig), findsOneWidget);
      expect(find.text('Choose a configuration to open.'), findsOneWidget);
      expect(chooserRow('D&D'), findsOneWidget);
      expect(chooserRow('Yahtzee'), findsOneWidget);
      // What each one holds, and when it was last open.
      expect(
        find.descendant(
          of: find.byKey(kOpenConfig),
          matching: find.text('5 dice · used just now'),
        ),
        findsOneWidget,
      );

      await tester.tap(chooserRow('Yahtzee'));
      await tester.pumpAndSettle();

      expect(find.byKey(kOpenConfig), findsNothing);
      expect(rack(tester).length, 5);
    });

    testWidgets('opens a card configuration on the card page', (
      WidgetTester tester,
    ) async {
      configs.add(
        'Catan',
        Config(
          mode: ConfigMode.cards,
          groups: <List<DieSpec>>[
            <DieSpec>[for (int i = 0; i < 2; i++) kCardDie],
            <DieSpec>[],
            <DieSpec>[],
          ],
          colours: const <int>[kDiceWhite, 0xFFB3453F],
          decks: 3,
          reshuffleAt: 10,
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();

      // What it holds is the shoe, because that is the page it was made on.
      expect(
        find.descendant(
          of: find.byKey(kOpenConfig),
          matching: find.textContaining('3 decks, 108 cards'),
        ),
        findsOneWidget,
      );

      await tester.tap(chooserRow('Catan'));
      await tester.pumpAndSettle();

      expect(modeOf(tester), 1);
      expect(find.text('Shuffle'), findsOneWidget);
      expect(find.text('(108 in the shoe)'), findsOneWidget);
    });

    testWidgets('and does it again the next time the app is started', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      await goToMode(tester, 1);
      await tester.tap(
        find.descendant(of: find.byKey(kCardPage), matching: find.text('3')),
      );
      await tester.pumpAndSettle();
      await createSave(tester, 'Catan');

      // Put the app down, and read the file back the way `main` does.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      await configs.load();
      expect(configs.saves.single.config.mode, ConfigMode.cards);

      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      await tester.tap(chooserRow('Catan'));
      await tester.pumpAndSettle();

      expect(modeOf(tester), 1);
      expect(find.text('Shuffle'), findsOneWidget);
      expect(find.text('(108 in the shoe)'), findsOneWidget);
    });

    testWidgets(
      'a new configuration is the one the app has always started at',
      (WidgetTester tester) async {
        configs.add('Yahtzee', diceConfig(5));
        await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
        await tester.pumpAndSettle();

        await tapText(tester, '+ New Configuration');

        expect(find.byKey(kOpenConfig), findsNothing);
        expect(rack(tester).length, kDefaultDice.length);
        // And it is nobody's save, so editing it changes none of them.
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey<int>(0)),
            matching: find.byKey(kAddDie),
          ),
        );
        await tester.pumpAndSettle();
        expect(configs.saves.single.config.groups[0].length, 5);
      },
    );
  });

  group('a scanned code', () {
    testWidgets('with no name on it changes the screen and keeps nothing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();

      await scan(tester, diceConfig(4));

      expect(rack(tester).length, 4);
      expect(
        configs.isEmpty,
        isTrue,
        reason: 'nothing was named, so nothing is kept',
      );
      expect(find.text('Roll Hippo'), findsOneWidget);
      expect(find.text('Set up from a shared code.'), findsOneWidget);
    });

    testWidgets('carries the mode, and the shoe with it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();

      await scan(
        tester,
        Config(
          mode: ConfigMode.cards,
          groups: <List<DieSpec>>[
            <DieSpec>[kCardDie],
            <DieSpec>[],
            <DieSpec>[],
          ],
          colours: const <int>[kDiceWhite, 0xFFB3453F],
          decks: 3,
          reshuffleAt: 12,
        ),
      );

      expect(modeOf(tester), 1, reason: 'a card code opens on the card page');
      expect(find.text('Shuffle'), findsOneWidget);
      expect(find.text('(108 in the shoe)'), findsOneWidget);
      expect(find.text('<12%'), findsOneWidget);
      expect(find.text('2 / $kMaxCardDice'), findsOneWidget);
    });

    testWidgets('you already have, to the die, opens without a word', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      await createSave(tester, 'Yahtzee');
      final Config kept = configs.saves.single.config;
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
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      await createSave(tester, 'Yahtzee');

      await scan(tester, diceConfig(5), name: 'Yahtzee');
      expect(find.text('Replace "Yahtzee"?'), findsOneWidget);

      await tapText(tester, 'Load');

      expect(rack(tester).length, 5, reason: 'the scanned one is on screen');
      expect(
        configs.saves.single.config.groups[0].length,
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
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      await createSave(tester, 'Yahtzee');

      await scan(tester, diceConfig(5), name: 'Yahtzee');
      await tapText(tester, 'Replace');

      expect(rack(tester).length, 5);
      expect(configs.saves.length, 1, reason: 'replaced, not added beside');
      expect(configs.saves.single.config.groups[0].length, 5);
      expect(find.text('Roll Hippo - Yahtzee'), findsOneWidget);
      // And it is on the file, not just in the row.
      await configs.load();
      expect(configs.saves.single.config.groups[0].length, 5);
    });

    testWidgets('cancelled, leaves the screen and the save alone', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      await createSave(tester, 'Yahtzee');

      await scan(tester, diceConfig(5), name: 'Yahtzee');
      await tapText(tester, 'Cancel');

      expect(rack(tester).length, kDefaultDice.length);
      expect(configs.saves.single.config.groups[0].length, kDefaultDice.length);
      expect(find.text('Roll Hippo - Yahtzee'), findsOneWidget);
    });

    testWidgets('with a name you have not got offers to keep it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();

      await scan(tester, diceConfig(7), name: 'Catan');
      expect(find.text('Save "Catan"?'), findsOneWidget);

      await tapText(tester, 'Save');

      expect(pill('Catan'), findsOneWidget);
      expect(configs.saves.single.config.groups[0].length, 7);
      expect(rack(tester).length, 7);
      expect(find.text('Roll Hippo - Catan'), findsOneWidget);
    });

    testWidgets('or to be tried without being kept', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();

      await scan(tester, diceConfig(7), name: 'Catan');
      await tapText(tester, 'Load');

      expect(rack(tester).length, 7);
      expect(configs.isEmpty, isTrue);
      expect(pill('Catan'), findsNothing);
      expect(find.text('Roll Hippo'), findsOneWidget);
    });

    testWidgets('is cut down to what the picker has room for', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();

      // A code from some later build: four sets, twelve dice in the first, and
      // four dice on the card.
      await scan(
        tester,
        Config(
          mode: ConfigMode.dice,
          groups: <List<DieSpec>>[
            <DieSpec>[for (int i = 0; i < 12; i++) kCardDie],
            <DieSpec>[],
            <DieSpec>[],
            <DieSpec>[kCardDie],
          ],
          colours: const <int>[kDiceWhite, kDiceWhite, kDiceWhite, kDiceWhite],
          decks: 9,
          reshuffleAt: 99,
        ),
      );

      expect(rack(tester).length, kMaxDice);
      await goToMode(tester, 1);
      expect(find.text('$kMaxCardDice / $kMaxCardDice'), findsOneWidget);
      expect(find.text('3'), findsWidgets, reason: 'the decks are clamped too');
      expect(find.text('<$kMaxReshuffleAt%'), findsOneWidget);
    });

    testWidgets('the code the picker offers carries the name it is open as', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.pumpAndSettle();
      await createSave(tester, 'Yahtzee');

      await tester.tap(find.byType(AppMenuButton));
      await tester.pumpAndSettle();
      await tapText(tester, 'Share');

      final ScannedConfig code =
          decodeConfig(
            tester.widget<ShareCodeView>(find.byType(ShareCodeView)).code,
          )!;
      expect(code.name, 'Yahtzee');
      expect(code.config, configs.saves.single.config);
      // And it says as much in words, under the square.
      expect(find.text('Yahtzee · 2 dice'), findsOneWidget);
    });
  });
}
