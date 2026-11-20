import 'package:flutter/widgets.dart';

import '../theme/palette.dart';
import '../widgets/clay.dart';
import 'eq.dart';
import 'library.dart';
import 'player_service.dart';
import 'playlists.dart';
import 'storage.dart';
import 'cover_finder.dart';
import 'connect.dart';
import 'sync.dart';
import 'user_data.dart';

/// Small app-wide preferences.
class AppPrefs extends ChangeNotifier {
  AppPrefs(this._storage);

  final Storage _storage;
  bool reduceMotion = false;
  SortMode sort = SortMode.title;
  String themeId = kThemes.first.id;
  double volume = 100;
  bool haptics = true;

  StarTheme get theme => kThemes.firstWhere((t) => t.id == themeId, orElse: () => kThemes.first);

  Future<void> init() async {
    final raw = await _storage.read('prefs.json');
    if (raw is Map) {
      reduceMotion = (raw['reduceMotion'] as bool?) ?? false;
      sort = SortMode.values.firstWhere((s) => s.name == raw['sort'], orElse: () => SortMode.title);
      themeId = (raw['theme'] as String?) ?? themeId;
      volume = (raw['volume'] as num?)?.toDouble() ?? 100;
      haptics = (raw['haptics'] as bool?) ?? true;
    }
    StopMotion.instance.enabled = !reduceMotion;
    Clay.current = theme;
  }

  Future<void> _save() {
    notifyListeners();
    return _storage.write('prefs.json', {
      'reduceMotion': reduceMotion,
      'sort': sort.name,
      'theme': themeId,
      'volume': volume,
      'haptics': haptics,
    });
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

  Future<void> setTheme(String id) {
    themeId = id;
    Clay.current = theme;
    return _save();
  }

  Future<void> setHaptics(bool v) {
    haptics = v;
    return _save();
  }

  /// Saved quietly (no rebuild) so dragging the volume stays smooth.
  void rememberVolume(double v) {
    volume = v;
    _storage.write('prefs.json', {
      'reduceMotion': reduceMotion,
      'sort': sort.name,
      'theme': themeId,
      'volume': volume,
      'haptics': haptics,
    });
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
    required this.user,
    required this.sync,
    required this.connect,
    required this.covers,
    required super.child,
  });

  final Library library;
  final PlaylistStore playlists;
  final PlayerService player;
  final EqController eq;
  final AppPrefs prefs;
  final UserData user;
  final SyncService sync;
  final ConnectService connect;
  final CoverFinder covers;

  static AppScope of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
