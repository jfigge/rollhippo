import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/tray/tray.dart';

/// [DieSpec] has no equality of its own, and giving it one for a test's benefit
/// would be a change to the model. Compare it the way the picker does.
void expectSame(List<List<DieSpec>> got, List<List<DieSpec>> want) {
  expect(got.length, want.length, reason: 'wrong number of sets');
  for (int g = 0; g < want.length; g++) {
    expect(got[g].length, want[g].length, reason: 'set $g is the wrong size');
    for (int d = 0; d < want[g].length; d++) {
      expect(got[g][d].kind, want[g][d].kind, reason: 'set $g die $d kind');
      expect(got[g][d].colour, want[g][d].colour, reason: 'set $g die $d hue');
    }
  }
}

DieSpec spec(DieKind kind, int colour) => DieSpec(kind: kind, colour: colour);

void main() {
  group('a code says exactly what was in the picker', () {
    test('every kind and every colour survives the round trip', () {
      // One die per kind and one per colour, so nothing in either list can be
      // dropped or shifted by one without this noticing.
      final List<List<DieSpec>> groups = <List<DieSpec>>[
        <DieSpec>[
          for (final DieKind kind in DieKind.values) spec(kind, kDiceWhite),
        ],
        <DieSpec>[
          for (final int colour in kDicePalette) spec(DieKind.d20, colour),
        ],
        <DieSpec>[],
      ];
      expectSame(decodeGroups(encodeGroups(groups))!, groups);
    });

    test('an empty set stays empty and stays where it was', () {
      // The middle one, because a set is identified by nothing but its
      // position: dropping it would silently promote the third.
      final List<List<DieSpec>> groups = <List<DieSpec>>[
        <DieSpec>[spec(DieKind.d6, kDiceWhite)],
        <DieSpec>[],
        <DieSpec>[spec(DieKind.d4, kDicePalette[3])],
      ];
      expectSame(decodeGroups(encodeGroups(groups))!, groups);
    });

    test('a full picker still fits in a code you can scan across a table', () {
      final List<List<DieSpec>> full = <List<DieSpec>>[
        for (int g = 0; g < 3; g++)
          <DieSpec>[
            for (int d = 0; d < 10; d++)
              spec(DieKind.values[d % 6], kDicePalette[d % 8]),
          ],
      ];
      final String code = encodeGroups(full);
      expectSame(decodeGroups(code)!, full);
      // Three sets of ten is 34 bytes, which base64 turns into 48 characters.
      // Under sixty keeps the code inside QR version 3 at the weakest error
      // correction — a coarse grid of big modules rather than a dense one.
      expect(
        code.length,
        lessThan(60),
        reason: 'a denser code is a code you have to lean into',
      );
    });
  });

  group('a code that is not ours', () {
    test('anything without the prefix is refused', () {
      expect(decodeGroups(''), isNull);
      expect(decodeGroups('https://example.com/'), isNull);
      expect(decodeGroups('WIFI:S:cafe;T:WPA;P:hunter2;;'), isNull);
      // Right shape, wrong app — and the version has to match exactly, so a
      // later format is declined rather than misread.
      expect(decodeGroups('RH2:AQEA'), isNull);
      expect(decodeGroups('rh1:AQEA'), isNull);
    });

    test('a code with the prefix and rubbish behind it is refused', () {
      expect(decodeGroups('${kShareCodePrefix}not base64 at all!'), isNull);
    });

    test('a truncated code is refused rather than half read', () {
      final String code = encodeGroups(<List<DieSpec>>[
        <DieSpec>[spec(DieKind.d6, kDiceWhite), spec(DieKind.d20, kDiceWhite)],
      ]);
      final List<int> bytes = base64Url.decode(
        code.substring(kShareCodePrefix.length),
      );
      // The header promises two dice; hand it one.
      final String short =
          kShareCodePrefix +
          base64Url.encode(bytes.sublist(0, bytes.length - 1));
      expect(decodeGroups(short), isNull);
    });

    test('trailing bytes mean the two ends disagree, so it is refused', () {
      final String code = encodeGroups(<List<DieSpec>>[
        <DieSpec>[spec(DieKind.d6, kDiceWhite)],
      ]);
      final List<int> bytes = base64Url.decode(
        code.substring(kShareCodePrefix.length),
      );
      final String long =
          kShareCodePrefix + base64Url.encode(<int>[...bytes, 0x00]);
      expect(decodeGroups(long), isNull);
    });

    test('a kind or a colour this build has never heard of is refused', () {
      // High nibble 15 is a seventh die; low nibble 9 is a ninth colour.
      expect(
        decodeGroups(kShareCodePrefix + base64Url.encode(<int>[1, 1, 0xF0])),
        isNull,
      );
      expect(
        decodeGroups(kShareCodePrefix + base64Url.encode(<int>[1, 1, 0x09])),
        isNull,
      );
    });

    test('surrounding whitespace is not a reason to refuse', () {
      final String code = encodeGroups(<List<DieSpec>>[
        <DieSpec>[spec(DieKind.d8, kDicePalette[5])],
      ]);
      expect(decodeGroups('  $code\n'), isNotNull);
    });
  });
}
