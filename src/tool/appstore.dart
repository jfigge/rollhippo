import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rollhippo/app/card_screen.dart';
import 'package:rollhippo/app/picker_screen.dart';
import 'package:rollhippo/app/profiles.dart';
import 'package:rollhippo/app/settings.dart';
import 'package:rollhippo/app/tray_screen.dart';
import 'package:rollhippo/app/tutorial.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/render/tray_painter.dart';
import 'package:rollhippo/tray/tray.dart';

/// Renders the store listing and the user guide's figures. Run with:
///
///     flutter test tool/appstore.dart
///
/// and again, for the other two slots, with:
///
///     APPSTORE_SLOT=6.5  flutter test tool/appstore.dart
///     APPSTORE_SLOT=play flutter test tool/appstore.dart
///
/// Three directories come out of it, from one screen each:
///
///   `appstore/`               the capture dropped onto a branded background
///                             under a caption, at the exact pixel size Apple
///                             accepts. This is an upload and nothing else.
///                             The 6.5" run puts its own set in `6.5/` beneath
///                             it, at 1242 × 2688; see [Slot].
///   `website/images/screens/` the bare screen at half that, which is what the
///                             site and the guide put on a page. No caption:
///                             a figure with marketing copy across the top
///                             contradicts the paragraph it sits next to.
///                             Written by the 6.9" run only — the site wants
///                             one set of pictures, not one per slot.
///   `appstore/play/`          Play's own upload, and its own slot. The same
///                             seven captures on a wider frame, because Play
///                             refuses anything more than twice as long as it
///                             is wide and a modern phone is 2.167; plus the
///                             1024 × 500 feature graphic, which is the one
///                             thing Play asks for that Apple has no
///                             equivalent of. Everything here is written
///                             without an alpha channel. See [kSlotPlay].
///
/// TO RE-RENDER ONE SHOT AND NOT THE REST, name it:
///
///     APPSTORE_OUT=<repo root> flutter test tool/appstore.dart \
///       --plain-name '07 · the tutorial'
///
/// Worth knowing because the dice are not seeded. A tray's `Random` is a fresh
/// one every run, so every capture with dice in it comes out a different roll
/// — which is the honest thing for a tool that photographs a simulation to do,
/// and means a full run rewrites all seven files in a directory the project
/// commits. Naming one leaves the other six byte-for-byte where they were.
/// Only the composites care about their neighbours: the hero is built from
/// three of the web-sized files, so a run that skips those and rebuilds it
/// would compose new pictures with old ones.
///
/// WHY THE FONTS ARE LOADED BY HAND. `flutter test` substitutes a font with no
/// glyphs in it, which is why the sibling tools in this directory all note that
/// their labels come out as blank boxes. That is fine for looking at a shape
/// and useless for a screenshot somebody is meant to read, so this one finds
/// the real Roboto in the Flutter cache and registers it before pumping
/// anything. If it cannot — no `FLUTTER_ROOT`, a cache that moved — it says so
/// and carries on, because a blank-box render is still worth having when you
/// are checking a layout.

/// Logical → device pixels. Every slot below is a real iPhone's screen at 3×,
/// which is the whole reason a slot can be described by its logical size at
/// all.
const double _kScale = 3.0;

/// One slot in App Store Connect's screenshot form.
///
/// Apple takes iPhone screenshots at exactly one of a handful of pixel sizes
/// and rejects everything else — no scaling, no nearest fit. Each of those
/// sizes is a real phone's screen at 3×, so the honest way to hit one is to
/// lay the app out at that phone's logical size and capture it, rather than
/// capture once and resample. Resampling loses on all three counts: it is
/// soft, the aspect ratios are close but not equal so it is fractionally the
/// wrong shape, and — the one that actually moves pixels the eye notices — it
/// carries the wrong safe area. A Dynamic Island insets the top by 59, the
/// notch it replaced by 44, and the tray's control row sits inside a
/// `SafeArea` that believes whichever it is told.
class Slot {
  const Slot({
    required this.screen,
    required this.safeTop,
    required this.safeBottom,
    required this.dir,
    required this.web,
    this.canvas,
    this.opaque = false,
  });

  /// The phone's screen in logical pixels. At [_kScale] this is [pixels].
  final Size screen;

  /// The insets that phone actually has, in logical pixels — whatever is
  /// above the screen and the home indicator below it.
  ///
  /// Set on the test view rather than left at zero because the app asks for
  /// them: a capture taken without them puts Close and Throw where no thumb
  /// on a real phone would find them.
  final double safeTop;
  final double safeBottom;

  /// Where this slot's files land, under `APPSTORE_OUT`.
  final String dir;

  /// Whether the website's pictures are cut from this slot too.
  ///
  /// True for exactly one of them. The site wants one set of screenshots, not
  /// one per store slot, and which slot they come from is arbitrary — so it
  /// rides along with the slot that is going to be captured anyway.
  final bool web;

  /// The framed file's size, when it is not simply the capture's own.
  ///
  /// Null for both Apple slots, because Connect demands a screenshot be
  /// exactly a real phone's screen and the frame around the capture has to be
  /// that same size. Play demands the opposite kind of thing — not a size, a
  /// *shape*: no side may be more than twice the other. A modern phone is
  /// 19.5:9, which is 2.167, so the very files Apple insists on are the ones
  /// Play refuses. Since these frames are a composition on a gradient rather
  /// than a raw capture, the way out is to widen the canvas and leave the
  /// phone in it alone. See [kSlotPlay].
  final Size? canvas;

