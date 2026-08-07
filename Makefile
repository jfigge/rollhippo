# Roll Hippo — dice tray.
#
# The app lives in src/, matching Roll Hippo 1's layout.

SRC      := src
DEVICE   ?= 00008110-000414C63A51401E   # Jason's iPhone
SCRATCH  ?= /tmp/rollhippo

# The Android phone, by its `adb devices` id. Blank means "the only one
# attached", which is the usual case; name one when there are two.
ANDROID_DEVICE ?=

.DEFAULT_GOAL := help
.PHONY: help all format analyze test desktop ios android gif filmstrip picker cards hippo icon clean

help:  ## Show this help
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2}'

all: format analyze test  ## Format, analyse and test

format:  ## Format all Dart sources
	cd $(SRC) && dart format lib test tool

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

icon:  ## Draw the app icon into the iOS, macOS and Android catalogues
	@# Writes into the project, not /tmp: the files it makes are the icon.
	cd $(SRC) && flutter test tool/app_icon.dart

clean:  ## Remove build output
	cd $(SRC) && flutter clean
