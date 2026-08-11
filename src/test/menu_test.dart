import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/haptics.dart';
import 'package:rollhippo/app/menu.dart';
import 'package:rollhippo/app/page_dots.dart';
import 'package:rollhippo/app/picker_screen.dart';
import 'package:rollhippo/app/profile_row.dart';
import 'package:rollhippo/app/settings.dart';
import 'package:rollhippo/app/tray_screen.dart';
import 'package:rollhippo/motion/motion.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/tray/tray.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The dice one group's rack is showing.
///
/// Scoped to the group's key rather than counted across the tree, because a
/// page view keeps its neighbours built.
List<DieSpec> rackOf(WidgetTester tester, int group) => <DieSpec>[
  for (final DiePreview preview in tester.widgetList<DiePreview>(
    find.descendant(
      of: find.byKey(ValueKey<int>(group)),
      matching: find.byType(DiePreview),
    ),
  ))
    preview.spec,
];

/// Swipes the rack one set to the left, and lets the page view land.
///
/// A [PageView] only builds the page it is showing, so this is the only way to
/// look at what is in the second set.
Future<void> swipeLeft(WidgetTester tester) async {
  await tester.drag(find.byType(PageView), const Offset(-300, 0));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

PageDots dotsOf(WidgetTester tester) =>
    tester.widget<PageDots>(find.byKey(kGroupDots));

/// The two switches in the settings sheet, in the order they are drawn:
/// motion control, and the shake-to-deal that hangs underneath it.
final Finder motionSwitch = find.byType(Switch).first;
final Finder shakeSwitch = find.byType(Switch).at(1);

/// The calibration slider, which is the one inside the sheet — the picker
/// underneath it has a slider of its own for the cut in card mode.
final Finder gainSlider = find.descendant(
  of: find.byType(BottomSheet),
  matching: find.byType(Slider),
);

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(AppMenuButton));
  await tester.pumpAndSettle();
}

/// Puts up the Share sheet for what is on screen, the way a thumb would: hold
/// the dashed profile down and take Share off the menu it gives you.
///
/// The dashed one rather than a save, because these tests are about the code
/// the *picker* produces and nothing here has been saved. A save's own Share
/// sends what that save holds, which `profiles_test.dart` is where to look for.
Future<void> shareCurrent(WidgetTester tester) async {
  await tester.longPress(find.byKey(kNewProfile));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Share'));
  await tester.pumpAndSettle();
}

/// The plus in the first set's rack, which is how a die is added. Scoped to
/// that rack: card mode has one of its own, one screen to the side.
final Finder addDie = find.descendant(
  of: find.byKey(const ValueKey<int>(0)),
  matching: find.byKey(kAddDie),
);

/// The picker, with the settings put back afterwards.
///
/// [settings] is one object for the whole app, so a test that drags the slider
/// leaves it dragged for whatever runs next.
/// Puts a recorder in front of the phone's actuator for the length of one
/// test, and hands it back.
///
/// The interface's taps do not go through a [HapticEngine] — there is no
/// impulse behind a button press to weigh — so there is no engine to hand a
/// driver to. See [uiHaptic].
RecordedHaptics recordHaptics() {
  final RecordedHaptics driver = RecordedHaptics();
  debugUiHaptics = driver;
  addTearDown(() => debugUiHaptics = null);
  return driver;
}

Future<void> pumpPicker(WidgetTester tester) async {
  final double was = settings.hapticGain;
  final bool motion = settings.motion;
  addTearDown(() {
    settings.hapticGain = was;
    settings.motion = motion;
  });
  // Phone-shaped, because the picker is: at the default 800 × 600 the rack is
  // centred inside its [kPickerWidth] cap with 180 points of nothing either
  // side, and every measurement below would be against the window instead of
  // against the screen.
  await tester.binding.setSurfaceSize(kHarnessScreen);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: PickerScreen()));
}