  /// Whether this slot's files must be written without an alpha channel.
  ///
  /// Play rejects a screenshot or a feature graphic that merely *has* the
  /// channel, transparent or not — the same rule, and the same wording, that
  /// `tool/app_icon.dart` already meets for the iOS icon. Apple asks nothing
  /// of the sort about screenshots, so its slots leave the engine's own PNG
  /// alone rather than paying a re-encode for nothing.
  final bool opaque;

  /// The size every capture bound for this slot must be, in device pixels.
  Size get pixels => Size(screen.width * _kScale, screen.height * _kScale);

  /// The size the framed file comes out at — [canvas] when it is set, and the
  /// capture's own size when it is not.
  Size get framed => canvas ?? pixels;
}

/// The 6.9" slot — iPhone 16 Pro Max, 1290 × 2796.
///
/// Apple requires this one and fills in the smaller devices by scaling it
/// down itself, which is why it is the default, and why it is the slot the
/// website's pictures are cut from.
const Slot kSlot69 = Slot(
  screen: Size(430, 932),
  safeTop: 59,
  safeBottom: 34,
  dir: 'appstore',
  web: true,
);

/// The 6.5" slot — iPhone 11 Pro Max, 1242 × 2688.
///
/// Optional, given the 6.9" set exists, and worth having anyway: Apple's own
/// downscale is a downscale, and a listing viewed on a 6.5" phone shows this
/// slot's files untouched when they are there. Connect accepts 1284 × 2778
/// here as well — that is a 12/13 Pro Max, 428 × 926 at 3× — so switching
/// this slot to that phone is a change to two numbers and nothing else.
const Slot kSlot65 = Slot(
  screen: Size(414, 896),
  safeTop: 44,
  safeBottom: 34,
  dir: 'appstore/6.5',
  web: false,
);

/// Play's slot — the 6.9" capture, framed onto 1400 × 2796 with no alpha.
///
/// Play's screenshot rules are two, and Apple's files fail both. **No side may
/// be more than twice the other**: 2796 / 1290 is 2.167, so the set that went
/// to Connect is rejected at Play's upload form, and every phone shaped like a
/// phone since about 2018 fails the same way. And **no alpha channel**, which
/// the engine's PNG encoder always writes whether or not a single pixel uses
/// it.
///
/// Neither is a reason to capture the app again. The screen is identical — the
/// same phone, the same safe area, the same seven shots — and what changes is
/// only the mount: the canvas widens by 110 pixels either side of a phone that
/// stays exactly where it was, which takes the ratio to 1.997 and is invisible
/// next to the Apple version. So this slot deliberately shares [kSlot69]'s
/// geometry and overrides nothing but the frame around it.
///
/// 1400 rather than the 1398 that would make it exactly 2.000, because a rule
/// written as "not more than twice" is a rule somebody's validator may have
/// implemented as "less than twice", and two pixels is nothing to pay to never
/// find out which.
const Slot kSlotPlay = Slot(
  screen: Size(430, 932),
  safeTop: 59,
  safeBottom: 34,
  dir: 'appstore/play',
  web: false,
  canvas: Size(1400, 2796),
  opaque: true,
);

/// The slots by the name `APPSTORE_SLOT` calls them.
const Map<String, Slot> kSlots = <String, Slot>{
  '6.9': kSlot69,
  '6.5': kSlot65,
  'play': kSlotPlay,
};

/// Which slot this run captures, from `APPSTORE_SLOT`, defaulting to the one
/// Apple requires. An unknown name is a typo in a Makefile, and silently
/// rendering the wrong size for it would be found out hours later at the
/// upload form — so it throws here instead.
final Slot _slot = _slotFor(Platform.environment['APPSTORE_SLOT']);

Slot _slotFor(String? name) {
  if (name == null || name.isEmpty) {
    return kSlot69;
  }
  final Slot? slot = kSlots[name];
  if (slot == null) {
    throw StateError(
      'APPSTORE_SLOT=$name is not one of ${kSlots.keys.join(', ')}',
    );
  }
  return slot;
}

/// What the website and the guide get instead: 645 × 1398, which is a retina
/// two-up of the ~320 px a phone screenshot is actually displayed at.
const double _kWebScale = 1.5;

/// Where the website's copies land, under `APPSTORE_OUT` — which the Makefile
/// points at the repository root, because these are files the project keeps
/// rather than scratch output. [Slot.dir] is what gets uploaded to App Store
/// Connect and Play Console; this is content the website is built from and is
/// committed with it.
const String _kWebDir = 'website/images/screens';

/// Where the things only Play asks for land.
///
/// Separate from [Slot.dir] because they are not screenshots and do not belong
/// in a slot: Play takes the same seven captures Apple does, and then asks for
/// one more picture that Apple has no equivalent of. Keeping it out of
/// `appstore/` also keeps that directory what its own comment says it is —
/// the set you drag into a screenshot form, all the same size.
const String _kPlayDir = 'appstore/play';

/// The 512 × 512 icon `tool/app_icon.dart` writes for the Play listing, which
/// the feature graphic below is built around rather than redrawing.
const String _kPlayIcon = 'src/android/app/src/main/ic_launcher-playstore.png';

/// Roll Hippo's brand red — the same value `hippoherd.com` uses for it.
const Color _kBrand = Color(0xFFD7263D);

/// The app's own background, which the framed shots fade down to so the
/// screenshot sits on something related to itself.
const Color _kInk = Color(0xFF0B0E13);

