# CLAUDE.md

## Git — hands off

**Never run `git add`, `git rm --cached`, `git commit` or `git stash`.** Staging
and committing are the user's, always. Leave work in the working tree and say
what changed. Reading the repo — `git status`, `diff`, `log`, `show`, `blame` —
is fine, as is `git checkout`/`branch` when the user asks for it.

## What this is

A 3D dice-tray app: rigid-body physics for a chosen set of dice — up to ten,
D4 through D20, each its own colour — in a phone-sized box, simulated in the
*phone's own frame of reference* so the walls never move and the acceleration
field inside them comes straight off the accelerometer.

`README.md` explains why that decision is the whole thing, and what the six
solids are. Read it once; don't restate it here.

## Commands

Run from the repo root:

| | |
|---|---|
| `make test` | the suites — headless, no device |
| `make analyze` | `flutter analyze --fatal-infos --fatal-warnings` |
| `make format` | `dart format lib test tool` |
| `make all` | format + analyze + test |
| `make desktop` | macOS harness. Space shakes, **R** throws, arrows tilt, **G** toggles the rotational pseudo-forces for an A/B |
| `make gif` / `make filmstrip` | render a scripted roll into `/tmp/rollhippo/` |
| `make picker` | render the picker — both modes, its saves, the chooser and the naming dialog — and every kind at rack size, into `/tmp/rollhippo/` |
| `make hippo` | render the hippopotamus — every pose a roll can present it in, the rack angle, and the die it is |
| `make icon` | redraw the app icon from `src/assets/rollhippo.svg` into both asset catalogues — writes into the project, not `/tmp` |
| `make ios` | `--profile`, not debug: debug cannot run on iOS 18.4+ with Flutter 3.29.2 (flutter#163984). That costs hot reload on device — tune on the harness, confirm on the phone |

Raw `flutter`/`dart` commands must run from `src/`, which is the package root.

## Layout, and the one invariant

```
src/lib/physics/   body (RigidBody) · shape (ConvexShape) · collision · contact · solver · world
src/lib/tray/      tray (walls + DiceTray) · tuning (Tuning) · dice (DieKind · DieSpec · faceValue)
                   profile (Profile · ProfileMode — the whole picker, as data) · share_code (both payloads)
src/lib/motion/    MotionSource — the sensors, a synthetic phone for the harness, and a still one
                   (StillMotionSource) for when motion control is switched off
src/lib/cards/     Deck (every outcome, shuffled) · PlayingCard · CardTable · Deal
src/lib/render/    TrayCamera · TrayPainter · TrayPagesPainter · CardPainter · DiePreview
                   hippo (the animal, in lumps — a picture, not a body)
src/lib/app/       PickerScreen (the rack, in two modes) · TrayScreen · CardScreen · chrome · PageDots
                   menu (AppMenuButton + the Settings and Share sheets) · scan_screen (the camera)
                   haptics (HapticEngine + HapticDriver) · settings (haptic gain · motion control)
                   profiles (SavedProfile · ProfileStore — the saves, stored)
                   profile_row (the row of them, and the naming and delete dialogs)
                   open_dialog (which one to open, asked once at launch)
src/assets/        rollhippo.svg — the mark, as drawn. Not a Flutter asset: nothing loads it at
                   runtime, `tool/app_icon.dart` transcribes it
src/test/          headless
src/tool/          filmstrip · roll_gif · one_die · picker · hippo · app_icon — run via `flutter test`,
                   they write image files
```

`tray.dart` re-exports `profile.dart`, `dice.dart`, `tuning.dart` and
`share_code.dart`, so one `import 'tray/tray.dart'` still brings `Tuning`,
`DieSpec`, `DieKind`, `Profile` and the encoders with it.

**`lib/physics/` does not import Flutter**, only `dart:math` and `vector_math`.
That is what makes the simulation testable without a device or a frame, and it
is worth defending. `lib/tray/` holds the same line — `dice.dart` stores a die's
colour as a packed ARGB `int` rather than a `Color` so nothing below the widgets
has to know Flutter exists. Flutter starts at `render/`, `app/` and `main.dart`.

**Shapes are found, not transcribed.** `ConvexShape.fromVertices` takes a vertex
list and derives the faces, their winding, their neighbours, the numbering, the
volume and the inertia tensor. Adding a die means adding its vertices to
`lib/tray/dice.dart` and nothing else. Don't hand-write face index lists.

## Conventions

- **SI units everywhere**, life-sized on purpose. A 16 mm die weighs 4.8 g
  because it is one, so every constant can be checked against a real object
  instead of tuned until it looks about right.
- **Explicit types** on locals and collection literals — `final Vector3 field =`,
  `<Wall>[…]`, `for (final RigidBody body in bodies)`. The codebase is consistent
  about this; match it.
- **Comments say why, at length, and are load-bearing.** Match the density of the
  surrounding file rather than trimming to fit a house style.
- `flutter_lints`, with infos and warnings fatal. Analysis must come back clean.

## The tuning is pinned

`test/tuning_test.dart` asserts the exact value of every constant in `Tuning`.
That is deliberate: the numbers were settled by shaking a phone, so they are not
derivable from anything in the repo and nothing else would notice them drifting.

**To change one, change it in `lib/tray/tuning.dart` and in
`test/tuning_test.dart` in the same edit.** That is the whole ceremony — the
test exists to make the change deliberate, not to make it hard.

## Traps

- **Collision is generic convex-polyhedron SAT**, not box code. Face normals of
  both bodies plus the cross products of their edge *directions* — which is the
  complete candidate set, and the face axes are deliberately one-sided because a
  face normal can only separate on the side it points at. Two D12s put 225
  candidate axes through both vertex lists, which is why the edge loop in
  `collision.dart` is written out in scalars and why `RigidBody` caches its
  world-space vertices, face normals and edge directions in `syncDerived`.
- **The bevel is a fraction of each shape's inradius**, not a fixed 1.3 mm. It
  works out to exactly `Tuning.dieBevel` on the D6, which is what the feel was
  tuned against; a D4 bevelled by the same absolute amount would be a ball.
- **Restitution runs in its own solver pass**, against
  `ContactPoint.approachSpeed` recorded before any impulse. Read the velocity
  back after the non-penetration solve and a speculative contact will already
  have taken nearly all of it, and the dice land dead. This was a real bug; the
  bounce test in `dice_test.dart` is what holds it.
- **`ConvexShape.inertiaPerMass` keeps only the diagonal.** That is exact only
  because every die's own frame is a principal frame, which `offDiagonalInertia`
  and a test in `shape_test.dart` exist to hold it to. A new shape that is not
  aligned that way will be silently wrong.
- **Sizing is by circumradius, not volume or edge length.** Every die is as wide
  as a 16 mm D6 across its widest point, which is what lets `throwDice()` pack
  any mixture of ten on one grid without them starting inside each other. Change
  it and the spawn grid needs to change with it.
- **vector_math turns a vector two different ways.** `Quaternion.rotated` applies
  `q⁻¹ v q`; `asRotationMatrix` builds `q v q⁻¹`. They are inverses of each
  other, and the app is on the matrix side — `RigidBody.syncDerived` derives all
  its world geometry from `orientation.asRotationMatrix()`. Anything that
  reasons about an orientation by hand, `previewOrientation` included, has to
  turn its vectors with the matrix or it will silently work out the mirror
  image. Composition follows the matrix: in `a * b`, `b` acts first.
- **A box you are not looking at is not simulated.** `TrayScreen` holds one
  `DiceTray` per group and ticks exactly one of them — none at all while a swipe
  is in flight. That is the feature, not an optimisation: a group's numbers stay
  the numbers it rolled, and a swipe cannot shake them. The exception is a group
  nobody has thrown yet, which is fed `MotionFrame.still` off-screen until it
  sleeps so its dice are lying on the floor by the time you reach them. Anything
  that assumes every tray advances every frame will be wrong.
- **A deck is every *ordered* outcome, six to the power of the dice.** 1-2 and
  2-1 are two ways for a pair to land, and a deck holding each unordered pair
  once would quietly halve the odds of every double. `Deck.build` counts in base
  six for exactly that reason. It differs from rolling in the one way a shoe
  always does — it is drawn without replacement — which is what `reshuffleAt`,
  `Deck.cut` and `Deck.spent` are about.
- **The card pile is life-sized until it cannot be.** Three dice across three
  decks is 648 cards, and at real 0.32 mm stock that pile is deeper than the
  tray — it would come out through the glass. `_maxPileDepth` in
  `card_painter.dart` is where it stops being a measurement.
- **A held die is a static body, not a sleeping one.** `RigidBody.held` takes
  `invMass` and the world-space inverse inertia to zero, and that is the whole
  mechanism: the solver's effective mass along a contact axis goes to infinity,
  so the impulse comes back zero and the entire bounce goes to whatever hit it.
  `integrate` skips it and `_containStrays` leaves it alone. `sleeping` is a
  different thing and a shake clears it; `held` survives every throw until the
  player taps the die again.
- **The haptic is an impulse, not a speed.** `PhysicsWorld.lastWallImpulse` is
  the peak normal impulse a *wall* handed a die last frame, in newton-seconds,
  read off `ContactPoint.maxNormalImpulse` after the solve. Newton-seconds are
  a change of momentum, so the number already carries the die's mass and a D20
  registers harder than a D4 arriving at the same speed — which a hand expects
  and `lastImpactSpeed` cannot express. Two filters are load-bearing: `b == null`
  is the wall test, and the approach-speed gate is what stops a die *resting* on
  the floor from buzzing forever, because holding itself up against gravity puts
  a real impulse through its contacts on every substep. `TrayScreen` reads it for
  the box on screen only, and feeds `HapticEngine.impact` **every** frame,
  including silent and frozen ones — the engine's rate limit keeps time off that
  `dt`, and a gap that only advanced on frames with an impact would never close.
- **A dealt card is dealt before it has arrived.** `CardTable.draw` takes the
  card off the shoe at once and `Deck.shown` is the new one immediately; `Deal`
  animates only its journey from the top of the pile to the glass. So a second
  ask mid-flight lands the first card rather than losing it, and anything that
  wants the card *presently on the glass* during a deal has to ask `Deal.under`
  rather than `Deck.shown`. The flying card is drawn behind the card it is
  landing on until it has turned past its own edge, and in front afterwards —
  ordering the two by depth instead would be true to the box and wrong to look
  at, because the card is behind the glass for all but the last instant of the
  journey and would slide in underneath the one it is being dealt onto.
- **The profiles wrap, and the Roll button does not move.** `ProfileRow` is a
  `Wrap` inside a `SingleChildScrollView`, under a "Profiles" heading that is
  *outside* that scroll view so it stays put while the block scrolls under it,
  and the picker hands the pair of them an `Expanded` — every point between the
  mode dots and the Roll button, and not one more. So the block grows downwards
  as saves are made, and once it has filled that space it scrolls inside it.
  Two things follow. A profile has to hug
  its own label, which is why it uses a `Center` with both factors rather than
  `Container.alignment` — that one is an `Align` with no factors and fills
  whatever width it is offered, which in a `Wrap` is the whole line. And the
  block needs a `SizedBox(width: double.infinity)` around the `Wrap`, because a
  `Wrap` is only as wide as its widest run and the column above would centre
  it, so the profiles would drift sideways as they were added.

- **Motion control off is a source, not a flag.** `Settings.motion` is read in
  exactly two places — `TrayScreen.initState` and `CardScreen.initState`, both
  through `motionSourceFor` — and what it selects is a `StillMotionSource`
  whose every frame is `MotionFrame.still`. Nothing below that knows the
  setting exists: the tray asks how the phone is moving and is told, truthfully,
  that it is lying on a table. So gravity points down the screen, `isShake` is
  never true, and Throw and Draw are the whole interface. Anything that wants
  to *test* the setting rather than obey the source is doing it wrong — with
  one exception, the unthrown group's prompt, which has to name a gesture that
  still works.

- **There are two share codes, and they are different things.** `RH1:` is a set
  of dice — `encodeGroups`/`decodeGroups` — and is now only what a save's dice
  are written as *inside the preferences file*, where everything else is a plain
  JSON field. `RH2:` is `encodeProfile`/`decodeProfile`: the whole picker, mode
  and shoe and all, plus the name its owner saved it under, and it is what a QR
  code carries. Each reader declines the other version outright rather than
  decoding two thirds of it, which is what the version in the prefix is for.
  What happens to a scanned one is decided in `PickerScreen._scanned` and turns
  entirely on that name: blank loads it unnamed, a name you already have and
  match opens it without a word, and anything else asks. `Profile` has value
  equality — and `DieSpec` has it for that reason — because "do I already have
  this one" is the question the whole tree hangs off.

- **Nothing is saved on its own.** Two places write a profile, and both
  are gestures: `+ New`, which makes one out of what is on screen, and Save on
  the menu a profile gives you when you hold it down (or right-click it). Between
  them, `PickerScreen._saveTo` and `_newSave` are the only callers of
  `_capture()`, and an edit to the picker touches no save at all. So the lit
  profile — and the title above it, which reads `Roll Hippo - <name>` — says which
  profile you *opened*, not that the screen still matches it. Save goes
  onto whichever profile was held down, which need not be that one. The mode rides along in `_capture()`, which means a profile is
  saved on a page and opens on the page it was saved from. `ProfileStore.write`
  is deliberately a no-op for a save that is no longer there.
- **The hippopotamus is a D6 with a picture on it.** `DieKind.hippo` *is* the
  cube — the D6's numbering, the D6's inertia, the D6's fairness — and
  `render/hippo.dart` is a drawing that `paintHippo` puts inside the hull the
  tray collides with. Two things follow. Nothing of the animal may leave that
  hull, and nothing may fall short of it: whichever face the die lands on is
  the face the floor is against, so a nose poking out would sink into the floor
  by as much as it stuck out and a nose falling short would hover above it —
  `hippo_test.dart` holds both ends. And which way the animal *lies* inside its
  cube is not free. The readout stands a numeral up, and on a cube "up for a
  numeral" is a different direction on every face, in a cycle no re-ordering of
  the corners can undo; `hippoToDie` is the one arrangement that buys a profile
  on the face carrying the 6 — which is the face the picker introduces every
  die by — and a head-on view on the 2. Two of the six still present it lying
  down. The rack turns it further round than the generic search would, through
  `previewFor`: a polyhedron needs a corner to read as a solid and an animal
  needs its head. The kind itself is never withheld, so a save or a share code holding
  one still opens; what is withheld is the chip, which `PickerScreen` only
  offers when the open profile is named `kHippoProfile`.

- **A held die keeps the face *index* it was read at**, in `DiceTray.held`.
  Reading one live is reading it against a gravity that has nothing to do with
  the face it is resting on — it cannot fall over to re-read itself when the
  phone is tilted somewhere new. `DiceTray.readings` is the one place that
  decides, and `throwDice` calls `readout.release()` *before* it scatters
  anything so that a held die is put back on the spot it landed on rather than
  left hanging where the formation had lifted it to.
