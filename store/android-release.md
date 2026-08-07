# Roll Hippo — shipping to Google Play

`listing.md` is the copy. This is the machinery: what has to exist before Play
will take a build, what the Console asks that App Store Connect never did, and
the order to do it in.

It assumes the iOS submission has already happened, because it has, and spends
most of its time on the places where Play is *not* Apple with different words.

---

## The one that decides your calendar

Everything else here is an afternoon. This is not.

**A personal developer account cannot publish straight to production.** Google
requires a closed test first — **at least 12 testers, opted in and staying
opted in for 14 continuous days** — after which you apply for production
access and wait for that to be granted. The 14 days are a floor, not an
estimate, and the counter resets if the tester count drops below twelve.

Two things follow, and both are worth acting on before anything else:

- **Start the closed track the day the first `.aab` builds.** Every other item
  on this list can be done while the clock runs. Nothing can be done to make
  the clock shorter.
- **Twelve is twelve real Google accounts**, each of which must actually opt in
  via the tester link. Family and friends count; a spreadsheet of addresses
  that never click the link does not.

Organisation accounts are exempt from this, but an organisation account needs a
D-U-N-S number and its own verification, so it is not a shortcut unless the
company already exists.

⚠️ **Check the current numbers in the Console rather than trusting this
paragraph.** Google has changed the tester count and the duration more than
once since the rule was introduced, and this file is only as fresh as the last
person to edit it.

Beyond that: registration is **$25, once** — not $99 a year — and identity
verification (government ID and proof of address, for an individual) is its own
few days. Do it first.

---

## What was missing from the repo, and now is not

Five things were wrong or absent when the iOS build shipped. All five are
fixed; this section is what they were, so that a future change does not quietly
undo one.

The first four were found by reading the repo against Play's rules. The fifth
was found by plugging in a cheap Android phone, and could not have been found
any other way — which is the argument for owning one, made better than the
paragraphs above make it.

### The release build was signed with the debug key

`android/app/build.gradle.kts` carried the Flutter template's TODO and pointed
the release build type at `signingConfigs.getByName("debug")`. Play rejects a
debug-signed upload outright.

It now reads `android/key.properties` and uses that, **falling back to the
debug key when the file is absent**. The fallback is deliberate and load-bearing
— CI builds a release APK on every push and must keep doing so without being
handed a real signing key. The worst the fallback can produce is something that
only sideloads.

### The package declared `INTERNET`

`website/privacy.html` says, in bold, that the Android release package is built
without it, and offers that as the reason the no-network claim cannot be
quietly reversed. It was not true: `mobile_scanner` → ML Kit →
`com.google.android.datatransport:transport-backend-cct` declares `INTERNET`
in its library manifest, and the merged manifest carried it.

`android/app/src/release/AndroidManifest.xml` now removes it with
`tools:node="remove"`. Verified against the built APK, not the intermediate:

```
$ aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk
uses-permission: name='android.permission.CAMERA'
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
```

`ACCESS_NETWORK_STATE` is left in on purpose — it reads whether a network
exists and cannot transmit anything, and removing it would make
`ConnectivityManager` throw inside ML Kit where nothing here could catch it.
The privacy page does not currently mention it. It is not a false statement,
but it is the one thing on that page a curious reader with `aapt2` could ask
about.

### Play would have rejected the screenshots

Two separate rules, and Apple's files fail both:

| Rule | Apple's files |
|---|---|
| No side more than twice the other | 2796 / 1290 = **2.167** |
| No alpha channel — 24-bit PNG or JPEG | the engine always writes **RGBA** |

The first is not a Roll Hippo problem, it is a *phone* problem: every handset
shaped like a handset since about 2018 is 19.5:9, and Connect insists on
exactly that shape.

`make screenshots-play` now renders a third slot — the same six captures on a
1400 × 2796 frame, which is 1.997, with the phone left exactly where it was and
the extra 110 px a side going to background. Written without an alpha channel.
See `kSlotPlay` in `tool/appstore.dart`.

### There was no feature graphic

Play requires a **1024 × 500** banner that Apple has no equivalent of.
`make screenshots-play` writes it to `appstore/play/feature-graphic.png`,
composed from the 512 icon `make icon` already produces and the first capture,
so it cannot drift from the listing it sits above.

### The app threw twice on launch on any phone without a gyroscope

