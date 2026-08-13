import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/page_dots.dart';
import 'package:rollhippo/app/picker_screen.dart';
import 'package:rollhippo/app/settings.dart';
import 'package:rollhippo/app/tray_screen.dart';
import 'package:rollhippo/app/tutorial.dart';
import 'package:rollhippo/motion/motion.dart';
import 'package:rollhippo/physics/body.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/render/tray_painter.dart';
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

/// The rack's own page controller, for the one test that watches a page move
/// rather than reading where it ended up.
PageController racksOf(WidgetTester tester) =>
    tester
        .widget<PageView>(
          find.descendant(
            of: find.byKey(kRack),
            matching: find.byType(PageView),
          ),
        )
        .controller!;

/// The tray's own dots, which say which box you are looking at. The only page
/// control on that screen, so it needs no name.
PageDots trayDotsOf(WidgetTester tester) =>
    tester.widget<PageDots>(find.byType(PageDots));

/// Swipes the rack one group to the left, and lets the page view land.
///
/// Settled rather than pumped for a fixed while: a page view ignores pointers
/// for as long as it is still moving, so a rack that is a few points short of
/// home takes no taps — and the plus that adds a die is a tap on the rack.
Future<void> swipeLeft(WidgetTester tester) async {
  await tester.drag(find.byKey(kRack), const Offset(-300, 0));
  await tester.pumpAndSettle();
}

/// Back the other way, and settled for the same reason.
Future<void> swipeRight(WidgetTester tester) async {
  await tester.drag(find.byKey(kRack), const Offset(300, 0));
  await tester.pumpAndSettle();
}

/// The plus in one group's rack: the empty slot another die would land in.
///
/// Per group, because every rack with room in it draws one and the page view
/// keeps more than one built — and because the plus adds to the set it is
/// drawn in rather than to whichever one is on screen.
Finder addIn(int group) => find.descendant(
  of: find.byKey(ValueKey<int>(group)),
  matching: find.byKey(kAddDie),
);

Future<void> tapAdd(WidgetTester tester, int group) async {
  await tester.tap(addIn(group));
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

/// Remove, on a press that may put a question up and may animate a set out.
/// Settled rather than pumped once, for both of those reasons.
Future<void> tapRemoveAndSettle(WidgetTester tester) async {
  await tester.tap(diceRemove);
  await tester.pumpAndSettle();
}

/// Answers the question a set's last die gets.
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

/// Which slot of a group's rack has the ring round it: the die that group's
/// panel is pointed at.
///
/// The panel's title used to name the die in words, and names the set now, so
/// the ring is where a selection is written down — and it is written down per
/// group, which is what makes it worth asking of one.
int selectedIn(WidgetTester tester, int group) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byKey(ValueKey<int>(group)),
        matching: find.byType(Container),
      ),
    )
    .toList()
    .indexWhere((Container slot) => _edgeOf(slot) == kSelectedRing);

/// The blue a selected slot is edged with — see `_RackSlot`.
const Color kSelectedRing = Color(0xFF6E9AD0);

Color? _edgeOf(Container container) {
  final Decoration? decoration = container.decoration;
  final BoxBorder? border =
      decoration is BoxDecoration ? decoration.border : null;
  return border is Border ? border.top.color : null;
}

