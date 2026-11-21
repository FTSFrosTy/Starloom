import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  /// Re-importing a playlist: swap in the new song list, keep id and pin.
  Future<void> replaceSongs(Playlist pl, List<String> songIds, List<MissingEntry> missing) async {
    pl.songIds
      ..clear()
      ..addAll(songIds);
    pl.missing
      ..clear()
      ..addAll(missing);
    await _save(pl);
  }

  Playlist? byName(String name) {
    final n = name.trim().toLowerCase();
    return playlists.where((p) => p.name.trim().toLowerCase() == n).firstOrNull;
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

  Future<void> togglePin(Playlist pl) async {
    pl.pinned = !pl.pinned;
    await _save(pl);
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
ImportReport importSpotifyList(String text, List<Song> library, {Map<String, String> trackTitles = const {}}) {
  final byTitle = <String, List<Song>>{};
  for (final s in library) {
    byTitle.putIfAbsent(normalizeTitle(s.title), () => []).add(s);
    // Untagged files: Spotify uses the raw file name as the title.
    final st = normalizeTitle(s.stem);
    if (st != normalizeTitle(s.title)) byTitle.putIfAbsent(st, () => []).add(s);
  }

  final matched = <String>[];
  final missing = <MissingEntry>[];
  final streaming = <MissingEntry>[];
  var skipped = 0;

  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.contains('open.spotify.com/track/')) {
      final id = line.split('/track/').last.split('?').first.trim();
      final title = trackTitles[id];
      final song = title == null ? null : _bestMatch(_LocalEntry('', '', title, 0), byTitle);
      if (song != null) {
        matched.add(song.id);
      } else {
        streaming.add(MissingEntry(title: title ?? 'Spotify track $id', artist: '', album: '', seconds: 0, streaming: true));
      }
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
    if (normalizeTitle(s.stem) == key && !s.hasTags) score += 2;
    if (score > bestScore) {
      bestScore = score;
      best = s;
    }
  }
  // Same title but clearly a different length: treat as missing.
  if (bestScore <= -20) return null;
  return best;
}

/// Spotify track ids in a pasted list.
List<String> spotifyTrackIds(String text) =>
    RegExp(r'open\.spotify\.com/track/([A-Za-z0-9]+)').allMatches(text).map((m) => m.group(1)!).toSet().toList();

/// Looks up the titles of Spotify tracks (public oEmbed, no login), so
/// pasted Spotify songs can be matched to files you have.
Future<Map<String, String>> fetchSpotifyTitles(List<String> ids, {void Function(int done)? progress}) async {
  final out = <String, String>{};
  if (ids.isEmpty) return out;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  var next = 0, done = 0;
  Future<void> worker() async {
    while (next < ids.length) {
      final id = ids[next++];
      try {
        final uri = Uri.https('open.spotify.com', '/oembed', {'url': 'https://open.spotify.com/track/$id'});
        final res = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final j = jsonDecode(await utf8.decoder.bind(res).join());
          final t = j is Map ? j['title'] : null;
          if (t is String && t.isNotEmpty) out[id] = t;
        } else {
          await res.drain<void>();
        }
      } catch (_) {}
      progress?.call(++done);
    }
  }

  await Future.wait(List.generate(6, (_) => worker()));
  client.close(force: true);
  return out;
}

/// A Spotify playlist read from its public web page (the embed player).
class SpotifyPlaylistPage {
  SpotifyPlaylistPage(this.name, this.lines);
  final String name;

  /// One line per song in the same `open.spotify.com/local/artist/album/title/seconds`
  /// shape the desktop copy uses, so the normal matcher handles it.
  final List<String> lines;
}

/// Reads a public Spotify playlist straight from a link, no login.
/// Spotify only shows its own catalog songs this way: local files in the
/// playlist aren't visible, so those still need the desktop copy-paste.
Future<SpotifyPlaylistPage> fetchSpotifyPlaylist(String link) async {
  final id = RegExp(r'playlist[/:]([A-Za-z0-9]+)').firstMatch(link)?.group(1);
  if (id == null) throw 'That doesn\'t look like a Spotify playlist link';
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.https('open.spotify.com', '/embed/playlist/$id'));
    req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1');
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw 'Spotify answered ${res.statusCode}. Is the playlist public?';
    final html = await utf8.decoder.bind(res).join();
    final m = RegExp(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', dotAll: true).firstMatch(html);
    if (m == null) throw 'Spotify changed its page; use the desktop copy-paste instead';
    final data = jsonDecode(m.group(1)!);
    final entity = _dig(data, ['props', 'pageProps', 'state', 'data', 'entity']);
    if (entity is! Map) throw 'Couldn\'t read that playlist';
    final name = (entity['name'] ?? entity['title'] ?? 'Spotify playlist').toString();
    final lines = <String>[];
    for (final t in (entity['trackList'] as List?) ?? const []) {
      if (t is! Map) continue;
      final title = (t['title'] ?? '').toString();
      if (title.isEmpty) continue;
      final artist = (t['subtitle'] ?? '').toString().split(',').first.trim();
      final secs = ((t['duration'] as num?) ?? 0) ~/ 1000;
      String enc(String s) => Uri.encodeComponent(s);
      lines.add('https://open.spotify.com/local/${enc(artist)}//${enc(title)}/$secs');
    }
    return SpotifyPlaylistPage(name, lines);
  } finally {
    client.close(force: true);
  }
}

Object? _dig(Object? o, List<String> path) {
  for (final k in path) {
    if (o is Map && o.containsKey(k)) {
      o = o[k];
    } else {
      return null;
    }
  }
  return o;
}
