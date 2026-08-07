# Roll Hippo — App Store listing copy

Everything App Store Connect asks for, in the order it asks. Paste each block
verbatim; the character counts are measured, not estimated, and each sits under
Apple's limit for that field.

Google Play reuses most of this — see the note at the bottom.

---

## 1. App Name

**Limit 30 · using 10**

```
Roll Hippo
```

---

## 2. Subtitle

**Limit 30 · using 29**

```
Dice roller with real physics
```

Apple indexes app name + subtitle + keywords together, and *not* the
description. "Roll Hippo" carries no search value on its own, so the subtitle
spends its characters on "dice roller" — the phrase people type — and on the
one word that separates this from the animated-RNG apps. It deliberately does
not say "D4 to D20"; those are cheaper in the keyword field below.

---

## 3. Keywords

**Limit 100 · using 94**

```
d20,d4,d6,d8,d10,d12,polyhedral,rpg,ttrpg,tabletop,boardgame,craps,farkle,3d,tray,shake,random
```

No spaces after the commas — a space costs a character and buys nothing.
Nothing here repeats a word already in the name or subtitle, because Apple
searches the fields as one pooled bag and a repeat is a wasted slot. Singular
forms only; Apple matches plurals itself.

Two omissions are on purpose. **Yahtzee** is a Hasbro trademark and **D&D** is
Wizards of the Coast's; using either as a keyword is a metadata rejection and,
if it sticks, a takedown request later. `craps`, `farkle` and `backgammon` are
generic and safe.

---

## 4. Promotional Text

**Limit 170 · using 168**

```
Roll real dice in a box the size of your screen — a rigid-body simulation, not an animation. Or deal the same odds from a shoe instead: every outcome, shuffled and cut.
```

This is the only field you can change without shipping a new build, so it is
where a seasonal note or a "now with X" goes later. For 1.0 it restates the
hook above the fold and adds the one feature the subtitle has no room for.

Two words in it are load-bearing, and both are the honest version of a claim
that is easy to overstate:

- **"the same odds"**, not "statistically accurate cards". A card is not a suit
  and a rank — `PlayingCard` holds one face per die, and the deck is every
  *ordered* outcome, six to the power of the dice. The shoe is then drawn
  without replacement on purpose, which is what `reshuffleAt` and the cut card
  are for, so as it is dealt the odds knowingly stop matching a roll. Claiming
  accuracy claims the opposite of the feature.
- **"and cut"** does the same work in three characters: it says out loud that
  this is a shoe rather than a re-roll, so nobody arrives expecting one.

The earlier draft — `Ten dice, six solids, and a box the size of your screen
with a real rigid-body simulation inside it. The face you read is the face it
landed on, not one that was picked.` — is 169 characters and says nothing about
card mode. It is the better line if this field is ever needed for the dice
alone.

---:q
## 5. Description
:
**Limit 4000 · using 2473**

Only the first two or three lines show before the "more" link, which is why the
opening sentence is the whole argument.

```
Most dice apps pick a number first and animate a cube to agree with it. Roll Hippo doesn't. It runs a real rigid-body simulation — mass, inertia, friction, bounce — inside a box the size of your screen, and the face you read is the face the die actually landed on.

The box is simulated in the phone's own frame of reference. The walls never move; what moves is the gravity inside them, and that comes straight off the accelerometer. So there is no shake threshold and no gesture detector, and no seam where tilting stops and shaking starts. Tip the phone and the dice slide. Flick your wrist and they tumble, because a die under no torque holds its orientation in the world while the box turns around it. That is the whole idea, and it is why they land like dice instead of sliding like counters.

WHAT'S IN IT

• Up to ten dice at once — any mixture of D4, D6, D8, D10, D12 and D20, each its own colour.
• Six solids, every one of them fair. Each is built from its vertices alone and every face sits the same distance from the centre, which is what fairness in a die actually means.
• Real weights and real sizes. A 16 mm D6 weighs 4.8 g here because it does in your hand, and a D20 is heavier than a D4 because acrylic has a density and the shapes have volumes.
• Haptics keyed to impact, not to speed. A heavy die hitting a wall hard feels different from a light one nudging it.
• Card mode. The same odds dealt from a shoe instead of thrown — every ordered outcome, shuffled, and drawn without replacement the way a real deck is.
• Profiles. Save the set of dice a game needs, give it a name, and open it straight to that page next time.
• Share by QR code. The whole setup — every die, its kind, its colour, the page you were on and the name you saved it under — onto the next player's phone in one scan.
• Motion optional. If you would rather not shake anything, turn motion off: down becomes down the screen and the buttons do everything.

A NOTE ON THE HIPPOPOTAMUS

There is one. It is a six-sided die like any other, with the same numbering and the same inertia, and it is exactly as fair as the cube it is. Finding it is left to you.

PRIVACY

Roll Hippo makes no network connection of any kind. There are no accounts, no analytics, no advertising, no tracking and nothing to collect. Your dice, your saved profiles and your settings never leave the phone. The camera is used in exactly one place — reading a shared QR code — and only while that screen is open.
```

---

## 6. What's New in This Version

Leave blank for 1.0 — Apple does not require it on a first release, and
"Initial release" tells a reader nothing they cannot see.

---

## 7. URLs

| Field | Required | Value |
|---|---|---|
| Support URL | **Yes** | `https://hippoherd.com/rollhippo/support` |
| Marketing URL | No | `https://hippoherd.com/rollhippo` |
| Privacy Policy URL | **Yes** | `https://hippoherd.com/rollhippo/privacy` |

All three depend on the website. The privacy policy is the blocking one — Apple
will not let you submit without a reachable URL, and it must be reachable at
review time, not just at submission time. It can be one short page; the truthful
version of it is three sentences long.