void main() {
  group('the app menu', () {
    testWidgets('is three lines in the top left, and opens', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      final Offset menu = tester.getCenter(find.byType(AppMenuButton));
      expect(
        menu.dy,
        lessThan(tester.getSize(find.byType(PickerScreen)).height / 2),
      );

      await openMenu(tester);
      // Three now: the app, somebody else's phone, and the app explaining
      // itself. `tutorial_test.dart` is where the order of them is held.
      for (final String label in <String>['Settings', 'Scan', 'How to use']) {
        expect(find.text(label), findsOneWidget, reason: '$label is missing');
      }
      // And not the third it used to have. Sharing is about a profile, so it
      // is on the profiles — see the group below, which reaches it from there.
      expect(find.text('Share'), findsNothing);
    });

    testWidgets('sits on the title line, over the rack edge', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      final Rect button = tester.getRect(find.byType(AppMenuButton));
      final Rect title = tester.getRect(find.text('Roll Hippo'));
      final Rect subtitle = tester.getRect(
        find.text('Tap a die to change it. Swipe for another set.'),
      );
      // The slot itself, not the die drawn inside it — the die is inset from
      // the ring so a selected one does not touch it.
      final Rect slot = tester.getRect(
        find
            .descendant(
              of: find.byKey(const ValueKey<int>(0)),
              matching: find.byType(AspectRatio),
            )
            .first,
      );

      // On the title's own line and centred against it, rather than hung off
      // the bottom of a two-line block. The icon is centred in its tap target
      // both ways, so the button's centre is where the strokes are.
      expect(
        button.center.dy,
        closeTo(title.center.dy, 0.01),
        reason: 'the three lines are meant to be level with the R',
      );
      expect(
        button.right,
        lessThanOrEqualTo(title.left),
        reason: 'inline with the title, not on top of it',
      );

      // And one left edge down the whole screen: the strokes, the sentence
      // about the rack, and the rack. Asserted against each other rather than
      // against [kRackEdge], because agreeing is the requirement — the number
      // they agree on is the layout's business.
      expect(slot.left, closeTo(kRackEdge, 0.01));
      expect(
        subtitle.left,
        closeTo(slot.left, 0.01),
        reason: 'the subtitle no longer starts where the rack does',
      );
      expect(
        button.left + kAppMenuInset,
        closeTo(slot.left, 0.01),
        reason: 'the three lines no longer start where the rack does',
      );
    });
  });

  group('the taps the menu makes', () {
    testWidgets('one as it opens, and a lighter one as an entry is taken', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      settings.hapticGain = Tuning.hapticGain;
      final RecordedHaptics taps = recordHaptics();

      await openMenu(tester);
      // The firmer of the two. A menu arriving is the moment nothing else on
      // the screen confirms — see [uiHaptic], where the pair is argued.
      expect(taps.fired, <HapticLevel>[HapticLevel.medium]);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(taps.fired, <HapticLevel>[HapticLevel.medium, HapticLevel.light]);
    });

    testWidgets('and none of them with the calibration turned off', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      settings.hapticGain = 0;
      final RecordedHaptics taps = recordHaptics();

      await openMenu(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // That dial is described against the tray, and it is still the only
      // switch there is: nobody who has turned it down to nothing expects the
      // menus to go on tapping.
      expect(taps.fired, isEmpty);
    });
  });

  group('the settings panel', () {
    testWidgets('the slider is the haptic calibration, and moves it', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      settings.hapticGain = Tuning.hapticGain;

      await openMenu(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Impact strength'), findsOneWidget);
      expect(
        find.text('100%'),
        findsOneWidget,
        reason: 'starts at the default',
      );

      // All the way to the left is off, which is the setting that has to work
      // whatever else does: it is how someone who dislikes the whole feature
      // turns it off.
      await tester.drag(gainSlider, const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(settings.hapticGain, 0.0);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('0%'), findsNothing, reason: 'off is a word, not a sum');

      // And all the way to the right is the top of the scale rather than
      // wherever the drag happened to land.
      await tester.drag(gainSlider, const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(settings.hapticGain, Tuning.hapticMaxGain);
      expect(find.text('300%'), findsOneWidget);
    });
  });

  group('motion control', () {
    testWidgets('is a switch in the settings sheet, and is on to begin with', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      settings.motion = true;

      await openMenu(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Motion control'), findsOneWidget);
      // The first of the two switches. The second is Shake to deal, which
      // lives underneath this one and is the group below.
      expect(tester.widget<Switch>(motionSwitch).value, isTrue);

      await tester.tap(motionSwitch);
      await tester.pumpAndSettle();

      expect(settings.motion, isFalse);
      expect(tester.widget<Switch>(motionSwitch).value, isFalse);
      // And the paragraph under it says what that now means.
      expect(
        find.textContaining('a shake does nothing'),
        findsOneWidget,
        reason: 'the explanation has to follow the switch',
      );
    });

    testWidgets('carries the shake-to-deal switch underneath it', (
      WidgetTester tester,
    ) async {
      final bool was = settings.shakeToDraw;
      addTearDown(() => settings.shakeToDraw = was);
      await pumpPicker(tester);
      settings.motion = true;
      settings.shakeToDraw = false;

      await openMenu(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Shake to deal a card'), findsOneWidget);
      expect(
        tester.widget<Switch>(shakeSwitch).value,
        isFalse,
        reason: 'off is the default, and the point of the setting',
      );
      // Underneath the switch it depends on, not beside it.
      expect(
        tester.getTopLeft(find.text('Shake to deal a card')).dy,
        greaterThan(tester.getTopLeft(find.text('Motion control')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Shake to deal a card')).dx,
        greaterThan(tester.getTopLeft(find.text('Motion control')).dx),
        reason: 'and indented under it, because it is a narrowing of it',
      );

      await tester.tap(shakeSwitch);
      await tester.pumpAndSettle();
      expect(settings.shakeToDraw, isTrue);
    });

    testWidgets('and that switch goes quiet when motion itself is off', (
      WidgetTester tester,
    ) async {
      final bool was = settings.shakeToDraw;
      addTearDown(() => settings.shakeToDraw = was);
      await pumpPicker(tester);
      settings.motion = false;
      settings.shakeToDraw = false;

      await openMenu(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // A still phone is never shaken, so the control has nothing to say.
      // Tapping it does nothing at all rather than setting something that
      // would not take effect.
      await tester.tap(shakeSwitch, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(settings.shakeToDraw, isFalse);
    });

    testWidgets('decides what the screens are driven by', (
      WidgetTester tester,
    ) async {
      final bool was = settings.motion;
      addTearDown(() => settings.motion = was);

      settings.motion = false;
      expect(
        motionSourceFor(device: true, motion: settings.motion),
        isA<StillMotionSource>(),
        reason: 'the phone is told it is lying on a table',
      );
      expect(
        motionSourceFor(device: false, motion: settings.motion),
        isA<StillMotionSource>(),
        reason: 'and so is the harness',
      );

      // A source that never moves is never a shake, whatever it is asked.
      final MotionSource still = motionSourceFor(device: true, motion: false);
      for (int i = 0; i < 120; i++) {
        expect(isShake(still.sample(1 / 60)), isFalse);
      }

      settings.motion = true;
      expect(
        motionSourceFor(device: false, motion: settings.motion),
        isA<ManualMotionSource>(),
      );
    });

    testWidgets('survives a relaunch, because it is how you play', (
      WidgetTester tester,
    ) async {
      final bool was = settings.motion;
      addTearDown(() => settings.motion = was);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      settings.motion = false;
      await tester.pumpAndSettle();

      final Settings relaunched = Settings();
      expect(relaunched.motion, isTrue, reason: 'on, until told otherwise');
      await relaunched.load();
      expect(relaunched.motion, isFalse);
    });
  });

  group('what is remembered', () {
    testWidgets('the calibration survives a relaunch', (
      WidgetTester tester,
    ) async {
      // The whole reason there is a store at all: the number was arrived at by
      // shaking the phone with the sheet open, and asking for it again every
      // launch would waste that.
      final double was = settings.hapticGain;
      addTearDown(() => settings.hapticGain = was);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      settings.hapticGain = 2.25;
      await tester.pumpAndSettle();

      // A fresh Settings is what the next launch gets.
      final Settings relaunched = Settings();
      expect(relaunched.hapticGain, Tuning.hapticGain, reason: 'starts fresh');
      await relaunched.load();
      expect(relaunched.hapticGain, 2.25);
    });

    testWidgets('a store that is not there is one at its defaults', (
      WidgetTester tester,
    ) async {
      // No mock values registered, so the platform channel behind
      // [SharedPreferences] answers nothing at all. That is a dial that
      // forgets where it was, not a crash on the way to the first frame.
      final Settings offline = Settings();
      await offline.load();
      expect(offline.hapticGain, Tuning.hapticGain);
      expect(offline.motion, isTrue);
      offline.hapticGain = 1.5;
      await tester.pumpAndSettle();
      expect(offline.hapticGain, 1.5, reason: 'still works, just forgets');
    });

    testWidgets('shake-to-deal is off on a phone that has never been asked', (
      WidgetTester tester,
    ) async {
      final bool was = settings.shakeToDraw;
      addTearDown(() => settings.shakeToDraw = was);

      // Including a phone that had the app before the setting existed: there
      // is nothing written for the key, and the answer is no. A build that
      // silently kept dealing on a shake for those players would be leaving
      // the bug where it was for the people most likely to meet it.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final Settings fresh = Settings();
      expect(fresh.shakeToDraw, isFalse);
      await fresh.load();
      expect(fresh.shakeToDraw, isFalse);

      settings.shakeToDraw = true;
      await tester.pumpAndSettle();
      final Settings relaunched = Settings();
      await relaunched.load();
      expect(relaunched.shakeToDraw, isTrue, reason: 'asked for, and kept');
    });

    testWidgets('a stored value from another build is clamped, not trusted', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'haptic.gain': 99.0,
      });
      final Settings loaded = Settings();
      await loaded.load();
      expect(loaded.hapticGain, Tuning.hapticMaxGain);
    });
  });

  group('the share sheet', () {
    testWidgets('shows a code for the dice that are actually in the picker', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await shareCurrent(tester);

      final ShareCodeView qr = tester.widget<ShareCodeView>(
        find.byType(ShareCodeView),
      );
      // What the picker starts with: one set of two white D6s, on the dice
      // page, and no name — nothing has been saved.
      final ScannedProfile read = decodeProfile(qr.code)!;
      expect(read.name, isEmpty);
      expect(read.profile.mode, ProfileMode.dice);
      expectSame(read.profile.groups, <List<DieSpec>>[
        List<DieSpec>.of(kDefaultDice),
        <DieSpec>[],
        <DieSpec>[],
      ]);
      // And the whole of it, in one line, because a profile has value equality.
      // This is the constant `+ New` puts the picker back to, so it is also
      // what holds the two together: what the app opens at *is* a new profile.
      expect(read.profile, kDefaultProfile);
      expect(find.text('2 dice'), findsOneWidget);
    });

    testWidgets('follows the picker rather than the defaults', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);
      await tester.tap(addDie);
      await tester.pump();
      await tester.tap(find.text('D20'));
      await tester.pump();

      await shareCurrent(tester);

      final ShareCodeView qr = tester.widget<ShareCodeView>(
        find.byType(ShareCodeView),
      );
      final List<List<DieSpec>> coded = decodeProfile(qr.code)!.profile.groups;
      expect(coded[0].length, 3);
      expect(coded[0].last.kind, DieKind.d20);
      expect(find.text('3 dice'), findsOneWidget);
    });
  });

  group('a scanned code', () {
    testWidgets('replaces every set, and puts you on the first', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      // What is driven here is the seam the scanner pops back through, which
      // is the part with the picker's own limits in it and the part that can
      // be got wrong. The screen in front of it is somebody else's test —
      // `scan_test.dart`, which drives the camera's own callback and needs no
      // camera to do it.
      final AppMenuButton menu = tester.widget<AppMenuButton>(
        find.byType(AppMenuButton),
      );
      menu.onScanned(
        scanned(<List<DieSpec>>[
          <DieSpec>[DieSpec(kind: DieKind.d20, colour: kDicePalette[6])],
          <DieSpec>[
            const DieSpec(kind: DieKind.d4, colour: kDiceWhite),
            DieSpec(kind: DieKind.d8, colour: kDicePalette[2]),
          ],
          <DieSpec>[],
        ]),
      );
      await tester.pumpAndSettle();

      expect(rackOf(tester, 0).length, 1);
      expect(rackOf(tester, 0).single.kind, DieKind.d20);
      expect(
        find.text('Set up from a shared code.'),
        findsOneWidget,
        reason: 'a scan that changes everything has to say that it did',
      );

      // Landing back on the first set is the point of the second half of
      // [_applyScanned]: a code read while looking at the third set would
      // otherwise leave you on a page whose contents just changed under you.
      expect(dotsOf(tester).current, 0);
      expect(dotsOf(tester).filled, <bool>[true, true, false]);

      await swipeLeft(tester);
      expect(rackOf(tester, 1).length, 2);
      expect(rackOf(tester, 1).first.kind, DieKind.d4);
      expect(rackOf(tester, 1).last.kind, DieKind.d8);
    });

    testWidgets('is cut down to what the picker has room for', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      final AppMenuButton menu = tester.widget<AppMenuButton>(
        find.byType(AppMenuButton),
      );
      // A code from some later build: four sets, and twelve dice in the first.
      menu.onScanned(
        scanned(<List<DieSpec>>[
          <DieSpec>[
            for (int i = 0; i < 12; i++)
              const DieSpec(kind: DieKind.d6, colour: kDiceWhite),
          ],
          <DieSpec>[],
          <DieSpec>[],
          <DieSpec>[const DieSpec(kind: DieKind.d12, colour: kDiceWhite)],
        ]),
      );
      await tester.pumpAndSettle();

      expect(
        rackOf(tester, 0).length,
        kMaxDice,
        reason: 'the tray takes ten, so the code loses two',
      );
      expect(find.text('$kMaxDice / $kMaxDice'), findsOneWidget);
    });

    testWidgets('cannot leave the first set empty', (
      WidgetTester tester,
    ) async {
      await pumpPicker(tester);

      final AppMenuButton menu = tester.widget<AppMenuButton>(
        find.byType(AppMenuButton),
      );
      menu.onScanned(
        scanned(<List<DieSpec>>[<DieSpec>[], <DieSpec>[], <DieSpec>[]]),
      );
      await tester.pumpAndSettle();

      expect(
        rackOf(tester, 0),
        isNotEmpty,
        reason: 'the picker has nothing to show you with no first set',
      );
    });
  });
}

/// A code carrying [groups] and nothing else worth saying: the dice page, the
/// shoe at its defaults, and no name on it.
ScannedProfile scanned(List<List<DieSpec>> groups, {String name = ''}) =>
    ScannedProfile(
      name: name,
      profile: Profile(
        mode: ProfileMode.dice,
        groups: groups,
        colours: const <int>[kDiceWhite, kDiceWhite],
        decks: 2,
        reshuffleAt: 5,
      ),
    );

/// Set by set, die by die — which says which set went wrong when one does.
void expectSame(List<List<DieSpec>> got, List<List<DieSpec>> want) {
  expect(got.length, want.length);
  for (int g = 0; g < want.length; g++) {
    expect(got[g].length, want[g].length, reason: 'set $g is the wrong size');
    for (int d = 0; d < want[g].length; d++) {
      expect(got[g][d].kind, want[g][d].kind);
      expect(got[g][d].colour, want[g][d].colour);
    }
  }
}
