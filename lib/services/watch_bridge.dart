import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/models.dart' show Song;
import 'library.dart';
import 'playlists.dart';
import 'storage.dart';
import 'sync.dart';
import 'user_data.dart';

/// iPhone side of the Apple Watch app: picks which playlists live on the
/// watch and copies their songs over, so the watch can play them with no
/// phone around (AirPods + watch on a run).
class WatchBridge extends ChangeNotifier {
  WatchBridge(this._storage, this._library, this._playlists, this._user);

  final Storage _storage;
  final Library _library;
  final PlaylistStore _playlists;
  final UserData _user;

  static const _ch = MethodChannel('starloom/watch');

  bool supported = false;
  bool paired = false;
  bool installed = false;
  bool reachable = false;
  int pending = 0;
  String? lastError;

  /// Playlists the user put on the watch (id -> name). 'liked' = Liked Songs.
  final Map<String, String> onWatch = {};

  /// Song keys already sent (or on their way).
  final Set<String> _sent = {};

  bool get available => Platform.isIOS;

  Future<void> init() async {
    if (!available) return;
    final raw = await _storage.read('watch.json');
    if (raw is Map) {
      for (final e in ((raw['playlists'] as Map?) ?? const {}).entries) {
        onWatch['${e.key}'] = '${e.value}';
      }
      _sent.addAll(((raw['sent'] as List?) ?? const []).map((e) => '$e'));
    }
    _ch.setMethodCallHandler(_onCall);
    await refresh();
    // New songs on the phone (or added to a watch playlist) follow along
    // to the watch automatically.
    _library.addListener(_libraryChanged);
    _playlists.addListener(_libraryChanged);
    _user.addListener(_libraryChanged);
  }

  Timer? _autoTimer;

  void _libraryChanged() {
    if (onWatch.isEmpty) return;
    _autoTimer?.cancel();
    _autoTimer = Timer(const Duration(seconds: 4), () async {
      if (supported && installed) await syncAll();
    });
  }

  Future<void> _save() => _storage.write('watch.json', {'playlists': onWatch, 'sent': _sent.toList()});

  Future<void> refresh() async {
    try {
      final s = await _ch.invokeMapMethod<String, Object?>('status') ?? const {};
      supported = s['supported'] == true;
      paired = s['paired'] == true;
      installed = s['installed'] == true;
      reachable = s['reachable'] == true;
      pending = (s['pending'] as num?)?.toInt() ?? 0;
    } catch (_) {
      supported = false;
    }
    notifyListeners();
  }

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'changed':
        await refresh();
      case 'transferDone':
        final args = (call.arguments as Map?) ?? const {};
        final err = args['error'] as String?;
        if (err != null) {
          _sent.remove(args['key']);
          lastError = err;
          await _save();
        }
        await refresh();
      case 'watchMessage':
        // The watch reports what it actually has (e.g. after it cleaned up).
        final have = (call.arguments as Map?)?['have'];
        if (have is List) {
          _sent
            ..clear()
            ..addAll(have.map((e) => '$e'));
          await _save();
          notifyListeners();
        }
    }
    return null;
  }

  /// Songs of a watch playlist id. 'all' = every song on the phone.
  List<Song> songsOf(String id) {
    if (id == 'all') return _library.songs.where(_sendable).toList();
    final ids = id == 'liked' ? _user.liked : (_playlists.byId(id)?.songIds ?? const <String>[]);
    return [for (final sid in ids) ?_library.byId(sid)];
  }

  bool isOn(String id) => onWatch.containsKey(id);

  /// Size of the songs in [id] that still need copying.
  int bytesToSend(String id) =>
      songsOf(id).where((s) => !_sent.contains(SyncService.keyOf(s)) && _sendable(s)).fold(0, (a, s) => a + s.size);

  static const _formats = {'.mp3', '.m4a', '.aac', '.mp4', '.wav', '.flac', '.aif', '.aiff', '.caf'};

  /// The watch can't play Ogg/Opus/WMA, and streamed songs aren't on disk.
  bool _sendable(Song s) => !s.path.startsWith('http') && _formats.contains(p.extension(s.path).toLowerCase());

  /// Put a playlist on the watch (or copy what's new in it since last time).
  /// Returns how many songs were queued.
  Future<int> put(String id, String name) async {
    onWatch[id] = name;
    lastError = null;
    var queued = 0;
    for (final s in songsOf(id)) {
      final key = SyncService.keyOf(s);
      if (_sent.contains(key) || !_sendable(s)) continue;
      try {
        await _ch.invokeMethod('sendFile', {
          'path': s.path,
          'meta': {
            'key': key,
            'title': s.title,
            'artist': s.artist,
            'album': s.album,
            'durationMs': s.durationMs,
            'ext': p.extension(s.path).toLowerCase().replaceFirst('.', ''),
          },
        });
        _sent.add(key);
        queued++;
      } catch (e) {
        lastError = '${s.title}: $e';
      }
    }
    await _save();
    await pushPlaylists();
    await refresh();
    return queued;
  }

  /// Take a playlist off the watch. Songs no other watch playlist uses get
  /// deleted on the watch to free space.
  Future<void> remove(String id) async {
    onWatch.remove(id);
    final keep = {for (final pid in onWatch.keys) for (final s in songsOf(pid)) SyncService.keyOf(s)};
    _sent.removeWhere((k) => !keep.contains(k));
    await _save();
    await pushPlaylists();
    notifyListeners();
  }

  /// Copy anything new in every watch playlist.
  Future<int> syncAll() async {
    var n = 0;
    for (final e in Map.of(onWatch).entries) {
      n += await put(e.key, e.value);
    }
    return n;
  }

  Future<void> cancelPending() async {
    try {
      await _ch.invokeMethod('cancelAll');
    } catch (_) {}
    await refresh();
  }

  /// Sends the watch its playlist list (names + song keys, in order).
  Future<void> pushPlaylists() async {
    if (!available) return;
    try {
      await _ch.invokeMethod('context', {
        'playlists': [
          for (final e in onWatch.entries)
            {
              'id': e.key,
              'name': switch (e.key) {
                'liked' => 'Liked Songs',
                'all' => 'Everything',
                _ => _playlists.byId(e.key)?.name ?? e.value,
              },
              'keys': [for (final s in songsOf(e.key)) SyncService.keyOf(s)],
            },
        ],
        'sentAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      lastError = '$e';
    }
  }
}