void main() {
  final String dir =
      Platform.environment['APPSTORE_OUT'] ?? Directory.systemTemp.path;

  setUpAll(() async {
    // Motion control off, which selects `StillMotionSource` and means no
    // sensor stream is opened at all — there is no accelerometer behind a
    // `flutter test`, and asking for one would hang rather than fail. The tray
    // is handed a phone lying perfectly still, so gravity points down the
    // screen and the dice fall to the bottom of the box and stay there. Every
    // roll below is thrown by the Throw button, which is exactly the interface
    // somebody with motion control off uses.
    settings.motion = false;

    await _loadFonts();

    // The numbers on the dice are drawn by the painter straight onto the
    // canvas, so they never see the theme the widgets are wrapped in and come
    // out as the blank boxes `flutter test` substitutes. This is the seam that
    // exists for exactly that — see [dieGlyphFont] — pointed at the Roboto
    // just registered, because a screenshot of a die whose number is a black
    // rectangle is a screenshot of nothing.
    dieGlyphFont = 'Roboto';
  });

  tearDownAll(() {
    dieGlyphFont = null;
  });

  _capture('01 · the tray, read', (WidgetTester tester) async {
    await _view(tester);
    await tester.pumpWidget(
      _app(
        TrayScreen(
          groups: <List<DieSpec>>[
            <DieSpec>[
              DieSpec(kind: DieKind.d20, colour: kDicePalette[0]),
              DieSpec(kind: DieKind.d6, colour: kDicePalette[3]),
              DieSpec(kind: DieKind.d6, colour: kDicePalette[3]),
              DieSpec(kind: DieKind.d8, colour: kDicePalette[5]),
              DieSpec(kind: DieKind.d4, colour: kDicePalette[2]),
            ],
          ],
        ),
      ),
    );
    await _settle(tester);

    await _shot(tester, dir, '01-tray', 'Shake it.\nRead what it says.');
  });

  _capture('02 · the picker', (WidgetTester tester) async {
    await _view(tester);
    await tester.pumpWidget(_app(const PickerScreen()));
    await tester.pumpAndSettle();

    // Driven the way a thumb would rather than constructed, which is the
    // sibling picker tool's bargain and the same one holds here: this shot
    // fails if the rack stops working.
    for (int i = 0; i < 6; i++) {
      if (i >= kDefaultDice.length) {
        await tester.tap(_addDie);
        await tester.pump();
      } else {
        await tester.tap(_onDicePage(find.byType(DiePreview)).at(i));
        await tester.pump();
      }
      await tester.tap(
        _onDicePage(find.text(_offered[i % _offered.length].label)),
      );
      await tester.pump();
      await tester.tap(
        _onDicePage(_swatch(kDicePalette[i % kDicePalette.length])),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    await _shot(
      tester,
      dir,
      '02-picker',
      'Six solids, D4 to D20.\nAny colour each.',
    );
  });

  _capture('03 · a full tray', (WidgetTester tester) async {
    await _view(tester);
    await tester.pumpWidget(
      _app(
        TrayScreen(
          groups: <List<DieSpec>>[
            <DieSpec>[
              for (int i = 0; i < kMaxDice; i++)
                DieSpec(
                  kind: _offered[i % _offered.length],
                  colour: kDicePalette[i % kDicePalette.length],
                ),
            ],
          ],
        ),
      ),
    );
    await _settle(tester);

    await _shot(
      tester,
      dir,
      '03-full-tray',
      'Ten at once,\nin a box you can feel.',
    );
  });

  _capture('04 · the card table', (WidgetTester tester) async {
    await _view(tester);
    await tester.pumpWidget(
      _app(
        CardScreen(
          dice: 2,
          decks: 2,
          reshuffleAt: 5,
          colours: <int>[kDicePalette[5], kDicePalette[2]],
        ),
      ),
    );
    // Pumped a fixed number of times rather than settled: this screen holds a
    // `Ticker` that is running whether or not anything is moving, so
    // `pumpAndSettle` would wait for a frame that is never the last one and
    // time the test out. The same goes for the tray.
    await _pump(tester, 8);

    // One card already on the glass, and its flight finished — a shoe with
    // nothing turned over yet is a picture of a card back.
    await tester.tap(find.text('Draw'));
    await _pump(tester, 60);

    await _shot(tester, dir, '04-cards', 'Same odds, dealt.\nNo table needed.');
  });

  _capture('05 · the profiles', (WidgetTester tester) async {
    await _view(tester);

    profiles.add('Yahtzee', _saved(5));
    profiles.add('D&D', _saved(7));
    profiles.add('Craps', _saved(2));
    profiles.add('Backgammon', _saved(2));
    profiles.add('Farkle', _saved(6));

    await tester.pumpWidget(_app(const PickerScreen()));
    await tester.pumpAndSettle();

    await _shot(
      tester,
      dir,
      '05-profiles',
      'Every game you play,\nsaved and named.',
    );
  });

  _capture('06 · the share code', (WidgetTester tester) async {
    await _view(tester);

    profiles.add('Yahtzee', _saved(5));

    await tester.pumpWidget(_app(const PickerScreen()));
    await tester.pumpAndSettle();

    // Off the save's own menu, which is where sharing lives: hold the profile
    // down, take Share. A long press is not a tap, so nothing is opened by it
    // — and because the code comes off the save rather than off the screen,
    // the caption under the square names it.
    await tester.longPress(find.text('Yahtzee'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    await _shot(
      tester,
      dir,
      '06-share',
      'Hand the whole setup\nto the next player.',
    );
  });

  _capture('07 · the tutorial', (WidgetTester tester) async {
    await _view(tester);

    // One save behind it, so the row of profiles in the backdrop is a row
    // somebody has used rather than a lone dashed outline. The tour builds its
    // own dice and its own shoe to demonstrate with, but the profiles it shows
    // are the real ones — see `tutorial.dart`.
    profiles.add('Yahtzee', _saved(5));

    // `tutorial: true` is what `main` passes on a launch that has never shown
    // it, and the only thing that puts the tour up unasked.
    await tester.pumpWidget(_app(const PickerScreen(tutorial: true)));
    await tester.pumpAndSettle();

    // Settled rather than pumped a fixed number of times, unlike the tray and
    // the card table: nothing behind either of the first two cards is ticking.
    // The tour builds its tray on the fifth card and not before, which is a
    // decision made for the phone's sake and pays for itself again here.
    //
    // The second card, which is the rack. The first is said over the *card*
    // page and is the truer picture of what the backdrop is for — it shows a
    // page you would have to swipe to reach — but a rack of five coloured
    // solids with a ring of light round it is the one that can still be read
    // at thumbnail size.
    await tester.tap(_onCard('Next'));
    await tester.pumpAndSettle();

    await _shot(
      tester,
      dir,
      '07-tutorial',
      'A tour on the first run.\nAnd any time after.',
    );
  });

  // Declared last, and a plain `test` rather than a `testWidgets`: it pumps
  // nothing, and what it composes are three of the web-sized files the
  // captures above have just written. Declaration order is run order, which is the whole of what
  // makes reading them back from disk safe.
  // Composed from the website's copies, so it belongs to the slot that writes
  // them — and like them it is one picture for the site, not one per slot.
  if (_slot.web) {
    test('08 · the hero', () => heroes(dir));
  }

  // Declared under the Play slot so that `appstore/play/` has one origin —
  // everything in that directory is what `make screenshots-play` wrote, which
  // is a rule worth more than saving the run its one cross-run dependency.
  // The picture it is built from was written by the 6.9" run rather than this
  // one; [feature] says so itself if it is not there.
  if (identical(_slot, kSlotPlay)) {
    test('08 · the feature graphic', () => feature(dir));
  }
}

/// One shot, as a test, starting from an empty desk.
///
/// The wrapper exists for the clearing. [profiles] is one store for the whole
/// process — the app has exactly one and so does a `flutter test` run of it —
/// and nothing empties it between tests, so every save a capture makes is
/// still there for the next one. That is not merely untidy: capture 05 seeds
/// five profiles and capture 06 wants a screen with one Yahtzee on it, so
/// without this the second Yahtzee joins the first and `find.text('Yahtzee')`
/// has two answers where `longPress` needs one. The whole run then fails on
/// 06 — *after* the five before it have already been written over the ones in
/// the project, and with capture 07 going on to compose the hero out of five
/// fresh pictures and one stale one.
///
/// So each capture starts from nothing, which is also what each of them
/// describes: they set up the screen they are a picture of, and none of them
/// means "and whatever the last one left lying about". Cleared going in rather
/// than coming out, because the state that matters is the state a body starts
/// with — a capture added at the end of the file would otherwise be the one
/// that inherits everything.
void _capture(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (WidgetTester tester) async {
    // `saves` hands back a copy, so removing as we go is safe.
    for (final SavedProfile save in profiles.saves) {
      profiles.remove(save.id);
    }
    await body(tester);
  });
}

// ── The capture ──────────────────────────────────────────────────────────────

/// Puts the test view at the running slot's geometry, insets and all.
Future<void> _view(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_slot.screen);
  tester.view.physicalSize = _slot.pixels;
  tester.view.devicePixelRatio = _kScale;
  tester.view.padding = FakeViewPadding(
    top: _slot.safeTop * _kScale,
    bottom: _slot.safeBottom * _kScale,
  );
}

/// The app around a screen, carrying the real font family.
///
/// The screens set weights and sizes but never a family, so naming Roboto once
/// here is what puts a readable glyph behind every label in every shot.
Widget _app(Widget home) => RepaintBoundary(
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
    home: home,
  ),
);

/// Throws, then runs the tray on until the dice have stopped and been read.
///
/// The screen arrives already thrown for its first group, so this is only
/// waiting — but it waits on the simulation rather than a fixed count, because
/// ten dice take visibly longer to settle than four and a picture taken while
/// one is still rolling is a picture of a number that had not happened yet.
Future<void> _settle(WidgetTester tester) => _pump(tester, 450);

/// Advances a ticker-driven screen by [frames] frames.
///
/// 33 ms a frame, which is the largest step `_onTick` will accept — it clamps
/// anything longer to 1/30 s on the grounds that a frame that took longer than
/// that was a hitch rather than a slow frame. So this is the same simulated
/// second as a 60 Hz pump for half the layout and paint work, and the dice
/// arrive in exactly the same place.
Future<void> _pump(WidgetTester tester, int frames) async {
  for (int frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 33));
  }
}

