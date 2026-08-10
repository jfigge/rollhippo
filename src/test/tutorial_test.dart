import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/menu.dart';
import 'package:rollhippo/app/page_dots.dart';
import 'package:rollhippo/app/picker_screen.dart';
import 'package:rollhippo/app/profiles.dart';
import 'package:rollhippo/app/settings.dart';
import 'package:rollhippo/app/tray_screen.dart';
import 'package:rollhippo/app/tutorial.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lets whatever is moving land, without waiting for everything to stop.
///
/// `pumpAndSettle` is no use past the fifth page: the backdrop there is a real
/// [TrayScreen], and a real tray schedules a frame for ever — so settling
/// waits for a frame that is never the last one. Half a second of pumping is
/// longer than anything here moves for, the longest being the 320 ms the card
/// takes to change ends, and it works the same on both sides of that page.
Future<void> settle(WidgetTester tester, [int frames = 26]) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// The dots on the tutorial's own card, which are not the backdrop's: there
/// are three screens under there and two of them have dots.
PageDots tutorialDots(WidgetTester tester) => tester.widget<PageDots>(
  find.descendant(
    of: find.byKey(kTutorialCard),
    matching: find.byType(PageDots),
  ),
);

/// The card's page view, for the same reason.
final Finder tutorialPages = find.descendant(
  of: find.byKey(kTutorialCard),
  matching: find.byType(PageView),
);

/// Where the tutorial has cut its hole, or null while it dims everything.
Rect? spotOf(WidgetTester tester) {
  final CustomPaint paint = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .firstWhere((CustomPaint paint) => paint.painter is TutorialSpotlight);
  return (paint.painter! as TutorialSpotlight).spot;
}

/// Finds [label] on the card rather than anywhere on the screen — the backdrop
/// is a whole picker, and it has a Roll on it.
Finder onCard(String label) =>
    find.descendant(of: find.byKey(kTutorialCard), matching: find.text(label));

/// The dice in the first set of whatever picker is on screen. Only asked with
/// the tutorial shut, when there is exactly one of those.
List<DieSpec> rackOf(WidgetTester tester) => <DieSpec>[
  for (final DiePreview preview in tester.widgetList<DiePreview>(
    find.descendant(
      of: find.byKey(const ValueKey<int>(0)),
      matching: find.byType(DiePreview),
    ),
  ))
    preview.spec,
];

/// The picker, phone-shaped, with the settings put back afterwards.
///
/// [settings] is one object for the whole app, and every test below either
/// opens the tutorial or closes it — both of which write the flag that decides
/// whether the *next* launch offers it. Leaving that set would quietly change
/// what every test after it is testing.
Future<void> pumpPicker(WidgetTester tester, {bool tutorial = false}) async {
  final bool seen = settings.tutorialSeen;
  addTearDown(() => settings.tutorialSeen = seen);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await tester.binding.setSurfaceSize(kHarnessScreen);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: PickerScreen(tutorial: tutorial)));
  await settle(tester);
}

/// Opens it the way somebody who has seen it once would: the menu, and the
/// entry at the bottom of it.
Future<void> openFromMenu(WidgetTester tester) async {
  await tester.tap(find.byType(AppMenuButton));
  await settle(tester);
  await tester.tap(find.text('How to use'));
  await settle(tester);
}

/// Every case here runs as macOS, which is the harness path.
///
/// The same reason `groups_test.dart` gives: past the fifth page the backdrop
/// is a real [TrayScreen], and on a platform the tray believes is a phone it
/// reaches for an accelerometer this machine has not got. It costs nothing
/// elsewhere — at [kHarnessScreen] the letterbox is the identity — and it is a
/// variant rather than a debug flag because the flag is checked for having
/// been left set before any tear-down gets to unset it.
final TargetPlatformVariant harness = TargetPlatformVariant.only(
  TargetPlatform.macOS,
);

/// Walks forward with Next until [page] is showing.
Future<void> goTo(WidgetTester tester, int page) async {
  while (tutorialDots(tester).current < page) {
    await tester.tap(onCard('Next'));
    await settle(tester);
  }
}

