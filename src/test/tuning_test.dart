import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo2/tray/tray.dart';

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
    expect(Tuning.trayDepth, 0.10, reason: '10 cm deep');
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

    // The tray lining, and the glass you look through.
    expect(Tuning.wallRestitution, 0.28);
    expect(Tuning.wallFriction, 0.5);
    expect(Tuning.glassRestitution, 0.4);
    expect(Tuning.glassFriction, 0.08);
  });

  test('a 16 mm acrylic die still weighs what one weighs', () {
    // Independent of the constants above: if someone changes the size or the
    // density, this is the sanity check that the die is still a die.
    final double volume = Tuning.dieSize * Tuning.dieSize * Tuning.dieSize;
    final double grams = volume * Tuning.dieDensity * 1000;
    expect(grams, closeTo(4.8, 0.3), reason: 'a 16 mm D6 weighs about 4.8 g');
  });
}