/// Writes one shot twice, for its two quite different readers.
///
/// `appstore/` is the framed capture at Apple's exact pixel size, which is an
/// upload and nothing else. `web/` is the bare screen at half that, which is
/// what the site and the guide put on a page — a full-width PNG of a dark app
/// displayed 320 px wide is three quarters of a megabyte spent on pixels the
/// reader will never see, and there are seven of them.
///
/// The second capture is re-rendered at the lower ratio rather than resampled
/// down from the first. It costs one more `toImage` and it is the difference
/// between text that was laid out at that size and text that was laid out at
/// twice it and then blurred.
///
/// All of it inside [WidgetTester.runAsync], and that is not a detail. A
/// `testWidgets` body runs against a fake clock with its own microtask queue,
/// and `Picture.toImage` is completed by the engine on a real one — await it
/// under the fake clock and it simply never returns, which it does silently,
/// for the full ten minutes the test framework allows before it gives up.
Future<void> _shot(
  WidgetTester tester,
  String dir,
  String name,
  String caption,
) async {
  final RenderRepaintBoundary boundary =
      tester.renderObject(find.byType(RepaintBoundary).first)
          as RenderRepaintBoundary;

  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: _kScale);
    _check(name, image);

    final ui.Image framed = await _frame(image, caption);
    await _writePng(
      '$dir/${_slot.dir}/$name.png',
      framed,
      opaque: _slot.opaque,
    );
    framed.dispose();
    image.dispose();

    // Only from the slot that owns them. A second slot writing these would
    // overwrite one set of website pictures with another set the same size,
    // which is churn in a committed directory and nothing else.
    if (_slot.web) {
      final ui.Image web = await boundary.toImage(pixelRatio: _kWebScale);
      await _writePng('$dir/$_kWebDir/$name.png', web);
      web.dispose();
    }
  });
}

