# Roll Hippo — dice tray

[![CI](https://github.com/jfigge/rollhippo/actions/workflows/ci.yml/badge.svg)](https://github.com/jfigge/rollhippo/actions/workflows/ci.yml)

Pick a set of dice — up to ten of them, any mixture of D4 through D20, each its
own colour — throw them into a box the size of the phone screen and 20 cm deep,
and read what they landed on. They fall under gravity, bounce off the walls and
off each other, and tumble when the phone is shaken.

## The one idea

Roll Hippo 1 simulated in 2D (Forge2D, a Box2D port) and pointed a single
gravity vector around a flat plane. Dice slid; they did not tumble, and the
number showing was chosen rather than landed on. That is the whole of why it
felt unnatural.

Here the simulation is a real rigid-body one — mass, inertia tensor, quaternion
orientation, contact manifolds — and it runs **in the phone's own frame of
reference**. The walls never move. What moves is the acceleration field inside
the box, and for a phone that field is exactly the **negated accelerometer
reading**:

```
a_rel = g − a_phone = −(a_phone − g) = −(what the accelerometer reads)
```

One vector, straight off the sensor, already containing both which way is down
and every jolt of the shake. No shake threshold, no gesture detector, no seam
where tilting stops and shaking starts. The gyroscope adds the Euler, Coriolis
and centrifugal terms, and — the line that matters most for feel — a die under
no torque holds its orientation in the *world*, so in the tray's frame it
counter-rotates exactly as fast as the phone twists. That is what turns a wrist
flick into a tumble instead of a slide.

Because gravity and shake arrive from the sensor as one number, tuning one
without the other means splitting them back apart — the steady pull comes from
CoreMotion's gravity estimate, the rest is movement. `Tuning.gravityScale` then
softens only the pull. It currently sits at **0.6**: the dice hang longer and
tumble further per bounce, while a shake still hits with the full force your
hand put into it, exactly as it would on a smaller planet.

Separately, `Tuning.timeScale` runs the simulation at **0.85** of real time.
That is not the same knob: gravity changes the *shape* of the arcs, time scale
replays the identical arcs more slowly. Real time still goes to the sensors,
since angular acceleration is a physical rate and has no business being scaled.

Three details do more for how it reads than their size suggests:

- **Dice are bevelled**, and collision treats them as the polyhedron inflated by
  that bevel. A sharp solid landing on an edge pivots about a line and stalls; a
  rounded one rolls over the edge onto the next face, which is why real dice are
  made that way. The bevel is a fixed *fraction* of each shape's inradius, so a
  D4 — whose faces sit a third as far from its centre as a cube's — is not
  rounded nearly to a ball.
- **The face you see is the face it landed on** — read off the orientation, not
  chosen and animated towards. A D4 is read off the face it is *sitting* on,
  because a tetrahedron at rest has a vertex pointing at the sky and no face at
  all, and its numbers are printed along its edges accordingly.
- **Restitution is taken against the speed a die arrives with**, not the speed
  it has left once the non-penetration constraint has had its way. A die falling
  at two metres a second is caught by a speculative contact a millimetre out and
  held to just reaching the floor by the end of the substep; bounce off *that*
  and it lands dead. This is the difference between a throw and a drop.

The screen is locked to portrait, in both `Info.plist` and `SystemChrome`. That
is not a cosmetic choice: the walls are fixed to the screen and gravity comes
from the accelerometer, so a screen that re-oriented as you tipped the phone
would swing the tray out from under the dice while down carried on pointing the
same way.

## The dice

Six shapes, all of them isohedral — every face the same distance from the
centre — which is both what makes a die fair and what lets one uniform shrink
serve as the bevel for all of them.

| | | |
|---|---|---|
| D4 | tetrahedron | read off the face it lands on |
| D6 | cube | pips, not numerals |
| D8 | octahedron | |
| D10 | pentagonal trapezohedron | the only one that is not Platonic |
| D12 | dodecahedron | |
| D20 | icosahedron | |

None of their faces are transcribed by hand. Each shape is defined by its
vertices alone, and `ConvexShape.fromVertices` *finds* the faces — every plane
through three vertices with all the others behind it — then orders each
polygon, links its edges to their neighbours, numbers opposite faces to sum to
n+1, and computes volume and inertia by decomposing the solid into tetrahedra.
A pentagonal trapezohedron's inertia tensor is in no table, and a die whose
inertia is wrong is a loaded die.

Every die is built to the same circumradius as a 16 mm D6, so they all measure
the same across their widest point and one spawn grid packs any mixture of them
without two starting inside each other. Mass follows from each shape's own
volume at acrylic's density, so a D20 really is heavier than a D4.

## Layout

```
rollhippo/
├── Makefile
├── website/           the whole of hippoherd.com/rollhippo — the product page, the user
│                      guide, and the pictures both are built from. `make site` copies it
├── appstore/          the store screenshots, framed at Apple's 1290 × 2796
└── src/
    ├── lib/physics/   body · shape · contact · collision · solver · world   (no Flutter)
    ├── lib/tray/      tray geometry · dice · tuning constants · a profile · the share codes
    ├── lib/motion/    sensor source, and a synthetic one for the harness
    ├── lib/render/    perspective camera and painter
    ├── lib/app/       the two screens, the app menu, and the haptics
    ├── test/          119 tests, all headless
    └── tool/          filmstrip · roll_gif · one_die · picker · appstore  (render to image files)
```

`lib/physics/` imports nothing from Flutter, so the simulation is testable
without a device or a frame. `lib/tray/` holds the same line: a die's colour is
a packed ARGB `int` rather than a `Color`, so nothing below the widgets has to
know Flutter exists.

## Running it

```
make test        # 213 headless tests: geometry, integration, resting, containment, fairness
make desktop     # macOS harness — phone-sized tray, simulated shake
make ios         # build and install on the iPhone
make android     # build and install on the Android phone
make gif         # render a scripted roll to an animated GIF
```

The app opens on the dice you are about to throw: add up to ten, give each one a
colour and a number of sides, then **Roll**. In the tray, **Throw** puts them
back in from the top and **Close** returns to the set.

The three lines in the top left are the app menu, and it is two entries.
**Settings** is two controls.
**Motion control** is whether the phone's own movement plays at all: on, the box
is simulated in the phone's frame of reference and tilting and shaking do what
they look like they should; off, the tray is handed a phone held perfectly still
— down is down the screen and stays there — and the buttons along the top are
the only way to roll or deal. **Impact strength** is how hard the phone taps
back when a die hits the side of the box, which is keyed on the impulse the wall
actually delivered, so a heavy die landing hard feels different from a light one
nudging a wall. Drag the slider and it plays each notch back at you, because a
multiplier is not a sensation and nobody can set one by reading it. **Scan** is
the other entry: it opens the camera and reads a code off another phone. One
that arrives with a name offers to become a save on this phone too; one that
names a profile you already have, and matches it, simply opens it.

Making those codes belongs to the profiles rather than to the menu, because a
code *is* a profile. Hold one down — or right-click it in the harness — and
**Share** is on the menu that comes up, beside Save, Rename and Delete. It turns
that save into a QR code: which page you are on, every die, its kind and its
colour, the shoe if you are in card mode, and the name it is saved under. What
goes out is what the *save* holds, so an edit you have not kept does not travel
under a name that no longer describes it. The dashed **+ New** has a Share of its
own, and that one sends what is actually on screen, unnamed — which is what
+ New has always meant.

The desktop harness letterboxes to 393 × 852 points whatever size its window is,
so the tray it simulates is the same 64 × 140 mm tray as the phone's. Drag to
shove the tray around, **space** to shake, **R** to throw, **arrows** to tilt,
**G** to toggle the rotational pseudo-forces on and off for an A/B.

The device build is `--profile`, not debug — by choice now rather than by force.
Debug was once impossible on the phone (flutter#163984, iOS 18.4+ on the pinned
Flutter 3.29.2), which is the same constraint Roll Hippo 1 hit; since the Flutter
upgrade it builds, installs and hot-reloads on device perfectly well. It stays
`--profile` anyway, because the solver runs in Dart on every frame and under
debug's JIT the tray is not the tray that ships — a feel judged there is judged
against the wrong thing. Tune on the desktop harness, confirm on the phone, and
reach for `flutter run -d <id>` when hot reload is worth more than the feel being
honest.

## The locked tuning

Settled by hand on a phone, and pinned by `test/tuning_test.dart` so a change
has to be a decision rather than a drift. To move one, change it in
`lib/tray/tuning.dart` and in that test in the same edit.

| | | |
|---|---|---|
| `trayDepth` | 20 cm | deep enough that the dice use the depth |
| `gravityScale` | 0.6 | dice fall at 0.6 g; shakes land at full force |
| `timeScale` | 0.85 | the same arcs, replayed slower |
| `dieSize` / `dieBevel` | 16 mm / 1.3 mm | a real acrylic D6, 4.8 g, and the yardstick for every other shape |
| `dieRestitution` / `dieFriction` | 0.38 / 0.42 | |
| `wallRestitution` / `wallFriction` | 0.28 / 0.5 | the tray lining |
| `glassRestitution` / `glassFriction` | 0.4 / 0.08 | the pane you look through |
| `throwSpeed` / `throwSpin` | 2.0 m/s / 8 rad/s | reaches the floor at 2.3 m/s and comes back up about 25 mm |
| `eyeDistance` | 32 cm | real reading distance |
| `hapticFloor` / `hapticCeiling` | 1 / 18 mN·s | a 4.8 g D6 at 0.16 m/s and at 2.8 m/s; the bottom and top of the haptic scale |
| `hapticGap` | 45 ms | at most 22 taps a second, which is all a hand can tell apart |
| `hapticGain` / `hapticMaxGain` | 1.0 / 3.0 | where the calibration slider starts, and where it stops |

Still tuned for 1 g at full speed, and not yet re-judged against the above:
damping, and the sleep thresholds that decide when a roll is over.

## What is checked

`make test` covers the geometry of all six solids — face count, convexity, the
shared inradius, the numbering, inertia against the published tensors for the
three that have one, and that each solid's own frame really is a principal frame
— then free-fall acceleration, the direction of angular integration, the
gravity/shake split, a die settling flat on the floor and sleeping, a settled die
not drifting, bounces losing height, every kind of die landing flat on a face and
reading it, a thrown die reaching the floor and coming back up off it, ten
assorted dice starting apart and staying inside the tray through a hard shake,
two dice not passing through each other, the pip mapping, and fairness smoke
tests for the D6 and the D20.

Cost per frame, ten dice, measured in the test VM: **0.3–0.6 ms** for a throw
settling, and **3–4 ms** under eight seconds of continuous 8 g shaking, which is
the worst the simulation is ever asked to do. The shaken figure is all
separating-axis work — two D12s alone put 225 candidate axes through both vertex
lists — and Gauss-map pruning of the edge pairs is where the next order of
magnitude is if it is ever needed.

## What is not settled

Everything about feel. The constants in `lib/tray/tuning.dart` — restitution,
friction, damping, bevel, sleep thresholds — are set to real-world values for
acrylic dice on a lined tray, which is a starting point and not an answer.
`gravityScale` is the one that has been moved off its real value on purpose.

Open questions worth deciding early: whether 0.6 gravity wants the damping and
sleep thresholds moved with it (dice now take longer to give up); whether 20 cm
of depth is too much now that a die at the back is drawn at 62% of one at the
glass; whether the dice should settle faster than physics says, so a roll reads
sooner; and whether the rotational pseudo-forces are worth their complexity —
press **G** on the harness and see.
