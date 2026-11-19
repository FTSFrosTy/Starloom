import 'dart:async';

import 'package:flutter/foundation.dart';

import 'storage.dart';

/// Liked songs, play counts and recently played. Kept by song id.
class UserData extends ChangeNotifier {
  UserData(this._storage);

  final Storage _storage;

  /// Liked song ids, newest first.
  final List<String> liked = [];
  final Set<String> _likedSet = {};

  /// Play counts by song id.
  final Map<String, int> plays = {};

  /// Recently played song ids, newest first (no repeats).
  final List<String> recent = [];

  /// Recently opened albums/playlists/artists for the home screen:
  /// "playlist:<id>", "album:<key>", "artist:<name>", "liked".
  final List<String> recentCollections = [];

  /// Last change, for syncing between devices.
  int likesModifiedMs = 0;

  Timer? _saveTimer;

  Future<void> init() async {
    final raw = await _storage.read('user.json');
    if (raw is Map) {
      liked.addAll(((raw['liked'] as List?) ?? const []).cast<String>());
      _likedSet.addAll(liked);
      final p = raw['plays'];
      if (p is Map) {
        p.forEach((k, v) => plays[k as String] = (v as num).toInt());
      }
      recent.addAll(((raw['recent'] as List?) ?? const []).cast<String>());
      recentCollections.addAll(((raw['recentCollections'] as List?) ?? const []).cast<String>());
      likesModifiedMs = (raw['likesModifiedMs'] as num?)?.toInt() ?? 0;
    }
    notifyListeners();
  }

  bool isLiked(String id) => _likedSet.contains(id);

  void toggleLike(String id) {
    if (_likedSet.remove(id)) {
      liked.remove(id);
    } else {
      _likedSet.add(id);
      liked.insert(0, id);
    }
    likesModifiedMs = DateTime.now().millisecondsSinceEpoch;
    _changed();
  }

  void recordPlay(String id) {
    plays[id] = (plays[id] ?? 0) + 1;
    recent.remove(id);
    recent.insert(0, id);
    if (recent.length > 100) recent.removeRange(100, recent.length);
    _changed();
  }

  void recordCollection(String key) {
    recentCollections.remove(key);
    recentCollections.insert(0, key);
    if (recentCollections.length > 20) recentCollections.removeRange(20, recentCollections.length);
    _changed();
  }

  /// Song ids by play count, most played first.
  List<String> mostPlayed({int limit = 50}) {
    final entries = plays.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(limit)) e.key];
  }

  void _changed() {
    notifyListeners();
    // Batch disk writes: play counts can change every few minutes.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), save);
  }

  Future<void> save() => _storage.write('user.json', {
        'liked': liked,
        'plays': plays,
        'recent': recent,
        'recentCollections': recentCollections,
        'likesModifiedMs': likesModifiedMs,
      });
}