`SensorMotionSource` opened three sensor streams and gave none of them an
`onError`. On iOS that is invisible, because every iPhone has all three. On
Android it is not: `sensors_plus` does not hand back a stream that stays quiet
for a sensor the phone lacks, it completes the subscription with a
`PlatformException(NO_SENSOR)`. An unhandled stream error is an unhandled
exception, and there were two of them on every cold start:

```
E/flutter: Unhandled Exception: PlatformException(NO_SENSOR, Sensor not found,
           It seems that your device has no Gyroscope sensor, null)
E/flutter: Unhandled Exception: PlatformException(NO_SENSOR, Sensor not found,
           It seems that your device has no User Accelerometer sensor, null)
```

Found on a **BLU B1660V** — Android 15, a MediaTek budget handset whose entire
sensor complement is an accelerometer, a light sensor, a barometer, a proximity
sensor and a step counter. No gyroscope, no fused linear acceleration, no
magnetometer. That is not an exotic device; it is a large slice of what a free
dice app gets installed onto.

`lib/motion/motion.dart` now gives all three `listen` calls an `onError` that
does nothing, and says at length why doing nothing is right. Verified by
cold-launching against a cleared `logcat`: two matches before, zero after.

**The degradation was already correct — only the noise was new.** `sample()`
guards every reader behind a count, so the missing sensors cost exactly what
they should and nothing crashed even before the fix:

| Missing | Costs |
|---|---|
| Gyroscope | The rotational pseudo-forces. A wrist flick no longer adds tumble — the state the harness's **G** key toggles. Tilt and shake are unaffected, because those are the accelerometer. |
| Fused linear acceleration | The clean split of movement from gravity. "Down" drags around during a hard shake. Android derives this by sensor fusion, so a phone with no gyroscope generally has no linear-acceleration sensor either — the comment in `motion.dart` that assumed "iOS and Android both supply the good one" was wrong, and now says so. |

Two things worth recording from that session, because neither is guessable:

- **The tray held ~90 fps on that phone**, frame times 10.2–12.1 ms against an
  11.1 ms budget on a 90 Hz panel. The solver runs in Dart on every frame and
  it keeps up on the low end.
- **The vibrator reports `capabilities = []` and `supportedPrimitives = []`** —
  no amplitude control, only canned CLICK/TICK effects. The impulse-keyed
  haptic, where a D20 registers harder than a D4, cannot be expressed on that
  class of device at all. It is not broken; it is flat.

---

## The build

```
make keystore   # once, ever
make aab        # every release
```

### `make keystore`

Generates `keys/rollhippo-upload.jks` and refuses if one is already there. It
then prints the four lines to put in `src/android/key.properties`.

Both that file and `keys/` are gitignored, as are `*.jks` and `*.p12`.

Two things about this key that are genuinely different from Apple:

- **Nobody issues it.** There is no equivalent of the Apple Distribution
  certificate. You make it, and the first bundle you upload is what tells Play
  which key to expect from then on.
- **It is an *upload* key, not the signing key.** Under Play App Signing —
  mandatory for new apps — Google holds the key that signs what phones actually
  install, strips yours at the door and re-signs. So losing this file is
  recoverable: Google resets an upload key on request. That is a support ticket
  and several days, so back it up anyway, along with the passwords, which are
  useless apart from it.

### `make aab`

An **App Bundle**, not an APK — Play has not accepted an APK for a new app
since 2021. The `.aab` is not installable; it is the ingredients, and Play
generates a per-device APK from it at download time.

The target refuses to run without `key.properties`, because the build would
otherwise succeed, be signed with the debug key, and be rejected at the upload
form an hour later.

`versionCode` comes from the `+N` in `src/pubspec.yaml`, exactly as the iOS
build number does. Play refuses a `versionCode` it has already seen, so a
second upload means bumping it and rebuilding — the same ceremony as
`make upload`.

---

## What the Console asks for

### Reused from the Apple submission

| Field | Where it is |
|---|---|
| App name | `listing.md` §1 — `Roll Hippo` |
| Full description | `listing.md` §5, verbatim |
| Screenshots (2–8) | `appstore/play/*.png` |
| 512 × 512 icon | `src/android/app/src/main/ic_launcher-playstore.png` |
| Feature graphic | `appstore/play/feature-graphic.png` |
| Privacy policy URL | `https://hippoherd.com/rollhippo/privacy` |

### Written for Play specifically

**Short description**, 80 characters, in `listing.md`'s "Reusing this for
Google Play" section. Do not paste Apple's subtitle here — that field was
written knowing Apple pools name + subtitle + keywords and indexes the
description not at all. Play has no keyword field, so the short description is
the only short high-weight field there is, and it has to carry the shapes
itself.

