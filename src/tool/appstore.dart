import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/card_screen.dart';
import 'package:rollhippo/app/picker_screen.dart';
import 'package:rollhippo/app/profiles.dart';
import 'package:rollhippo/app/settings.dart';
import 'package:rollhippo/app/tray_screen.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/render/tray_painter.dart';
import 'package:rollhippo/tray/tray.dart';

/// Renders the store listing and the user guide's figures. Run with:
///
///     flutter test tool/appstore.dart
///
/// and again, for the second store slot, with:
///
///     APPSTORE_SLOT=6.5 flutter test tool/appstore.dart
///
/// Two directories come out of it, from one screen each:
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
///
/// Google Play is far looser than either slot and takes the same files.
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

  /// The size every file bound for this slot must be, in device pixels.
  Size get pixels => Size(screen.width * _kScale, screen.height * _kScale);
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

/// The slots by the name `APPSTORE_SLOT` calls them.
const Map<String, Slot> kSlots = <String, Slot>{'6.9': kSlot69, '6.5': kSlot65};

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

    // Past the chooser the app opens with when there is anything to choose.
    await tester.tap(find.text('+ New Profile'));
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
    await tester.tap(find.text('+ New Profile'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Menu'));
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

  // Declared last, and a plain `test` rather than a `testWidgets`: it pumps
  // nothing, and what it composes are the six files the captures above have
  // just written. Declaration order is run order, which is the whole of what
  // makes reading them back from disk safe.
  // Composed from the website's copies, so it belongs to the slot that writes
  // them — and like them it is one picture for the site, not one per slot.
  if (_slot.web) {
    test('07 · the hero', () => heroes(dir));
  }
}

/// One shot, as a test.
///
/// The wrapper exists for one line of it. `debugDefaultTargetPlatformOverride`
/// puts the app on iOS, which is what stops `letterbox()` shrinking the screen
/// into `kHarnessScreen` and lets it lay out at the phone geometry the capture
/// claims to be — but the test framework checks after EVERY test body that no
/// foundation debug variable was left set, and it checks before `tearDown`
/// runs. So the reset has to happen inside the body, which means it has to
/// happen in a `finally`, which means it has to happen here.
void _capture(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (WidgetTester tester) async {
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
/// reader will never see, and there are six of them.
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
    await _writePng('$dir/${_slot.dir}/$name.png', framed);
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
/// point of a framed shot: a store listing scrolls sideways through six of
/// these at thumbnail size, and at that size a full-bleed screenshot of a dark
/// app is a dark rectangle. The caption and the brand wash are what make one
/// thumbnail tell itself apart from the next.
Future<ui.Image> _frame(ui.Image shot, String caption) async {
  final double w = _slot.pixels.width;
  final double h = _slot.pixels.height;

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
  final double phoneW = w * 0.78;
  final double phoneH = phoneW * h / w;
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

/// The caption, laid out centred and wrapped to [maxWidth].
ui.Paragraph _paragraph(String caption, double maxWidth) {
  final ui.ParagraphBuilder builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontFamily: 'Roboto',
      fontSize: 78,
      fontWeight: FontWeight.w700,
      height: 1.22,
    ),
  )..pushStyle(
    ui.TextStyle(
      color: const Color(0xFFFFFFFF),
      fontFamily: 'Roboto',
      fontSize: 78,
      fontWeight: FontWeight.w700,
      height: 1.22,
      letterSpacing: -1.5,
    ),
  );
  builder.addText(caption);
  final ui.Paragraph paragraph = builder.build();
  paragraph.layout(ui.ParagraphConstraints(width: maxWidth));
  return paragraph;
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

Future<void> _writePng(String path, ui.Image image) async {
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  final File file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote $path  (${image.width}x${image.height})');
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
