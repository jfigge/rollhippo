import 'dart:convert';
import 'dart:typed_data';

import 'config.dart';
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
///
/// This is not what a QR code carries any more — see [encodeConfig], which
/// wraps these same bytes in the rest of a configuration. It is still what a
/// save's dice are written as inside the preferences file, where the sets are
/// the only part of it that is not already a plain JSON field.
String encodeGroups(List<List<DieSpec>> groups) {
  final List<int> bytes = <int>[];
  _writeGroups(bytes, groups);
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

  final _Groups? read = _readGroups(bytes, 0);
  // Anything left over is not padding, it is disagreement.
  if (read == null || read.end != bytes.length) return null;
  return read.groups;
}

/// What every Roll Hippo *configuration* code starts with.
///
/// A version on from [kShareCodePrefix], and a different thing: that one is a
/// set of dice, and this is the whole picker — which mode it is in, what is in
/// the rack, what the shoe is made of, and what its owner calls it. A build
/// that only knows how to read the old one will decline this outright rather
/// than decode two thirds of it, which is what the version is for.
const String kConfigCodePrefix = 'RH2:';

/// A configuration read off somebody else's screen.
///
/// The [name] is theirs, and is blank when the phone it came from had not
/// saved that configuration under anything — which is a real answer, and the
/// difference between a code that offers to become a save on this phone and
/// one that is only a set of dice to try.
class ScannedConfig {
  const ScannedConfig({required this.name, required this.config});

  final String name;
  final Config config;
}

/// A whole configuration, small enough to put in a QR code.
///
/// Header first, because it is fixed width and every code has one: the mode,
/// the two numbers the shoe is made of, and the card's own dice as palette
/// indices. Then the sets of dice, in exactly the bytes [encodeGroups] would
/// have written. Then the name, which goes last because it is the only part
/// whose length nobody can predict.
///
/// A full house — three sets of ten, three cards, a twelve-character name —
/// comes to 55 bytes, which is 76 characters of base64 and a QR code still
/// coarse enough to read across a table.
String encodeConfig(Config config, {String name = ''}) {
  final List<int> bytes = <int>[
    config.mode.index,
    config.decks,
    config.reshuffleAt,
    config.colours.length,
    for (final int colour in config.colours) _paletteIndex(colour),
  ];
  _writeGroups(bytes, config.groups);
  final List<int> label = utf8.encode(name);
  bytes
    ..add(label.length)
    ..addAll(label);
  return kConfigCodePrefix + base64Url.encode(bytes);
}

/// The configuration a code describes, or null if [text] is not one.
///
/// Null covers every way this can fail, for the reason [decodeGroups] gives:
/// they are all the same answer to the caller, and a half-decoded
/// configuration would be worse than none.
///
/// What comes back is what was encoded, *without* being held to the picker's
/// limits — those belong to the picker, which knows how many sets it has room
/// for. See `ConfigScreen._apply`.
ScannedConfig? decodeConfig(String text) {
  final String trimmed = text.trim();
  if (!trimmed.startsWith(kConfigCodePrefix)) return null;

  final Uint8List bytes;
  try {
    bytes = base64Url.decode(trimmed.substring(kConfigCodePrefix.length));
  } on FormatException {
    return null;
  }
  // The header, and at least one colour: a card with no dice on it is not a
  // configuration this build has ever produced.
  if (bytes.length < 5) return null;

  int at = 0;
  final int mode = bytes[at++];
  if (mode >= ConfigMode.values.length) return null;
  final int decks = bytes[at++];
  final int reshuffleAt = bytes[at++];
  final int cardDice = bytes[at++];
  if (cardDice == 0 || at + cardDice > bytes.length) return null;
  final List<int> colours = <int>[];
  for (int i = 0; i < cardDice; i++) {
    final int index = bytes[at++];
    if (index >= kDicePalette.length) return null;
    colours.add(kDicePalette[index]);
  }

  final _Groups? read = _readGroups(bytes, at);
  if (read == null) return null;
  at = read.end;

  if (at >= bytes.length) return null;
  final int length = bytes[at++];
  // The name is the last thing in the code, so it ends where the code does.
  // Anything else means the reader and the writer disagree about the format.
  if (at + length != bytes.length) return null;
  final String name;
  try {
    name = utf8.decode(bytes.sublist(at, at + length));
  } on FormatException {
    return null;
  }

  return ScannedConfig(
    name: name,
    config: Config(
      mode: ConfigMode.values[mode],
      groups: read.groups,
      colours: colours,
      decks: decks,
      reshuffleAt: reshuffleAt,
    ),
  );
}

/// The sets of dice, and where they stopped. Both codes carry them the same
/// way, so both read them with the same eyes.
class _Groups {
  const _Groups(this.groups, this.end);

  final List<List<DieSpec>> groups;
  final int end;
}

void _writeGroups(List<int> bytes, List<List<DieSpec>> groups) {
  bytes.add(groups.length);
  for (final List<DieSpec> group in groups) {
    bytes.add(group.length);
    for (final DieSpec die in group) {
      bytes.add((die.kind.index << 4) | _paletteIndex(die.colour));
    }
  }
}

_Groups? _readGroups(Uint8List bytes, int at) {
  if (at >= bytes.length) return null;
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
  return _Groups(groups, at);
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
