import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/config_screen.dart';
import 'package:rollhippo/app/tray_screen.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/tray/tray.dart';

/// Renders the picker, so the rack can be looked at without a device in your
/// hand. Run with:
///
///     flutter test tool/picker.dart
///
/// Two images: the whole screen with a full rack of assorted dice, and a strip
/// of the six kinds at rack size, which is what to check after touching
/// [previewOrientation] — the angle is chosen by a search, and the only way to
/// know a change to it helped is to look at all six.
///
/// The labels come out as blank boxes: `flutter test` substitutes a font with
/// no glyphs in it, and that goes for the numbers on the dice too. Everything
/// with a shape to it — the solids, the shading, the colours, the layout — is
/// exactly what the phone draws.
void main() {
  final String dir =
      Platform.environment['PICKER_OUT'] ?? Directory.systemTemp.path;

  testWidgets('the picker, with a full rack', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(kHarnessScreen);
    tester.view.physicalSize = kHarnessScreen * 2;
    tester.view.devicePixelRatio = 2.0;

    await tester.pumpWidget(
      const RepaintBoundary(child: MaterialApp(home: ConfigScreen())),
    );

    // Fill the rack by driving the picker the way a thumb would, one die at a
    // time — which also means this tool fails if the picker stops working.
    for (int i = 0; i < kMaxDice; i++) {
      if (i >= kDefaultDice.length) {
        await tester.tap(find.text('Add a die'));
        await tester.pump();
      } else {
        await tester.tap(find.byType(DiePreview).at(i));
        await tester.pump();
      }
      await tester.tap(
        find.text(DieKind.values[i % DieKind.values.length].label),
      );
      await tester.pump();
      await tester.tap(_swatch(kDicePalette[i % kDicePalette.length]));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    await _write(tester, '$dir/picker.png');
  });

  testWidgets('the six kinds at rack size', (WidgetTester tester) async {
    const double slot = 72;
    await tester.binding.setSurfaceSize(
      Size(slot * DieKind.values.length, slot),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: const Color(0xFF0B0E13),
            child: Row(
              children: <Widget>[
                for (int i = 0; i < DieKind.values.length; i++)
                  SizedBox.square(
                    dimension: slot,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: DiePreview(
                        spec: DieSpec(
                          kind: DieKind.values[i],
                          colour: kDicePalette[i % kDicePalette.length],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _write(tester, '$dir/kinds.png', pixelRatio: 4);
  });
}

/// The palette swatch for one colour — a filled circle, which is enough to
/// tell it from every other [Container] on the screen.
Finder _swatch(int colour) => find.byWidgetPredicate((Widget widget) {
  if (widget is! Container) return false;
  final Decoration? decoration = widget.decoration;
  return decoration is BoxDecoration &&
      decoration.shape == BoxShape.circle &&
      decoration.color == Color(colour);
});

Future<void> _write(
  WidgetTester tester,
  String path, {
  double pixelRatio = 2,
}) async {
  final RenderRepaintBoundary boundary =
      tester.renderObject(find.byType(RepaintBoundary).first)
          as RenderRepaintBoundary;
  ByteData? png;
  // Encoding is real asynchronous work, which a test's fake clock will not run.
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    png = await image.toByteData(format: ui.ImageByteFormat.png);
  });
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote $path');
}
