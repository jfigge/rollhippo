import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tray/tray.dart';

/// The longest a saved configuration's name is allowed to be.
///
/// The name is worn as a pill in a row of them, and the row is the width of a
/// phone: a name long enough to need scrolling to read is a name that stops the
/// pills doing the one thing they are for, which is telling you at a glance
/// what is saved. Twelve rather than ten because "Poker Night" is eleven, and a
/// limit that cannot spell the example everybody reaches for first is a limit
/// that reads as a bug.
const int kMaxConfigName = 12;

/// A configuration, as it goes into the preferences file.
///
/// JSON with named fields rather than [encodeConfig]'s bytes, because this one
/// is read by a person as often as by the app — a preferences file you can look
/// at is a preferences file you can debug — and there is no size to fight for.
/// The dice are the exception: they go out as a share code, which is the same
/// data in a format that already exists and is already tested.
///
/// Not the name. That belongs to the save, not to the configuration inside it,
/// and is written a level up by [SavedConfig.toJson].
Map<String, Object?> configToJson(Config config) => <String, Object?>{
  'mode': config.mode.name,
  'dice': encodeGroups(config.groups),
  'colours': config.colours,
  'decks': config.decks,
  'cut': config.reshuffleAt,
};

/// What [configToJson] wrote, or null for anything this build cannot read.
///
/// Null rather than a throw or a patched-up half configuration: the only
/// caller is [ConfigStore.load], which drops what it cannot read and carries
/// on. A save written by some later build, or a preferences file somebody has
/// been editing, must not be able to stop the app starting.
Config? configFromJson(Object? source) {
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
  return Config(
    // Anything that is not the card page is the dice page. A mode this build
    // has never heard of is not worth refusing the whole configuration over.
    mode:
        source['mode'] == ConfigMode.cards.name
            ? ConfigMode.cards
            : ConfigMode.dice,
    groups: groups,
    colours: colours,
    decks: decks,
    reshuffleAt: cut,
  );
}

/// One configuration, named and kept.
///
/// The [id] is what everything else holds it by. Names are not unique — nothing
/// stops two saves being called Yahtzee — and a position in the list is not
/// stable, because deleting the one above moves it. An id survives both.
@immutable
class SavedConfig {
  const SavedConfig({
    required this.id,
    required this.name,
    required this.config,
    required this.usedAt,
  });

  final int id;
  final String name;
  final Config config;

  /// When it was last opened. What the chooser at launch sorts nothing by and
  /// says out loud — "used 2h ago" is how you tell two saves apart when their
  /// names have stopped meaning much.
  final DateTime usedAt;

  SavedConfig copyWith({String? name, Config? config, DateTime? usedAt}) =>
      SavedConfig(
        id: id,
        name: name ?? this.name,
        config: config ?? this.config,
        usedAt: usedAt ?? this.usedAt,
      );

  /// The line under the name in the launch chooser: what it holds, and when you
  /// last had it open.
  String subtitle(DateTime now) =>
      '${config.summary} · used ${agoLabel(usedAt, now)}';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'used': usedAt.millisecondsSinceEpoch,
    'config': configToJson(config),
  };

  static SavedConfig? fromJson(Object? source) {
    if (source is! Map<String, Object?>) return null;
    final Object? id = source['id'];
    final Object? name = source['name'];
    final Object? used = source['used'];
    if (id is! int || name is! String || used is! int) return null;
    final Config? config = configFromJson(source['config']);
    if (config == null) return null;
    return SavedConfig(
      id: id,
      name: name,
      config: config,
      usedAt: DateTime.fromMillisecondsSinceEpoch(used),
    );
  }
}

