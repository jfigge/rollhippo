import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/app/picker_screen.dart';
import 'package:rollhippo/app/profile_row.dart';
import 'package:rollhippo/app/profiles.dart';
import 'package:rollhippo/app/tray_screen.dart';
import 'package:rollhippo/app/tutorial.dart';
import 'package:rollhippo/render/die_preview.dart';
import 'package:rollhippo/tray/tray.dart';

/// Renders the picker, so the rack can be looked at without a device in your
/// hand. Run with:
///
///     flutter test tool/picker.dart
///
/// Two images: the whole screen with a full rack of assorted dice, and a strip
/// of every kind at rack size, which is what to check after touching
/// [previewOrientation] — the angle is chosen by a search, and the only way to
/// know a change to it helped is to look at all of them. The hippopotamus is
/// in that strip and not in the rack, because the rack is the picker and the
/// picker only offers it to somebody who has asked for it by name.
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
      const RepaintBoundary(child: MaterialApp(home: PickerScreen())),
    );

    // Fill the rack by driving the picker the way a thumb would, one die at a
    // time — which also means this tool fails if the picker stops working.
    for (int i = 0; i < kMaxDice; i++) {
      if (i >= kDefaultDice.length) {
        await tester.tap(_addDie);
        await tester.pump();
      } else {
        await tester.tap(_dice(find.byType(DiePreview)).at(i));
        await tester.pump();
      }
      await tester.tap(_dice(find.text(_offered[i % _offered.length].label)));
      await tester.pump();
      await tester.tap(_dice(_swatch(kDicePalette[i % kDicePalette.length])));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    await _write(tester, '$dir/picker.png');

    // And the group next door, which nobody has put anything in yet: an empty
    // rack, the second dot lit and hollow, and an editor gone quiet in exactly
    // the place it was. It is the one layout that only exists after a swipe,
    // which makes it the one worth having a picture of.
    await tester.drag(find.byKey(kRack), const Offset(-300, 0));
    await tester.pumpAndSettle();

    await _write(tester, '$dir/picker-empty.png');
  });

  testWidgets('the picker in card mode', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(kHarnessScreen);
    tester.view.physicalSize = kHarnessScreen * 2;
    tester.view.devicePixelRatio = 2.0;

    await tester.pumpWidget(
      const RepaintBoundary(child: MaterialApp(home: PickerScreen())),
    );

    // The second mode dot, which is the same place a swipe on the panel gets
    // you and a great deal easier to aim at from a script.
    await tester.tap(
      find
          .descendant(
            of: find.byKey(kModeDots),
            matching: find.byType(GestureDetector),
          )
          .at(1),
    );
    await tester.pumpAndSettle();

    // Two dice in two colours, because ivory is what the card looks like
    // already and the point of this picture is the swatch row the panel grew —
    // and that it paints one die of the card at a time, the way the rack does.
    await tester.tap(_card(_swatch(kDicePalette[5])));
    await tester.pump();
    await tester.tap(_card(find.byType(DiePreview)).at(1));
    await tester.pump();
    await tester.tap(_card(_swatch(kDicePalette[2])));
    await tester.pumpAndSettle();

    await _write(tester, '$dir/picker-cards.png');
  });

  testWidgets('the saves, and the dialogs about them', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(kHarnessScreen);
    tester.view.physicalSize = kHarnessScreen * 2;
    tester.view.devicePixelRatio = 2.0;

    // Several saves, put straight into the store rather than made through the
    // dialog: what these pictures are for is the row, and typing six names in
    // through a keyboard that is not there would only be a slower way to
    // arrive at the same screen.
    profiles.add('Yahtzee', _saved(5));
    profiles.add('D&D', _saved(7));
    profiles.add('Craps', _saved(2));
    profiles.add('Backgammon', _saved(2));
    profiles.add('Farkle', _saved(6));
    profiles.add('Poker Night', _saved(3));

    await tester.pumpWidget(
      const RepaintBoundary(child: MaterialApp(home: PickerScreen())),
    );
    await tester.pumpAndSettle();

    // The row, with one of them open.
    await tester.tap(find.text('Yahtzee'));
    await tester.pumpAndSettle();
    await _write(tester, '$dir/picker-saves.png');

    // The menu that profile has: Reset, which lives nowhere else, and Share,
    // which every profile in the row has one of. The whole of it is the thing
    // on this screen that no label announces.
    await tester.longPress(find.byKey(kNewProfile));
    await tester.pumpAndSettle();
    await _write(tester, '$dir/picker-reset.png');
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(kNewProfile));
    await tester.pumpAndSettle();
    await _write(tester, '$dir/picker-name.png');
  });

  testWidgets('every kind at rack size', (WidgetTester tester) async {
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

/// A profile with [dice] dice in its first set, which is enough for one save
/// to be told from another.
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
  cards: <CardSet>[
    CardSet(
      colours: const <int>[kDiceWhite, kDiceWhite],
      decks: 2,
      reshuffleAt: 5,
    ),
    kEmptyShoe,
    kEmptyShoe,
  ],
);

/// The kinds the picker will let you choose without being asked by name — see
/// [DieKind.secret], which is what keeps the hippopotamus out of a sheet that
/// is meant to show the rack rather than the easter egg.
final List<DieKind> _offered = <DieKind>[
  for (final DieKind kind in DieKind.values)
    if (!kind.secret) kind,
];

/// Whichever of [finder]'s widgets is in one mode's panel. Both modes are built
/// at once, one screen apart, and both have a rack and a palette — so anything
/// they share has to say which of them it means.
Finder _dice(Finder finder) =>
    find.descendant(of: find.byKey(kDicePage), matching: finder);

Finder _card(Finder finder) =>
    find.descendant(of: find.byKey(kCardPage), matching: finder);

/// The plus in the first set's rack, which is where a die is added.
final Finder _addDie = find.descendant(
  of: find.byKey(const ValueKey<int>(0)),
  matching: find.byKey(kAddDie),
);

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
