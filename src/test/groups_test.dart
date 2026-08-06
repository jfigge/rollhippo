import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/config_screen.dart';
import 'package:rollhippo/app/page_dots.dart';
import 'package:rollhippo/app/tray_screen.dart';
import 'package:rollhippo/motion/motion.dart';
import 'package:rollhippo/physics/body.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/tray/tray.dart';

/// The dice one group's rack is showing, whichever page is on screen.
///
/// Scoped to the group rather than counted across the whole tree: a page view
/// keeps its neighbours built, so a bare `find.byType(DiePreview)` would pick
/// up the dice of a group you had already swiped away from.
List<DieSpec> rackOf(WidgetTester tester, int group) => <DieSpec>[
  for (final DiePreview preview in tester.widgetList<DiePreview>(
    find.descendant(
      of: find.byKey(ValueKey<int>(group)),
      matching: find.byType(DiePreview),
    ),
  ))
    preview.spec,
];

PageDots dotsOf(WidgetTester tester) =>
    tester.widget<PageDots>(find.byKey(kGroupDots));

/// The tray's own dots, which say which box you are looking at. The only page
/// control on that screen, so it needs no name.
PageDots trayDotsOf(WidgetTester tester) =>
    tester.widget<PageDots>(find.byType(PageDots));

/// Swipes the rack one group to the left, and lets the page view land.
Future<void> swipeLeft(WidgetTester tester) async {
  await tester.drag(find.byType(PageView), const Offset(-300, 0));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> tapText(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
}

/// The dice panel's Remove. Card mode is built at the same time, one screen to
/// the side, and it has a Remove of its own.
final Finder diceRemove = find.descendant(
  of: find.byKey(kDicePage),
  matching: find.text('Remove'),
);

Future<void> tapRemove(WidgetTester tester) async {
  await tester.tap(diceRemove);
  await tester.pump();
}

/// Whether the button carrying [label] can be pressed at all.
///
/// By base class rather than by type: `TextButton.icon` hands back a private
/// subclass, which `find.byType` — being exact about runtime types — does not
/// match.
bool enabled(WidgetTester tester, Finder label) =>
    tester
        .widget<ButtonStyleButton>(
          find.ancestor(
            of: label,
            matching: find.byWidgetPredicate(
              (Widget widget) => widget is ButtonStyleButton,
            ),
          ),
        )
        .onPressed !=
    null;

const String kEmptyEditor = 'No dice yet';

void main() {
  group('three groups', () {
    testWidgets('start as one set of dice and two empty ones', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));

      expect(dotsOf(tester).filled, <bool>[true, false, false]);
      expect(dotsOf(tester).current, 0);
      expect(rackOf(tester, 0).length, kDefaultDice.length);
    });

    testWidgets('swiping reaches a group with nothing in it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await swipeLeft(tester);

      expect(dotsOf(tester).current, 1);
      expect(rackOf(tester, 1), isEmpty);
      // The editor is still exactly where it was, saying so.
      expect(find.text(kEmptyEditor), findsOneWidget);
      expect(enabled(tester, diceRemove), isFalse);
      expect(find.text('0 / $kMaxDice'), findsOneWidget);
    });

    testWidgets('a group with a die in it lights its dot, and can be emptied', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await swipeLeft(tester);

      await tapText(tester, 'Add a die');
      expect(rackOf(tester, 1).length, 1);
      expect(dotsOf(tester).filled, <bool>[true, true, false]);
      // A first die has nothing to copy, so it is what the app starts with.
      expect(rackOf(tester, 1).single.kind, kDefaultDice.first.kind);
      expect(rackOf(tester, 1).single.colour, kDiceWhite);

      // Unlike the first group, this one is allowed to go back to nothing.
      expect(enabled(tester, diceRemove), isTrue);
      await tapRemove(tester);
      expect(rackOf(tester, 1), isEmpty);
      expect(dotsOf(tester).filled, <bool>[true, false, false]);
      expect(find.text(kEmptyEditor), findsOneWidget);
    });

    testWidgets('the first group always keeps a die', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tapRemove(tester);

      expect(rackOf(tester, 0).length, 1);
      expect(enabled(tester, diceRemove), isFalse);
      expect(dotsOf(tester).filled.first, isTrue);
    });

    testWidgets('the editor of an empty group cannot be worked', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await swipeLeft(tester);

      // Faded and behind an IgnorePointer, so this lands on nothing at all.
      await tester.tap(find.text('D20'), warnIfMissed: false);
      await tester.pump();
      await tapText(tester, 'Add a die');

      expect(rackOf(tester, 1).single.kind, DieKind.d6);
    });

    testWidgets('tapping a dot goes to that group', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));

      await tester.tap(
        find
            .descendant(
              of: find.byType(PageDots),
              matching: find.byType(GestureDetector),
            )
            .at(2),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(dotsOf(tester).current, 2);
    });

    testWidgets('each group remembers which die you were working on', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConfigScreen()));
      await tester.tap(find.byType(DiePreview).at(1));
      await tester.pump();
      expect(find.text('Die 2 — D6'), findsOneWidget);

      await swipeLeft(tester);
      expect(find.text(kEmptyEditor), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(300, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Die 2 — D6'), findsOneWidget);
    });
  });

  group('the tray, group by group', () {
    const DieSpec white = DieSpec(kind: DieKind.d6, colour: kDiceWhite);
    const String kPrompt = 'Shake to roll';

    /// Runs the tray for [seconds] of real time, a frame at a time. The
    /// binding's clock is a fake one, so this is exactly [seconds] of
    /// simulation and not a wait.
    Future<void> run(WidgetTester tester, double seconds) async {
      for (int i = 0; i < (seconds * 60).round(); i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    /// Every case here runs as macOS, which is the harness path: the tray uses
    /// the synthetic phone rather than reaching for an accelerometer a test
    /// machine does not have, and space is a shake.
    final TargetPlatformVariant harness = TargetPlatformVariant.only(
      TargetPlatform.macOS,
    );

    Future<void> open(WidgetTester tester, int groups) async {
      await tester.binding.setSurfaceSize(kHarnessScreen);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: TrayScreen(
            groups: <List<DieSpec>>[
              for (int i = 0; i < groups; i++) <DieSpec>[white, white],
            ],
          ),
        ),
      );
    }

    testWidgets('one group is the tray as it was — no dots, no swiping', (
      WidgetTester tester,
    ) async {
      await open(tester, 1);
      await run(tester, 3);

      expect(find.byType(PageDots), findsNothing);
      expect(find.text(kPrompt), findsNothing);
    }, variant: harness);

    testWidgets(
      'the group you arrive on is thrown, the next one is waiting',
      (WidgetTester tester) async {
        await open(tester, 2);
        await run(tester, 4);

        expect(trayDotsOf(tester).current, 0);
        expect(find.text(kPrompt), findsNothing);

        await tester.dragFrom(const Offset(200, 500), const Offset(-300, 0));
        await run(tester, 1);

        expect(trayDotsOf(tester).current, 1);
        expect(
          find.text(kPrompt),
          findsOneWidget,
          reason: 'the second group should be sitting there unthrown',
        );

        // Space is the harness's shake, and a shake is what an unthrown group is
        // waiting for.
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await run(tester, 1);
        expect(find.text(kPrompt), findsNothing);
      },
      variant: harness,
    );

    testWidgets('the box will not move while the dice are', (
      WidgetTester tester,
    ) async {
      await open(tester, 2);
      // A tenth of a second in, the dice you arrived with are still in the air.
      await run(tester, 0.1);

      await tester.dragFrom(const Offset(200, 500), const Offset(-300, 0));
      await run(tester, 1);

      expect(
        trayDotsOf(tester).current,
        0,
        reason: 'a roll in flight swiped away',
      );
    }, variant: harness);
  });

  group('what gets thrown', () {
    const DieSpec d6 = DieSpec(kind: DieKind.d6, colour: kDiceWhite);

    test('an empty group is not a box on the tray', () {
      final List<List<DieSpec>> groups = <List<DieSpec>>[
        <DieSpec>[d6],
        <DieSpec>[],
        <DieSpec>[d6, d6],
      ];

      final List<List<DieSpec>> rollable = rollableGroups(groups);
      expect(rollable.length, 2);
      expect(rollable[1].length, 2);
      // Copies: editing the picker afterwards must not reach a live tray.
      expect(identical(rollable[0], groups[0]), isFalse);
    });

    test('the group you were on is the one you arrive at', () {
      final List<List<DieSpec>> groups = <List<DieSpec>>[
        <DieSpec>[d6],
        <DieSpec>[],
        <DieSpec>[d6],
      ];

      expect(rollableIndex(groups, 0), 0);
      // Group three is the second box once the empty one is dropped.
      expect(rollableIndex(groups, 2), 1);
      // An empty group has no box of its own, and clamps onto the last real
      // one rather than sending you back to the beginning.
      expect(
        rollableIndex(groups, 1).clamp(0, rollableGroups(groups).length - 1),
        1,
      );
    });
  });

  group('the shake that throws a group', () {
    test('a phone held still is not one', () {
      expect(isShake(MotionFrame.still), isFalse);
    });

    test('a hand shake is', () {
      final ManualMotionSource motion = ManualMotionSource();
      motion.shake();

      bool shaken = false;
      for (int i = 0; i < 60 && !shaken; i++) {
        shaken = isShake(motion.sample(1 / 60));
      }
      expect(shaken, isTrue, reason: 'a shake never crossed the threshold');
    });

    test('and it stops being one once the hand does', () {
      final ManualMotionSource motion = ManualMotionSource();
      motion.shake(seconds: 0.3);
      for (int i = 0; i < 60; i++) {
        motion.sample(1 / 60);
      }
      expect(isShake(motion.sample(1 / 60)), isFalse);
    });
  });

  test('a group nobody is looking at puts its dice down on its own', () {
    // What an unthrown box does off-screen: it is fed a phone holding
    // perfectly still until it settles, so the dice are lying on the floor by
    // the time you swipe to them rather than hanging in mid-air.
    final DiceTray tray = DiceTray(
      width: 393 / Tuning.logicalPixelsPerMetre,
      height: 852 / Tuning.logicalPixelsPerMetre,
      dice: <DieSpec>[
        for (final DieKind kind in DieKind.values)
          DieSpec(kind: kind, colour: kDiceWhite),
      ],
    );

    double elapsed = 0;
    while (!tray.world.asleep && elapsed < 6.0) {
      tray.update(MotionFrame.still, 1 / 120);
      elapsed += 1 / 120;
    }

    expect(
      tray.world.asleep,
      isTrue,
      reason: 'still at $elapsed s — an unthrown group would hang in the air',
    );
    for (final RigidBody die in tray.dice) {
      expect(die.position.y.abs(), lessThan(tray.height / 2));
      expect(die.position.x.abs(), lessThan(tray.width / 2));
    }
  });
}
