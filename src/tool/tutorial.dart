import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/picker_screen.dart';
import 'package:rollhippo/app/tray_screen.dart';
import 'package:rollhippo/app/tutorial.dart';

/// Renders the tutorial, page by page, over the screen it is talking about.
/// Run with:
///
///     flutter test tool/tutorial.dart
///
/// One picture per page at phone size, and then the whole run again on the
/// shortest screen this app is likely to meet. These are the pictures that
/// answer what no assertion can. `tutorial_test.dart` can hold the hole to the
/// rectangle of the widget the page names and the card to the roomier side of
/// it, and it does; what it cannot say is whether the lit part *reads* as the
/// thing being talked about, or whether what is left dimmed round it is still
/// worth having behind the words.
///
/// The labels come out as blank boxes, exactly as they do in `tool/picker.dart`
/// and for the same reason: `flutter test` substitutes a font with no glyphs
/// in it. That is more useful here than it sounds. The substitute sets every
/// glyph on a square body, so a paragraph of it is close to twice the width
/// the real face would take — which means a page that fits its block here fits
/// it comfortably on the phone, and a page that spills has spilled by a margin
/// worth knowing about. The dice are not affected: everything with a shape to
/// it is exactly what the phone draws, which is most of what these pictures
/// are for.
void main() {
  final String dir =
      Platform.environment['TUTORIAL_OUT'] ?? Directory.systemTemp.path;

  /// One pass over every page, at [size].
  Future<void> pages(WidgetTester tester, Size size, String prefix) async {
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2.0;

    // `tutorial: true` is what `main` passes on a launch that has never shown
    // it. Reaching it through the menu instead would need the same seven taps
    // and would put a popup route in the first picture.
    await tester.pumpWidget(
      const RepaintBoundary(
        child: MaterialApp(home: PickerScreen(tutorial: true)),
      ),
    );
    await _settle(tester);

    for (int i = 0; i < kTutorialPages.length; i++) {
      await _write(tester, '$dir/$prefix-${i + 1}.png');
      if (i < kTutorialPages.length - 1) {
        await tester.tap(_onCard('Next'));
        await _settle(tester);
      }
    }

    // And the way out, which leaves the picker where it was.
    await tester.tap(_onCard('Done'));
    await _settle(tester);
    await _write(tester, '$dir/$prefix-closed.png');
  }

  // The harness path, for the reason `groups_test.dart` gives: past the fifth
  // page the backdrop is a real tray, and on a platform it believes is a phone
  // it reaches for an accelerometer this machine has not got. At
  // [kHarnessScreen] the letterbox that comes with it is the identity; on the
  // short pass it is not, so the two tray pages there come out with a bar down
  // each side that a phone does not have.
  final TargetPlatformVariant harness = TargetPlatformVariant.only(
    TargetPlatform.macOS,
  );

  testWidgets('the tutorial, page by page', (WidgetTester tester) async {
    await pages(tester, kHarnessScreen, 'tutorial');
  }, variant: harness);

  testWidgets('and on a short screen', (WidgetTester tester) async {
    // An iPhone SE, in logical pixels — the smallest thing still worth
    // shipping to, and the one where a card sized off the screen has the least
    // to spend.
    await pages(tester, const Size(375, 667), 'tutorial-small');
  }, variant: harness);
}

/// Lets what is moving land, without waiting for what never stops.
///
/// The backdrop past the fifth page is a real tray, and a real tray schedules
/// a frame for ever — so `pumpAndSettle` would sit there until it gave up.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 26; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// The tutorial's own buttons rather than the backdrop's, which is a whole
/// picker and has a Roll on it.
Finder _onCard(String label) =>
    find.descendant(of: find.byKey(kTutorialCard), matching: find.text(label));

Future<void> _write(WidgetTester tester, String path) async {
  final RenderRepaintBoundary boundary =
      tester.renderObject(find.byType(RepaintBoundary).first)
          as RenderRepaintBoundary;
  ByteData? png;
  // Encoding is real asynchronous work, which a test's fake clock will not run.
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    png = await image.toByteData(format: ui.ImageByteFormat.png);
  });
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote $path');
}
