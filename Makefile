# Roll Hippo — dice tray.
#
# The app lives in src/, matching Roll Hippo 1's layout.

SRC      := src
DEVICE   ?= 00008110-000414C63A51401E   # Jason's iPhone
SCRATCH  ?= /tmp/rollhippo

# Where hippoherd is checked out. Roll Hippo's website is written here and
# served from there — see the `site` target.
HERD     ?= $(CURDIR)/../../../js/projects/hippoherd

# The Android phone, by its `adb devices` id. Blank means "the only one
# attached", which is the usual case; name one when there are two.
ANDROID_DEVICE ?=

# App Store Connect, for `upload`. The issuer and key ids are not themselves
# secrets, but the .p8 they name is, so all three stay together: the ids in
# release.env and the key in keys/, both gitignored. Between them they are the
# whole of what a new machine has to be given before it can ship.
-include release.env
KEYS ?= $(CURDIR)/keys
IPA  ?= $(SRC)/build/ios/ipa/rollhippo.ipa

# Play's half of the same arrangement. The upload key lives beside the Apple
# one and is gitignored by both `keys/` and `*.jks`; the passwords that open it
# live in src/android/key.properties, which is gitignored by name. Neither is
# a certificate anybody issued — you make this key yourself, once, with
# `make keystore`, and Play remembers its fingerprint from the first upload
# onwards. See android/app/build.gradle.kts for what reads it.
KEYSTORE ?= $(KEYS)/rollhippo-upload.jks
AAB      ?= $(SRC)/build/app/outputs/bundle/release/app-release.aab

.DEFAULT_GOAL := help
.PHONY: help all ci format format-check analyze test desktop ios android ipa upload keystore aab gif filmstrip picker cards hippo screenshots screenshots-65 screenshots-play site icon clean

