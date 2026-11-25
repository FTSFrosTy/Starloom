import 'dart:async';

import 'package:flutter/widgets.dart';

import 'library.dart';
import 'player_service.dart';
import 'storage.dart';

/// Remembers what you were listening to — the queue, the song, where you
/// were in it, and what it was playing from — and puts it back (paused,
/// at the same spot) the next time the app opens, like Spotify.
class SessionKeeper {
  SessionKeeper(this._storage, this._library, this._player);

  final Storage _storage;
  final Library _library;
  final PlayerService _player;

  Timer? _tick;
  AppLifecycleListener? _life;
  bool _restoring = false;
  bool _ready = false;
  String _lastSaved = '';

  /// Call once the library's cached songs are loaded.
  Future<void> restore() async {
    _restoring = true;
    try {
      final raw = await _storage.read('session.json');
      if (raw is Map && _player.queue.isEmpty) {
        final ids = ((raw['ids'] as List?) ?? const []).map((e) => '$e').toList();
        final songs = [for (final id in ids) ?_library.byId(id)];
        if (songs.isNotEmpty) {
          final wantedId = raw['current'] as String?;
          var index = songs.indexWhere((s) => s.id == wantedId);
          if (index < 0) index = ((raw['index'] as num?)?.toInt() ?? 0).clamp(0, songs.length - 1);
          final pos = Duration(milliseconds: (raw['posMs'] as num?)?.toInt() ?? 0);
          await _player.restoreQueue(
            songs,
            index,
            position: pos,
            from: raw['from'] as String?,
            queuedAhead: (raw['queuedAhead'] as num?)?.toInt() ?? 0,
          );
        }
      }
    } catch (_) {
      // A bad session file just means starting fresh.
    } finally {
      _restoring = false;
      _ready = true;
    }

    _player.currentId.addListener(_save);
    _player.addListener(_onPlayer);
    // While playing, note the spot every few seconds so a crash or a
    // force-quit loses almost nothing.
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_player.playing) _save();
    });
    _life = AppLifecycleListener(
      onPause: _save,
      onHide: _save,
      onInactive: _save,
      onDetach: _save,
      onExitRequested: () async {
        _save();
        await _storage.flush();
        return AppExitResponse.exit;
      },
    );
  }

  bool _wasPlaying = false;

  void _onPlayer() {
    if (_player.playing != _wasPlaying) {
      _wasPlaying = _player.playing;
      _save(); // paused/resumed: remember the exact spot
    }
  }

  void _save() {
    if (!_ready || _restoring) return;
    final q = _player.queue;
    final data = <String, Object?>{
      'ids': [for (final s in q) if (!s.path.startsWith('http')) s.id],
      'current': _player.current?.id,
      'index': _player.index,
      'posMs': _player.position.inMilliseconds,
      'from': _player.playingFrom,
      'queuedAhead': _player.queuedAhead,
    };
    // Skip identical saves (paused, nothing changed).
    final key = '${data['current']}|${data['posMs']! as int ~/ 1000}|${q.length}|${data['from']}';
    if (key == _lastSaved) return;
    _lastSaved = key;
    _storage.write('session.json', data);
  }

  void dispose() {
    _tick?.cancel();
    _life?.dispose();
    _player.currentId.removeListener(_save);
    _player.removeListener(_onPlayer);
  }
}
