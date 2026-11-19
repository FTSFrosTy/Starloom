import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'storage.dart';

class PlaylistStore extends ChangeNotifier {
  PlaylistStore(this._storage);

  final Storage _storage;
  final List<Playlist> playlists = [];

  /// Deleted playlist ids and when, so a sync doesn't bring them back.
  final Map<String, int> deleted = {};

  Future<void> init() async {
    final raw = await _storage.read('playlists.json');
    // Old format: a plain list. New: {playlists: [...], deleted: {...}}.
    final list = raw is List ? raw : (raw is Map ? (raw['playlists'] as List? ?? const []) : const []);
    for (final p in list) {
      playlists.add(Playlist.fromJson((p as Map).cast<String, Object?>()));
    }
    if (raw is Map && raw['deleted'] is Map) {
      (raw['deleted'] as Map).forEach((k, v) => deleted[k as String] = (v as num).toInt());
    }
    notifyListeners();
  }

  Future<void> _save([Playlist? changed]) async {
    changed?.touch();
    notifyListeners();
    await _storage.write('playlists.json', {
      'playlists': playlists.map((p) => p.toJson()).toList(),
      'deleted': deleted,
    });
  }

  /// Replace everything (after a sync merge).
  Future<void> replaceAll(List<Playlist> lists, Map<String, int> tombstones) async {
    playlists
      ..clear()
      ..addAll(lists);
    deleted
      ..clear()
      ..addAll(tombstones);
    await _save();
  }

  /// Turns `key:` placeholders (songs that arrived by sync before their
  /// file did) into real song ids once the file is in the library.
  Future<void> resolvePending(String? Function(String key) idForKey) async {
    var changed = false;
    for (final pl in playlists) {
      for (var i = 0; i < pl.songIds.length; i++) {
        final id = pl.songIds[i];
        if (!id.startsWith('key:')) continue;
        final real = idForKey(id.substring(4));
        if (real != null) {
          pl.songIds[i] = real;
          changed = true;
        }
      }
    }
    if (changed) await _save();
  }

  Playlist? byId(String id) => playlists.where((p) => p.id == id).firstOrNull;

  Future<Playlist> create(String name, {List<String>? songIds, List<MissingEntry>? missing}) async {
    final r = Random();
    final pl = Playlist(
      id: List.generate(10, (_) => r.nextInt(36).toRadixString(36)).join(),
      name: name.trim().isEmpty ? 'Untitled' : name.trim(),
      songIds: songIds ?? [],
      missing: missing,
    );
    playlists.insert(0, pl);
    await _save();
    return pl;
  }

  Future<void> rename(Playlist pl, String name) async {
    pl.name = name.trim().isEmpty ? pl.name : name.trim();
    await _save(pl);
  }

  Future<void> delete(Playlist pl) async {
    playlists.remove(pl);
    deleted[pl.id] = DateTime.now().millisecondsSinceEpoch;
    await _save();
  }

  Future<void> addSong(Playlist pl, String songId) async {
    pl.songIds.add(songId);
    await _save(pl);
  }

  Future<void> addSongs(Playlist pl, Iterable<String> ids) async {
    pl.songIds.addAll(ids);
    await _save(pl);
  }

  Future<void> removeAt(Playlist pl, int i) async {
    pl.songIds.removeAt(i);
    await _save(pl);
  }

  Future<void> move(Playlist pl, int from, int to) async {
    final id = pl.songIds.removeAt(from);
    pl.songIds.insert(to > from ? to - 1 : to, id);
    await _save(pl);
  }
}

// ---------------------------------------------------------------------------
// Spotify link-list import
// ---------------------------------------------------------------------------

class ImportReport {
  ImportReport({required this.matched, required this.missing, required this.streaming, required this.skippedLines});

  /// Matched song ids, in playlist order (duplicates kept).
  final List<String> matched;
  final List<MissingEntry> missing;
  final List<MissingEntry> streaming;
  final int skippedLines;
}

class _LocalEntry {
  _LocalEntry(this.artist, this.album, this.title, this.seconds);
  final String artist, album, title;
  final int seconds;
}

String _decode(String s) {
  try {
    return Uri.decodeQueryComponent(s); // handles %20 and '+' for spaces
  } catch (_) {
    return s;
  }
}

/// Lowercase, underscores to spaces, punctuation dropped, spaces collapsed.
String normalizeTitle(String s) {
  final lower = s.toLowerCase().replaceAll('_', ' ');
  final cleaned = lower.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');
  return cleaned.trim().replaceAll(RegExp(r'\s+'), ' ');
}

_LocalEntry? _parseLocal(String line) {
  const marker = '/local/';
  final i = line.indexOf(marker);
  if (i < 0) return null;
  final parts = line.substring(i + marker.length).split('/');
  if (parts.length < 4) return null;
  // Titles can't contain '/', but be safe: everything between album and the
  // last part is the title.
  final seconds = int.tryParse(parts.last.trim()) ?? 0;
  final title = parts.sublist(2, parts.length - 1).join('/');
  return _LocalEntry(_decode(parts[0]), _decode(parts[1]), _decode(title), seconds);
}

/// Matches each line of a pasted Spotify playlist (Ctrl+A, Ctrl+C in Spotify
/// desktop) to songs in the library by title, artist, album and length.
ImportReport importSpotifyList(String text, List<Song> library) {
  final byTitle = <String, List<Song>>{};
  for (final s in library) {
    byTitle.putIfAbsent(normalizeTitle(s.title), () => []).add(s);
  }

  final matched = <String>[];
  final missing = <MissingEntry>[];
  final streaming = <MissingEntry>[];
  var skipped = 0;

  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.contains('open.spotify.com/track/')) {
      final id = line.split('/track/').last.split('?').first;
      streaming.add(MissingEntry(title: 'Spotify track $id', artist: '', album: '', seconds: 0, streaming: true));
      continue;
    }
    final e = _parseLocal(line);
    if (e == null) {
      skipped++;
      continue;
    }
    final song = _bestMatch(e, byTitle);
    if (song != null) {
      matched.add(song.id);
    } else {
      missing.add(MissingEntry(title: e.title, artist: e.artist, album: e.album, seconds: e.seconds, streaming: false));
    }
  }
  return ImportReport(matched: matched, missing: missing, streaming: streaming, skippedLines: skipped);
}

Song? _bestMatch(_LocalEntry e, Map<String, List<Song>> byTitle) {
  final key = normalizeTitle(e.title);
  if (key.isEmpty) return null;
  final candidates = byTitle[key];
  if (candidates == null || candidates.isEmpty) return null;

  Song? best;
  var bestScore = -1 << 30;
  for (final s in candidates) {
    var score = 0;
    final secs = (s.durationMs / 1000).round();
    final diff = (secs - e.seconds).abs();
    if (e.seconds > 0 && s.durationMs > 0) {
      if (diff <= 2) {
        score += 10;
      } else if (diff > 10) {
        score -= 20; // probably a different version of the song
      }
      score -= diff;
    }
    if (e.artist.isNotEmpty && normalizeTitle(e.artist) == normalizeTitle(s.artist)) score += 5;
    if (e.album.isNotEmpty && normalizeTitle(e.album) == normalizeTitle(s.album)) score += 3;
    if (e.artist.isEmpty && e.album.isEmpty && !s.hasTags) score += 2;
    if (score > bestScore) {
      bestScore = score;
      best = s;
    }
  }
  // Same title but clearly a different length: treat as missing.
  if (bestScore <= -20) return null;
  return best;
}