/// A capture that is not exactly the size Apple accepts is a capture that will
/// be rejected at upload, hours later, by a web form. Better to hear it here.
void _check(String name, ui.Image image) {
  if (image.width != _slot.pixels.width.round() ||
      image.height != _slot.pixels.height.round()) {
    throw StateError(
      '$name is ${image.width}x${image.height}, '
      'not ${_slot.pixels.width.round()}x${_slot.pixels.height.round()}',
    );
  }
}

// ── The frame ────────────────────────────────────────────────────────────────

/// Drops [shot] onto a branded background under [caption].
///
/// The screenshot is inset rather than filling the canvas, which is the whole
/// point of a framed shot: a store listing scrolls sideways through seven of
/// these at thumbnail size, and at that size a full-bleed screenshot of a dark
/// app is a dark rectangle. The caption and the brand wash are what make one
/// thumbnail tell itself apart from the next.
Future<ui.Image> _frame(ui.Image shot, String caption) async {
  final double w = _slot.framed.width;
  final double h = _slot.framed.height;

  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  final Rect all = Rect.fromLTWH(0, 0, w, h);

  // Ink at the bottom, a brand wash at the top — dark enough throughout that
  // white type sits on it without a scrim.
  canvas.drawRect(
    all,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(w / 2, 0),
        Offset(w / 2, h),
        <Color>[const Color(0xFF2A0B12), const Color(0xFF16070C), _kInk],
        <double>[0.0, 0.45, 1.0],
      ),
  );
  // A soft brand glow behind the caption, so the top of the frame carries the
  // colour the mark does rather than being merely dark red.
  canvas.drawCircle(
    Offset(w / 2, h * 0.06),
    w * 0.72,
    Paint()
      ..shader = ui.Gradient.radial(Offset(w / 2, h * 0.06), w * 0.72, <Color>[
        _kBrand.withValues(alpha: 0.34),
        _kBrand.withValues(alpha: 0.0),
      ]),
  );

  // The caption, centred in the band above the phone.
  final ui.Paragraph text = _paragraph(caption, w * 0.86);
  canvas.drawParagraph(text, Offset((w - w * 0.86) / 2, h * 0.055));

  // The phone: the capture, scaled down and rounded off. No bezel drawing —
  // the shot already has the app's own rounded dark chrome in it, and a
  // painted-on aluminium rail is the kind of detail that dates a listing.
  //
  // Sized by the frame's height and the *shot's* own aspect, not by the
  // frame's width and the frame's aspect. For both Apple slots those are the
  // same arithmetic to within a pixel, because there the canvas is the
  // capture's size — 0.78 of the width of a 1290 × 2796 frame is the same
  // phone as 0.78 of its height. They come apart the moment a frame is not
  // the shape of the thing inside it, which is exactly what [kSlotPlay] is,
  // and doing it the other way there would stretch the screenshot sideways.
  final double phoneH = h * 0.78;
  final double phoneW = phoneH * shot.width / shot.height;
  final double phoneX = (w - phoneW) / 2;
  final double phoneY = h * 0.215;
  final RRect phone = RRect.fromRectAndRadius(
    Rect.fromLTWH(phoneX, phoneY, phoneW, phoneH),
    Radius.circular(phoneW * 0.085),
  );

  canvas.drawRRect(
    phone.shift(const Offset(0, 18)),
    Paint()
      ..color = const Color(0x99000000)
      ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 40),
  );
  canvas.save();
  canvas.clipRRect(phone);
  canvas.drawImageRect(
    shot,
    Rect.fromLTWH(0, 0, shot.width.toDouble(), shot.height.toDouble()),
    phone.outerRect,
    Paint()..filterQuality = FilterQuality.high,
  );
  canvas.restore();
  // A hairline, because a dark screenshot on a dark background otherwise has
  // no edge at all at thumbnail size.
  canvas.drawRRect(
    phone,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0x33FFFFFF),
  );

  return recorder.endRecording().toImage(w.round(), h.round());
}

