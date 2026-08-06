import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tray/tray.dart';

/// What the app remembers between launches.
///
/// One instance, [settings], reached directly rather than handed down through
/// the widget tree. There is exactly one setting and three places that read it,
/// and an inherited widget threaded through the picker, the tray and a modal
/// sheet to carry a single double would be more machinery than the thing it
/// carries.
///
/// It is a [ChangeNotifier] so the sheet that edits it and the tray that obeys
/// it stay in step without either one owning the value.
class Settings extends ChangeNotifier {
  static const String _hapticGainKey = 'haptic.gain';

  double _hapticGain = Tuning.hapticGain;

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

  /// Reads what was stored, if anything was.
  ///
  /// Awaited from `main` before the first frame, so the tray never runs a
  /// throw at the default and then jumps to the stored value mid-roll.
  Future<void> load() async {
    final double? stored = await _guard(() async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_hapticGainKey);
    });
    if (stored == null) return;
    _hapticGain = stored.clamp(0.0, Tuning.hapticMaxGain);
    notifyListeners();
  }

  Future<void> _save() async {
    final double value = _hapticGain;
    await _guard(() async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_hapticGainKey, value);
      return null;
    });
  }

  /// A settings store that is not there is a settings store at its defaults.
  ///
  /// Widget tests and the `tool/` renderers run without the platform channel
  /// behind [SharedPreferences], and a throw from it would fail a test about
  /// something else entirely. Nothing here is worth crashing over: the worst
  /// case is a dial that forgets where it was.
  Future<double?> _guard(Future<double?> Function() body) async {
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
