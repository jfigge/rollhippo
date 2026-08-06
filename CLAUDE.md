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
| `make ios` | `--profile`, not debug: debug cannot run on iOS 18.4+ with Flutter 3.29.2 (flutter#163984). That costs hot reload on device — tune on the harness, confirm on the phone |

Raw `flutter`/`dart` commands must run from `src/`, which is the package root.

## Layout, and the one invariant

```
src/lib/physics/   body (RigidBody) · shape (ConvexShape) · collision · contact · solver · world
src/lib/tray/      tray (walls + DiceTray) · tuning (Tuning) · dice (DieKind · DieSpec · faceValue)
src/lib/motion/    MotionSource — the sensors, and a synthetic phone for the harness
src/lib/render/    TrayCamera · TrayPainter
src/lib/app/       ConfigScreen (choose the dice) · TrayScreen (throw them)
src/test/          headless
src/tool/          filmstrip · roll_gif · one_die — run via `flutter test`, they write image files
```

`tray.dart` re-exports `dice.dart` and `tuning.dart`, so one
`import 'tray/tray.dart'` still brings `Tuning`, `DieSpec` and `DieKind` with it.

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