/// The caption, laid out and wrapped to [maxWidth].
///
/// The defaults are the framed screenshot's caption, which is what this was
/// written for and still its only caller at those values; the feature graphic
/// below reaches for the same layout at three other sizes, which is the whole
/// reason any of it is a parameter.
ui.Paragraph _paragraph(
  String caption,
  double maxWidth, {
  double fontSize = 78,
  FontWeight weight = FontWeight.w700,
  Color colour = const Color(0xFFFFFFFF),
  TextAlign align = TextAlign.center,
  double letterSpacing = -1.5,
  double height = 1.22,
}) {
  final ui.ParagraphBuilder builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textAlign: align,
      fontFamily: 'Roboto',
      fontSize: fontSize,
      fontWeight: weight,
      height: height,
    ),
  )..pushStyle(
    ui.TextStyle(
      color: colour,
      fontFamily: 'Roboto',
      fontSize: fontSize,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
    ),
  );
  builder.addText(caption);
  final ui.Paragraph paragraph = builder.build();
  paragraph.layout(ui.ParagraphConstraints(width: maxWidth));
  return paragraph;
}

// ── The feature graphic ──────────────────────────────────────────────────────

/// Play's feature graphic: 1024 × 500, and required for every listing.
///
/// Apple has no equivalent, which is why this is the one picture the Apple run
/// never needed. Play puts it across the top of the store page above the
/// screenshots, and uses it again on its own promotional surfaces, where the
/// listing's name and icon are drawn over the top by the store rather than by
/// this canvas.
///
/// Two consequences shape the layout. It gets **cropped** — Play shows it at
/// other aspect ratios than the one it demands, and what survives every crop
/// is the middle — so nothing that has to be read goes near an edge. And it is
/// often seen at a few hundred pixels wide in a list, which is the same
/// argument [_frame] makes for its captions: at that size a screenshot is a
/// dark rectangle, and the mark and the wordmark are the only things doing any
/// work.
///
/// Composed from files on disk for [heroes]' reason. The icon is the one
/// `tool/app_icon.dart` already writes for this exact upload, and the phone is
/// the website's copy of capture 01 — so the banner cannot drift from the
/// listing it sits above.
Future<void> feature(String dir) async {
  final File icon = File('$dir/$_kPlayIcon');
  if (!icon.existsSync()) {
    throw StateError(
      'no Play icon at $_kPlayIcon — run `make icon` first, which is what '
      'writes it',
    );
  }

  final File capture = File('$dir/$_kWebDir/01-tray.png');
  if (!capture.existsSync()) {
    throw StateError(
      'no capture at $_kWebDir/01-tray.png — run `make screenshots` first, '
      'which is the run that writes the website copies this is built from',
    );
  }

  final ui.Image mark = await _load(icon.path);
  final ui.Image phone = await _load(capture.path);
  final ui.Image banner = await _banner(mark, phone);

  // Opaque, for the reason every Play-bound file here is: the store rejects a
  // feature graphic that so much as has an alpha channel.
  await _writePng('$dir/$_kPlayDir/feature-graphic.png', banner, opaque: true);

  banner.dispose();
  mark.dispose();
  phone.dispose();
}

/// Lays the mark, the wordmark and one phone across Play's 1024 × 500.
Future<ui.Image> _banner(ui.Image mark, ui.Image phone) async {
  // Play's size, exactly, and not negotiable — the upload form rejects
  // anything else outright rather than scaling it. Written as constants
  // because unlike a [Slot] there is only ever this one.
  const double w = 1024;
  const double h = 500;

  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);

  // The same wash the framed shots and the hero use, turned on its side: this
  // canvas is twice as wide as it is tall, and a vertical gradient across 500
  // pixels reads as a flat colour.
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, w, h),
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(w, h),
        <Color>[const Color(0xFF2A0B12), const Color(0xFF16070C), _kInk],
        <double>[0.0, 0.5, 1.0],
      ),
  );
  // The glow sits behind the mark rather than the middle, because the middle
  // is where the phone goes and the mark is what needs lifting off the ink.
  canvas.drawCircle(
    const Offset(w * 0.24, h * 0.5),
    w * 0.34,
    Paint()
      ..shader = ui.Gradient.radial(
        const Offset(w * 0.24, h * 0.5),
        w * 0.34,
        <Color>[
          _kBrand.withValues(alpha: 0.34),
          _kBrand.withValues(alpha: 0.0),
        ],
      ),
  );

  // ── The left block: mark, wordmark beside it, tagline under both ──
  const double markSide = 132;
  const double left = w * 0.055;
  const double gap = 28;

  final ui.Paragraph wordmark = _paragraph(
    'Roll Hippo',
    w * 0.42,
    fontSize: 74,
    align: TextAlign.left,
  );
  final ui.Paragraph tagline = _paragraph(
    'D4 to D20, ten at once —\nand they land where they land.',
    w * 0.52,
    fontSize: 29,
    weight: FontWeight.w400,
    colour: const Color(0xCCFFFFFF),
    align: TextAlign.left,
    letterSpacing: 0,
    height: 1.35,
  );

  // Centred as one block rather than each piece against the canvas, so the
  // tagline growing a line moves the mark up instead of walking off the
  // bottom edge.
  final double blockH = markSide + 26 + tagline.height;
  final double top = (h - blockH) / 2;

  final RRect marked = RRect.fromRectAndRadius(
    const Rect.fromLTWH(left, 0, markSide, markSide).translate(0, 0),
    const Radius.circular(markSide * 0.225),
  ).shift(Offset(0, top));
  canvas.save();
  canvas.clipRRect(marked);
  canvas.drawImageRect(
    mark,
    Rect.fromLTWH(0, 0, mark.width.toDouble(), mark.height.toDouble()),
    marked.outerRect,
    Paint()..filterQuality = FilterQuality.high,
  );
  canvas.restore();

  // The wordmark's own box is taller than its glyphs, so it is centred against
  // the mark by its height rather than sharing a baseline with it.
  canvas.drawParagraph(
    wordmark,
    Offset(left + markSide + gap, top + (markSide - wordmark.height) / 2),
  );
  canvas.drawParagraph(tagline, Offset(left, top + markSide + 26));

  // ── The phone ──
  //
  // Bleeding off the top and the bottom rather than fitted inside them. 500
  // pixels is not enough height for a whole phone at a size worth looking at,
  // and a shrunk-to-fit one reads as a stamp; a cropped one reads as a phone
  // that happens to be bigger than the frame.
  const double phoneH = 640;
  final double phoneW = phoneH * phone.width / phone.height;
  final Rect rect = Rect.fromCenter(
    center: const Offset(w * 0.795, h * 0.5),
    width: phoneW,
    height: phoneH,
  );
  final RRect rounded = RRect.fromRectAndRadius(
    rect,
    Radius.circular(phoneW * 0.085),
  );

  canvas.save();
  canvas.translate(rect.center.dx, rect.center.dy);
  canvas.rotate(-0.06);
  canvas.translate(-rect.center.dx, -rect.center.dy);

  canvas.drawRRect(
    rounded.shift(const Offset(0, 12)),
    Paint()
      ..color = const Color(0xAA000000)
      ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 22),
  );
  canvas.save();
  canvas.clipRRect(rounded);
  canvas.drawImageRect(
    phone,
    Rect.fromLTWH(0, 0, phone.width.toDouble(), phone.height.toDouble()),
    rect,
    Paint()..filterQuality = FilterQuality.high,
  );
  canvas.restore();
  canvas.drawRRect(
    rounded,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0x33FFFFFF),
  );
  canvas.restore();

  return recorder.endRecording().toImage(w.round(), h.round());
}

