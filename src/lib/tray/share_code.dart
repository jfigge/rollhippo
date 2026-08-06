import 'dart:convert';
import 'dart:typed_data';

import 'dice.dart';

/// What every Roll Hippo share code starts with.
///
/// The point of a prefix is the *negative* case. A camera pointed at the world
/// finds QR codes constantly — a parcel label, a menu, a Wi-Fi card — and the
/// scanner has to be able to say "that is not one of mine" without guessing.
/// Four characters answers that before any decoding is attempted.
///
/// The 1 is the format version, and it is in the prefix rather than in the
/// payload on purpose: a version 2 code is not a version 1 code with a
/// different byte in it, it is a code this build should decline outright and
/// say so, rather than decode into the wrong dice.
const String kShareCodePrefix = 'RH1:';

/// The dice sets, small enough to put in a QR code.
///
/// Ten dice fit in ten bytes because a die is only two choices, and both are
/// from a fixed list: six kinds and eight colours, three bits each. A full
/// three groups of ten is 34 bytes — 48 characters of base64 — which is a QR
/// code you can scan across a table rather than one you have to lean into.
///
/// Storing the colour as an index into [kDicePalette] rather than as its ARGB
/// is what buys most of that, and it is honest because the palette is the only
/// place a die's colour can come from: the picker offers those eight and
/// nothing else. A colour from anywhere else has no index, and is written out
/// as the first one — see [_paletteIndex].
String encodeGroups(List<List<DieSpec>> groups) {
  final List<int> bytes = <int>[groups.length];
  for (final List<DieSpec> group in groups) {
    bytes.add(group.length);
    for (final DieSpec die in group) {
      bytes.add((die.kind.index << 4) | _paletteIndex(die.colour));
    }
  }
  return kShareCodePrefix + base64Url.encode(bytes);
}

/// The sets a share code describes, or null if [text] is not one.
///
/// Null covers every way this can fail and they are all the same answer to the
/// caller: someone pointed the camera at a QR code that was not ours. Wrong
/// prefix, not base64, truncated, a kind or a colour this build has never heard
/// of, or trailing bytes that mean the reader and the writer disagree about the
/// format — none of them is a config, and a half-decoded config would be worse
/// than none.
///
/// What comes back is exactly what was encoded, groups and all, *without* being
/// held to the picker's own limits. Those belong to the picker: this knows the
/// wire format, and `ConfigScreen` knows how many sets it has room for.
List<List<DieSpec>>? decodeGroups(String text) {
  final String trimmed = text.trim();
  if (!trimmed.startsWith(kShareCodePrefix)) return null;

  final Uint8List bytes;
  try {
    bytes = base64Url.decode(trimmed.substring(kShareCodePrefix.length));
  } on FormatException {
    return null;
  }
  if (bytes.isEmpty) return null;

  int at = 0;
  final int count = bytes[at++];
  final List<List<DieSpec>> groups = <List<DieSpec>>[];
  for (int g = 0; g < count; g++) {
    if (at >= bytes.length) return null;
    final int size = bytes[at++];
    if (at + size > bytes.length) return null;
    final List<DieSpec> group = <DieSpec>[];
    for (int d = 0; d < size; d++) {
      final DieSpec? die = _die(bytes[at++]);
      if (die == null) return null;
      group.add(die);
    }
    groups.add(group);
  }
  // Anything left over is not padding, it is disagreement.
  if (at != bytes.length) return null;
  return groups;
}

/// One die, or null if the byte names a kind or a colour that does not exist.
DieSpec? _die(int byte) {
  final int kind = byte >> 4;
  final int colour = byte & 0x0F;
  if (kind >= DieKind.values.length) return null;
  if (colour >= kDicePalette.length) return null;
  return DieSpec(kind: DieKind.values[kind], colour: kDicePalette[colour]);
}

/// Where [colour] sits in [kDicePalette], or 0 for a colour that is not in it.
///
/// Unreachable from the picker, which only ever writes palette entries. It is
/// here so that a die built in a test or by some later feature cannot make
/// [encodeGroups] throw halfway through building a code — falling back to
/// ivory loses a colour, which is recoverable, where an exception thrown at
/// the moment the Share sheet opens is not.
int _paletteIndex(int colour) {
  final int index = kDicePalette.indexOf(colour);
  return index < 0 ? 0 : index;
}