void main() {
  group('the sets of dice', () {
    testWidgets('start as one set of dice and one empty one', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));

      // Two pages, not [kMaxGroups] of them: the set you have and the one you
      // could have. The rest arrive as you fill them — see [shownPages].
      expect(dotsOf(tester).filled, <bool>[true, false]);
      expect(dotsOf(tester).current, 0);
      expect(rackOf(tester, 0).length, kDefaultDice.length);
    });

    testWidgets('grow a page at a time, and stop at kMaxGroups', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));

      // One filled set and one empty page after it, every time, until the
      // ceiling — where the empty page is the last one there is room for and
      // filling it adds nothing.
      for (int group = 1; group < kMaxGroups; group++) {
        expect(dotsOf(tester).filled.length, group + 1);
        await swipeLeft(tester);
        expect(dotsOf(tester).current, group);
        await tapAdd(tester, group);
      }
      expect(dotsOf(tester).filled.length, kMaxGroups);
      expect(dotsOf(tester).filled, List<bool>.filled(kMaxGroups, true));

      // And there is nowhere left to swipe to.
      await swipeLeft(tester);
      expect(dotsOf(tester).current, kMaxGroups - 1);
    });

    testWidgets('swiping reaches a group with nothing in it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
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
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await swipeLeft(tester);

      await tapAdd(tester, 1);
      expect(rackOf(tester, 1).length, 1);
      expect(dotsOf(tester).filled, <bool>[true, true, false]);
      // A first die has nothing to copy, so it is what the app starts with.
      expect(rackOf(tester, 1).single.kind, kDefaultDice.first.kind);
      expect(rackOf(tester, 1).single.colour, kDiceWhite);

      // Unlike the first group, this one is allowed to go back to nothing.
      expect(enabled(tester, diceRemove), isTrue);
      await tapRemove(tester);
      expect(rackOf(tester, 1), isEmpty);
      // And the page it grew is gone with it: an emptied last set leaves the
      // one empty page a fresh picker has.
      expect(dotsOf(tester).filled, <bool>[true, false]);
      expect(find.text(kEmptyEditor), findsOneWidget);
    });

    /// Three sets, the third holding two dice with the ring on the second of
    /// them — which is what makes it worth watching the third set move.
    Future<void> threeSets(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await swipeLeft(tester);
      await tapAdd(tester, 1);
      await swipeLeft(tester);
      await tapAdd(tester, 2);
      await tapAdd(tester, 2);
    }

    testWidgets('the last set in the row empties without being asked about', (
      WidgetTester tester,
    ) async {
      await threeSets(tester);

      // Set three is where the row ends, so emptying it deletes nothing: it
      // becomes the empty page every rack finishes with, which is where it
      // already was.
      await tapRemoveAndSettle(tester);
      await tapRemoveAndSettle(tester);

      expect(find.byKey(kDropSetDialog), findsNothing);
      expect(rackOf(tester, 2), isEmpty);
      expect(dotsOf(tester).filled, <bool>[true, true, false]);
      expect(dotsOf(tester).current, 2);
      expect(find.text(kEmptyEditor), findsOneWidget);
    });

    testWidgets('any other set asks before its last die goes', (
      WidgetTester tester,
    ) async {
      await threeSets(tester);
      await swipeRight(tester);

      // Set two has one die and set three behind it, so this press is about
      // to do more than take a die off a rack.
      await tapRemoveAndSettle(tester);
      await answerDrop(tester, 'Cancel');

      expect(rackOf(tester, 1).length, 1, reason: 'cancel means nothing moved');
      expect(dotsOf(tester).filled, <bool>[true, true, true, false]);
      expect(dotsOf(tester).current, 1);
    });

    testWidgets('and OK deletes it, with the set behind it coming forward', (
      WidgetTester tester,
    ) async {
      await threeSets(tester);
      await swipeRight(tester);

      await tapRemoveAndSettle(tester);
      await answerDrop(tester, 'Remove');

      // Set three has come forward a page and the row has closed up behind it.
      expect(dotsOf(tester).filled, <bool>[true, true, false]);
      expect(dotsOf(tester).current, 1);
      // With its dice, and with the die its ring was round: the selection is
      // per set, so it travels with the set rather than staying on a page.
      expect(rackOf(tester, 1).length, 2);
      expect(selectedIn(tester, 1), 1);
    });

    testWidgets('and the set behind it slides in from the right', (
      WidgetTester tester,
    ) async {
      await threeSets(tester);
      await swipeRight(tester);
      await tapRemoveAndSettle(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(kDropSetDialog),
          matching: find.text('Remove'),
        ),
      );
      // Watched frame by frame rather than sampled at one moment, because
      // what has to be true is that the view *travelled*: the dialog goes, the
      // page view sets off towards the set behind, and only then does the row
      // close up underneath it.
      double furthest = 1;
      for (int frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        final double? page = racksOf(tester).page;
        if (page != null && page > furthest) furthest = page;
      }

      expect(
        furthest,
        greaterThan(1.2),
        reason: 'the next set never slid in; it was swapped in place',
      );

      // And it lands a page *back*, because the row closed up underneath it:
      // page two's dice are page one's now, so the jump moves nothing.
      await tester.pumpAndSettle();
      expect(racksOf(tester).page, 1.0);
      expect(rackOf(tester, 1).length, 2);
    });

    testWidgets('the first set goes the same way once there is a second', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await swipeLeft(tester);
      await tapAdd(tester, 1);
      await tapAdd(tester, 1);
      await swipeRight(tester);

      // Nothing about the first set is special: with a second one started it
      // comes apart like any other, question and all.
      await tapRemoveAndSettle(tester);
      expect(find.byKey(kDropSetDialog), findsNothing, reason: 'two dice left');
      await tapRemoveAndSettle(tester);
      await answerDrop(tester, 'Remove');

      // Set two has become set one, and it is now the only one there is.
      expect(dotsOf(tester).filled, <bool>[true, false]);
      expect(dotsOf(tester).current, 0);
      expect(rackOf(tester, 0).length, 2);
    });

    testWidgets('swiping onto the empty page at the end does not clear it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await swipeLeft(tester);
      // Away and back: the page you are on is empty both times, and it is the
      // one empty page a picker is supposed to have.
      await swipeRight(tester);
      await swipeLeft(tester);

      expect(dotsOf(tester).current, 1);
      expect(dotsOf(tester).filled, <bool>[true, false]);
      await tapAdd(tester, 1);
      expect(rackOf(tester, 1).length, 1);
    });

    testWidgets('the only group there is always keeps a die', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await tapRemove(tester);

      expect(rackOf(tester, 0).length, 1);
      expect(enabled(tester, diceRemove), isFalse);
      expect(dotsOf(tester).filled.first, isTrue);
    });

    testWidgets('the editor of an empty group cannot be worked', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await swipeLeft(tester);

      // Faded and behind an IgnorePointer, so this lands on nothing at all.
      await tester.tap(find.text('D20'), warnIfMissed: false);
      await tester.pump();
      await tapAdd(tester, 1);

      expect(rackOf(tester, 1).single.kind, DieKind.d6);
    });

    testWidgets('tapping a dot goes to that group', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      // A third dot to aim at, and back to the first to aim from.
      await swipeLeft(tester);
      await tapAdd(tester, 1);
      await swipeRight(tester);

      // Scoped to the group's own dots: the card page's are built at the same
      // time, one screen to the side, and the mode dots are under both.
      await tester.tap(
        find
            .descendant(
              of: find.byKey(kGroupDots),
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
      await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
      await tester.tap(find.byType(DiePreview).at(1));
      await tester.pump();
      expect(selectedIn(tester, 0), 1);

      await swipeLeft(tester);
      expect(find.text(kEmptyEditor), findsOneWidget);

      await tester.drag(find.byKey(kRack), const Offset(300, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(selectedIn(tester, 0), 1);
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
      // And it is waiting, like every other group and like the card table:
      // nothing is thrown on the way in.
      expect(find.text(kPrompt), findsOneWidget);
    }, variant: harness);

    testWidgets('every group is waiting, the one you arrive on included', (
      WidgetTester tester,
    ) async {
      await open(tester, 2);
      await run(tester, 4);

      expect(trayDotsOf(tester).current, 0);
      expect(
        find.text(kPrompt),
        findsOneWidget,
        reason: 'the tray must not roll itself as it opens',
      );

      // Space is the harness's shake, and a shake is what an unthrown group
      // is waiting for.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await run(tester, 1);
      expect(find.text(kPrompt), findsNothing);

      // And the group next door is still waiting: a throw is one group's,
      // which is the whole reason they are separate boxes. Settled first,
      // because a box will not move while its dice are — see `_canSwipe`.
      await run(tester, 5);
      await tester.dragFrom(const Offset(200, 500), const Offset(-300, 0));
      await run(tester, 1);

      expect(trayDotsOf(tester).current, 1);
      expect(
        find.text(kPrompt),
        findsOneWidget,
        reason: 'the second group should be sitting there unthrown',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await run(tester, 1);
      expect(find.text(kPrompt), findsNothing);
    }, variant: harness);

    testWidgets('a box per set, up to every set the picker can hold', (
      WidgetTester tester,
    ) async {
      await open(tester, kMaxGroups);
      await run(tester, 3);

      expect(trayDotsOf(tester).filled.length, kMaxGroups);
      expect(trayDotsOf(tester).current, 0);
    }, variant: harness);

    testWidgets('and its dice are lying still, not falling into view', (
      WidgetTester tester,
    ) async {
      await open(tester, 1);
      // One frame. The box you arrive on is stepped to rest inside the layout
      // pass that built it, so there is nothing left of the constructor's
      // throw to watch — which is the difference between a tray that is
      // waiting and a tray that is mid-roll.
      await tester.pump(const Duration(milliseconds: 16));

      final DiceTray tray =
          ((tester
                          .widget<CustomPaint>(
                            find
                                .descendant(
                                  of: find.byType(TrayScreen),
                                  matching: find.byType(CustomPaint),
                                )
                                .first,
                          )
                          .painter!
                      as TrayPagesPainter)
                  .trays)
              .first;
      expect(tray.world.asleep, isTrue);
      for (final RigidBody die in tray.dice) {
        expect(die.velocity.length, lessThan(0.01));
      }
    }, variant: harness);

    testWidgets('with motion control off, the button is the whole of it', (
      WidgetTester tester,
    ) async {
      final bool was = settings.motion;
      addTearDown(() => settings.motion = was);
      settings.motion = false;

      await open(tester, 2);
      await run(tester, 4);

      // Straight to the group nobody has thrown.
      await tester.dragFrom(const Offset(200, 500), const Offset(-300, 0));
      await run(tester, 1);
      expect(
        find.text('Tap Throw to roll'),
        findsOneWidget,
        reason: 'the prompt has to ask for a gesture that still works',
      );
      expect(find.text(kPrompt), findsNothing);

      // A shake is nothing now: the tray is being handed a phone that is
      // lying on a table whatever the real one is doing.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await run(tester, 1);
      expect(
        find.text('Tap Throw to roll'),
        findsOneWidget,
        reason: 'a shake threw a group that was not listening for one',
      );

      await tester.tap(find.text('Throw'));
      await run(tester, 2);
      expect(find.text('Tap Throw to roll'), findsNothing);
    }, variant: harness);

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

  group('how many pages there are', () {
    // The rule itself, without a widget in front of it: what you are shown is
    // the slots you have started and one empty one after them. The ceiling is
    // passed in rather than read, so these say `kMaxGroups` where the picker
    // would — a rule that only held at one particular ceiling would be a rule
    // nobody could move.
    test('is one more than the number started', () {
      expect(shownPages(1, kMaxGroups), 2);
      expect(shownPages(2, kMaxGroups), 3);
      expect(shownPages(3, kMaxGroups), 4);
    });

    test('stops at the ceiling, empty page and all', () {
      // Every slot started: there is no room left for an empty page, so the
      // row is the ceiling itself and there is nowhere for another set to go.
      expect(shownPages(kMaxGroups, kMaxGroups), kMaxGroups);
      expect(shownPages(kMaxGroups + 1, kMaxGroups), kMaxGroups);
    });

    test('is at least the one you have and one you could have', () {
      // Nothing started at all is not a state the picker can be in — the last
      // set there is keeps its last die — but the floor is what makes that
      // true rather than something every caller has to know.
      expect(shownPages(0, kMaxGroups), 2);
    });
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
