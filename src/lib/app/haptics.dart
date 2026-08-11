import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../tray/tray.dart';
import 'chrome.dart';
import 'settings.dart';

/// The impact the calibration slider plays back, in newton-seconds.
///
/// A middling throw: across the six kinds, a die thrown the length of the tray
/// peaks somewhere between 2 and 20 mN·s, and 8 is the middle of that. Not the
/// hardest hit the tray can produce and not the softest — the one you will feel
/// most often, which is the one worth setting the dial against.
///
/// It also happens to be the value that makes the slider sweep all four
/// strengths across its travel, so dragging it is a demonstration of the whole
/// scale rather than of one tap getting marginally firmer.
const double _kDemoImpulse = 0.008;

/// Where each strength starts, as a fraction of the way from
/// [Tuning.hapticFloor] to [Tuning.hapticCeiling].
///
/// Uneven on purpose. The platform's four taps are not evenly spaced in how
/// hard they feel — the gap between light and medium is far wider than the one
/// between a selection tick and light — so the bands that map onto them are not
/// evenly spaced either. Widening the bottom two is what stops an ordinary
/// throw from reading as one long medium.
const List<double> _kBands = <double>[0.25, 0.55, 0.82];

/// The four strengths a phone actually has.
///
/// Not a scale anyone chose: iOS exposes exactly these through
/// [HapticFeedback], with no amplitude parameter, and Android's
/// `performHapticFeedback` is the same shape. A continuously variable tap
/// would mean Core Haptics behind a platform channel — worth doing one day,
/// and the reason [HapticDriver] is an interface rather than four static calls.
///
/// Declaration order is significant: [HapticEngine] compares by [Enum.index] to
/// decide whether an impact is harder than the one still ringing.
enum HapticLevel { selection, light, medium, heavy }

/// Whatever it is that makes the phone buzz.
abstract class HapticDriver {
  void fire(HapticLevel level);
}

/// The real thing.
class SystemHaptics implements HapticDriver {
  const SystemHaptics();

  @override
  void fire(HapticLevel level) {
    // Nothing waits on these. A tap is wanted *now* and its completion tells
    // us nothing we could act on; awaiting one would put a platform-channel
    // round trip inside the frame that produced it.
    switch (level) {
      case HapticLevel.selection:
        unawaited(HapticFeedback.selectionClick());
      case HapticLevel.light:
        unawaited(HapticFeedback.lightImpact());
      case HapticLevel.medium:
        unawaited(HapticFeedback.mediumImpact());
      case HapticLevel.heavy:
        unawaited(HapticFeedback.heavyImpact());
    }
  }
}

/// Nothing at all.
class SilentHaptics implements HapticDriver {
  const SilentHaptics();

  @override
  void fire(HapticLevel level) {}
}

/// Fires nothing and writes down what it was asked for.
class RecordedHaptics implements HapticDriver {
  final List<HapticLevel> fired = <HapticLevel>[];

  @override
  void fire(HapticLevel level) => fired.add(level);

  void clear() => fired.clear();
}

/// What to buzz with on a phone, and what to buzz with anywhere else.
///
/// Only a phone has an actuator. Asking macOS for one throws a
/// `MissingPluginException` into the console for every die that lands, so the
/// harness gets silence — the same bargain `ManualMotionSource` makes for the
/// accelerometer it does not have either. Pass `onDevice`.
HapticDriver hapticsFor({required bool device}) =>
    device ? const SystemHaptics() : const SilentHaptics();

/// What [uiHaptic] fires through, or null for the real thing.
///
/// Resolved at the moment of the tap rather than kept in a field, because
/// [onDevice] reads `defaultTargetPlatform` and a widget test moves that about
/// underneath it. A driver picked once and held would be whatever the first
/// tap in a suite happened to ask for.
@visibleForTesting
HapticDriver? debugUiHaptics;

