import 'dart:convert';
import 'dart:typed_data';

import 'dice.dart';
import 'profile.dart';

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
/// from a fixed list: six kinds and eight colours, three bits each. A group
/// costs one byte more than its dice and the run of them costs one, so the
/// full `kMaxGroups` sets of ten come to 45 bytes — 60 characters of base64 —
/// which is a QR code you can scan across a table rather than one you have to
/// lean into.
///
/// Storing the colour as an index into [kDicePalette] rather than as its ARGB
/// is what buys most of that, and it is honest because the palette is the only
/// place a die's colour can come from: the picker offers those eight and
/// nothing else. A colour from anywhere else has no index, and is written out
/// as the first one — see [_paletteIndex].
///
/// This is not what a QR code carries any more — see [encodeProfile], which
/// wraps these same bytes in the rest of a profile. It is still what a
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
/// format — none of them is a profile, and a half-decoded profile would be worse
/// than none.
///
/// What comes back is exactly what was encoded, groups and all, *without* being
/// held to the picker's own limits. Those belong to the picker: this knows the
/// wire format, and `PickerScreen` knows how many sets it has room for.
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

/// What every Roll Hippo *profile* code starts with.
///
/// Two versions on from [kShareCodePrefix], and a different thing: that one is
/// a set of dice, and this is the whole picker — which mode it is in, what is
/// in the rack, what the shoes are made of, and what its owner calls it. A
/// build that only knows how to read an older one declines this outright
/// rather than decode two thirds of it, which is what the version is for.
const String kProfileCodePrefix = 'RH3:';

/// The profile code this app used to write, and still reads.
///
/// Identical to [kProfileCodePrefix] but for its shoes: an `RH2:` code carries
/// one, as the only one there was, where an `RH3:` carries a run of them. It
/// is read and never written, which costs a branch in [decodeProfile] and
/// means a code somebody saved to a photo or printed on a card still opens.
/// The other direction is not available and is not meant to be: an `RH2:`
/// reader that took an `RH3:` code would silently drop every shoe but the
/// first, which is the whole reason the version is in the prefix.
///
/// The run is what buys the *next* change for nothing. [kMaxCardSets] went
/// from three to four without a version after it, because a count and then
/// that many of a thing describes any number of shoes as readily as three —
/// an older build reads the whole code and then holds it to the three sets it
/// has room for, which is what it does with any profile from a later build.
const String kProfileCodeV2Prefix = 'RH2:';

/// A profile read off somebody else's screen.
///
/// The [name] is theirs, and is blank when the phone it came from had not
/// saved that profile under anything — which is a real answer, and the
/// difference between a code that offers to become a save on this phone and
/// one that is only a set of dice to try.
class ScannedProfile {
  const ScannedProfile({required this.name, required this.profile});

  final String name;
  final Profile profile;
}

/// A whole profile, small enough to put in a QR code.
///
/// The mode first, then the shoes, then the sets of dice in exactly the bytes
/// [encodeGroups] would have written, then the name — which goes last because
/// it is the only part whose length nobody can predict.
///
/// A shoe is its own little run for the same reason a group of dice is: a
/// count and then that many of a thing, so the reader never has to know how
/// many there were going to be — which is why [kMaxCardSets] could be raised
/// without a fourth version of this format. Three dice, two numbers and a
/// length is five bytes at the most, so four shoes cost twenty where one cost
/// five.
///
/// A full house — four sets of ten dice, four shoes of three cards, a
/// twelve-character name — comes to 84 bytes, which is 112 characters of
/// base64 and a QR code still coarse enough to read across a table. A profile
/// anybody actually keeps is a fraction of it.
String encodeProfile(Profile profile, {String name = ''}) {
  final List<int> bytes = <int>[profile.mode.index];
  _writeCards(bytes, profile.cards);
  _writeGroups(bytes, profile.groups);
  final List<int> label = utf8.encode(name);
  bytes
    ..add(label.length)
    ..addAll(label);
  return kProfileCodePrefix + base64Url.encode(bytes);
}

