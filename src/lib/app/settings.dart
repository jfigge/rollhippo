import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tray/tray.dart';

/// What the app remembers between launches.
///
/// One instance, [settings], reached directly rather than handed down through
/// the widget tree. There are four settings and a flag, and a handful of
/// places that read them; an inherited widget threaded through the picker, the
/// tray and a modal sheet to carry a double and four bools would be more
/// machinery than the thing it carries.
///
/// It is a [ChangeNotifier] so the sheet that edits it and the tray that obeys
/// it stay in step without either one owning the value.
class Settings extends ChangeNotifier {
  static const String _hapticGainKey = 'haptic.gain';
  static const String _motionKey = 'motion.enabled';
  static const String _shakeDrawKey = 'cards.shake';
  static const String _timerKey = 'timer.enabled';
  static const String _limitKey = 'timer.limit';
  static const String _tutorialKey = 'tutorial.seen';

  double _hapticGain = Tuning.hapticGain;

  bool _motion = true;

  bool _shakeToDraw = false;

  bool _timer = false;

  int _limit = 0;

  bool _tutorialSeen = false;

  /// The calibration multiplier applied to every wall impact. See
  /// [Tuning.hapticGain]; zero is off.
  double get hapticGain => _hapticGain;

  set hapticGain(double value) {
    final double clamped = value.clamp(0.0, Tuning.hapticMaxGain);
    if (clamped == _hapticGain) return;
    _hapticGain = clamped;
    notifyListeners();
    unawaited(_save());
  }

  /// Whether the phone's own movement drives the tray.
  ///
  /// On — which is the whole point of the app — the box is simulated in the
  /// phone's frame of reference: tilting pours the dice down the screen and
  /// shaking throws them. Off, the tray is handed a phone held perfectly
  /// still: gravity points down the screen and stays there, a shake does
  /// nothing, and the buttons along the top are the only way to roll or deal.
  ///
  /// It is a real setting rather than an accessibility afterthought. A phone
  /// on a table, a hand that cannot shake one, a game being played on a train
  /// — all of them want the dice and none of them wants the accelerometer.
  bool get motion => _motion;

  set motion(bool value) {
    if (value == _motion) return;
    _motion = value;
    notifyListeners();
    unawaited(_save());
  }

  /// Whether a shake deals a card, on the card table only.
  ///
  /// **Off**, and off is the default, which is the one setting here that does
  /// not simply mirror what the app used to do. A shake on the tray and a
  /// shake on the card table are not the same kind of act. Shaking dice is the
  /// simulation — the accelerometer is gravity, the dice tumble because the
  /// box moved, and a throw you did not mean is undone by throwing again. A
  /// shoe has memory. Dealing a card takes it off the shoe for good, `spent`
  /// goes up, and what is left to come has genuinely changed — which is the
  /// whole reason to play with a shoe rather than dice, and the whole reason
  /// an accidental one cannot be waved away. A phone handed across a table is
  /// a shake, and half a dozen of them is half a dozen cards nobody drew.
  ///
  /// So the gesture is still there for anyone who wants it, and it is asked
  /// for rather than assumed. It means nothing while [motion] is off — a
  /// still phone is never shaken — which is why the sheet draws it underneath
  /// that switch rather than beside it.
  bool get shakeToDraw => _shakeToDraw;

  set shakeToDraw(bool value) {
    if (value == _shakeToDraw) return;
    _shakeToDraw = value;
    notifyListeners();
    unawaited(_save());
  }

  /// Whether a clock counting up from the last roll is drawn along the top.
  ///
  /// **Off**, because the app's whole job is to answer a question and get out
  /// of the way, and a clock that nobody asked for is a second thing on the
  /// screen moving while you are trying to read a number off the first. Turned
  /// on it sits between Close and Throw and says how long since the last
  /// throw — or, on the card table, since the last card — in minutes and
  /// seconds.
  ///
  /// It measures, and that is all it does. Nothing counts down, nothing runs
  /// out, and nothing on either screen behaves differently for it being there:
  /// a game with a turn limit keeps the limit in the players' heads and this
  /// only saves somebody having to watch a second phone.
  ///
  /// Read where it is drawn rather than obeyed further down, which is the
  /// opposite of what [motion] does and is right for the same reason it is
  /// wrong there. Motion changes what the tray *is handed*, so it belongs in
  /// the source; this changes nothing but whether one widget is built.
  bool get timer => _timer;

  set timer(bool value) {
    if (value == _timer) return;
    _timer = value;
    notifyListeners();
    unawaited(_save());
  }

  /// How long a turn is allowed to run, in seconds, or zero for no limit.
  ///
  /// **Zero**, which is off, and a limit is a thing you have to ask for twice:
  /// it lives under [timer] and means nothing while that is off, because what
  /// it does when it runs out is turn a clock red and a clock nobody is
  /// showing cannot go red. The same nesting Shake to deal has under [motion],
  /// for the same reason.
  ///
  /// Between 30 seconds and 5 minutes in quarter-minutes, which is
  /// [kLimitSteps] positions of a slider and not a free number. A turn limit
  /// is a thing people agree on out loud — "about a minute each" — and it is
  /// never 47 seconds; the notches are what make it settable by dragging
  /// rather than typing. Anything outside that range is a different feature: a
  /// ten-second limit is a buzzer, and a twenty-minute one is not a limit
  /// anybody is watching a phone for.
  ///
  /// What happens when it passes is in `TimeUpAlert` and [ElapsedTimer]: the
  /// screen flashes three times, the phone taps three times with it, and the
  /// clock goes red and stays red until the next roll. Nothing is prevented.
  /// The app has no opinion about whose turn it is and does not acquire one
  /// here — it says the time is up, and what that costs is between the people
  /// playing.
  int get limit => _limit;