---

## 8. App Information

| Field | Value |
|---|---|
| Primary Category | Utilities |
| Secondary Category | Entertainment *(optional)* |
| Content Rights | Does **not** contain, show or access third-party content |
| Age Rating | Answer every question "None" → **4+** |

On the age rating: there is no wagering, no scoring, no casino simulation and
nothing bought or lost. A dice tray is a tool. If Apple's questionnaire asks
about contests or gambling, the honest answer to all of them is none.

---

## 9. App Privacy

Select **Data Not Collected**, and answer nothing further — the questionnaire
ends there.

This is true and worth keeping true: the app opens no socket. `shared_preferences`
writes the haptic calibration and the saved profiles to the device and nowhere
else, and the camera frames from the QR scanner are processed in memory and
never stored or transmitted.

---

## 10. Export Compliance

Already answered in code — `ITSAppUsesNonExemptEncryption` is set to `false` in
`src/ios/Runner/Info.plist`, so App Store Connect will stop asking on every
upload. Nothing to do here.

---

## 11. App Review Information

Sign-in required: **No**. Demo account: not needed. Contact: your name, phone
and email.

**Notes:**

```
Roll Hippo is a dice tray. It needs no account, no sign-in and no network connection, and it collects no data.

Two permissions are requested, both optional to the app's main use:

1. MOTION — the dice are simulated in the phone's frame of reference, so the accelerometer and gyroscope supply the gravity and the shake. Denying it, or turning "Motion control" off in Settings, leaves the app fully usable: gravity then points down the screen and the Throw and Draw buttons do everything.

2. CAMERA — used in one place only. The app menu (the three lines, top left) has a Share item that turns the current set of dice into a QR code, and a Scan item that reads one back off another phone. The camera is opened only while the Scan screen is showing.

TO TEST THE SCANNER without a second device, a valid code is attached to this submission. Open the menu, choose Scan, and point the phone at the attached image on your monitor. It will load a set of dice named "Yahtzee-style". The same codes can be generated in-app from Share, so a second device with the app installed also works.

Because the tray is driven by the accelerometer, the Simulator will show dice resting on the floor and not tumbling. Please test on a physical device — shake the phone, or use the Throw button, which works everywhere.
```

⚠️ **Attach a QR code image to the submission.** This is the one thing likely to
stall the review. A reviewer who cannot exercise the camera feature sometimes
rejects on the permission alone. Generate one with `make screenshots`, or from
Share on a device, and add it under App Review Information → Attachment.

---

## 12. Screenshots

`make screenshots` writes six framed shots at 1290 × 2796. The captions live in
`src/tool/appstore.dart` and are already written:

| File | Caption |
|---|---|
| `01-tray` | Shake it. / Read what it says. |
| `02-picker` | Six solids, D4 to D20. / Any colour each. |
| `03-full-tray` | Ten at once, / in a box you can feel. |
| `04-cards` | Same odds, dealt. / No table needed. |
| `05-profiles` | Every game you play, / saved and named. |
| `06-share` | Hand the whole setup / to the next player. |

Two things worth changing before you upload:

- **Shot 05 shows profiles named "Yahtzee" and "D&D".** Both are registered
  trademarks, and a screenshot is a more visible use of one than a keyword is.
  Rename them in `appstore.dart` — `Five Dice` and `Adventure` keep the shot
  saying exactly what it says now with none of the exposure. `Craps`,
  `Backgammon` and `Farkle` are generic and can stay.
- **Shot 01 is the one that appears in search results**, next to the subtitle,
  and it is the only screenshot most people will ever see. "Shake it. / Read
  what it says." describes the gesture but not the reason to care. Consider
  `They land where they land.` or `The face you read / is the face it landed on.`

---

## Reusing this for Google Play

Play asks for a different shape and mostly less of it:

| Play field | Limit | Source |
|---|---|---|
| App name | 30 | Same — `Roll Hippo` |
| Short description | 80 | Below — the subtitle is too short for it, the promo text too long |
| Full description | 4000 | Section 5 verbatim; Play *does* index it, so it earns its keywords |
| Screenshots | 2–8 | The same 1290 × 2796 files; Play is far looser about size |

There is no keyword field on Play — the name, the short description and the
full description are indexed instead, which is the one real difference in how
the copy has to work.

### Short description

**Limit 80 · using 77**

```
3D dice roller with real physics. D4 to D20, ten at once, in a box you can shake.
```

This is a different job from Apple's subtitle, and copying that one across
would waste the field. Apple pools name + subtitle + keywords into one bag and
indexes the description not at all, so the subtitle could spend all 30
characters on `Dice roller with real physics` and leave `d4`,`d20`,`polyhedral`
to the keyword field. Play has no keyword field. `Roll Hippo` carries no search
value on its own and the full description is indexed but weighted far below the
short one, so this is the only short, high-weight field there is — which is why
it carries the shapes itself rather than deferring them.

`3D` earns its two characters: it is a phrase people type, and it is the axis
this app actually wins on. `ten at once` and `a box you can shake` are there
because they are true and specific; a promise about physics that stays abstract
reads like every other listing's.

⚠️ **The full description has a gap on Play that it does not have on Apple.**
Section 5 never uses the words *dice roller*, *3D* or *polyhedral* — it opens
with "Most dice apps", which is an argument rather than a keyword. That costs
nothing on the App Store, where the description is not indexed at all, but on
Play it is the index. Before uploading, consider working those three terms into
the opening paragraph and the WHAT'S IN IT list without bending a sentence out
of shape. The line about the six solids is the natural home for *polyhedral*.
