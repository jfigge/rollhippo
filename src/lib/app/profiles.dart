import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tray/tray.dart';

/// The longest a saved profile's name is allowed to be.
///
/// A profile wears its name in a row of them, and the row is the width of a
/// phone: a name long enough to need scrolling to read is a name that stops the
/// row doing the one thing it is for, which is telling you at a glance what is
/// saved. Twelve rather than ten because "Poker Night" is eleven, and a
/// limit that cannot spell the example everybody reaches for first is a limit
/// that reads as a bug.
const int kMaxProfileName = 12;

/// A profile, as it goes into the preferences file.
///
/// JSON with named fields rather than [encodeProfile]'s bytes, because this one
/// is read by a person as often as by the app — a preferences file you can look
/// at is a preferences file you can debug — and there is no size to fight for.
/// The dice are the exception: they go out as a share code, which is the same
/// data in a format that already exists and is already tested.
///
/// Not the name. That belongs to the save, not to the profile inside it,
/// and is written a level up by [SavedProfile.toJson].
Map<String, Object?> profileToJson(Profile profile) => <String, Object?>{
  'mode': profile.mode.name,
  'dice': encodeGroups(profile.groups),
  'colours': profile.colours,
  'decks': profile.decks,
  'cut': profile.reshuffleAt,
};

/// What [profileToJson] wrote, or null for anything this build cannot read.
///
/// Null rather than a throw or a patched-up half profile: the only
/// caller is [ProfileStore.load], which drops what it cannot read and carries
/// on. A save written by some later build, or a preferences file somebody has
/// been editing, must not be able to stop the app starting.
Profile? profileFromJson(Object? source) {
  if (source is! Map<String, Object?>) return null;
  final Object? dice = source['dice'];
  if (dice is! String) return null;
  final List<List<DieSpec>>? groups = decodeGroups(dice);
  if (groups == null) return null;
  final Object? stored = source['colours'];
  if (stored is! List) return null;
  final List<int> colours = stored.whereType<int>().toList();
  if (colours.isEmpty || colours.length != stored.length) return null;
  final Object? decks = source['decks'];
  final Object? cut = source['cut'];
  if (decks is! int || cut is! int) return null;
  return Profile(
    // Anything that is not the card page is the dice page. A mode this build
    // has never heard of is not worth refusing the whole profile over.
    mode:
        source['mode'] == ProfileMode.cards.name
            ? ProfileMode.cards
            : ProfileMode.dice,
    groups: groups,
    colours: colours,
    decks: decks,
    reshuffleAt: cut,
  );
}

/// One profile, named and kept.
///
/// The [id] is what everything else holds it by. Names are not unique — nothing
/// stops two saves being called Yahtzee — and a position in the list is not
/// stable, because deleting the one above moves it. An id survives both.
@immutable
class SavedProfile {
  const SavedProfile({
    required this.id,
    required this.name,
    required this.profile,
    required this.usedAt,
  });

  final int id;
  final String name;
  final Profile profile;

  /// When it was last opened.
  ///
  /// Written and kept up to date, and at present read by nothing: it was the
  /// second line of the launch chooser — "5 dice · used 2h ago" — and that
  /// screen is gone. It stays because it is *data*, and the one thing that
  /// cannot be recovered later is a timestamp nobody recorded. A row of
  /// profiles sorted by what you last reached for is the obvious use, and it
  /// costs one integer in the preferences file to keep the option open.
  final DateTime usedAt;

  SavedProfile copyWith({String? name, Profile? profile, DateTime? usedAt}) =>
      SavedProfile(
        id: id,
        name: name ?? this.name,
        profile: profile ?? this.profile,
        usedAt: usedAt ?? this.usedAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'used': usedAt.millisecondsSinceEpoch,
    // `config`, not `profile`. The word changed in the code; this one is a
    // field name in a file that is already on people's phones, and changing
    // it would not rename anything — it would lose every save written before
    // the rename. [profileFromJson] reads the same field for the same reason.
    'config': profileToJson(profile),
  };

  static SavedProfile? fromJson(Object? source) {
    if (source is! Map<String, Object?>) return null;
    final Object? id = source['id'];
    final Object? name = source['name'];
    final Object? used = source['used'];
    if (id is! int || name is! String || used is! int) return null;
    final Profile? profile = profileFromJson(source['config']);
    if (profile == null) return null;
    return SavedProfile(
      id: id,
      name: name,
      profile: profile,
      usedAt: DateTime.fromMillisecondsSinceEpoch(used),
    );
  }
}

/// The saved profiles, and the file they live in.
///
/// One instance, [profiles], reached directly rather than handed down the widget
/// tree — the same bargain `Settings` makes and for the same reason: the picker
/// owns the profile and the row under it lists the saves, and threading a store
/// through both to be read in one of them would be more machinery than the
/// thing it carries.
///
/// Newest first. A save is made *from* what is on screen, so the one you just
/// made is the one you are looking at, and it belongs where your eye already
/// is rather than at the end of a row that may have scrolled off.
class ProfileStore extends ChangeNotifier {
  /// Where the saves live, under the word they were written with. Same bargain
  /// as the `config` field inside each of them: a key is not a name anybody
  /// reads, and a new one would find an empty preferences file rather than the
  /// saves sitting next to it under the old one.
  static const String _key = 'configs.saved';

  final List<SavedProfile> _saves = <SavedProfile>[];

