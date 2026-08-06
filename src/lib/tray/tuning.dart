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

  /// How long the dice sit where they landed before they tidy themselves up.
  ///
  /// Long enough to see the throw finish — the roll is the point, and a tray
  /// that snatches the dice away the instant they stop has hidden the only
  /// part of it that was ever in doubt.
  static const double readoutDelay = 0.25;

  /// How long it takes to put the dice back down where they landed.
  ///
  /// Quicker than the move out. Going out is the reveal and is worth watching;
  /// coming home is tidying away, and a tidy-away that dawdles reads as the app
  /// being slow rather than as the app being careful.
  static const double readoutReturn = 0.35;

  /// How long the move into the reading formation takes.
  static const double readoutDuration = 0.55;

  /// How far the formation tips back from square-on, radians.
  ///
  /// Square on, a die is a polygon: a D6 showing a six is a square with six
  /// dots on it and nothing about it says cube. Fifteen degrees brings the
  /// faces above and beside it into view and costs three percent of the
  /// number's height, which is not a cost anyone can see.
  static const double readoutTilt = 0.26;

  /// How much of the top of the tray the formation keeps clear of, metres.
  ///
  /// The Close and Throw buttons live along the top edge, and on a phone with a
  /// notch they start below a 59-point safe area rather than at the top of the
  /// glass — so they reach about 103 logical points down. 22 mm is 134 of them
  /// at [logicalPixelsPerMetre], which leaves a gap you can see rather than one
  /// that merely exists.
  ///
  /// It only costs anything with a full tray of ten, where it makes the dice
  /// three percent smaller. Fewer than that and the formation is already
  /// life-sized, and this just sits it lower on the screen.
  static const double readoutTopClearance = 0.022;

  /// How long the box takes to slide aside and bring the next group in.
  ///
  /// Half the readout's move, and near enough the third of a second a system
  /// page transition takes: long enough to read as the same box being pushed
  /// sideways rather than a cut, short enough that flicking through three
  /// groups to find the one you want is not a wait.
  static const double traySlideDuration = 0.28;

  /// The dark left between one box and the next as they slide, metres.
  ///
  /// About 49 logical points at [logicalPixelsPerMetre]. Without it the two
  /// linings meet edge to edge and the swipe reads as one long room being
  /// panned across; with it there are plainly two boxes, and the one arriving
  /// is a different tray rather than more of the same one.
  static const double trayPageGap = 0.008;

  /// The quietest wall impact worth feeling, in newton-seconds.
  ///
  /// A safety net rather than the real filter. `PhysicsWorld` has already
  /// thrown away every contact the solver calls resting — anything arriving
  /// slower than 0.12 m/s — and that is the physically correct place to draw
  /// the line, because it is the same line below which there is no bounce.
  /// This one only catches what gets past it, and sets the bottom of the scale.
  ///
  /// The signal is a change of momentum, so the number can be read off a real
  /// die. A 16 mm D6 weighs 4.83 g and die-on-lining restitution comes out at
  /// √(0.38 × 0.28) = 0.33, so a wall takes `m · v · 1.33` off it: 1 mN·s is
  /// that die arriving at 0.16 m/s. Deliberately low enough that every die the
  /// tray actually throws is felt landing — the softest of those, a 1.6 g D4,
  /// still turns up at half as much again.
  static const double hapticFloor = 0.001;

  /// Where the scale tops out, newton-seconds.
  ///
  /// 18 mN·s is the same D6 at 2.8 m/s, and it is set against what the tray
  /// really produces rather than against what it could: a thrown die peaks
  /// somewhere between 2 and 20 mN·s depending on its kind and what it lands
  /// on, and a hard shake of ten tops out around 22. Putting the ceiling at
  /// the hardest *imaginable* hit instead would spend the whole useful range
  /// on the bottom third of the scale and every ordinary throw would feel
  /// identical.
  ///
  /// Heavier dice cross it sooner, and that is the point: every die is the
  /// same width across, so a D12 is five times the mass of a D4 and lands
  /// like it.
  static const double hapticCeiling = 0.018;

  /// Shortest time between two taps, seconds.
  ///
  /// A hand cannot resolve 22 taps a second into separate events and the
  /// actuator cannot produce them — asking anyway turns ten dice landing at
  /// once into one continuous smear. So the loudest impact in each 45 ms wins
  /// and the rest are dropped, which is roughly what a real tray would have
  /// handed you anyway.
  static const double hapticGap = 0.045;

  /// What the calibration slider starts at, and what 1.0 means.
  ///
  /// A multiplier on the impulse before it is weighed against [hapticFloor]
  /// and [hapticCeiling], which is why turning it up does not merely make taps
  /// harder — it lets quieter impacts through the floor at all. Phones differ
  /// enormously here (a Taptic Engine inside a case is a different instrument
  /// from one against a bare palm), and this is not a number anybody else can
  /// pick for you. It is the one piece of tuning the app hands to the player.
  static const double hapticGain = 1.0;

  /// The top of the slider.
  ///
  /// Zero is silent. At three the effective floor is a third of a millinewton-
  /// second, which is below the solver's own resting threshold — so everything
  /// the physics is willing to call an impact at all is felt.
  static const double hapticMaxGain = 3.0;

  /// A mini playing card — 44.5 × 63.5 mm, and the 0.32 mm of stock a real one
  /// is printed on.
  ///
  /// Mini rather than poker size for the same reason the dice are 16 mm: it is
  /// a real thing, and it is the real thing that fits. A 63 mm poker card in a
  /// 64 mm tray would touch both walls.
  static const double cardWidth = 0.0445;
  static const double cardHeight = 0.0635;
  static const double cardThickness = 0.00032;

  /// How far a drawn card is lifted off the floor of the tray.
  ///
  /// The only number either card position needs. The pile stands in the middle
  /// of the back wall and a drawn card lies along the bottom of the glass, and
  /// both of those come out of the tray's own measurements — a height that
  /// looked right on one phone would be somewhere else on another.
  ///
  /// A fifth of a card clear of the floor rather than the three millimetres of
  /// clearance it started as. Three was enough to stop the card looking cut off
  /// by the bottom edge and no more, which left it sitting on the very bottom
  /// of the glass with the whole pile stacked above it; carried up by a fifth
  /// of its own height the card sits where a dealt card sits, in the near half
  /// of the table with the deck behind and above it, and it still covers only
  /// the bottom of the pile.
  static const double cardFloorGap = 0.0157;
}
