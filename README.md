# Roll Hippo 2 — dice tray prototype

A 3D dice tray: a box the size of the phone screen and 10 cm deep, with two
16 mm D6 in it that fall under gravity, bounce off the walls and off each other, and
tumble when the phone is shaken.

This is the movement only. No dice sets, no persistence, no controls beyond what
is needed to shake the thing and look at it.

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

Two details do more for how it reads than their size suggests:

- **Dice are bevelled**, and collision treats them as a box inflated by that
  bevel. A sharp cube landing on an edge pivots about a line and stalls; a
  rounded one rolls over the edge onto the next face, which is why real dice are
  made that way.
- **The face you see is the face it landed on** — read off the orientation, not
  chosen and animated towards.

The screen is locked to portrait, in both `Info.plist` and `SystemChrome`. That
is not a cosmetic choice: the walls are fixed to the screen and gravity comes
from the accelerometer, so a screen that re-oriented as you tipped the phone
would swing the tray out from under the dice while down carried on pointing the
same way.

## Layout

```
rollhippo2/
├── Makefile
└── src/
    ├── lib/physics/   body · contact · collision · solver · world   (no Flutter)
    ├── lib/tray/      tray geometry, dice, tuning constants
    ├── lib/motion/    sensor source, and a synthetic one for the harness
    ├── lib/render/    perspective camera and painter
    ├── test/          15 tests, all headless
    └── tool/          filmstrip · roll_gif · one_die  (render to image files)
```

`lib/physics/` imports nothing from Flutter, so the simulation is testable
without a device or a frame.

## Running it

```
make test        # 15 headless tests: integration, resting, containment, fairness
make desktop     # macOS harness — phone-sized tray, simulated shake
make ios         # build and install on the iPhone
make gif         # render a scripted roll to an animated GIF
```

The desktop harness letterboxes to 393 × 852 points whatever size its window is,
so the tray it simulates is the same 64 × 140 mm tray as the phone's. Drag to
shove the tray around, **space** to shake, **R** to throw, **arrows** to tilt,
**G** to toggle the rotational pseudo-forces on and off for an A/B.

The device build is `--profile`, not debug: debug mode cannot run on iOS 18.4+
with the pinned Flutter 3.29.2 (flutter#163984), which is the same constraint
Roll Hippo 1 hit. That costs hot reload on device — tune on the desktop harness,
then confirm on the phone.

## The locked tuning

Settled by hand on a phone, and pinned by `test/tuning_test.dart` so a change
has to be a decision rather than a drift. To move one, change it in
`lib/tray/tray.dart` and in that test in the same edit.

| | | |
|---|---|---|
| `trayDepth` | 10 cm | deep enough that the dice use the depth |
| `gravityScale` | 0.6 | dice fall at 0.6 g; shakes land at full force |
| `timeScale` | 0.85 | the same arcs, replayed slower |
| `dieSize` / `dieBevel` | 16 mm / 1.3 mm | a real acrylic D6, 4.8 g |
| `dieRestitution` / `dieFriction` | 0.38 / 0.42 | |
| `wallRestitution` / `wallFriction` | 0.28 / 0.5 | the tray lining |
| `glassRestitution` / `glassFriction` | 0.4 / 0.08 | the pane you look through |
| `eyeDistance` | 32 cm | real reading distance |

Still tuned for 1 g at full speed, and not yet re-judged against the above:
damping, and the sleep thresholds that decide when a roll is over.

## What is checked

`make test` covers free-fall acceleration, the direction of angular
integration, the gravity/shake split, a die settling flat on the floor and sleeping, a settled die not
drifting, bounces losing height, dice staying inside the tray through eight
seconds of an 8 g shake, two dice not passing through each other, the pip
mapping, and a fairness smoke test (220 rolls, 440 dice, χ² = 1.9 on 5 df).

Cost on an iPhone: **under 0.01 ms of CPU per frame** for two dice, against a
8.3 ms budget at 120 Hz.

## What is not settled

Everything about feel. The constants in `lib/tray/tray.dart` — restitution,
friction, damping, bevel, sleep thresholds — are set to real-world values for
acrylic dice on a lined tray, which is a starting point and not an answer.
`gravityScale` is the one that has been moved off its real value on purpose.

Open questions worth deciding early: whether 0.6 gravity wants the damping and
sleep thresholds moved with it (dice now take longer to give up); whether 10 cm
of depth is too much (deep enough that the dice can get lost behind each other); whether
the dice should settle faster than physics says, so a roll reads sooner; and
whether the rotational pseudo-forces are worth their complexity — press **G** on
the harness and see.