/// The profile a code describes, or null if [text] is not one.
///
/// Null covers every way this can fail, for the reason [decodeGroups] gives:
/// they are all the same answer to the caller, and a half-decoded
/// profile would be worse than none.
///
/// What comes back is what was encoded, *without* being held to the picker's
/// limits — those belong to the picker, which knows how many sets it has room
/// for. See `PickerScreen._apply`.
ScannedProfile? decodeProfile(String text) {
  final String trimmed = text.trim();
  final bool v2 = trimmed.startsWith(kProfileCodeV2Prefix);
  if (!v2 && !trimmed.startsWith(kProfileCodePrefix)) return null;

  final Uint8List bytes;
  try {
    bytes = base64Url.decode(trimmed.substring(kProfileCodePrefix.length));
  } on FormatException {
    return null;
  }
  // The mode, and enough after it to be a shoe. Anything shorter is not a code
  // this build or the one before it has ever produced.
  if (bytes.length < 5) return null;

  int at = 0;
  final int mode = bytes[at++];
  if (mode >= ProfileMode.values.length) return null;

  final _Cards? cards = v2 ? _readCardsV2(bytes, at) : _readCards(bytes, at);
  if (cards == null) return null;
  at = cards.end;

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

  return ScannedProfile(
    name: name,
    profile: Profile(
      mode: ProfileMode.values[mode],
      groups: read.groups,
      cards: cards.cards,
    ),
  );
}

/// The shoes, and where they stopped.
class _Cards {
  const _Cards(this.cards, this.end);

  final List<CardSet> cards;
  final int end;
}

void _writeCards(List<int> bytes, List<CardSet> cards) {
  bytes.add(cards.length);
  for (final CardSet shoe in cards) {
    bytes
      ..add(shoe.colours.length)
      ..addAll(<int>[
        for (final int colour in shoe.colours) _paletteIndex(colour),
      ])
      ..add(shoe.decks)
      ..add(shoe.reshuffleAt);
  }
}

_Cards? _readCards(Uint8List bytes, int at) {
  if (at >= bytes.length) return null;
  final int count = bytes[at++];
  final List<CardSet> cards = <CardSet>[];
  for (int c = 0; c < count; c++) {
    if (at >= bytes.length) return null;
    final int dice = bytes[at++];
    // Two numbers follow the colours, and a shoe with neither is a truncated
    // code rather than a short one.
    if (at + dice + 2 > bytes.length) return null;
    final List<int> colours = <int>[];
    for (int d = 0; d < dice; d++) {
      final int index = bytes[at++];
      if (index >= kDicePalette.length) return null;
      colours.add(kDicePalette[index]);
    }
    cards.add(
      CardSet(colours: colours, decks: bytes[at++], reshuffleAt: bytes[at++]),
    );
  }
  return _Cards(cards, at);
}

/// The one shoe an `RH2:` code carries, read into the list of them this build
/// works in.
///
/// The old header put its two numbers *before* the colours rather than after,
/// which is the whole of the difference and the reason this is a separate
/// reader rather than a flag inside the other one. It comes back as a single
/// shoe: the two the code has no room for arrive empty, exactly as they would
/// on a phone where nobody had started them.
_Cards? _readCardsV2(Uint8List bytes, int at) {
  final int decks = bytes[at++];
  final int reshuffleAt = bytes[at++];
  final int dice = bytes[at++];
  if (dice == 0 || at + dice > bytes.length) return null;
  final List<int> colours = <int>[];
  for (int i = 0; i < dice; i++) {
    final int index = bytes[at++];
    if (index >= kDicePalette.length) return null;
    colours.add(kDicePalette[index]);
  }
  return _Cards(<CardSet>[
    CardSet(colours: colours, decks: decks, reshuffleAt: reshuffleAt),
    for (int i = 1; i < kMaxCardSets; i++)
      const CardSet(colours: <int>[], decks: 1, reshuffleAt: 0),
  ], at);
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