/// How long ago [then] was, in the coarsest form that is still true.
///
/// Coarse on purpose. Nobody is timing anything: the question this answers is
/// "is this the one I was playing with, or the one from last month", and to
/// that "2h ago" and "yesterday" are complete answers where a timestamp is
/// something you have to work out.
///
/// The days are elapsed days rather than calendar ones, so "yesterday" means
/// somewhere between one and two days back rather than after midnight. A clock
/// that has gone backwards — a timezone change, a phone corrected off the
/// network — lands on "just now", which is wrong by less than the alternatives.
String agoLabel(DateTime then, DateTime now) {
  final Duration gap = now.difference(then);
  if (gap.inMinutes < 1) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes}m ago';
  if (gap.inHours < 24) return '${gap.inHours}h ago';
  if (gap.inDays < 2) return 'yesterday';
  if (gap.inDays < 7) return '${gap.inDays} days ago';
  if (gap.inDays < 14) return 'last week';
  if (gap.inDays < 60) return '${gap.inDays ~/ 7} weeks ago';
  if (gap.inDays < 365) return '${gap.inDays ~/ 30} months ago';
  return 'over a year ago';
}

/// The saved configurations, and the file they live in.
///
/// One instance, [configs], reached directly rather than handed down the widget
/// tree — the same bargain `Settings` makes and for the same reason: the picker
/// owns the configuration, the pills under it list the saves, and the chooser
/// at launch opens one, and threading a store through all three to be read in
/// two of them would be more machinery than the thing it carries.
///
/// Newest first. A save is made *from* what is on screen, so the one you just
/// made is the one you are looking at, and it belongs where your eye already
/// is rather than at the end of a row that may have scrolled off.
class ConfigStore extends ChangeNotifier {
  static const String _key = 'configs.saved';

  final List<SavedConfig> _saves = <SavedConfig>[];

  /// The saves, newest first. A copy: the list is edited through this class so
  /// that nothing changes without the pills being told about it.
  List<SavedConfig> get saves => List<SavedConfig>.unmodifiable(_saves);

  bool get isEmpty => _saves.isEmpty;
  bool get isNotEmpty => _saves.isNotEmpty;

  SavedConfig? byId(int? id) {
    for (final SavedConfig save in _saves) {
      if (save.id == id) return save;
    }
    return null;
  }

  /// The first save called [name], or null if nothing here is.
  ///
  /// The first, because names are not unique — nothing stops two pills being
  /// called Yahtzee. This is only asked by a scanned code, which arrives with
  /// a name and no id and has to decide whether it is one you already have;
  /// the first match is the one your eye would land on too.
  SavedConfig? byName(String name) {
    for (final SavedConfig save in _saves) {
      if (save.name == name) return save;
    }
    return null;
  }

  /// Reads what was stored, replacing whatever is in memory.
  ///
  /// Awaited from `main` before the first frame, because the first thing the
  /// app does with this is decide whether to show the chooser at all — and a
  /// chooser that appeared a moment after the picker had already been drawn
  /// would be a dialog over a screen the player had started using.
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
          final SavedConfig? save = SavedConfig.fromJson(entry);
          if (save != null) _saves.add(save);
        }
      }
    }
    notifyListeners();
  }

  /// Keeps [config] under [name], at the front of the row.
  SavedConfig add(String name, Config config) {
    final DateTime now = DateTime.now();
    final SavedConfig save = SavedConfig(
      // The clock, in microseconds, which is unique enough for something a
      // thumb creates one of at a time and needs no counter kept anywhere.
      id: now.microsecondsSinceEpoch,
      name: name,
      config: config,
      usedAt: now,
    );
    _saves.insert(0, save);
    _changed();
    return save;
  }

  /// Puts what is on screen into an existing save.
  ///
  /// Only ever from Save, on the menu a pill gives you when you hold it down.
  /// Nothing here happens on its own: a save is a photograph of the picker
  /// taken when you asked for one, and editing the dice under an open pill
  /// leaves that pill exactly as it was until you say otherwise.
  ///
  /// An id that is not here — the save was deleted a moment ago — writes
  /// nothing. What is on screen stays on screen; it is simply not kept.
  void write(int? id, Config config) {
    final int at = _indexOf(id);
    if (at < 0) return;
    _saves[at] = _saves[at].copyWith(config: config);
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
        for (final SavedConfig save in _saves) save.toJson(),
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
      debugPrint('Roll Hippo: saved configurations unavailable ($error)');
      return null;
    }
  }
}

/// The saves.
final ConfigStore configs = ConfigStore();
