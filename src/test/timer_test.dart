import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// `tray_screen.dart` re-exports the chrome, which is where [ElapsedTimer],
// [kElapsedTimer] and [formatElapsed] live.
import 'package:rollhippo/app/card_screen.dart';
import 'package:rollhippo/app/haptics.dart';
import 'package:rollhippo/app/settings.dart';
import 'package:rollhippo/app/tray_screen.dart';
import 'package:rollhippo/tray/tray.dart';

/// One plain die, twice over, which is all either screen needs to have
/// something to time.
const DieSpec white = DieSpec(kind: DieKind.d6, colour: kDiceWhite);

/// Every case here runs as macOS, which is the harness path: the tray is
/// handed the synthetic phone rather than reaching for an accelerometer a
/// test machine does not have, and space is a shake.
final TargetPlatformVariant harness = TargetPlatformVariant.only(
  TargetPlatform.macOS,
);

/// Puts the settings where a case wants them, and back afterwards. [settings]
/// is one object for the whole run, and both screens read these at build.
void withTimer(bool on, {int limit = 0}) {
  final bool was = settings.timer;
  final int wasLimit = settings.limit;
  addTearDown(() {
    settings.timer = was;
    settings.limit = wasLimit;
  });
  settings.timer = on;
  settings.limit = limit;
}

/// The colour the clock is drawn in.
Color inkOf(WidgetTester tester) =>
    tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(kElapsedTimer),
            matching: find.byType(Text),
          ),
        )
        .style!
        .color!;

/// How far through a flash the screen is, as the wash's alpha. Zero between
/// alerts, and zero if the alert is not on this screen at all.
double washOf(WidgetTester tester) {
  final Iterable<ColoredBox> boxes = tester.widgetList<ColoredBox>(
    find.descendant(
      of: find.byType(TimeUpAlert),
      matching: find.byType(ColoredBox),
    ),
  );
  return boxes.isEmpty ? 0 : boxes.first.color.a;
}

/// What the clock says, or null if it is drawing nothing — which is what an
/// unthrown group and a bare glass both come out as.
String? clockOf(WidgetTester tester) {
  final Iterable<Text> texts = tester.widgetList<Text>(
    find.descendant(of: find.byKey(kElapsedTimer), matching: find.byType(Text)),
  );
  return texts.isEmpty ? null : texts.first.data;
}

