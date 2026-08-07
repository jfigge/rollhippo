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

.DEFAULT_GOAL := help
.PHONY: help all ci format format-check analyze test desktop ios android ipa upload gif filmstrip picker cards hippo screenshots screenshots-65 site icon clean

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
	@echo "→ appstore/  (upload these)"
	@echo "→ website/images/screens/  (the site and the guide)"

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

icon:  ## Draw the app icon, and both launch images, into the catalogues
	@# Writes into the project, not /tmp: the files it makes are the icon.
	cd $(SRC) && flutter test tool/app_icon.dart

clean:  ## Remove build output
	cd $(SRC) && flutter clean
