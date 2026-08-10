import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/render/tray_painter.dart';
import 'package:rollhippo/tray/tray.dart';

void main() {
  test('every face has as many pips as it claims', () {
    for (int value = 1; value <= 6; value++) {
      expect(
        pipLayout(value)?.length,
        value,
        reason: 'the $value face must have $value pips',
      );
    }
  });

  test('the pip layouts cover exactly a d6', () {
    for (int value = 1; value <= 6; value++) {
      expect(pipLayout(value), isNotNull);
    }
    expect(pipLayout(0), isNull);
    expect(pipLayout(7), isNull);
  });

  test('the camera fits a box into a window that has changed shape', () {
    const double width = 393 / Tuning.logicalPixelsPerMetre;
    const double height = 852 / Tuning.logicalPixelsPerMetre;

    // The ordinary case, and every case there has ever been: the box was
    // measured off this very screen, so both ratios come to the same constant
    // and there is nothing to letterbox.
    final TrayCamera square = cameraFor(const Size(393, 852), width, height);
    expect(square.pixelsPerMetre, closeTo(Tuning.logicalPixelsPerMetre, 1e-9));
    expect(square.pixelsPerMetre * width, closeTo(393, 1e-9));

    // Split screen: the same width, half the height, and a box that was built
    // before it happened. It has to fit the short way rather than fill the
    // wide way — filling would draw the floor of the tray off the bottom of
    // the window, with the dice resting on it.
    final TrayCamera short = cameraFor(const Size(393, 426), width, height);
    expect(short.pixelsPerMetre * height, lessThan(426 + 1e-9));
    expect(short.pixelsPerMetre * width, lessThan(393 + 1e-9));
    expect(
      short.pixelsPerMetre * height,
      closeTo(426, 1e-9),
      reason: 'the tighter axis is the one that should be filled exactly',
    );
    expect(short.centre, const Offset(393 / 2, 426 / 2));
  });

  test('the painter and the reader agree on what a face is worth', () {
    // Both `faceUp` and the pips the painter draws come from `faceValue`, so
    // the only way they can disagree is if `faceValue` stops describing a real
    // die. Opposite faces summing to seven is that property.
    for (int axis = 0; axis < 3; axis++) {
      final int front = faceValue(axis, 1);
      final int back = faceValue(axis, -1);
      expect(front + back, 7);
      expect(pipLayout(front)?.length, front);
      expect(pipLayout(back)?.length, back);
    }
  });
}