void main() {
  group('the first run', () {
    testWidgets('is the one launch that puts the tutorial up on its own', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester, tutorial: true);
      expect(find.byKey(kTutorial), findsOneWidget);
      // One picker underneath and two behind: the route is see-through, and
      // the screen it was asked for from is what it fades back onto.
      expect(find.byType(PickerScreen), findsNWidgets(3));
    }, variant: harness);

    testWidgets('and every other way of building the picker is not', (
      WidgetTester tester,
    ) async {
      // The default, which is what `tool/` renders into the store screenshots
      // and what the other two hundred tests pump. A first run is a fact about
      // a launch, and none of those is one.
      await pumpPicker(tester);
      expect(find.byKey(kTutorial), findsNothing);
      expect(find.byType(PickerScreen), findsOneWidget);
    }, variant: harness);

    testWidgets('closing it is what stops it coming back', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester, tutorial: true);
      expect(
        settings.tutorialSeen,
        isFalse,
        reason: 'still open, so nobody has been shown anything yet',
      );

      await tester.tap(onCard('Skip'));
      await settle(tester);
      expect(find.byKey(kTutorial), findsNothing);
      expect(settings.tutorialSeen, isTrue);
    }, variant: harness);

    testWidgets('and it is remembered across a relaunch', (
      WidgetTester tester,
    ) async {
      final bool seen = settings.tutorialSeen;
      addTearDown(() => settings.tutorialSeen = seen);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      settings.tutorialSeen = true;
      await tester.pumpAndSettle();

      // A fresh Settings is what the next launch reads, and `main` asks it
      // this one question before it builds anything.
      final Settings relaunched = Settings();
      expect(
        relaunched.tutorialSeen,
        isFalse,
        reason: 'a phone with nothing written for it has never been shown it',
      );
      await relaunched.load();
      expect(relaunched.tutorialSeen, isTrue);
    }, variant: harness);
  });

  group('the pages', () {
    testWidgets('are one per entry, and Next walks to the end of them', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester, tutorial: true);

      expect(tutorialDots(tester).filled, hasLength(kTutorialPages.length));
      expect(tutorialDots(tester).current, 0);
      expect(onCard(kTutorialPages.first.title), findsOneWidget);

      for (int i = 1; i < kTutorialPages.length; i++) {
        expect(onCard('Next'), findsOneWidget, reason: 'on page $i');
        await tester.tap(onCard('Next'));
        await settle(tester);
        expect(tutorialDots(tester).current, i);
      }

      // The last page has nowhere left to go, so the button changes its name
      // and the way out stops being phrased as a regret.
      expect(onCard('Next'), findsNothing);
      expect(onCard('Skip'), findsNothing);
      expect(onCard('Done'), findsOneWidget);

      await tester.tap(onCard('Done'));
      await settle(tester);
      expect(find.byKey(kTutorial), findsNothing);
    }, variant: harness);

    testWidgets('answer the gesture they are teaching', (
      WidgetTester tester,
    ) async {
      // The point of the thing being pages: the sideways swipe is what the
      // picker and the tray both ask for and the one gesture nothing on screen
      // can advertise, so the tutorial is built out of it.
      await pumpPicker(tester, tutorial: true);

      await tester.drag(tutorialPages, const Offset(-400, 0));
      await settle(tester);
      expect(tutorialDots(tester).current, 1);

      await tester.drag(tutorialPages, const Offset(400, 0));
      await settle(tester);
      expect(tutorialDots(tester).current, 0);

      // And a tapped dot, which is what the picker's own dots do. Scoped to
      // the dots themselves rather than to the card: a page view has
      // recognisers of its own, and counting every [GestureDetector] under the
      // card would be counting those too.
      await tester.tap(
        find
            .descendant(
              of: find.descendant(
                of: find.byKey(kTutorialCard),
                matching: find.byType(PageDots),
              ),
              matching: find.byType(GestureDetector),
            )
            .at(2),
      );
      await settle(tester);
      expect(tutorialDots(tester).current, 2);
    }, variant: harness);

    testWidgets('name every gesture the screens cannot advertise', (
      WidgetTester tester,
    ) async {
      // The assertion worth having about a tutorial is about what it says.
      // Each of these is something the app has no room to explain in place.
      final String all = <String>[
        for (final TutorialPage page in kTutorialPages)
          '${page.title} ${page.body}',
      ].join(' ');

      for (final String phrase in <String>[
        'Swipe the panel', // the two modes
        'swipe sideways', // the three sets, in the tray
        'Shake the phone', // and the button that does it without moving
        'Throw',
        'Draw',
        '+ New', // keeping what is on screen
        'Press and hold', // the menu a profile gives you
        'Roll',
        'Deal',
        'motion control', // and where it is turned off
        'top left',
        'How to use', // and how to get back here
      ]) {
        expect(
          all,
          contains(phrase),
          reason: 'the tutorial never mentions "$phrase"',
        );
      }
    }, variant: harness);
  });

  group('the backdrop', () {
    testWidgets('is the screen the page is about', (WidgetTester tester) async {
      await pumpPicker(tester, tutorial: true);

      // Two pickers behind the tutorial and one under it, and no tray: a live
      // simulation with a haptic in front of it has no business running under
      // a page about the card panel.
      expect(find.byType(PickerScreen), findsNWidgets(3));
      expect(find.byType(TrayScreen), findsNothing);

      await goTo(tester, 4);
      expect(
        find.byType(TrayScreen),
        findsOneWidget,
        reason: 'the page about throwing is said over a tray',
      );

      // And it stays built. Coming back to a page about the picker must not
      // throw the roll away, because going forward again should be the roll
      // you left rather than a new one.
      await goTo(tester, 6);
      expect(find.byType(TrayScreen), findsOneWidget);
    }, variant: harness);

    testWidgets('is lit where the page is pointing, and only there', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester, tutorial: true);
      final Size screen = tester.getSize(find.byKey(kTutorial));

      // Every page names something, and the hole has to be over the copy of it
      // that is actually on screen. That is the whole difficulty: both backdrop
      // pickers build both of their own pages, so there are two racks and two
      // card panels in the tree, and one of each pair is translated a screen
      // width off to the side.
      for (int page = 0; page < kTutorialPages.length; page++) {
        await goTo(tester, page);
        final Key? spot = kTutorialPages[page].spot;
        if (spot == null) continue;

        final Rect? hole = spotOf(tester);
        expect(hole, isNotNull, reason: 'page $page lights nothing');
        expect(
          hole!.left,
          greaterThan(-1),
          reason: 'page $page is lighting the copy that is off screen',
        );
        expect(hole.right, lessThan(screen.width + 1));

        // And it is that widget, rather than merely something on screen: one
        // of the rectangles carrying the page's key, to the point.
        final List<Rect> candidates = <Rect>[
          for (int i = 0; i < find.byKey(spot).evaluate().length; i++)
            tester.getRect(find.byKey(spot).at(i)),
        ];
        expect(
          candidates.any(
            (Rect rect) =>
                (rect.left - hole.left).abs() < 1 &&
                (rect.top - hole.top).abs() < 1 &&
                (rect.width - hole.width).abs() < 1,
          ),
          isTrue,
          reason: 'page $page lights $hole, which is none of $candidates',
        );
      }
    }, variant: harness);

    testWidgets('and the card hangs off its roomier side', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester, tutorial: true);
      final Size screen = tester.getSize(find.byKey(kTutorial));

      for (int page = 0; page < kTutorialPages.length; page++) {
        await goTo(tester, page);
        final Rect? hole = spotOf(tester);
        if (hole == null) continue;
        final Rect card = tester.getRect(find.byKey(kTutorialCard));
        expect(
          card.overlaps(hole),
          isFalse,
          reason: 'page $page covers what it points at: $card over $hole',
        );
        // And it is hung off the roomier side of the hole rather than merely
        // somewhere clear, which is the rule that makes the first one true.
        // The card panel the first page points at lies across the middle of
        // the screen, so a card placed by which half the spot is in would have
        // had nowhere to go — and the tray pages, where a card dropped to the
        // bottom would sit exactly where the dice land, are why it is hung off
        // the hole rather than dropped to the far edge.
        final bool above = hole.top > screen.height - hole.bottom;
        expect(
          above ? card.bottom <= hole.top : card.top >= hole.bottom,
          isTrue,
          reason: 'page $page put the card on the cramped side',
        );
      }
    }, variant: harness);
  });

  group('the menu entry', () {
    testWidgets('is at the bottom, and opens the tutorial again', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      expect(find.byKey(kTutorial), findsNothing);

      await tester.tap(find.byType(AppMenuButton));
      await settle(tester);

      // Last of the three. The two above it are the ones somebody comes to
      // this menu meaning to press; this is the one you reach for when
      // something else has not worked.
      final List<double> tops = <double>[
        for (final String label in <String>['Settings', 'Scan', 'How to use'])
          tester.getTopLeft(find.text(label)).dy,
      ];
      expect(tops[0], lessThan(tops[1]));
      expect(tops[1], lessThan(tops[2]));

      await tester.tap(find.text('How to use'));
      await settle(tester);
      expect(find.byKey(kTutorial), findsOneWidget);
      expect(tutorialDots(tester).current, 0, reason: 'from the beginning');
    }, variant: harness);

    testWidgets('and asking for it a second time starts it over', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      await openFromMenu(tester);
      await tester.tap(onCard('Next'));
      await settle(tester);
      expect(tutorialDots(tester).current, 1);
      await tester.tap(onCard('Skip'));
      await settle(tester);

      await openFromMenu(tester);
      expect(tutorialDots(tester).current, 0);
    }, variant: harness);

    testWidgets('and it never touches what the picker is set to', (
      WidgetTester tester,
    ) async {
      // The backdrop is a picker of the tutorial's own, built from
      // [kTutorialProfile]. The one underneath belongs to the player, and a
      // tour of the app must not be a thing that rearranges it.
      await pumpPicker(tester);
      expect(rackOf(tester), kDefaultDice);

      await openFromMenu(tester);
      await goTo(tester, kTutorialPages.length - 1);
      await tester.tap(onCard('Done'));
      await settle(tester);

      expect(find.byKey(kTutorial), findsNothing);
      expect(rackOf(tester), kDefaultDice);
      expect(profiles.saves, isEmpty);
    }, variant: harness);
  });
}
