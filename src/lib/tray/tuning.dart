/// Everything with a number in it, in one place, in SI units.
///
/// The simulation is metric and life-sized on purpose. A 16 mm die weighing
/// 4.8 g falling under 9.81 m/s² inside a 20 cm box behaves like a 16 mm die
/// because it *is* one, and every constant below can be checked against a real
/// object rather than tuned until it looks about right.
class Tuning {
  /// Logical Flutter pixels per metre of real screen.
  ///
  /// Every modern iPhone lays out at very close to 155 logical points per inch
  /// — a 15 Pro is 393 pt across 64.4 mm, a 15 Pro Max 430 pt across 70.6 mm —
  /// so one constant sizes the tray correctly on all of them without asking the
  /// platform for a physical measurement it does not expose.
  static const double logicalPixelsPerMetre = 6100.0;

  /// Tray depth. Deep enough that the dice have somewhere to go in z, which is
  /// what stops a shake reading as a flat scramble.
  static const double trayDepth = 0.20;

  /// A standard 16 mm casino-size D6.
  ///
  /// This is also the yardstick for every other die in the set: they are all
  /// built to the same *circumradius* as this cube, so a D20 and a D6 are the
  /// same size point-to-point and one spawn grid packs any mixture of them.
  static const double dieSize = 0.016;

  /// Corner bevel on the D6. Real dice are rounded; see [RigidBody] for why
  /// this matters more than its size suggests.
  ///
  /// The other shapes bevel in the same *proportion* rather than by the same
  /// millimetre: a tetrahedron's faces sit far closer to its centre than a
  /// cube's, and 1.3 mm off those would round a D4 nearly to a ball.
  static const double dieBevel = 0.0013;

  /// Cast acrylic, ~1180 kg/m³, so a 16 mm die comes out at 4.8 g — which is
  /// what a 16 mm die weighs. Every other die takes its mass from its own
  /// volume at this density, so a D20 is genuinely heavier than a D4.
  static const double dieDensity = 1180.0;

  static const double dieRestitution = 0.38;
  static const double dieFriction = 0.42;

  /// The tray lining. Deader than the dice, so a die dropped on it does not
  /// pogo, but not so dead that a shake feels like stirring porridge.
  static const double wallRestitution = 0.28;
  static const double wallFriction = 0.5;

  /// The pane you are looking through. Slightly livelier than the lining and
  /// nearly frictionless, so a die that gets thrown forward skates off it
  /// rather than sticking to the glass.
  static const double glassRestitution = 0.4;
  static const double glassFriction = 0.08;

  /// How far the eye sits from the glass. Real reading distance, which makes
  /// the perspective inside the tray the perspective you would actually see.
  static const double eyeDistance = 0.32;

  /// Fraction of real gravity the dice fall under.
  ///
  /// Below 1 the dice hang longer, tumble further per bounce and settle more
  /// slowly — a bigger tray than the phone really is. It scales *only* the
  /// steady pull: a shake still hits with the full force your hand put into it,
  /// exactly as it would on a smaller planet. Turning this down is not the same
  /// as turning the whole field down, which would just make everything slower.
  static const double gravityScale = 0.6;

  /// How fast simulated time runs against real time.
  ///
  /// Below 1 everything is slower without anything moving differently: the
  /// trajectories are identical, just played back at this rate. That is what
  /// separates it from turning gravity down, which changes the shape of the
  /// arcs as well as the pace of them.
  static const double timeScale = 0.85;

  /// Accelerometer magnitude beyond which we call it a shake and wake the dice.
  static const double wakeAcceleration = 12.5;

  /// Sensor readings are clamped here before becoming forces. A dropped phone
  /// or a sensor glitch should not launch the dice into next week.
  static const double maxFieldMagnitude = 70.0;

  /// Downward speed a die leaves the top of the tray with when it is thrown.
  ///
  /// It arrives at the floor at about 2.3 m/s, and at the combined die/lining
  /// restitution that is a rebound of some 25 mm — a sixth of the tray, and a
  /// throw you can watch land rather than a drop. Dice that land on a corner
  /// while spinning bounce less, which is what real ones do too.
  static const double throwSpeed = 2.0;

  /// Random spin put on a thrown die, rad/s about each axis.
  ///
  /// Enough to tumble several times on the way down — which is where a thrown
  /// die's randomness actually comes from — without so much that the corner it
  /// lands on absorbs the whole bounce.
  static const double throwSpin = 8.0;
}
