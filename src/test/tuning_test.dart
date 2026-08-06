import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/tray/tray.dart';

/// The agreed feel, pinned.
///
/// These numbers were settled by shaking a phone, which is the only way they
/// could have been settled — so they are not derivable from anything in the
/// repository and nothing else will notice if they drift. Changing one should
/// be a decision, so changing one breaks this test.
///
/// **To change a value: change it here too, in the same edit.** That is the
/// whole ceremony. This test exists to make the change deliberate, not to make
/// it hard.
void main() {
  test('the tuning is the agreed tuning', () {
    // The tray.
    expect(Tuning.trayDepth, 0.20, reason: '20 cm deep');
    expect(Tuning.logicalPixelsPerMetre, 6100.0);
    expect(Tuning.eyeDistance, 0.32, reason: 'real reading distance');

    // The feel — the two that were tuned by hand, and hardest to re-derive.
    expect(
      Tuning.gravityScale,
      0.6,
      reason: 'dice fall at 0.6 g; shakes still land at full force',
    );
    expect(Tuning.timeScale, 0.85, reason: 'same arcs, replayed at 0.85 speed');

    // The dice: a real 16 mm acrylic D6, bevelled like a real one.
    expect(Tuning.dieSize, 0.016);
    expect(Tuning.dieBevel, 0.0013);
    expect(Tuning.dieDensity, 1180.0);
    expect(Tuning.dieRestitution, 0.38);
    expect(Tuning.dieFriction, 0.42);

    // The throw: hard enough off the top of the tray to bounce off the floor.
    expect(
      Tuning.throwSpeed,
      2.0,
      reason: 'reaches the floor at about 2.3 m/s',
    );
    expect(Tuning.throwSpin, 8.0, reason: 'tumbles on the way down');

    // The tray lining, and the glass you look through.
    expect(Tuning.wallRestitution, 0.28);
    expect(Tuning.wallFriction, 0.5);
    expect(Tuning.glassRestitution, 0.4);
    expect(Tuning.glassFriction, 0.08);

    // The readout: what the dice do once they have stopped.
    expect(
      Tuning.readoutDelay,
      0.25,
      reason: 'a beat where they landed before they tidy up',
    );
    expect(Tuning.readoutDuration, 0.55);
    expect(Tuning.readoutReturn, 0.35, reason: 'and back down again, quicker');
    expect(
      Tuning.readoutTilt,
      0.26,
      reason: '15 degrees back — readable, but still a solid',
    );
    expect(
      Tuning.readoutTopClearance,
      0.022,
      reason: 'clear of the Close and Throw buttons',
    );

    // Swiping from one group of dice to the next.
    expect(
      Tuning.traySlideDuration,
      0.28,
      reason: 'the same box pushed sideways, not a cut',
    );
    expect(
      Tuning.trayPageGap,
      0.008,
      reason: '8 mm of dark, so there are plainly two boxes',
    );

    // The haptics, in newton-seconds of wall impact. Settled the same way as
    // the rest — with a phone in one hand — but bracketed by what the tray
    // actually produces, which the test below checks has not moved out from
    // under them.
    expect(
      Tuning.hapticFloor,
      0.001,
      reason: 'a 4.8 g D6 at 0.16 m/s; below every die the tray throws',
    );
    expect(
      Tuning.hapticCeiling,
      0.018,
      reason: 'the same die at 2.8 m/s; a hard landing, not an impossible one',
    );
    expect(Tuning.hapticGap, 0.045, reason: 'at most 22 taps a second');
    expect(Tuning.hapticGain, 1.0);
    expect(Tuning.hapticMaxGain, 3.0);
  });

  test('the haptic scale still brackets what the tray can produce', () {
    // Independent of the numbers above, and the reason they are what they are.
    // A thrown 16 mm D6 arrives at the floor at around 2.3 m/s and keeps a
    // third of it, so the wall takes `m · v · (1 + e)` off it. If the die, the
    // lining or the throw is ever retuned, this is what notices that the
    // haptic scale no longer covers the range it is supposed to describe.
    final double mass =
        Tuning.dieSize * Tuning.dieSize * Tuning.dieSize * Tuning.dieDensity;
    final double bounce =
        1 + math.sqrt(Tuning.dieRestitution * Tuning.wallRestitution);
    final double landing = mass * 2.3 * bounce;

    expect(
      landing,
      greaterThan(Tuning.hapticFloor),
      reason: 'a thrown die must be felt landing',
    );
    expect(
      landing,
      lessThan(Tuning.hapticCeiling),
      reason: 'an ordinary throw must leave headroom above it',
    );

    // Cards, for the mode that deals a roll instead of throwing one.
    expect(Tuning.cardWidth, 0.0445, reason: 'a mini card, and it fits');
    expect(Tuning.cardHeight, 0.0635);
    expect(Tuning.cardThickness, 0.00032, reason: 'real card stock');
    expect(Tuning.cardFloorGap, 0.0157, reason: 'a drawn card, off the floor');
    expect(Tuning.dealDuration, 0.45, reason: 'a hand putting a card down');
    expect(Tuning.dealTurn, 0.78, reason: 'over before it lands');
  });

  test('a 16 mm acrylic die still weighs what one weighs', () {
    // Independent of the constants above: if someone changes the size or the
    // density, this is the sanity check that the die is still a die.
    final double volume = Tuning.dieSize * Tuning.dieSize * Tuning.dieSize;
    final double grams = volume * Tuning.dieDensity * 1000;
    expect(grams, closeTo(4.8, 0.3), reason: 'a 16 mm D6 weighs about 4.8 g');
  });
}
