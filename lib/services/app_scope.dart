import 'package:flutter/widgets.dart';

import '../theme/palette.dart';
import '../widgets/clay.dart';
import '../widgets/panels.dart';
import 'eq.dart';
import 'library.dart';
import 'player_service.dart';
import 'playlists.dart';
import 'storage.dart';
import 'cover_finder.dart';
import 'connect.dart';
import 'sync.dart';
import 'watch_bridge.dart';
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

  /// PC: keep the animations going when another window is in front.
  bool animateUnfocused = false;

  /// Shuffle and repeat buttons, remembered between launches.
  bool shuffle = false;
  String loop = 'off';

  /// PC side panels (Your Library collapsed, right panel open + tab).
  Map<String, Object?> panels = const {};

  StarTheme get theme => kThemes.firstWhere((t) => t.id == themeId, orElse: () => kThemes.first);

  Future<void> init() async {
    final raw = await _storage.read('prefs.json');
    if (raw is Map) {
      reduceMotion = (raw['reduceMotion'] as bool?) ?? false;
      sort = SortMode.values.firstWhere((s) => s.name == raw['sort'], orElse: () => SortMode.title);
      themeId = (raw['theme'] as String?) ?? themeId;
      volume = (raw['volume'] as num?)?.toDouble() ?? 100;
      haptics = (raw['haptics'] as bool?) ?? true;
      animateUnfocused = (raw['animateUnfocused'] as bool?) ?? false;
      shuffle = (raw['shuffle'] as bool?) ?? false;
      loop = (raw['loop'] as String?) ?? 'off';
      panels = ((raw['panels'] as Map?) ?? const {}).cast<String, Object?>();
    }
    StopMotion.instance.enabled = !reduceMotion;
    StopMotion.instance.keepWhenUnfocused = animateUnfocused;
    Clay.current = theme;
  }

  Map<String, Object?> _json() => {
        'reduceMotion': reduceMotion,
        'sort': sort.name,
        'theme': themeId,
        'volume': volume,
        'haptics': haptics,
        'animateUnfocused': animateUnfocused,
        'shuffle': shuffle,
        'loop': loop,
        'panels': panels,
      };

  /// Restores the PC panels and keeps them saved as they change.
  void attachPanels() {
    Panels.leftCollapsed.value = panels['leftCollapsed'] == true;
    Panels.rightOpen.value = panels['rightOpen'] != false;
    Panels.rightTab.value = RightTab.values.where((t) => t.name == panels['rightTab']).firstOrNull ?? RightTab.nowPlaying;
    void save() {
      panels = {
        'leftCollapsed': Panels.leftCollapsed.value,
        'rightOpen': Panels.rightOpen.value,
        'rightTab': Panels.rightTab.value.name,
      };
      _storage.write('prefs.json', _json());
    }

    Panels.leftCollapsed.addListener(save);
    Panels.rightOpen.addListener(save);
    Panels.rightTab.addListener(save);
  }

  /// Saved quietly (no rebuild).
  void rememberModes(bool shuffle, String loop) {
    this.shuffle = shuffle;
    this.loop = loop;
    _storage.write('prefs.json', _json());
  }

  Future<void> _save() {
    notifyListeners();
    return _storage.write('prefs.json', _json());
  }

  Future<void> setAnimateUnfocused(bool v) {
    animateUnfocused = v;
    StopMotion.instance.keepWhenUnfocused = v;
    return _save();
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
    _storage.write('prefs.json', _json());
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
    required this.watch,
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
  final WatchBridge watch;
  final CoverFinder covers;

  static AppScope of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
