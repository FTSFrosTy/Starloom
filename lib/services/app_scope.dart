import 'package:flutter/widgets.dart';

import '../widgets/clay.dart';
import 'eq.dart';
import 'library.dart';
import 'player_service.dart';
import 'playlists.dart';
import 'storage.dart';

/// Small app-wide preferences.
class AppPrefs extends ChangeNotifier {
  AppPrefs(this._storage);

  final Storage _storage;
  bool reduceMotion = false;
  SortMode sort = SortMode.title;

  Future<void> init() async {
    final raw = await _storage.read('prefs.json');
    if (raw is Map) {
      reduceMotion = (raw['reduceMotion'] as bool?) ?? false;
      sort = SortMode.values.firstWhere((s) => s.name == raw['sort'], orElse: () => SortMode.title);
    }
    StopMotion.instance.enabled = !reduceMotion;
  }

  Future<void> _save() {
    notifyListeners();
    return _storage.write('prefs.json', {'reduceMotion': reduceMotion, 'sort': sort.name});
  }

  Future<void> setReduceMotion(bool v) {
    reduceMotion = v;
    StopMotion.instance.enabled = !v;
    return _save();
  }

  Future<void> setSort(SortMode v) {
    sort = v;
    return _save();
  }
}

/// Hands the app's services to every screen. The services notify on their
/// own; screens listen only to the ones they draw.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.library,
    required this.playlists,
    required this.player,
    required this.eq,
    required this.prefs,
    required super.child,
  });

  final Library library;
  final PlaylistStore playlists;
  final PlayerService player;
  final EqController eq;
  final AppPrefs prefs;

  static AppScope of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
