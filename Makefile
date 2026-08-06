# Roll Hippo — dice tray.
#
# The app lives in src/, matching Roll Hippo 1's layout.

SRC      := src
DEVICE   ?= 00008110-000414C63A51401E   # Jason's iPhone
SCRATCH  ?= /tmp/rollhippo

.DEFAULT_GOAL := help
.PHONY: help all format analyze test desktop ios gif filmstrip clean

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
	@# Debug mode cannot run on iOS 18.4+ with Flutter 3.29.2 (flutter#163984),
	@# so the device build is --profile. That costs hot reload; changing the
	@# feel means `make ios` again, or tune on the desktop harness first.
	cd $(SRC) && flutter build ios --profile
	cd $(SRC) && flutter install -d $(DEVICE) --profile

gif:  ## Render a scripted roll to an animated GIF
	@mkdir -p $(SCRATCH)
	cd $(SRC) && GIF_OUT=$(SCRATCH)/roll.gif flutter test tool/roll_gif.dart
	@echo "→ $(SCRATCH)/roll.gif"

filmstrip:  ## Render a scripted roll to a contact sheet
	@mkdir -p $(SCRATCH)
	cd $(SRC) && FILMSTRIP_OUT=$(SCRATCH)/filmstrip.png flutter test tool/filmstrip.dart
	@echo "→ $(SCRATCH)/filmstrip.png"

clean:  ## Remove build output
	cd $(SRC) && flutter clean