/// The same, as a number of seconds.
int? secondsOf(WidgetTester tester) {
  final String? label = clockOf(tester);
  if (label == null) return null;
  final List<String> parts = label.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// Runs a screen for at least [seconds] of real time, a frame at a time.
///
/// A frame at a time and not one long pump, because both tickers clamp `dt` to
/// a thirtieth of a second — a frame longer than that was a hitch rather than a
/// slow frame, and feeding the real number in would teleport the dice. So one
/// two-second pump advances the clock by 33 ms, and only a real sixty-odd
/// frames advance it by a real second: sixteen milliseconds is not a sixtieth,
/// and 60 of them are 0.96 s, which is the wrong side of every whole second
/// this file asserts on.
Future<void> run(WidgetTester tester, double seconds) async {
  for (int i = 0; i < (seconds / 0.016).ceil(); i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> openTray(WidgetTester tester, {int groups = 1}) async {
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

Future<void> openCards(
  WidgetTester tester, {
  int dice = 1,
  int reshuffleAt = 0,
}) async {
  await tester.binding.setSurfaceSize(kHarnessScreen);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: CardScreen(dice: dice, decks: 1, reshuffleAt: reshuffleAt),
    ),
  );
  await tester.pump();
}

/// Puts a recorder in front of the phone's actuator for one test. The alert's
/// taps go through [uiHaptic] rather than a [HapticEngine] — there is no
/// impulse behind a turn running out to weigh.
RecordedHaptics recordHaptics() {
  final RecordedHaptics driver = RecordedHaptics();
  debugUiHaptics = driver;
  addTearDown(() => debugUiHaptics = null);
  return driver;
}

void main() {
  group('the notches a limit has', () {
    test('are 30 seconds to 5 minutes, every 15', () {
      expect(limitForStep(0), 0, reason: 'the bottom of the slider is off');
      expect(limitForStep(1), 30);
      expect(limitForStep(2), 45);
      expect(limitForStep(kLimitSteps), 300);
      // Nothing between the notches, and nothing outside them.
      for (int step = 1; step <= kLimitSteps; step++) {
        expect(limitForStep(step) % 15, 0);
        expect(limitForStep(step), inInclusiveRange(30, 300));
      }
    });

    test('and a number from anywhere else lands on one of them', () {
      // What is in the preferences file was written by some build of this
      // app, and the range is this build's business.
      expect(stepForLimit(0), 0);
      expect(stepForLimit(30), 1);
      expect(stepForLimit(300), kLimitSteps);
      expect(stepForLimit(38), 2, reason: 'the nearest notch, not the floor');
      expect(stepForLimit(9999), kLimitSteps);
      expect(stepForLimit(-5), 0);
    });

    test('and the setting itself refuses anything off the scale', () {
      final Settings fresh = Settings();
      expect(fresh.limit, 0, reason: 'a limit is asked for, never assumed');
      fresh.limit = 9999;
      expect(fresh.limit, 300);
      fresh.limit = 38;
      expect(fresh.limit, 45);
      fresh.limit = -1;
      expect(fresh.limit, 0);
    });
  });

  group('m:ss', () {
    test('pads the seconds and does not pad the minutes', () {
      expect(formatElapsed(0), '0:00');
      expect(formatElapsed(7), '0:07');
      expect(formatElapsed(59), '0:59');
      expect(formatElapsed(60), '1:00');
      expect(formatElapsed(61), '1:01');
      expect(formatElapsed(629), '10:29');
    });

    test('counts past the hour rather than wrapping at it', () {
      // A turn that has genuinely run to sixty-three minutes is better said as
      // 63:00 than as 3:00, which is a different answer rather than a shorter
      // one. Nothing here is a clock face.
      expect(formatElapsed(3600), '60:00');
      expect(formatElapsed(3780), '63:00');
    });
  });

  group('off, which is the default', () {
    testWidgets('the tray draws no clock at all', (WidgetTester tester) async {
      withTimer(false);
      await openTray(tester);
      await run(tester, 2);

      expect(find.byKey(kElapsedTimer), findsNothing);
      // And the two buttons are laid out exactly as they always were: first at
      // one end, last at the other.
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Throw'), findsOneWidget);
    }, variant: harness);

    testWidgets('and neither does the card table', (WidgetTester tester) async {
      withTimer(false);
      await openCards(tester);
      await tester.tap(find.text('Draw'));
      await run(tester, 2);

      expect(find.byKey(kElapsedTimer), findsNothing);
    }, variant: harness);
  });

  group('the tray clock', () {
    testWidgets('starts at 0:00 on the group you arrive on, and counts', (
      WidgetTester tester,
    ) async {
      withTimer(true);
      await openTray(tester);

      // The group you arrive on arrives thrown — the picker's Roll is what
      // threw it — so it is being timed from the first frame with a `dt` in
      // it. A bare `pump()` is not one of those: it advances the clock by
      // nothing, and the tray's ticker takes no notice of a frame that took
      // no time.
      await run(tester, 0.1);
      expect(clockOf(tester), '0:00');

      await run(tester, 2.08);
      expect(clockOf(tester), '0:02');
    }, variant: harness);

    testWidgets('sits between Close and Throw', (WidgetTester tester) async {
      withTimer(true);
      await openTray(tester);
      await run(tester, 1);

      final double clock = tester.getCenter(find.byKey(kElapsedTimer)).dx;
      expect(clock, greaterThan(tester.getRect(find.text('Close')).right));
      expect(clock, lessThan(tester.getRect(find.text('Throw')).left));

      // On the buttons' own line rather than under them, which is the whole
      // reason it can go there: the dice settle along the bottom edge.
      expect(
        tester.getCenter(find.byKey(kElapsedTimer)).dy,
        closeTo(tester.getCenter(find.text('Throw')).dy, 12),
      );
    }, variant: harness);

    testWidgets('Throw puts it back to 0:00', (WidgetTester tester) async {
      withTimer(true);
      await openTray(tester);
      await run(tester, 2.08);
      expect(clockOf(tester), '0:02');

      // Zeroed under the thumb rather than a frame later, so this is asserted
      // before anything is pumped.
      await tester.tap(find.text('Throw'));
      await tester.pump();
      expect(clockOf(tester), '0:00');
    }, variant: harness);

    testWidgets('and so does a shake, which is the same throw', (
      WidgetTester tester,
    ) async {
      withTimer(true);
      await openTray(tester);
      await run(tester, 2.08);
      expect(clockOf(tester), '0:02');

      // A shake on a group already thrown never reaches `throwDice` — the
      // accelerometer scatters the dice itself. It is still the roll, and the
      // clock has to be counting from it rather than from the last tap.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await run(tester, 1);
      expect(secondsOf(tester), lessThan(2));
    }, variant: harness);
  });

  group('a turn running out', () {
    testWidgets('turns the clock red at the limit, and not before', (
      WidgetTester tester,
    ) async {
      withTimer(true, limit: 30);
      await openTray(tester);
      await run(tester, 2.08);

      expect(clockOf(tester), '0:02');
      expect(inkOf(tester), isNot(kTimeUpInk), reason: 'there is time left');

      await run(tester, 28.1);
      expect(secondsOf(tester), greaterThanOrEqualTo(30));
      expect(inkOf(tester), kTimeUpInk);

      // And it stays red — the clock goes on counting up past the limit
      // rather than down towards it, because how far over a turn has run is
      // the useful number.
      await run(tester, 3);
      expect(inkOf(tester), kTimeUpInk);
      expect(secondsOf(tester), greaterThan(30));
    }, variant: harness);

    testWidgets('flashes the screen three times as it goes', (
      WidgetTester tester,
    ) async {
      withTimer(true, limit: 30);
      await openTray(tester);
      await run(tester, 2);
      expect(washOf(tester), 0, reason: 'nothing has run out yet');

      // Up to just short of the limit, then a frame at a time across it and
      // through the whole alert, counting the times the wash comes up and
      // goes down again.
      await run(tester, 27.5);
      int peaks = 0;
      bool rising = false;
      double last = washOf(tester);
      for (int i = 0; i < 110; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final double now = washOf(tester);
        if (now > last + 1e-6) {
          rising = true;
        } else if (now < last - 1e-6 && rising) {
          peaks++;
          rising = false;
        }
        last = now;
      }
      expect(peaks, 3, reason: 'three flashes, and three is the whole signal');
      expect(washOf(tester), 0, reason: 'and it ends on the screen it began');
    }, variant: harness);

    testWidgets('taps three times in step with the flashes', (
      WidgetTester tester,
    ) async {
      withTimer(true, limit: 30);
      final double wasGain = settings.hapticGain;
      addTearDown(() => settings.hapticGain = wasGain);
      settings.hapticGain = Tuning.hapticGain;
      final RecordedHaptics taps = recordHaptics();

      await openTray(tester);
      await run(tester, 31);

      // Heavier than anything a press fires, because this is the app saying
      // something nobody asked about — see [uiHaptic].
      expect(taps.fired, <HapticLevel>[
        HapticLevel.heavy,
        HapticLevel.heavy,
        HapticLevel.heavy,
      ]);

      // And once. A limit passed is not a limit passed again on every frame
      // after it.
      await run(tester, 5);
      expect(taps.fired.length, 3);
    }, variant: harness);

    testWidgets('and says nothing at all when the phone is turned down', (
      WidgetTester tester,
    ) async {
      withTimer(true, limit: 30);
      final double wasGain = settings.hapticGain;
      addTearDown(() => settings.hapticGain = wasGain);
      settings.hapticGain = 0;
      final RecordedHaptics taps = recordHaptics();

      await openTray(tester);
      await run(tester, 31);

      // "Off" is a word with one meaning. The flash is still there, which is
      // the point of there being two of them.
      expect(taps.fired, isEmpty);
      expect(inkOf(tester), kTimeUpInk);
    }, variant: harness);

    testWidgets('the next throw puts the colour back with the clock', (
      WidgetTester tester,
    ) async {
      withTimer(true, limit: 30);
      await openTray(tester);
      await run(tester, 31);
      expect(inkOf(tester), kTimeUpInk);

      await tester.tap(find.text('Throw'));
      await tester.pump();
      expect(clockOf(tester), '0:00');
      expect(inkOf(tester), isNot(kTimeUpInk));

      // And the alert is armed again rather than spent.
      await run(tester, 31);
      expect(inkOf(tester), kTimeUpInk);
    }, variant: harness);

    testWidgets('no limit is no colour and no flash, however long it runs', (
      WidgetTester tester,
    ) async {
      withTimer(true);
      await openTray(tester);
      await run(tester, 40);

      expect(secondsOf(tester), greaterThanOrEqualTo(39));
      expect(inkOf(tester), isNot(kTimeUpInk));
      expect(washOf(tester), 0);
    }, variant: harness);

    testWidgets('a limit with the clock switched off does nothing', (
      WidgetTester tester,
    ) async {
      // The setting is nested under Timer and is read through it. A limit
      // whose whole job is to turn a clock red has nothing to turn.
      withTimer(false, limit: 30);
      final double wasGain = settings.hapticGain;
      addTearDown(() => settings.hapticGain = wasGain);
      settings.hapticGain = Tuning.hapticGain;
      final RecordedHaptics taps = recordHaptics();

      await openTray(tester);
      await run(tester, 31);

      expect(find.byKey(kElapsedTimer), findsNothing);
      expect(taps.fired, isEmpty);
      expect(washOf(tester), 0);
    }, variant: harness);

    testWidgets('the card table runs out the same way', (
      WidgetTester tester,
    ) async {
      withTimer(true, limit: 30);
      await openCards(tester);

      // Nothing to run out until a card is on the glass.
      await run(tester, 31);
      expect(clockOf(tester), isNull);

      await tester.tap(find.text('Draw'));
      await tester.pump();
      expect(inkOf(tester), isNot(kTimeUpInk));

      await run(tester, 31);
      expect(inkOf(tester), kTimeUpInk);

      await tester.tap(find.text('Draw'));
      await tester.pump();
      expect(clockOf(tester), '0:00');
      expect(inkOf(tester), isNot(kTimeUpInk));
    }, variant: harness);
  });

  group('a clock per group', () {
    testWidgets('an unthrown group is timing nothing, and says nothing', (
      WidgetTester tester,
    ) async {
      withTimer(true);
      await openTray(tester, groups: 2);
      await run(tester, 4);
      expect(clockOf(tester), isNotNull);

      await tester.dragFrom(const Offset(200, 500), const Offset(-300, 0));
      await run(tester, 1);

      // The dice are lying on the floor of that box, but they are not a
      // result — so 0:00 would be a lie about a throw nobody has made.
      expect(clockOf(tester), isNull);
    }, variant: harness);

    testWidgets('a group that ran out off-screen is red when you reach it', (
      WidgetTester tester,
    ) async {
      withTimer(true, limit: 30);
      await openTray(tester, groups: 2);
      await run(tester, 4);

      // Away to the second group, which nobody has thrown, and wait out the
      // first group's turn from over here.
      await tester.dragFrom(const Offset(200, 500), const Offset(-300, 0));
      await run(tester, 30);
      expect(clockOf(tester), isNull, reason: 'this one has not been thrown');
      expect(washOf(tester), 0, reason: 'a flash is for somebody watching');

      await tester.dragFrom(const Offset(200, 500), const Offset(300, 0));
      await run(tester, 1);
      // Red on arrival: it ran out while you were elsewhere, and the colour is
      // a fact about that group rather than about the moment you looked.
      expect(inkOf(tester), kTimeUpInk);
    }, variant: harness);

    testWidgets('and the group you left keeps its own, still running', (
      WidgetTester tester,
    ) async {
      withTimer(true);
      await openTray(tester, groups: 2);
      await run(tester, 4);

      await tester.dragFrom(const Offset(200, 500), const Offset(-300, 0));
      await run(tester, 3);
      await tester.dragFrom(const Offset(200, 500), const Offset(300, 0));
      await run(tester, 1);

      // Wall-clock, and not simulated time: the box was frozen the whole time
      // it was off screen, which is what keeps its numbers, but how long ago
      // it was thrown is a fact about the room. Seven seconds of pumping and a
      // swipe either way have all passed.
      expect(secondsOf(tester), greaterThanOrEqualTo(7));
    }, variant: harness);
  });

  group('the card clock', () {
    testWidgets('says nothing until a card is on the glass', (
      WidgetTester tester,
    ) async {
      withTimer(true);
      await openCards(tester);
      await run(tester, 2);
      expect(clockOf(tester), isNull);

      await tester.tap(find.text('Draw'));
      await tester.pump();
      expect(clockOf(tester), '0:00');

      await run(tester, 2.08);
      expect(clockOf(tester), '0:02');
    }, variant: harness);

    testWidgets('a reshuffle puts it away rather than restarting it', (
      WidgetTester tester,
    ) async {
      withTimer(true);
      // Six cards and a cut four from the bottom: two draws, and the third ask
      // is the reshuffle itself.
      await openCards(tester, reshuffleAt: 80);

      await tester.tap(find.text('Draw'));
      await run(tester, 1.08);
      await tester.tap(find.text('Draw'));
      await run(tester, 1.08);
      expect(clockOf(tester), '0:01');

      await tester.tap(find.text('Draw'));
      await tester.pump();
      // A full pile and an empty glass. There is no card to be counting since,
      // which is a different thing from a card that arrived just now.
      expect(clockOf(tester), isNull);

      await run(tester, 2);
      expect(clockOf(tester), isNull);
    }, variant: harness);

    testWidgets('sits between Close and Draw', (WidgetTester tester) async {
      withTimer(true);
      await openCards(tester);
      await tester.tap(find.text('Draw'));
      await run(tester, 1);

      final double clock = tester.getCenter(find.byKey(kElapsedTimer)).dx;
      expect(clock, greaterThan(tester.getRect(find.text('Close')).right));
      expect(clock, lessThan(tester.getRect(find.text('Draw')).left));
    }, variant: harness);
  });
}
