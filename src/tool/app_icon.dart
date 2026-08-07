import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Draws the app icon, at every size the three platforms ask for. Run with:
///
///     make icon
///
/// Unlike the other tools in here, this one writes into the project rather
/// than into `/tmp`: the files it produces *are* the icon, and the catalogues
/// and the `mipmap` folders already name them. Run it after touching
/// [paintMark] and commit what comes out.
///
/// The mark itself is `assets/rollhippo.svg`, which is the drawing of record —
/// it came from the Hippo Herd marks and is what the website uses. The painter
/// below is that file transcribed into a canvas, shape for shape and number
/// for number, because there is no SVG rasteriser in this toolchain and adding
/// one to render nine circles and two rounded rectangles would be a dependency
/// with more moving parts than the thing it draws. Change the SVG and change
/// [paintMark] with it; the list is short enough to read side by side.
void main() {
  testWidgets('draws the icon into every catalogue', (
    WidgetTester tester,
  ) async {
    // Real asynchronous work — encoding an image — which a test's fake clock
    // will not run. The same bargain every renderer in here makes.
    await tester.runAsync(() async {
      for (final MapEntry<String, int> icon in _kIosIcons.entries) {
        await _write(
          '$_kIosDir/${icon.key}',
          icon.value,
          // iOS masks the icon itself, to a shape that is not quite this one,
          // and rejects any icon with an alpha channel in it. So its version
          // is the square, full bleed and opaque, and the rounding on screen
          // is Apple's rather than ours.
          body: 1.0,
          rounded: false,
          opaque: true,
        );
      }
      for (final int pixels in _kMacIcons) {
        await _write('$_kMacDir/app_icon_$pixels.png', pixels, body: _kMacBody);
      }
      for (final MapEntry<String, double> density
          in _kAndroidDensities.entries) {
        final String dir = '$_kAndroidRes/mipmap-${density.key}';
        Directory(dir).createSync(recursive: true);
        // The pre-adaptive icon, for launchers older than API 26: the whole
        // mark, field and all, rounded by us because nothing else will round
        // it. Alpha stays on — the corners it cuts have to be see-through or
        // the launcher draws a red square behind the rounding.
        await _write(
          '$dir/ic_launcher.png',
          (_kLegacyDp * density.value).round(),
          body: 1.0,
        );
        await _writeLayer(
          '$dir/ic_launcher_foreground.png',
          (_kAdaptiveDp * density.value).round(),
        );
        await _writeLayer(
          '$dir/ic_launcher_monochrome.png',
          (_kAdaptiveDp * density.value).round(),
          monochrome: true,
        );
      }
      // What the Play console asks to be uploaded beside the listing. Square,
      // full bleed and opaque, for the same reason iOS wants that: the store
      // rounds it itself, and rejects an icon it could see through.
      await _write(_kPlayIcon, 512, body: 1.0, rounded: false, opaque: true);
    });
  });
}

const String _kIosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const String _kMacDir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';

/// What iOS asks for, by the names its catalogue already uses: the size in
/// points times the scale, which is the number of pixels on the side.
const Map<String, int> _kIosIcons = <String, int>{
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
};

/// And what macOS does — one file per pixel size, shared between the scales.
const List<int> _kMacIcons = <int>[16, 32, 64, 128, 256, 512, 1024];

/// How much of the macOS canvas the icon is allowed to fill.
///
/// Apple's own grid: 824 points of a 1024-point square, centred, with the rest
/// left as air. macOS draws icons at their own size on a desk rather than in a
/// slot cut to fit them — the margin is what keeps this one the same size as
/// everything else in the dock instead of a fifth larger than its neighbours.
///
/// The corner it wants there is 185.4 of 824, which is 22.5%; the mark's own
/// is 114 of 512, which is 22.3%. They are the same corner, so the drawing
/// needs nothing done to it but scaling.
const double _kMacBody = 824 / 1024;

const String _kAndroidRes = 'android/app/src/main/res';

/// Where the Play console's copy goes. Not compiled into anything — it is
/// uploaded by hand — but it is the same drawing, so it is drawn here.
const String _kPlayIcon = 'android/app/src/main/ic_launcher-playstore.png';

