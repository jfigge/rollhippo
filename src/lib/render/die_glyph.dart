import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The numbers printed on the dice, laid out once and scaled into each face.
///
/// Laying a paragraph out at a fixed size and letting the canvas transform
/// shrink it is both cheaper than re-laying it out every frame and the only
/// way to get a numeral to sit in perspective on a tilted face — so every
/// caller works in these units and scales afterwards.
///
/// This lives apart from `tray_painter.dart` because two painters now print
/// text on a die: the numerals, and the rank in the corner of a poker card.
/// The font seam below has to be one seam rather than two.
const double dieGlyphFontSize = 100.0;
const double dieGlyphLayoutWidth = 400.0;

final Map<String, ui.Paragraph> _glyphs = <String, ui.Paragraph>{};

String? _dieGlyphFont;

/// The face the numbers on the dice are laid out in, or null for the
/// platform's own — which is what the app uses, and what a phone should.
///
/// A seam for the tools, and the only reason it exists: `flutter test`
/// substitutes a font with no glyphs in it, so a rendered sheet comes out with
/// a solid box wherever a number should be. That is tolerable for a die, whose
/// shape is the thing being looked at, and not for the hippopotamus, whose
/// numbers are printed on an animal and have to be judged against it. A tool
/// names a real face here before it draws anything.
String? get dieGlyphFont => _dieGlyphFont;

set dieGlyphFont(String? family) {
  if (family == _dieGlyphFont) return;
  _dieGlyphFont = family;
  // The laid-out paragraphs are the old face's.
  _glyphs.clear();
}

/// One short run of text, laid out at [dieGlyphFontSize] and cached.
///
/// Keyed by the text and the ink together, because the colour is baked into a
/// paragraph and the same numeral is printed in two of them — dark on an ivory
/// die, cream on a graphite one.
ui.Paragraph dieGlyph(String text, Color ink) {
  final String key = '${ink.toARGB32()}:$text';
  return _glyphs[key] ??=
      (ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: _dieGlyphFont,
                textAlign: TextAlign.center,
                fontSize: dieGlyphFontSize,
                fontWeight: FontWeight.w600,
              ),
            )
            ..pushStyle(ui.TextStyle(color: ink))
            ..addText(text))
          .build()
        ..layout(const ui.ParagraphConstraints(width: dieGlyphLayoutWidth));
}