  /// The saves, newest first. A copy: the list is edited through this class so
  /// that nothing changes without the row being told about it.
  List<SavedProfile> get saves => List<SavedProfile>.unmodifiable(_saves);

  bool get isEmpty => _saves.isEmpty;
  bool get isNotEmpty => _saves.isNotEmpty;

  SavedProfile? byId(int? id) {
    for (final SavedProfile save in _saves) {
      if (save.id == id) return save;
    }
    return null;
  }

  /// The first save called [name], or null if nothing here is.
  ///
  /// The first, because names are not unique — nothing stops two profiles being
  /// called Yahtzee. This is only asked by a scanned code, which arrives with
  /// a name and no id and has to decide whether it is one you already have;
  /// the first match is the one your eye would land on too.
  SavedProfile? byName(String name) {
    for (final SavedProfile save in _saves) {
      if (save.name == name) return save;
    }
    return null;
  }

  /// Reads what was stored, replacing whatever is in memory.
  ///
  /// Awaited from `main` before the first frame, so the row of profiles is
  /// drawn with the saves already in it. Loading it afterwards would build the
  /// row empty and fill it in a frame or two later, which is a flicker on
  /// every launch of the one part of this screen that says what you have.
  ///
  /// Anything unreadable is dropped rather than repaired. One save from a later
  /// build, or one line somebody has been editing by hand, costs that save and
  /// nothing else.
  Future<void> load() async {
    final String? stored = await _guard<String>(() async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    });
    _saves.clear();
    if (stored != null) {
      final Object? decoded = _decode(stored);
      if (decoded is List) {
        for (final Object? entry in decoded) {
          final SavedProfile? save = SavedProfile.fromJson(entry);
          if (save != null) _saves.add(save);
        }
      }
    }
    notifyListeners();
  }

  /// Keeps [profile] under [name], at the front of the row.
  SavedProfile add(String name, Profile profile) {
    final DateTime now = DateTime.now();
    // The clock, in microseconds, which is unique enough for something a thumb
    // creates one of at a time and needs no counter kept anywhere — except
    // against itself. A loop can make two in the same microsecond, and two
    // saves with one id would be two profiles with one key.
    int id = now.microsecondsSinceEpoch;
    for (final SavedProfile save in _saves) {
      if (save.id >= id) id = save.id + 1;
    }
    final SavedProfile save = SavedProfile(
      id: id,
      name: name,
      profile: profile,
      usedAt: now,
    );
    _saves.insert(0, save);
    _changed();
    return save;
  }

  /// Puts what is on screen into an existing save.
  ///
  /// Only ever from Save, on the menu a profile gives you when you hold it down.
  /// Nothing here happens on its own: a save is a photograph of the picker
  /// taken when you asked for one, and editing the dice under an open profile
  /// leaves that profile exactly as it was until you say otherwise.
  ///
  /// An id that is not here — the save was deleted a moment ago — writes
  /// nothing. What is on screen stays on screen; it is simply not kept.
  void write(int? id, Profile profile) {
    final int at = _indexOf(id);
    if (at < 0) return;
    _saves[at] = _saves[at].copyWith(profile: profile);
    _changed();
  }

  void rename(int id, String name) {
    final int at = _indexOf(id);
    if (at < 0) return;
    _saves[at] = _saves[at].copyWith(name: name);
    _changed();
  }

  void remove(int id) {
    final int at = _indexOf(id);
    if (at < 0) return;
    _saves.removeAt(at);
    _changed();
  }

  /// Marks a save as opened just now.
  void touch(int id) {
    final int at = _indexOf(id);
    if (at < 0) return;
    _saves[at] = _saves[at].copyWith(usedAt: DateTime.now());
    _changed();
  }

  int _indexOf(int? id) {
    for (int i = 0; i < _saves.length; i++) {
      if (_saves[i].id == id) return i;
    }
    return -1;
  }

  void _changed() {
    notifyListeners();
    unawaited(_flush());
  }

  bool _writing = false;
  bool _again = false;

  /// Writes the whole list out, and never twice at once.
  ///
  /// [write] is called on every touch of a slider, so this can be asked to save
  /// far faster than the platform channel behind it answers. Overlapping writes
  /// of a value that is still changing can land in either order, so a second
  /// ask that arrives mid-write sets a flag instead of starting its own: the
  /// loop goes round again and writes whatever the list says by then, which is
  /// the only version anybody wanted.
  Future<void> _flush() async {
    if (_writing) {
      _again = true;
      return;
    }
    _writing = true;
    do {
      _again = false;
      final String payload = jsonEncode(<Object?>[
        for (final SavedProfile save in _saves) save.toJson(),
      ]);
      await _guard<void>(() async {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString(_key, payload);
      });
    } while (_again);
    _writing = false;
  }

  Object? _decode(String source) {
    try {
      return jsonDecode(source);
    } on FormatException {
      return null;
    }
  }

  /// A store that is not there is a store with nothing in it.
  ///
  /// Widget tests and the `tool/` renderers run without the platform channel
  /// behind [SharedPreferences], and a throw from it would fail a test about
  /// something else entirely. See `Settings` — same guard, same reasoning.
  Future<T?> _guard<T>(Future<T?> Function() body) async {
    try {
      return await body();
    } on Exception catch (error) {
      debugPrint('Roll Hippo: saved profiles unavailable ($error)');
      return null;
    }
  }
}

/// The saves.
final ProfileStore profiles = ProfileStore();