// ── The hero ─────────────────────────────────────────────────────────────────

/// The website's hero, and the card that social sites unfurl.
///
/// Composed from the web-sized captures the tests above have just written
/// rather than by pumping the screens again: they are on disk, they are the
/// same pixels, and re-rendering them would be a second place for the hero to
/// disagree with the gallery underneath it.
///
/// Three phones, because one is a screenshot and three is a product. The tray
/// stands in the middle at full height and the picker and the card table lean
/// away behind it — which is also the order the app is used in, left to right.
Future<void> heroes(String dir) async {
  final List<ui.Image> phones = <ui.Image>[
    await _load('$dir/$_kWebDir/02-picker.png'),
    await _load('$dir/$_kWebDir/01-tray.png'),
    await _load('$dir/$_kWebDir/04-cards.png'),
  ];

  // 2400 × 1200 for the page, and Open Graph's 1200 × 630 for the unfurl. The
  // same composition at both, which is why it is written against fractions of
  // the canvas rather than pixel offsets.
  await _writePng(
    '$dir/website/images/hero.png',
    await _composite(const Size(2400, 1200), phones),
  );
  await _writePng(
    '$dir/website/images/og.png',
    await _composite(const Size(1200, 630), phones),
  );

  for (final ui.Image phone in phones) {
    phone.dispose();
  }
}

/// Lays [phones] out across a canvas of [size], middle one forward.
Future<ui.Image> _composite(Size size, List<ui.Image> phones) async {
  final double w = size.width;
  final double h = size.height;

  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);

  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, h),
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(w, h),
        <Color>[const Color(0xFF2A0B12), const Color(0xFF16070C), _kInk],
        <double>[0.0, 0.5, 1.0],
      ),
  );
  canvas.drawCircle(
    Offset(w * 0.5, h * 0.5),
    w * 0.42,
    Paint()
      ..shader = ui.Gradient.radial(Offset(w * 0.5, h * 0.5), w * 0.42, <Color>[
        _kBrand.withValues(alpha: 0.30),
        _kBrand.withValues(alpha: 0.0),
      ]),
  );

  // The middle phone is the tallest and the two outside it are stepped down,
  // which is what stops three rectangles in a row from reading as a filmstrip.
  const List<double> heights = <double>[0.72, 0.86, 0.72];
  const List<double> centres = <double>[0.235, 0.5, 0.765];
  const List<double> tilts = <double>[-0.075, 0, 0.075];

  // Middle last, so it lands on top of the two it overlaps.
  for (final int i in <int>[0, 2, 1]) {
    final ui.Image phone = phones[i];
    final double phoneH = h * heights[i];
    final double phoneW = phoneH * phone.width / phone.height;
    final Rect rect = Rect.fromCenter(
      center: Offset(w * centres[i], h * 0.52),
      width: phoneW,
      height: phoneH,
    );
    final RRect rounded = RRect.fromRectAndRadius(
      rect,
      Radius.circular(phoneW * 0.085),
    );

    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(tilts[i]);
    canvas.translate(-rect.center.dx, -rect.center.dy);

    canvas.drawRRect(
      rounded.shift(Offset(0, h * 0.012)),
      Paint()
        ..color = const Color(0xAA000000)
        ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, w * 0.012),
    );
    canvas.save();
    canvas.clipRRect(rounded);
    canvas.drawImageRect(
      phone,
      Rect.fromLTWH(0, 0, phone.width.toDouble(), phone.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.0016
        ..color = const Color(0x33FFFFFF),
    );
    canvas.restore();
  }

  return recorder.endRecording().toImage(w.round(), h.round());
}

