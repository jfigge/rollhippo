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