/// The tap the interface answers a press with.
///
/// Not [HapticEngine], and the difference is what the number behind the tap
/// is. A tray tap is a measurement — `lastWallImpulse`, in newton-seconds,
/// weighed against a floor and four bands — so how hard it feels is derived
/// from something that actually happened. A press has no impulse behind it at
/// all. It is an acknowledgement at a strength somebody chose, and there is
/// nothing here for the gap or the escalation rule to do: two menus cannot
/// open in the same frame, and a menu and the entry taken out of it are two
/// gestures with a whole decision between them.
///
/// Two strengths, and which is which is deliberate. Picking an entry is
/// [HapticLevel.light], because the screen answers you anyway — a sheet
/// opens, a profile is written, something visibly happens. Opening a menu is
/// one step up, because it is the gesture where *nothing else* confirms that
/// the phone understood: a long press has no moment of contact of its own, and
/// the tap under your thumb is what says the press was long enough.
///
/// Silent while [Settings.hapticGain] is off. That dial is calibrated against
/// the tray and says so, and the fractions in between do not scale these —
/// there is no impulse to scale. But "Off" is a word with one meaning, and a
/// phone that went on tapping through every menu after it had been turned down
/// to nothing would read as a bug rather than as a distinction.
void uiHaptic(HapticLevel level) {
  if (settings.hapticGain <= 0) return;
  (debugUiHaptics ?? hapticsFor(device: onDevice)).fire(level);
}

/// Turns wall impacts into taps you can feel.
///
/// One of these per tray screen, fed `PhysicsWorld.lastWallImpulse` once a
/// frame. It owns two decisions: how hard a given impulse should feel, and
/// whether to say anything at all this frame.
class HapticEngine {
  HapticEngine({HapticDriver? driver, double? gain})
    : driver = driver ?? const SilentHaptics(),
      gain = gain ?? Tuning.hapticGain;

  final HapticDriver driver;

  /// The player's calibration. Zero is off; see [Tuning.hapticGain].
  double gain;

  /// Time since the last tap. Starts past the gap so the first impact of a
  /// throw is felt rather than swallowed by a window that never opened.
  double _since = Tuning.hapticGap;

  /// What the last tap was, so an escalation can interrupt it.
  HapticLevel _last = HapticLevel.selection;

  /// How hard [impulse] newton-seconds ought to feel, or null for not at all.
  ///
  /// The gain multiplies the impulse *before* it is weighed against the floor,
  /// which is the difference between a volume knob and a calibration. Turned
  /// up, quieter impacts cross the floor and start registering at all; turned
  /// down, they stop. That is what a player reaching for this control wants —
  /// "I can barely feel it" is nearly always about the small ones.
  HapticLevel? levelFor(double impulse) {
    final double scaled = impulse * gain;
    if (scaled < Tuning.hapticFloor) return null;
    final double t = ((scaled - Tuning.hapticFloor) /
            (Tuning.hapticCeiling - Tuning.hapticFloor))
        .clamp(0.0, 1.0);
    for (int i = 0; i < _kBands.length; i++) {
      if (t < _kBands[i]) return HapticLevel.values[i];
    }
    return HapticLevel.heavy;
  }

  /// One frame's worth of tray: the hardest wall impact in it, and how long it
  /// took. Call it every frame, including the ones where nothing happened —
  /// that is how the gap keeps time.
  void impact(double impulse, double dt) {
    _since += dt;
    if (impulse <= 0) return;

    final HapticLevel? level = levelFor(impulse);
    if (level == null) return;

    // Inside the gap, only a *harder* knock than the one still ringing gets
    // through. The strongest thing happening is the thing you should feel, and
    // holding a heavy hit back because a light one arrived two frames earlier
    // is how a tray of ten dice ends up feeling like a tray of one.
    if (_since < Tuning.hapticGap && level.index <= _last.index) return;

    driver.fire(level);
    _since = 0;
    _last = level;
  }

  /// One tap at the strength an ordinary throw produces, gap ignored.
  ///
  /// What the calibration slider plays as it is dragged. A number is not a
  /// feeling and nobody can set this one by reading it, so the control has to
  /// answer in the currency it is denominated in.
  void demo() {
    final HapticLevel? level = levelFor(_kDemoImpulse);
    if (level == null) return;
    driver.fire(level);
    _since = 0;
    _last = level;
  }
}
