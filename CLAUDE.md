# CLAUDE.md

## Git — hands off

**Never run `git add`, `git rm --cached`, `git commit` or `git stash`.** Staging
and committing are the user's, always. Leave work in the working tree and say
what changed. Reading the repo — `git status`, `diff`, `log`, `show`, `blame` —
is fine, as is `git checkout`/`branch` when the user asks for it.

## What this is

Two ways to get a roll, and the app is equally both. Nothing here is the tray
with a card mode attached — say it that way round and you have described the
wrong app.

**A shoe of cards, one per possible roll.** `lib/cards/` builds every *ordered*
outcome of one to three six-sided dice, one to three decks of them at once,
shuffles it and deals without replacement, with a cut card at whatever
percentage you set. Drawing a card is the same wager as throwing the dice it
stands for — that is what makes it a stand-in rather than a gimmick — and it
differs in the one way a shoe always does: what has already gone tells you
something about what is left. That difference is the point of the mode, and
`reshuffleAt` is there to let you decide how much of it you want.

**A 3D dice tray.** Rigid-body physics for a chosen set of dice — up to ten,
D4 through D20, each its own colour — in a phone-sized box, simulated in the
*phone's own frame of reference* so the walls never move and the acceleration
field inside them comes straight off the accelerometer.

They are two pages of one picker rather than two screens, because they are
alternatives to each other: whichever one you are looking at is what the button
at the bottom does, and it is named Deal or Roll accordingly. A [Profile] is
both pages at once for the same reason, so a save made on one does not throw
away the other.

`README.md` explains why the frame-of-reference decision is the whole of how
the tray *feels*, and what the six solids are. Read it once; don't restate it
here.

## Commands

Run from the repo root:

| | |
|---|---|
| `make test` | the suites — headless, no device |
| `make analyze` | `flutter analyze --fatal-infos --fatal-warnings` |
| `make format` | `dart format lib test tool` |
| `make all` | format + analyze + test |
| `make ci` | what CI runs: format-check + analyze + test |
| `make format-check` | the same files as `format`, but it reports the drift rather than fixing it |
| `make desktop` | macOS harness. Space shakes, **R** throws, arrows tilt, **G** toggles the rotational pseudo-forces for an A/B |
| `make gif` / `make filmstrip` | render a scripted roll into `/tmp/rollhippo/` |
| `make picker` | render the picker — both modes, its saves, the naming dialog and the Reset-and-Share menu behind `+ New` — and every kind at rack size, into `/tmp/rollhippo/` |
| `make hippo` | render the hippopotamus — every pose a roll can present it in, the rack angle, and the die it is |
| `make tutorial` | render the tutorial — every page, over the screen that page is about, with the part it names lit — on a phone and on the shortest screen worth shipping to, into `/tmp/rollhippo/` |
| `make icon` | redraw the app icon from `src/assets/rollhippo.svg` into both asset catalogues and Android's `mipmap` folders, and both platforms' launch images with it — writes into the project, not `/tmp`. The XML beside the rasters is structure, not drawing, and is not regenerated: the adaptive icon's two files, `LaunchScreen.storyboard`, and Android's `launch_background.xml` and `styles.xml`, which only place the launch image and paint the picker's colour behind it |
| `make ios` | `--profile` by choice, not by force. Debug was impossible under Flutter 3.29.2 (flutter#163984); since the upgrade it runs and hot-reloads on device fine. Still profile, because the solver is Dart every frame and debug's JIT is not the shipping feel. Installs with `xcrun devicectl`, **never `flutter install`** — that one uninstalls the old copy first and cannot be told not to, and an uninstalled iOS app takes its container, its `NSUserDefaults` and so every saved profile with it |
| `make android` | `--profile` for exactly the same reason, and `adb install -r` for the other one — same trap, same cost, `shared_preferences`' XML instead of `NSUserDefaults`. On either platform, `flutter run -d <id>` when hot reload is worth more than the feel; `run` installs over the top, which is why it is safe |
| `make ipa` | `--release`, and signed — the build that goes to App Store Connect. Needs the Apple Distribution certificate in the keychain |
| `make upload` | send that archive to App Store Connect. The key id and issuer come from `release.env`, the `.p8` itself from `keys/`, and both are gitignored — together they are the whole of what a new machine needs before it can ship. `--apiKey` takes the key's *id*, never a path: altool builds `AuthKey_<id>.p8` itself and hunts for it in four fixed directories, which `API_PRIVATE_KEYS_DIR` replaces. Connect refuses a build number it has already seen, so a second upload means bumping the `+N` in `pubspec.yaml` and rebuilding |
| `make screenshots` | render the store listing and the website's pictures. Writes into the *project*, like `make icon`: `appstore/` is framed and captioned at Apple's exact 1290 × 2796 and is what you upload, `website/images/screens/` is the bare screen at half that and is what the site and the guide are built from, and `website/images/hero.png` and `og.png` are composed from those. **A full run re-renders all seven, and the dice are not seeded** — every capture with dice in it comes out a different roll, so redoing one shot means naming it: `flutter test tool/appstore.dart --plain-name '07 · the tutorial'` |
| `make screenshots-65` | the same seven, for Apple's other iPhone slot: `appstore/6.5/` at 1242 × 2688. Rendered at that phone's own 414 × 896 rather than resampled from the 6.9" set — the aspect ratios are close but not equal, and the safe area is genuinely different (44 pt of notch against 59 of Dynamic Island), which moves everything inside a `SafeArea`. Writes no website pictures and no hero: those belong to the 6.9" run, which is what `Slot.web` in `tool/appstore.dart` decides. Optional — Apple requires only the 6.9" set and downscales it itself |
| `make site` | `rsync` `website/` into hippoherd's `website/rollhippo/`. That page is Roll Hippo's whole website — it is written here and served there — and hippoherd's generator leaves it alone rather than overwriting it. Commit and push in *that* repo to deploy |

Raw `flutter`/`dart` commands must run from `src/`, which is the package root.

## CI

`.github/workflows/ci.yml`, on every push to `main` and every pull request.
Four jobs: the checks — `make format-check`, `make analyze`, `make test`, on
Linux, because none of the suites need a device or a display — then a release
APK, an unsigned iOS build, and the macOS harness. The Apple two need no
certificate: iOS builds `--no-codesign` and the harness signs ad-hoc, so no
secret goes near a runner and nothing here ships anywhere. The builds are
`--release` where the Makefile is `--profile` — CI is not judging the feel, it
is asking whether AOT, R8, the pods and the merged manifest still work, and
release asks that hardest. The Flutter version is pinned in the workflow's
`env` on purpose, and bumping it is that one line.

## Layout, and the one invariant

```
src/lib/physics/   body (RigidBody) · shape (ConvexShape) · collision · contact · solver · world
src/lib/tray/      tray (walls + DiceTray) · tuning (Tuning) · dice (DieKind · DieSpec · faceValue)
                   profile (Profile · ProfileMode — the whole picker, as data) · share_code (both payloads)
src/lib/motion/    MotionSource — the sensors, a synthetic phone for the harness, and a still one
                   (StillMotionSource) for when motion control is switched off
src/lib/cards/     Deck (every outcome, shuffled) · PlayingCard · CardTable · Deal
src/lib/render/    TrayCamera · TrayPainter · TrayPagesPainter · CardPainter · DiePreview
                   hippo (the animal twice over: in lumps for the die, and in one line
                   for the back of a card — neither of them a body)
src/lib/app/       PickerScreen (the rack, in two modes) · TrayScreen · CardScreen · PageDots
                   chrome (letterbox · TrayButton · AppDialog — what every screen shares)
                   slide_confirm (the drag a question gets when a button is what went wrong)
                   menu (AppMenuButton + the Settings and Share sheets) · scan_screen (the camera)
                   tutorial (the first run: pages you swipe, over the screen each is about) ·
                   haptics (HapticEngine + HapticDriver, for the tray · uiHaptic, for
                   the interface) · settings (haptic gain · motion · shake to deal · tutorial)
                   profiles (SavedProfile · ProfileStore — the saves, stored)
                   profile_row (the row of them, and the naming and delete dialogs)
src/assets/        rollhippo.svg — the mark, as drawn. Not a Flutter asset: nothing loads it at
                   runtime, `tool/app_icon.dart` transcribes it
src/test/          headless
src/tool/          filmstrip · roll_gif · one_die · picker · hippo · tutorial · app_icon · appstore — run via `flutter test`,
                   they write image files
website/           Roll Hippo's whole website — index.html, docs/index.html (the user guide),
                   and images/. Hand-written, no build step. `make site` copies it to
                   hippoherd's website/rollhippo/, which is where it is served from
appstore/          the seven framed 1290 × 2796 screenshots, for App Store Connect and Play
                   Console. Written by `make screenshots`; an upload, not a source.
                   6.5/ is the same seven at 1242 × 2688, from `make screenshots-65`
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
  `<Wall>[…]`, `for (final RigidBody body in bodies)`. This is no longer a
  request: `always_specify_types` is on, along with `prefer_final_locals`, so
  the analyser will say so.
- **Comments say why, at length, and are load-bearing.** Match the density of the
  surrounding file rather than trimming to fit a house style. This one *is* a
  request — no linter can check it.
- `flutter_lints`, with infos and warnings fatal, plus the rules in
  `src/analysis_options.yaml` and the three `strict-*` language modes. Analysis
  must come back clean. That file explains what each rule is doing there; the
  short version is that every one of them describes what the code already did,
  and turning the set on found fourteen slips in 20,000 lines.

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
- **A contact's feature id is banded, and the bands have a ceiling.** Warm
  starting hands each contact back the impulse it settled on last step, and it
  finds it by `manifold key × featureIdLimit + featureId` — so an id that
  strays out of its own manifold's slot silently collects a *different pair of
  dice's* impulses. Three kinds of point come out of `collision.dart` and they
  are numbered from three separate bases so that cannot happen: below
  `_clippedId` (32) an id is a vertex of the incident face, up to `_edgeId`
  (128) it is a point the clipper invented, and above that it is a pair of edge
  groups at `_edgeId + i × _edgePitch + j`. That last band is the one with room
  to overrun — it reaches 1151, which is what puts `featureIdLimit` at 2048 and
  why a stride of 64 was a bug rather than a tight fit. The manifold keys are
  banded the same way and by the same reasoning: a wall is `i × 8 + w` and a
  pair is `1000 + i × 16 + j`, so a body gets eight wall slots and a pair
  sixteen. **A shape with 32 or more edge directions breaks the edge band, a
  ninth wall breaks the first stride, and a seventeenth die breaks the second**
  — today's six walls and ten dice leave two and six of margin respectively,
  and none of the three would fail loudly. The dice would just jitter. There is
  an assert at each end (`_edgeContact` and `ImpulseCache._key`) and two tests
  in `physics_test.dart`, and between them that is the whole guard.
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
- **A box is built once and never resized; the camera letterboxes instead.** A
  `DiceTray`'s constructor throws the dice and a `CardTable`'s builds a `Deck`,
  which shuffles — so rebuilding either one on a layout change is re-rolling a
  result somebody is looking at, or putting a half-dealt shoe back together.
  Android split screen and an opening foldable both do exactly that. So
  `_ensureBoxes` and `_ensureTable` build on the first non-empty size and never
  again, and `cameraFor` fits whatever was built into whatever room there now
  is, by the smaller of the two ratios — which leaves a margin down two sides
  rather than a stretched box or a floor drawn off the bottom of the screen. A
  roll that a swipe cannot shake is a roll a window cannot shake either. One
  function serves the painter and `dieAt`, so a tap lands on the die it looks
  like it landed on; `render_test.dart` holds the split-screen case. The sharp
  edge is at the other end of the same guard: both bail on an empty size and
  both callers then index straight into what was not built, so a genuinely
  zero-sized first layout throws rather than drawing nothing.
- **A deck is every *ordered* outcome, six to the power of the dice.** 1-2 and
  2-1 are two ways for a pair to land where snake eyes has only one, so a deck
  holding each unordered pair once would quietly make every double twice as
  likely as it is. `Deck.build` counts in base six for exactly that reason. It
  differs from rolling in the one way a shoe always does — it is drawn without
  replacement — which is what `reshuffleAt`, `Deck.cut` and `Deck.spent` are
  about.
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
  rather than `Deck.shown`.

  That card is not covered — it *leaves*. It slides down the glass and out of
  the bottom of the box on its own clock, `Tuning.dealDiscard`, which runs out
  before the flight does, so there is a beat of bare glass before the new card
  reaches it. `Deal.flying` and `Deal.discarding` are independent and neither
  implies the other: a reshuffle sweeps a card away with nothing following it,
  and the first deal onto an empty glass has nothing to sweep. `Deal.busy` is
  both, and is what `CardScreen` ticks on and what the painter asks before it
  draws anything lying still — during a deal there is no such card.

  Because the outgoing card leaves, the two are now drawn in the box's own
  depth order: the flight first, the card leaving over the top of it, and the
  new one comes out from behind the old one as it drops. That used to be a lie
  it had to tell — with the outgoing card staying put, depth order left the
  incoming one hidden behind it for the whole flight and popping into view at
  the end, so the two were swapped at the instant the flying card went edge on.
- **A played shoe is asked about before it is closed.** Close sits an inch
  from Draw and gets hit by the same hand doing the same thing, so
  `CardScreen._close` puts a question in front of it — but only when there is
  something to lose, which is what `Deck.dealt` answers: a card on the glass,
  or cards gone from the pile. A shoe nobody has drawn from closes on the tap,
  and so does one a reshuffle has just put back together, because both are the
  position a new table opens in. The question is a `SlideToConfirm` rather
  than a second button for the reason it exists at all: what it is guarding
  against is not a decision but a stray thumb, and a button under a button is
  another thing to hit by accident. The back gesture goes through the same
  door — `PopScope`, whose `canPop` is `!_dealt`, which is why `_draw` calls
  `setState` on the one card that changes that answer and on no other.

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

- **The sensor filters are in seconds, not in frames.** `lowPass(dt, tau)` is
  `1 − e^(−dt/τ)`, and `_kGravityTau`, `_kTwistTau` and `_kDragTau` are time
  constants — 0.1026, 0.0467 and 0.0326 s. They are not new numbers: each is
  the per-frame weight this file used to carry, converted at the 60 Hz it was
  written against by `τ = dt / −ln(1 − blend)`, so 0.15 a frame *is* 102.6 ms.
  A phone at 60 Hz therefore behaves exactly as it always did, to four figures.
  The reason it is written this way is the other phones: a fixed pair of
  weights — `held × 0.85 + sample × 0.15` — is not a filter with a time
  constant, it is a filter with a time constant *per frame*, so a 120 Hz
  ProMotion iPhone settles in half the wall-clock time a 60 Hz Android takes.
  Which way is down would then chase a shake twice as eagerly on one phone as
  on the other. **Writing a bare blend factor back in would reintroduce that,
  and it would only show up on hardware you are probably not holding** —
  `gravity_test.dart` pins rate-independence and step composition for exactly
  that reason. Two guards belong to the formula and not to taste: `dt <= 0`
  returns 0 because nothing moves in no time, and `tau <= 0` returns 1 because
  no constant is no filter.
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

  **`Settings.shakeToDraw` is the second setting through the same door, and
  the reason the door was worth having.** The card table asks for
  `settings.motion && settings.shakeToDraw`, so a table nobody asked the shake
  for is handed the same still phone the tray gets with motion off — one line
  in `CardScreen.initState`, and not a test of the flag anywhere below it. It
  is **off by default**, and it is the one setting here that does not restore
  what the app used to do. A shake on the tray *is* the simulation, and an
  unmeant throw is undone by throwing again; a shake on the cards is a
  trigger, and what it triggers takes a card off the shoe for good. That a
  shoe has memory is the whole point of the mode, which is exactly what makes
  an accidental deal unfixable — and a phone handed across a table is a shake.

- **There are two share codes, and they are different things.** `RH1:` is a set
  of dice — `encodeGroups`/`decodeGroups` — and is now only what a save's dice
  are written as *inside the preferences file*, where everything else is a plain
  JSON field. `RH2:` is `encodeProfile`/`decodeProfile`: the whole picker, mode
  and shoe and all, plus the name its owner saved it under, and it is what a QR
  code carries. Each reader declines the other version outright rather than
  decoding two thirds of it, which is what the version in the prefix is for.
  An `RH2:` code is produced from the row of profiles rather than from the app
  menu, and which one you held down decides what goes into it:
  `PickerScreen._share` encodes the *save* — `save.profile` under `save.name`,
  so an unkept edit does not travel under a name that no longer describes it —
  while `_shareCurrent`, off the dashed `+ New`, encodes `_capture()` with a
  blank name, because what is on screen belongs to no save.
  What happens to a scanned one is decided in `PickerScreen._scanned` and turns
  entirely on that name: blank loads it unnamed, a name you already have and
  match opens it without a word, and anything else asks. `Profile` has value
  equality — and `DieSpec` has it for that reason — because "do I already have
  this one" is the question the whole tree hangs off.

- **Nothing is saved on its own.** Two places write a profile, and both
  are gestures: `+ New`, which makes one out of what is on screen, and Save on
  the menu a profile gives you when you hold it down (or right-click it). Between
  them, `PickerScreen._saveTo` and `_newSave` are the only *writers*, and an
  edit to the picker touches no save at all. `_capture()` has a third caller,
  `_shareCurrent`, which writes nothing and hands the same object to another
  phone. So the lit
  profile — and the title above it, which reads `Roll Hippo - <name>` — says which
  profile you *opened*, not that the screen still matches it. Save goes
  onto whichever profile was held down, which need not be that one. The mode rides along in `_capture()`, which means a profile is
  saved on a page and opens on the page it was saved from. `ProfileStore.write`
  is deliberately a no-op for a save that is no longer there.

  The dashed `+ New` answers to the hold as well, and its menu is the two things
  that belong to no save. **Share**, which sends the screen unnamed, and above
  it — because it is the entry that lives nowhere else, where every profile in
  the row has a Share — **Reset**, `PickerScreen._reset`, which
  `_apply`s `kDefaultProfile` and clears the lit profile. `kDefaultProfile` is
  the picker as `main` opens it — the state fields are initialised from it — so
  starting again by hand and starting again by launching the app land on the
  same set-up. It asks nothing first, for the reason opening a save asks
  nothing: what it replaces was either kept in a profile of its own or was never
  named.

  Nothing is asked at launch either. The app used to put a chooser over the
  picker on every start that had a save behind it; the row answers the same
  question in one tap without standing in front of the screen to do it, so a
  first run and a hundredth now look the same.
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

  `HippoDrawing`, in the same file, is the *other* hippopotamus: the same
  animal in one gold line, and it is what is printed in the middle of a card
  back. It is not held to the cube, because nothing collides with a card, and
  it is not derived from the lumps either — it is drawn, three quarters on,
  which is the one view a box cannot give. That is what buys it two eyes, two
  ears, two nostrils, toes and a tail, none of which the die's hippopotamus
  can afford. It is also
  the only thing on either side of a card that is not symmetric about both of
  its axes, and `_paintFlight` in `card_painter.dart` is where that is paid
  for: the back is drawn only through the first quarter of a card's turn,
  which is exactly the part where a real card's back is still the right way
  up.

- **A held die keeps the face *index* it was read at**, in `DiceTray.held`.
  Reading one live is reading it against a gravity that has nothing to do with
  the face it is resting on — it cannot fall over to re-read itself when the
  phone is tilted somewhere new. `DiceTray.readings` is the one place that
  decides, and `throwDice` calls `readout.release()` *before* it scatters
  anything so that a held die is put back on the spot it landed on rather than
  left hanging where the formation had lifted it to.

- **A first run is a fact about the launch, not about the picker.**
  `PickerScreen` takes a `tutorial` flag and it defaults to *false*, because
  `main` is the only thing in the repository that knows a launch has happened:
  `tool/picker.dart` and `tool/appstore.dart` build that same screen to render
  the store listing and the website's pictures, better than two hundred widget
  tests pump it, and — since the tutorial gained a backdrop — the tutorial
  itself builds two more. Every one of those would have been a first run if the
  screen had asked `settings.tutorialSeen` for itself, the store listing would
  have shipped with a tutorial over it, and the tutorial would have opened a
  tutorial. So `main` reads the flag, hands down the answer, and nothing else
  has to know. `showTutorial` is what writes it back — on the way *out*, so an
  app killed with the tutorial open has not shown it to anybody and offers it
  again — and it writes it whichever of the two ways it was reached, the launch
  or **How to use** at the bottom of the app menu. There is deliberately no way
  back to false and no switch for it: the menu entry is one tap.

- **The tutorial brings its own screen, and the imports run one way.**
  Each page is said in front of the screen it is about — the card page, the
  dice page, or a live `TrayScreen` — with the one thing it names left undimmed
  and everything else at two thirds black, and the card of words hung off the
  roomier side of that hole. Three consequences, and the last is the one that
  bites.

  It is the tutorial's own picker rather than the player's, built from
  `kTutorialProfile`, because the backdrop has to show the page being
  *discussed*: card mode while card mode is being explained, three filled sets
  while the three sets are. A tour that drove the real picker would be a tour
  that rearranged your dice.

  Every backdrop is laid out at all times and only one is painted, which is
  what `Opacity` at zero does. That is not a saving — a screen taken out of the
  tree has no rectangle to measure when the page about it arrives, and the hole
  would open a frame late every time. The tray is the exception, built on
  arrival rather than at the start, because it is a live simulation with a
  haptic in front of it and one running under a page about something else taps
  the phone about dice nobody can see.

  **`lib/app/tutorial.dart` must not import `picker_screen.dart`.** The picker
  opens the tutorial, so the edge already runs that way; the tutorial reaches
  back through two handles instead. `tutorialBackdrop`, a function the picker
  passes to `showTutorial`, is how it gets its screens, and `AppMenuButton`
  takes an `onTutorial` callback so **How to use** does not have to know what
  it opens either. The three spots that had no name before — `kCardPanel`,
  `kRack`, `kRollButton` — are declared in `tutorial.dart` and used in
  `picker_screen.dart`, which is the same trick in the other direction and the
  reason they live somewhere surprising.

  A spot is found by walking the element tree for a `ValueKey`, scoped to the
  stage the page names. Not a `GlobalKey`: with two pickers on screen a global
  key on anything the picker draws would collide the moment the second one was
  built. And the scoping is not optional — both backdrop pickers build *both*
  of their own pages, so there are two racks and two card panels in the tree at
  any moment, one of each pair translated a screen width off to the side.