/// Android sizes everything in density-independent pixels and then asks for
/// one raster per bucket. The buckets are the scale factors, and every size
/// below is a dp figure multiplied by one of them.
const Map<String, double> _kAndroidDensities = <String, double>{
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

/// A launcher icon before adaptive icons existed: 48 dp, and the whole picture.
const double _kLegacyDp = 48;

/// And after them: a 108 dp layer, of which the launcher shows the middle 72 dp
/// and *guarantees* only the middle 66 dp circle.
///
/// The outer ring is not padding — it is the room the launcher moves the layers
/// through when it parallaxes them against each other, so anything drawn there
/// is being volunteered for cropping.
const double _kAdaptiveDp = 108;

/// How much of an adaptive layer the mark's own square is allowed to be.
///
/// The design square goes on the 72 dp the launcher will actually show, which
/// puts the animal — 276 x 304 of the mark's 512 units — at 38.8 x 42.8 dp.
/// Its furthest corner is then 28.9 dp from the centre, inside the 33 dp the
/// safe circle promises, and the corners of that box are empty anyway because
/// the animal is drawn out of round shapes. So the whole of it survives every
/// mask, and it is the same drawing iOS gets rather than one redrawn to fit.
const double _kAdaptiveBody = 72 / 108;

/// The mark, in its own 512-point square. See [assets/rollhippo.svg].
///
/// [body] is the fraction of [edge] the drawing fills, centred in it, and
/// [rounded] is whether the red field keeps its corners — see the two callers,
/// which want different answers to both.
void paintMark(
  Canvas canvas,
  double edge, {
  double body = 1.0,
  bool rounded = true,
}) {
  final Paint field = Paint()..color = kMarkRed;

  final double side = edge * body;
  canvas.save();
  canvas.translate((edge - side) / 2, (edge - side) / 2);
  canvas.scale(side / 512);

  const Rect square = Rect.fromLTWH(0, 0, 512, 512);
  if (rounded) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(square, const Radius.circular(114)),
      field,
    );
  } else {
    canvas.drawRect(square, field);
  }

  paintAnimal(
    canvas,
    white: Paint()..color = const Color(0xFFFFFFFF),
    mark: Paint()..color = kMarkRed,
  );

  canvas.restore();
}

/// The red the field is, and the eyes and pips are cut back to.
const Color kMarkRed = Color(0xFFD7263D);

/// The animal alone, in the mark's own 512-unit square, with no field under it.
///
/// Split out of [paintMark] because an adaptive icon wants the field and the
/// figure as separate layers — and because the two paints are worth handing in
/// rather than assuming. The monochrome layer needs [mark] to *cut* the eyes
/// and pips out rather than paint them red: tinted flat by the launcher, red on
/// white and white on white are the same colour, and an animal with no face is
/// a potato.
void paintAnimal(Canvas canvas, {required Paint white, required Paint mark}) {
  // Two ears, a head and a snout, in that order because the head is drawn over
  // the ears and the snout over the head.
  canvas.drawCircle(const Offset(170, 146), 40, white);
  canvas.drawCircle(const Offset(342, 146), 40, white);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(144, 140, 224, 190),
      const Radius.circular(74),
    ),
    white,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(118, 260, 276, 150),
      const Radius.circular(74),
    ),
    white,
  );

  // Two eyes, and three spots down the snout — which are the three pips of a
  // die read corner to corner, and the whole of the joke.
  canvas.drawCircle(const Offset(201, 198), 17, mark);
  canvas.drawCircle(const Offset(311, 198), 17, mark);
  canvas.drawCircle(const Offset(180, 303), 16, mark);
  canvas.drawCircle(const Offset(256, 335), 16, mark);
  canvas.drawCircle(const Offset(332, 367), 16, mark);
}

/// One icon, drawn and written.
///
/// [opaque] is its own switch rather than a consequence of [rounded], because
/// Android wants both answers at once: its legacy icon is rounded by us *and*
/// keeps its alpha, since the corners the rounding cuts have to be see-through.
Future<void> _write(
  String path,
  int pixels, {
  required double body,
  bool rounded = true,
  bool opaque = false,
}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  paintMark(Canvas(recorder), pixels.toDouble(), body: body, rounded: rounded);
  final ui.Image image = await recorder.endRecording().toImage(pixels, pixels);
  final Uint8List bytes = opaque ? await _opaquePng(image) : await _png(image);
  image.dispose();
  File(path).writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('wrote $path  ${pixels}x$pixels  ${(bytes.length / 1024).round()} kB');
}

/// One layer of the adaptive icon: the animal, on nothing, on a 108 dp canvas.
///
/// There is no background layer to draw — the field is one flat colour, so it
/// is a colour resource rather than five rasters of the same red.
Future<void> _writeLayer(
  String path,
  int pixels, {
  bool monochrome = false,
}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  final double edge = pixels.toDouble();
  // Onto a layer of its own, so [BlendMode.clear] has something to cut holes
  // in. Against the bare canvas it would take the whole picture with it.
  canvas.saveLayer(Rect.fromLTWH(0, 0, edge, edge), Paint());
  final double side = edge * _kAdaptiveBody;
  canvas.translate((edge - side) / 2, (edge - side) / 2);
  canvas.scale(side / 512);
  paintAnimal(
    canvas,
    white: Paint()..color = const Color(0xFFFFFFFF),
    mark:
        monochrome
            ? (Paint()..blendMode = BlendMode.clear)
            : (Paint()..color = kMarkRed),
  );
  canvas.restore();
  final ui.Image image = await recorder.endRecording().toImage(pixels, pixels);
  final Uint8List bytes = await _png(image);
  image.dispose();
  File(path).writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('wrote $path  ${pixels}x$pixels  ${(bytes.length / 1024).round()} kB');
}

/// Straight out of the engine, alpha and all — which is what the macOS margin
/// has to be.
Future<Uint8List> _png(ui.Image image) async {
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

/// The same picture with the alpha channel taken off it rather than filled in.
///
/// Every pixel of an iOS icon is opaque already — the field is a full square —
/// but App Store validation rejects an icon that merely *has* a channel it
/// could have been transparent through. Three channels is the only answer that
/// cannot be argued with, and the `image` package is here to encode them.
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
