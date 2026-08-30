import 'dart:typed_data';

/// Where a shuffle's seed comes from: the clock, and the noise the phone's own
/// movement makes.
///
/// A [Deck] shuffles with `Random.nextInt` and nothing about the deal is any
/// better than the number that started that stream off. Left to itself
/// `math.Random()` picks one, and what it picks is a fact about the moment the
/// object was made and nothing else — which on a phone is a launch, a tap and
/// a first frame, all of them within a few milliseconds of each other every
/// time. It is a perfectly good stream of numbers arrived at from a very small
/// place, and a shoe deserves better than a small place: what a shoe *is* is
/// the claim that nobody, the dealer included, knows what is left in it.
///
/// So the seed is stirred rather than chosen. Sensor readings go in as the
/// bits they are — an accelerometer at rest still fidgets in the last two or
/// three digits, because it is measuring a real thing with a real converter —
/// and so does the microsecond each one arrived at, which carries the
/// scheduler's own jitter and is there even on a phone lying flat on a table
/// whose readings are quantised to the same handful of values. Then the clock
/// again at the moment a seed is drawn.
///
/// **This is not a cryptographic generator and does not pretend to be one.**
/// The mixing is splitmix64's finaliser, which spreads every bit that goes in
/// across all sixty-four that come out, and that is the whole of what it
/// claims: a seed nobody could have written down in advance, from a pool with
/// real physical noise in it. If a shuffle ever has to be unguessable *by
/// construction* — money on it, another phone watching — the answer is
/// `Random.secure()` and the platform's own generator, not more stirring here.
class EntropyPool {
  /// [clock] is what [stirClock] reads, in microseconds.
  ///
  /// A parameter for one reason: nothing can hold the real clock still, and a
  /// test that cannot hold it still cannot ask whether a *reading* changed
  /// anything — every seed would differ whether the pool was working or not.
  /// The app never passes it.
  EntropyPool({int Function()? clock}) : _clock = clock ?? _microseconds;

  static int _microseconds() => DateTime.now().microsecondsSinceEpoch;

  final int Function() _clock;

  /// The pool. Any odd constant does to start from, because what makes a seed
  /// unguessable is what has been stirred into it rather than where the
  /// stirring began.
  int _state = 0x2545F4914F6CDD1D;

  /// How many seeds have been drawn from it. See [seed] — it is what keeps two
  /// shoes shuffled in the same microsecond apart.
  int _draws = 0;

  /// Eight bytes of scratch, so that a reading can be read as the bits it
  /// actually is.
  ///
  /// The entropy in a sensor sample is in the bottom of the mantissa, so
  /// anything that goes through arithmetic or rounding on the way in throws
  /// away most of what it was fetched for. This is a reinterpretation and not
  /// a conversion: the same eight bytes, read as an integer.
  static final ByteData _word = ByteData(8);

  /// One reading off a sensor.
  void stir(double sample) {
    _word.setFloat64(0, sample);
    _mix(_word.getInt64(0));
  }

  /// The moment this was called, to the microsecond.
  ///
  /// Worth stirring in its own right and not only as a timestamp: *when* a
  /// sensor sample reached the isolate is a fact about the scheduler, the
  /// radio, and everything else the phone was doing at the time, none of which
  /// anybody is in a position to predict.
  void stirClock() => _mix(_clock());

  /// A number to start a shuffle from.
  ///
  /// The clock every time, so that a pool nobody has managed to stir — the
  /// desktop harness, a phone whose accelerometer errored, a test — still
  /// hands back a different number on every launch rather than dealing the
  /// same shoe twice. And the draw count with it, because the four shoes a
  /// picker builds are built inside one microsecond and the clock cannot tell
  /// them apart.
  ///
  /// The pool is left stirred rather than spent: drawing from it mixes in more
  /// than it gives out, so the next seed is not the last one plus one.
  int seed() {
    stirClock();
    _mix(++_draws);
    return _avalanche(_state);
  }

  void _mix(int word) => _state = _avalanche(_state ^ word);

  /// splitmix64's finaliser: shift, multiply, shift, multiply, shift.
  ///
  /// Two rounds of xor-shift-multiply is what it takes for one bit going in to
  /// have an even chance of flipping every bit coming out. That is the whole
  /// property being bought — a phone at rest changes one reading by one part
  /// in a million between two shuffles, and without an avalanche two seeds a
  /// millionth apart would start two very similar streams.
  static int _avalanche(int x) {
    int mixed = x;
    mixed ^= mixed >>> 33;
    mixed *= 0xFF51AFD7ED558CCD;
    mixed ^= mixed >>> 33;
    mixed *= 0xC4CEB9FE1A85EC53;
    mixed ^= mixed >>> 33;
    return mixed;
  }
}

/// The one pool, reached directly like `settings` is.
///
/// One rather than one per shoe, because entropy does not divide: four shoes
/// each with a thimbleful of it are worse off than four drawing from the same
/// bucket. It carries no sensor dependency of its own — the sensors stir it
/// from [tapMotionForEntropy] and from `SensorMotionSource`, which is what
/// lets `lib/cards/` import this file without importing a plugin.
final EntropyPool entropy = EntropyPool();