  set limit(int value) {
    final int clamped = _clampLimit(value);
    if (clamped == _limit) return;
    _limit = clamped;
    notifyListeners();
    unawaited(_save());
  }

  /// Whether anybody has been shown the tutorial on this phone.
  ///
  /// False is a first run, and a first run is the one launch that puts
  /// something in front of the picker before you have asked for anything. It
  /// is read in exactly one place — `main`, which hands the answer to
  /// [PickerScreen] rather than letting the picker decide for itself, because
  /// a tool rendering that screen into a PNG and a test pumping it are not
  /// launches and must not be treated as one.
  ///
  /// Written by `showTutorial`, whichever of the two ways it was reached.
  /// There is no way back to false and there is deliberately no switch for it:
  /// the tutorial is in the app menu, at the bottom, and asking for it again
  /// is one tap.
  bool get tutorialSeen => _tutorialSeen;

  set tutorialSeen(bool value) {
    if (value == _tutorialSeen) return;
    _tutorialSeen = value;
    notifyListeners();
    unawaited(_save());
  }

  /// Reads what was stored, if anything was.
  ///
  /// Awaited from `main` before the first frame, so the tray never runs a
  /// throw at the default and then jumps to the stored value mid-roll.
  Future<void> load() async {
    final SharedPreferences? prefs = await _guard<SharedPreferences>(
      SharedPreferences.getInstance,
    );
    if (prefs == null) return;
    final double? gain = prefs.getDouble(_hapticGainKey);
    if (gain != null) _hapticGain = gain.clamp(0.0, Tuning.hapticMaxGain);
    _motion = prefs.getBool(_motionKey) ?? true;
    // Off unless somebody said otherwise, which includes every phone that had
    // the app before this setting existed. That is deliberate: a build that
    // silently kept dealing on a shake for the people who already had it would
    // be leaving the bug in place for exactly the players most likely to hit
    // it. It is one switch away for anyone who misses it.
    _shakeToDraw = prefs.getBool(_shakeDrawKey) ?? false;
    // Off unless asked for, on a phone that has never been asked and on one
    // that had the app before there was a clock to ask about. The screen is
    // the dice; anything else on it is there because somebody wanted it.
    _timer = prefs.getBool(_timerKey) ?? false;
    // Off, and clamped rather than trusted for the same reason the gain is:
    // what is in the file was written by some build of this app, and the range
    // is this build's business.
    _limit = _clampLimit(prefs.getInt(_limitKey) ?? 0);
    // A phone with nothing written for this has never been shown the
    // tutorial — which is true both of a genuine first run and of a launch
    // after the preferences file has been thrown away, and offering it again
    // is the right answer to both.
    _tutorialSeen = prefs.getBool(_tutorialKey) ?? false;
    notifyListeners();
  }

  Future<void> _save() async {
    final double gain = _hapticGain;
    final bool motion = _motion;
    final bool shake = _shakeToDraw;
    final bool timer = _timer;
    final int limit = _limit;
    final bool tutorial = _tutorialSeen;
    await _guard<void>(() async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_hapticGainKey, gain);
      await prefs.setBool(_motionKey, motion);
      await prefs.setBool(_shakeDrawKey, shake);
      await prefs.setBool(_timerKey, timer);
      await prefs.setInt(_limitKey, limit);
      await prefs.setBool(_tutorialKey, tutorial);
    });
  }

  /// The nearest limit this build will actually hold: off, or one of the
  /// notches. A number from somewhere else — an older build, a newer one, a
  /// hand-edited preferences file — is rounded onto the scale rather than
  /// kept, so a slider is never showing a position it does not have.
  int _clampLimit(int value) =>
      value <= 0 ? 0 : limitForStep(stepForLimit(value));

  /// A settings store that is not there is a settings store at its defaults.
  ///
  /// Widget tests and the `tool/` renderers run without the platform channel
  /// behind [SharedPreferences], and a throw from it would fail a test about
  /// something else entirely. Nothing here is worth crashing over: the worst
  /// case is a dial that forgets where it was.
  Future<T?> _guard<T>(Future<T?> Function() body) async {
    try {
      return await body();
    } on Exception catch (error) {
      debugPrint('Roll Hippo: settings unavailable ($error)');
      return null;
    }
  }
}

/// How many notches [Settings.limit] has above zero.
///
/// Nineteen: 30 seconds to 5 minutes, every 15 seconds. Step 0 is off, which
/// makes twenty positions on the slider.
const int kLimitSteps = 19;

/// The seconds at slider position [step], or zero for off.
///
/// `15 + 15 × step`, so step 1 is 30 seconds and step 19 is 300. Written as
/// arithmetic rather than a table because the table would be the arithmetic
/// with nineteen chances to mistype it.
int limitForStep(int step) =>
    step <= 0 ? 0 : 15 + 15 * step.clamp(1, kLimitSteps);

/// Which position of the slider [seconds] is, rounding to the nearest notch.
int stepForLimit(int seconds) =>
    seconds <= 0 ? 0 : ((seconds - 15) / 15).round().clamp(1, kLimitSteps);

/// The settings.
final Settings settings = Settings();
