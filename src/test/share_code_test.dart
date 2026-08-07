import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rollhippo/tray/tray.dart';

/// Set by set, die by die — which says which set went wrong when one does,
/// where comparing two lists whole says only that they differ.
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

  group('a profile code', () {
    Profile profile({
      ProfileMode mode = ProfileMode.dice,
      List<List<DieSpec>>? groups,
      List<int> colours = const <int>[kDiceWhite, kDiceWhite],
      int decks = 2,
      int cut = 5,
    }) => Profile(
      mode: mode,
      groups:
          groups ??
          <List<DieSpec>>[
            <DieSpec>[spec(DieKind.d6, kDiceWhite)],
            <DieSpec>[],
            <DieSpec>[],
          ],
      colours: colours,
      decks: decks,
      reshuffleAt: cut,
    );

    test('carries the whole picker, both modes of it', () {
      final Profile sent = profile(
        mode: ProfileMode.cards,
        groups: <List<DieSpec>>[
          <DieSpec>[
            spec(DieKind.d20, kDicePalette[6]),
            spec(DieKind.d4, kDiceWhite),
          ],
          <DieSpec>[],
          <DieSpec>[spec(DieKind.d12, kDicePalette[3])],
        ],
        colours: <int>[kDicePalette[2], kDicePalette[5], kDiceWhite],
        decks: 3,
        cut: 17,
      );

      final ScannedProfile back =
          decodeProfile(encodeProfile(sent, name: 'Catan'))!;

      expect(back.name, 'Catan');
      expect(
        back.profile,
        sent,
        reason: 'the same profile, not a copy of half of it',
      );
      expect(back.profile.mode, ProfileMode.cards);
      expect(back.profile.decks, 3);
      expect(back.profile.reshuffleAt, 17);
      expect(back.profile.colours, <int>[
        kDicePalette[2],
        kDicePalette[5],
        kDiceWhite,
      ]);
      expectSame(back.profile.groups, sent.groups);
    });

    test('a profile nobody has saved has a blank name', () {
      final ScannedProfile back = decodeProfile(encodeProfile(profile()))!;
      expect(back.name, isEmpty);
      expect(back.profile, profile());
    });

    test('a name is whatever somebody typed, to the character', () {
      for (final String name in <String>['A', 'Poker Night', 'Ünïcødé ✦']) {
        expect(decodeProfile(encodeProfile(profile(), name: name))!.name, name);
      }
    });

    test('stays small enough to scan across a table', () {
      final String code = encodeProfile(
        Profile(
          mode: ProfileMode.cards,
          groups: <List<DieSpec>>[
            for (int g = 0; g < 3; g++)
              <DieSpec>[
                for (int d = 0; d < 10; d++) spec(DieKind.d20, kDicePalette[7]),
              ],
          ],
          colours: <int>[kDiceWhite, kDiceWhite, kDiceWhite],
          decks: 3,
          reshuffleAt: 20,
        ),
        name: 'Poker Nights',
      );
      // The worst case there is: three full sets, three cards and the longest
      // name allowed. Under a hundred characters is a coarse QR code.
      expect(code.length, lessThan(100));
    });

    test('is not the other kind of code, and knows it', () {
      // Each reader takes its own version and declines the other outright,
      // which is the whole point of putting the version in the prefix.
      final String sets = encodeGroups(<List<DieSpec>>[
        <DieSpec>[spec(DieKind.d6, kDiceWhite)],
      ]);
      expect(decodeProfile(sets), isNull);
      expect(decodeGroups(encodeProfile(profile())), isNull);

      expect(decodeProfile(''), isNull);
      expect(decodeProfile('https://example.com/'), isNull);
      expect(decodeProfile('${kProfileCodePrefix}not base64 at all!'), isNull);
    });

    test('refuses anything it cannot read the whole of', () {
      final String code = encodeProfile(profile(), name: 'Yahtzee');
      final String body = code.substring(kProfileCodePrefix.length);
      final Uint8List bytes = base64Url.decode(body);

      // A byte short of the name, and a byte too many.
      expect(
        decodeProfile(
          kProfileCodePrefix +
              base64Url.encode(bytes.sublist(0, bytes.length - 1)),
        ),
        isNull,
      );
      expect(
        decodeProfile(
          kProfileCodePrefix + base64Url.encode(<int>[...bytes, 0]),
        ),
        isNull,
      );

      // A header and nothing else.
      expect(
        decodeProfile(kProfileCodePrefix + base64Url.encode(<int>[0, 2, 5])),
        isNull,
      );

      // A mode this build has never heard of, and a colour it has not either.
      final List<int> odd = <int>[...bytes];
      odd[0] = 7;
      expect(decodeProfile(kProfileCodePrefix + base64Url.encode(odd)), isNull);
      final List<int> wrong = <int>[...bytes];
      wrong[4] = 0x0F;
      expect(
        decodeProfile(kProfileCodePrefix + base64Url.encode(wrong)),
        isNull,
      );
    });

    test('surrounding whitespace is not a reason to refuse', () {
      final String code = encodeProfile(profile(), name: 'D&D');
      expect(decodeProfile('  $code\n')!.name, 'D&D');
    });
  });
}