help:  ## Show this help
	@# firstword, not the whole list: `-include release.env` puts that file
	@# in MAKEFILE_LIST too, and grep over two files prefixes every match
	@# with the filename, which is exactly where awk looks for the target.
	@grep -E '^[a-z0-9-]+:.*?## ' $(firstword $(MAKEFILE_LIST)) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-14s\033[0m %s\n", $$1, $$2}'

all: format analyze test  ## Format, analyse and test

ci: format-check analyze test  ## What CI checks, minus the builds
	@# The same three things .github/workflows/ci.yml runs, in the same
	@# order, so a green run here means a green run there. It differs from
	@# `all` in one way and on purpose: it checks the formatting rather
	@# than applying it.

format:  ## Format all Dart sources
	cd $(SRC) && dart format lib test tool

format-check:  ## Report formatting drift instead of fixing it
	@# The same file set as `format`, but it fails rather than rewrites.
	@# CI has to report the drift: a reformat in a checkout that is thrown
	@# away at the end of the job would fix nothing and hide it.
	cd $(SRC) && dart format --output=none --set-exit-if-changed lib test tool

analyze:  ## Static analysis, warnings fatal
	cd $(SRC) && flutter analyze --fatal-infos --fatal-warnings

test:  ## Physics and fairness suites (headless, no device)
	cd $(SRC) && flutter test

desktop:  ## Run the desktop harness — phone-sized tray, simulated shake
	cd $(SRC) && flutter run -d macos

ios:  ## Build and install on the iPhone
	@# --profile, and now by choice rather than by force. Debug was once
	@# impossible here (flutter#163984, iOS 18.4+ on Flutter 3.29.2); since the
	@# upgrade it builds, installs and hot-reloads on the phone perfectly well.
	@# It stays --profile anyway because the solver runs in Dart on every frame,
	@# and under debug's JIT the tray is not the tray that ships — a feel judged
	@# there is a feel judged against the wrong thing. `flutter run -d $(DEVICE)`
	@# when hot reload is worth more than the feel being honest.
	cd $(SRC) && flutter build ios --profile
	cd $(SRC) && flutter install -d $(DEVICE) --profile

android:  ## Build and install on the Android phone
	@# --profile for exactly the reason `ios` is: the solver runs in Dart on
	@# every frame, and under debug's JIT the tray is not the tray that ships.
	@# `flutter run -d <id>` when hot reload is worth more than the feel.
	cd $(SRC) && flutter build apk --profile
	@# The device is looked up rather than left to `flutter install`, which
	@# picks for itself when it is not told — and what it picks is the only
	@# mobile device attached, which on this machine is the iPhone. It will
	@# then cheerfully uninstall Roll Hippo from the phone to make room for a
	@# build that was never going to run on it. So: ask for an Android one by
	@# name, and stop if there is not one.
	@id=$${ANDROID_DEVICE:-$$(cd $(SRC) && flutter devices --machine | python3 -c \
	    "import json,sys; d=[x for x in json.load(sys.stdin) if str(x.get('targetPlatform','')).startswith('android')]; print(d[0]['id'] if d else '')")}; \
	  if [ -z "$$id" ]; then \
	    echo "make android: no Android device attached."; \
	    echo "  Plug one in, or name it with ANDROID_DEVICE=<id>."; \
	    echo "  The APK is built and waiting at $(SRC)/build/app/outputs/flutter-apk/."; \
	    exit 1; \
	  fi; \
	  echo "installing to $$id"; \
	  cd $(SRC) && flutter install -d "$$id" --profile

gif:  ## Render a scripted roll to an animated GIF
	@mkdir -p $(SCRATCH)
	cd $(SRC) && GIF_OUT=$(SCRATCH)/roll.gif flutter test tool/roll_gif.dart
	@echo "→ $(SCRATCH)/roll.gif"

filmstrip:  ## Render a scripted roll to a contact sheet
	@mkdir -p $(SCRATCH)
	cd $(SRC) && FILMSTRIP_OUT=$(SCRATCH)/filmstrip.png flutter test tool/filmstrip.dart
	@echo "→ $(SCRATCH)/filmstrip.png"

picker:  ## Render the picker in both modes, and every kind at rack size
	@mkdir -p $(SCRATCH)
	cd $(SRC) && PICKER_OUT=$(SCRATCH) flutter test tool/picker.dart
	@echo "→ $(SCRATCH)/picker*.png, $(SCRATCH)/kinds.png"

cards:  ## Render the card table, and a gif of a card being dealt
	@mkdir -p $(SCRATCH)
	cd $(SRC) && CARDS_OUT=$(SCRATCH) flutter test tool/cards.dart
	@echo "→ $(SCRATCH)/cards-*.png, $(SCRATCH)/cards-deal.gif"

hippo:  ## Render the hippopotamus — every pose a roll can present it in
	@mkdir -p $(SCRATCH)
	cd $(SRC) && HIPPO_OUT=$(SCRATCH)/hippo.png flutter test tool/hippo.dart
	@echo "→ $(SCRATCH)/hippo.png"

screenshots:  ## Render the store listing's screenshots, and the site's gallery
	@# Writes into the project, not /tmp, for the same reason `icon` does: the
	@# files it makes ARE the listing you upload and ARE the pictures the
	@# website and the guide are built around. Two sizes from one capture —
	@# appstore/ is framed at Apple's exact 1290x2796, website/images/screens/
	@# is the bare screen at half that. See tool/appstore.dart.
	cd $(SRC) && APPSTORE_OUT=$(CURDIR) flutter test tool/appstore.dart
	@echo "→ appstore/  (upload these to Connect)"
	@echo "→ website/images/screens/  (the site and the guide)"
	@echo "  Play needs its own set — run 'make screenshots-play' too."

screenshots-65:  ## Render the listing again, for Apple's second iPhone slot
	@# The same six captures at 414x896 and 3x, which is 1242x2688 — the 6.5"
	@# slot. Apple requires only the 6.9" set `screenshots` makes and scales
	@# it down itself for everything smaller, so this is optional; what it
	@# buys is that a listing read on a 6.5" phone shows these untouched
	@# rather than Apple's resample of a taller shot.
	@#
	@# Rendered, not resized. The app is laid out at that phone's logical
	@# size and captured there, which keeps the shot sharp, gets the aspect
	@# exactly right — 430:932 and 414:896 are close but not equal — and,
	@# the part that actually moves controls, gives it that phone's safe
	@# area: 44pt for the notch, where the 6.9" has 59 for the Island.
	@#
	@# It writes no website pictures and no hero. Those belong to the 6.9"
	@# run; see `Slot.web` in tool/appstore.dart.
	cd $(SRC) && APPSTORE_OUT=$(CURDIR) APPSTORE_SLOT=6.5 flutter test tool/appstore.dart
	@echo '→ appstore/6.5/  (upload these into the 6.5-inch slot)'

screenshots-play:  ## Render the listing for Play, which will not take Apple's
	@# Not optional, the way `screenshots-65` is. Play's rule is a shape
	@# rather than a size — no side more than twice the other — and 1290 x
	@# 2796 is 2.167, so the files Connect insists on are the files Play
	@# refuses. It also rejects an alpha channel outright. Both are handled
	@# in the slot rather than here; see `kSlotPlay` in tool/appstore.dart.
	@#
	@# Run it after `screenshots`, not instead of it. The feature graphic is
	@# composed from the website's copy of the first capture, which the 6.9"
	@# run is what writes — the tool says so plainly if it is missing.
	cd $(SRC) && APPSTORE_OUT=$(CURDIR) APPSTORE_SLOT=play flutter test tool/appstore.dart
	@echo '→ appstore/play/  (the six, plus the feature graphic, for Play)'

site:  ## Copy the site into hippoherd's Roll Hippo page
	@# Roll Hippo has no site of its own. hippoherd.com/rollhippo IS its site,
	@# and this repository is where that site is written — so this is the one
	@# direction the copy ever goes. hippoherd's generator leaves that one page
	@# alone rather than overwriting it; see `externalSite` in its
	@# content/hippos.mjs, which is what makes this safe.
	@test -d "$(HERD)" || { \
	  echo "make site: no hippoherd checkout at $(HERD)"; \
	  echo "  Clone jfigge/hippoherd beside this repo, or pass HERD=<path>."; \
	  exit 1; }
	@# --exclude .DS_Store because Finder leaves one in any directory it has
	@# been asked to show, and it would otherwise be published and committed.
	rsync -a --delete --exclude .DS_Store website/ "$(HERD)/website/rollhippo/"
	@echo "→ $(HERD)/website/rollhippo/"
	@echo "  Commit and push there; the Pages workflow deploys it."

ipa:  ## Build the signed App Store archive
	@# --release, unlike `ios`: this one *is* the shipping build, so the
	@# argument for --profile — that the feel should be judged against AOT —
	@# is the argument for --release here. Signing is Xcode's automatic
	@# signing against team 2C564TQ2FY; the Apple Distribution certificate
	@# has to be in the keychain for it.
	cd $(SRC) && flutter build ipa --release
	@echo "→ $(SRC)/build/ios/ipa/*.ipa"

upload:  ## Send the built ipa to App Store Connect
	@# Separate from `ipa` on purpose. The archive is worth keeping and worth
	@# re-sending, and an upload that fails at Apple's end should not cost a
	@# rebuild to retry. `make ipa upload` is the pair, when both are wanted.
	@#
	@# --apiKey takes the key's *id*, not a path to it. altool builds the
	@# filename itself — AuthKey_<id>.p8 — and then looks for that name in four
	@# fixed directories: ./private_keys, ~/private_keys, ~/.private_keys and
	@# ~/.appstoreconnect/private_keys. Hand it a path and it searches for
	@# AuthKey_<path>.p8, which is a confusing enough error to be worth the
	@# comment. API_PRIVATE_KEYS_DIR replaces that list outright, and is what
	@# keeps the key in this repo's own keys/ rather than loose in $$HOME.
	@#
	@# Connect rejects a build number it has already seen, so a second upload
	@# of the same archive needs the +N in src/pubspec.yaml bumped and `make
	@# ipa` run again. The version before the + can stay where it is.
	@test -n "$(API_KEY_ID)" || { \
	  echo "make upload: API_KEY_ID is not set"; \
	  echo "  Write it into release.env, beside API_ISSUER_ID."; \
	  exit 1; }
	@test -n "$(API_ISSUER_ID)" || { \
	  echo "make upload: API_ISSUER_ID is not set"; \
	  echo "  Write it into release.env, beside API_KEY_ID."; \
	  exit 1; }
	@test -f "$(KEYS)/AuthKey_$(API_KEY_ID).p8" || { \
	  echo "make upload: no key at $(KEYS)/AuthKey_$(API_KEY_ID).p8"; \
	  echo "  App Store Connect → Users and Access → Integrations issues it."; \
	  exit 1; }
	@test -f "$(IPA)" || { \
	  echo "make upload: no archive at $(IPA) — run 'make ipa' first"; \
	  exit 1; }
	API_PRIVATE_KEYS_DIR="$(KEYS)" xcrun altool --upload-app -t ios \
	  -f "$(IPA)" --apiKey $(API_KEY_ID) --apiIssuer $(API_ISSUER_ID)

keystore:  ## Generate the Play upload key — once, ever
	@# Android has no equivalent of an Apple Distribution certificate. Nobody
	@# issues this; you make it, and the first bundle you upload is what tells
	@# Play which key to expect from then on. So this target runs at most once
	@# in the life of the app, and the refusal below is the point of it.
	@#
	@# It is an *upload* key, not the app signing key. Under Play App Signing
	@# — which is mandatory for new apps — Google holds the key that actually
	@# signs what phones install, strips this one at the door and re-signs.
	@# That makes losing this file recoverable in a way losing an Apple cert
	@# is not: Google resets an upload key on request. Back it up anyway; a
	@# reset is a support ticket and several days.
	@#
	@# No -storetype: keytool's default is PKCS12, which is what a JKS-named
	@# file should contain these days and what Gradle reads without the
	@# migration warning the real JKS format now prints. 10000 days is about
	@# twenty-seven years, comfortably past Play's requirement that the key
	@# outlive 2033.
	@test ! -f "$(KEYSTORE)" || { \
	  echo "make keystore: $(KEYSTORE) already exists."; \
	  echo "  A second key would not replace it — it would be a key Play"; \
	  echo "  does not know, and every build signed with it would be"; \
	  echo "  rejected. Back this file up rather than regenerate it."; \
	  exit 1; }
	@mkdir -p "$(KEYS)"
	keytool -genkeypair -v -keystore "$(KEYSTORE)" \
	  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
	@echo
	@echo "Now write $(SRC)/android/key.properties, with these four lines:"
	@echo
	@echo "    storeFile=$(KEYSTORE)"
	@echo "    storePassword=<the store password you just chose>"
	@echo "    keyAlias=upload"
	@echo "    keyPassword=<the key password you just chose>"
	@echo
	@echo "That file and $(KEYS)/ are both gitignored. Back the .jks up"
	@echo "somewhere that is not this repository, and keep the passwords"
	@echo "with it — they are useless apart."

aab:  ## Build the signed App Bundle for Play
	@# The Play equivalent of `ipa`, and --release for the same reason: this
	@# one is the shipping build, so the argument that made `android`
	@# --profile — judge the feel against what ships — is the argument for
	@# --release here.
	@#
	@# An App Bundle rather than an APK, because Play has not accepted an APK
	@# for a new app since 2021. The .aab is not installable; it is the
	@# ingredients, and Play generates a per-device APK from it at download
	@# time. That is also why the ABI question `make android` raises does not
	@# arise here — the bundle carries every architecture and each phone is
	@# sent only its own.
	@#
	@# Signing is checked rather than assumed. Without key.properties the
	@# build still succeeds, signed with the debug key — build.gradle.kts
	@# falls back on purpose so CI keeps working without being handed a
	@# secret — and Play rejects that upload with an error about a debug
	@# certificate. Better to hear it here than at the upload form.
	@test -f "$(SRC)/android/key.properties" || { \
	  echo "make aab: no $(SRC)/android/key.properties"; \
	  echo "  Without it the bundle is signed with the debug key, which Play"; \
	  echo "  rejects. Run 'make keystore' if you have no upload key yet,"; \
	  echo "  or write the file if you do — see android/app/build.gradle.kts."; \
	  exit 1; }
	cd $(SRC) && flutter build appbundle --release
	@echo "→ $(AAB)"
	@echo "  Play Console → Testing or Production → Create new release."
	@echo "  Play refuses a versionCode it has already seen, exactly as"
	@echo "  Connect refuses a build number: bump the +N in $(SRC)/pubspec.yaml."

icon:  ## Draw the app icon, and both launch images, into the catalogues
	@# Writes into the project, not /tmp: the files it makes are the icon.
	cd $(SRC) && flutter test tool/app_icon.dart

clean:  ## Remove build output
	cd $(SRC) && flutter clean