⚠️ `listing.md` flags that the full description never uses the words *dice
roller*, *3D* or *polyhedral*. On Apple that costs nothing. On Play the
description **is** the index. Worth working them in before uploading.

**Support email.** Play requires an address, where Apple required a URL. The
website's support page covers the URL field, which is optional here.

### Four forms Apple has no equivalent of

- **Data safety.** Play's version of App Privacy, but longer, and it explicitly
  asks about bundled third-party SDKs rather than only your own code. The
  answer is "no data collected" — but read ML Kit's data-disclosure page first,
  given that it is the reason `INTERNET` was in the manifest at all.
- **Content rating.** An IARC questionnaire. No wagering, no scoring, no casino
  simulation, nothing bought or lost — a dice tray is a tool. Answer honestly;
  a wrong answer here is a takedown later rather than a rejection now.
- **Target audience and content.** Saying the app appeals to children inherits
  the whole Families policy. It does not; say 13+.
- **Ads, government app, financial features.** All no.

### The trademark note applies harder here

`listing.md` §12 says to rename the "Yahtzee" and "D&D" profiles in the
profiles screenshot before uploading. Play's enforcement on this is more
automated and less forgiving than Apple's. `Five Dice` and `Adventure` keep the
shot saying exactly what it says now. **Rename them in `tool/appstore.dart`
and re-run both screenshot targets** — the Play set is rendered from the same
code, so a rename fixes both at once.

---

## Order

1. Register, pay the $25, start identity verification.
2. `make keystore`, write `key.properties`, back the `.jks` up off this machine.
3. `make android` onto a real phone, and read `logcat`. Cheap, and it is where
   the `NO_SENSOR` bug came from — the suites cannot see a sensor that is not
   there and neither can the emulator.
4. `make aab`. Confirm it is signed with the upload key rather than the debug
   one before uploading anything:

   ```
   unzip -p <aab> META-INF/UPLOAD.RSA | keytool -printcert | grep SHA256
   ```

   That fingerprint is what Play Console → Setup → App signing will show after
   the first upload. They must match.
5. Upload to a **closed testing** track. Recruit twelve testers. **Clock starts.**
6. While it runs: `make screenshots` then `make screenshots-play`, the four
   forms, the listing text, the trademark renames.
7. Apply for production access.
8. Promote the build to production.

Steps 1 and 5 are the only ones with a queue in front of them. Everything
between them is one evening.

---

## Traps

- **`make screenshots-play` runs *after* `make screenshots`, not instead of
  it.** The feature graphic is composed from the website's copy of the first
  capture, which only the 6.9" run writes. The tool says so plainly if it is
  missing, rather than rendering a banner with a hole in it.
- **`applicationId` is frozen at the first upload.** It is
  `com.rollhippo.rollhippo`, matching the iOS bundle identifier. There is no
  changing it afterwards short of publishing a second app.
- **Three of the six captures are not reproducible between runs.** `01-tray`,
  `03-full-tray` and `04-cards` show thrown dice and land differently each
  time; the other three are byte-identical run to run. So a re-render always
  shows those three as modified in `git status`, and that is not a signal that
  anything changed. If the uploaded shots matter, `git checkout` them.
- **CI still builds a debug-signed release APK, on purpose.** It proves AOT,
  R8, the pods and the merged manifest still work. It is not a shippable
  artefact and the workflow names it so nobody mistakes it for one.
- **Nothing here uploads.** There is no `make` equivalent of `make upload` for
  Play. The Console's web form is the whole path for a first submission;
  automating it via the Play Developer API is worth doing only once the manual
  route has been walked at least once.
- **Android hardware is not one thing, and the accelerometer is the only part
  of it you can count on.** Anything reading a sensor has to survive that
  sensor being absent — not by testing for it, but by handling the stream
  error, because that is the shape `sensors_plus` reports it in. The emulator
  will not catch this: it exposes a full sensor suite and no vibration motor at
  all, so it is the exact inverse of the budget phone it is standing in for.
- **The emulator cannot answer the only question worth asking about the feel.**
  It has draggable virtual sensors, which is enough to see the dice slide, and
  no haptics whatsoever. Between it and a gyro-less budget phone, neither can
  tell you whether a wrist flick tumbles the dice the way the tuning intends —
  that needs a mid-range or better Android with a gyroscope. Until one exists,
  the twelve closed testers are the instrument, and they should be asked about
  shake and haptics specifically rather than "any bugs?".
