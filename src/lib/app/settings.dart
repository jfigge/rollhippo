import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tray/tray.dart';

/// What the app remembers between launches.
///
/// One instance, [settings], reached directly rather than handed down through
/// the widget tree. There are three settings and a flag, and a handful of
/// places that read them; an inherited widget threaded through the picker, the
/// tray and a modal sheet to carry a double and three bools would be more
/// machinery than the thing it carries.
///
/// It is a [ChangeNotifier] so the sheet that edits it and the tray that obeys
/// it stay in step without either one owning the value.
class Settings extends ChangeNotifier {
  static const String _hapticGainKey = 'haptic.gain';
  static const String _motionKey = 'motion.enabled';
  static const String _shakeDrawKey = 'cards.shake';
  static const String _tutorialKey = 'tutorial.seen';

  double _hapticGain = Tuning.hapticGain;

  bool _motion = true;

  bool _shakeToDraw = false;

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
    final bool tutorial = _tutorialSeen;
    await _guard<void>(() async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_hapticGainKey, gain);
      await prefs.setBool(_motionKey, motion);
      await prefs.setBool(_shakeDrawKey, shake);
      await prefs.setBool(_tutorialKey, tutorial);
    });
  }

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

/// The settings.
final Settings settings = Settings();