// ── Files and fonts ──────────────────────────────────────────────────────────

/// A PNG off the disk, as something the canvas can draw.
Future<ui.Image> _load(String path) async {
  final ui.Codec codec = await ui.instantiateImageCodec(
    File(path).readAsBytesSync(),
  );
  final ui.FrameInfo frame = await codec.getNextFrame();
  return frame.image;
}

/// Writes [image] as a PNG, with or without the channel Play objects to.
///
/// [opaque] re-encodes through the `image` package with three channels instead
/// of four, which is the same trick — and the same two lines — that
/// `tool/app_icon.dart` uses to get an iOS icon past App Store validation. It
/// is a re-encode rather than a fill: every pixel of these frames is already
/// opaque, because the first thing [_frame] and [_banner] draw is a gradient
/// across the whole canvas, so there is nothing to flatten and the only thing
/// being taken away is the channel itself.
Future<void> _writePng(
  String path,
  ui.Image image, {
  bool opaque = false,
}) async {
  final Uint8List bytes =
      opaque ? await _opaquePng(image) : await _rgbaPng(image);
  final File file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  // ignore: avoid_print
  print(
    'wrote $path  (${image.width}x${image.height}'
    '${opaque ? ', 24-bit' : ''})',
  );
}

/// Straight out of the engine, alpha and all.
Future<Uint8List> _rgbaPng(ui.Image image) async {
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

/// The same picture with the alpha channel taken off rather than filled in.
Future<Uint8List> _opaquePng(ui.Image image) async {
  final ByteData raw =
      (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final img.Image rgba = img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: raw.buffer,
    numChannels: 4,
  );
  return img.encodePng(rgba.convert(numChannels: 3));
}

/// Registers the real Roboto and the Material icon font.
///
/// Both live in the Flutter cache rather than in this repository, because they
/// are what the framework itself ships and a vendored copy would be a second
/// version of them to keep in step. `flutter test` exports `FLUTTER_ROOT`,
/// which is how they are found.
Future<void> _loadFonts() async {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    // ignore: avoid_print
    print('appstore: no FLUTTER_ROOT — labels will render as blank boxes');
    return;
  }
  final Directory fonts = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!fonts.existsSync()) {
    // ignore: avoid_print
    print('appstore: no font cache at ${fonts.path} — labels will be boxes');
    return;
  }

  Future<void> load(String family, List<String> files) async {
    final FontLoader loader = FontLoader(family);
    for (final String file in files) {
      final File source = File('${fonts.path}/$file');
      if (!source.existsSync()) continue;
      loader.addFont(
        Future<ByteData>.value(ByteData.sublistView(source.readAsBytesSync())),
      );
    }
    await loader.load();
  }

  const List<String> roboto = <String>[
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ];

  await load('Roboto', roboto);
  await load('MaterialIcons', <String>['MaterialIcons-Regular.otf']);

  // And again under the names a *null* family resolves to.
  //
  // Naming the family in the theme covers everything that inherits its style,
  // which is nearly everything — but not a control that sets its own. A
  // `TextButton.styleFrom(textStyle: …)` REPLACES the button's resolved text
  // style rather than merging into it, so a style given there for its size
  // alone arrives at the engine carrying no family at all, and the engine
  // falls back to the platform default. Under `TargetPlatform.iOS` that is one
  // of Apple's system faces, none of which a `flutter test` host has, and the
  // label comes out as the row of solid boxes this whole function exists to
  // prevent. Registering the same bytes under those names is what closes the
  // last gap: nothing here is pretending to be San Francisco, it is only
  // making sure that asking for it returns letters.
  for (final String family in const <String>[
    'Ahem',
    'FlutterTest',
    '.SF UI Text',
    '.SF UI Display',
    '.SF Pro Text',
    '.SF Pro Display',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
  ]) {
    await load(family, roboto);
  }
}

// ── Finders, shared with tool/picker.dart's conventions ──────────────────────

/// A profile with [dice] dice in its first set, which is enough for the row
/// under each name to have something to say.
Profile _saved(int dice) => Profile(
  mode: ProfileMode.dice,
  groups: <List<DieSpec>>[
    <DieSpec>[
      for (int i = 0; i < dice; i++)
        const DieSpec(kind: DieKind.d6, colour: kDiceWhite),
    ],
    <DieSpec>[],
    <DieSpec>[],
  ],
  colours: const <int>[kDiceWhite, kDiceWhite],
  decks: 2,
  reshuffleAt: 5,
);

/// The kinds the picker offers without being asked by name — see
/// [DieKind.secret], which is what keeps the hippopotamus out of a listing.
final List<DieKind> _offered = <DieKind>[
  for (final DieKind kind in DieKind.values)
    if (!kind.secret) kind,
];

Finder _onDicePage(Finder finder) =>
    find.descendant(of: find.byKey(kDicePage), matching: finder);

/// A button on the tutorial's own card rather than on the screen behind it,
/// which is a whole picker and has a Roll of its own.
Finder _onCard(String label) =>
    find.descendant(of: find.byKey(kTutorialCard), matching: find.text(label));

final Finder _addDie = find.descendant(
  of: find.byKey(const ValueKey<int>(0)),
  matching: find.byKey(kAddDie),
);

Finder _swatch(int colour) => find.byWidgetPredicate((Widget widget) {
  if (widget is! Container) return false;
  final Decoration? decoration = widget.decoration;
  return decoration is BoxDecoration &&
      decoration.shape == BoxShape.circle &&
      decoration.color == Color(colour);
});
