import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../models/models.dart';
import 'library.dart';
import 'playlists.dart' show normalizeTitle;
import 'storage.dart';

/// Finds cover art for songs that don't have any, using Apple's free iTunes
/// search (no account needed). Works slowly in the background (one lookup
/// every few seconds), remembers misses so it never asks twice, and stores
/// covers next to the ones taken from your files.
class CoverFinder extends ChangeNotifier {
  CoverFinder(this._storage, this._library);

  final Storage _storage;
  final Library _library;

  bool enabled = true;
  bool running = false;
  int found = 0;
  final Set<String> _tried = {};
  Timer? _kick;

  Future<void> init() async {
    final raw = await _storage.read('covers.json');
    if (raw is Map) {
      enabled = (raw['enabled'] as bool?) ?? true;
      _tried.addAll(((raw['tried'] as List?) ?? const []).cast<String>());
    }
    _library.addListener(_onLibrary);
    _onLibrary();
  }

  Future<void> _save() => _storage.write('covers.json', {'enabled': enabled, 'tried': _tried.toList()});

  Future<void> setEnabled(bool v) async {
    enabled = v;
    await _save();
    notifyListeners();
    if (v) _onLibrary();
  }

  void _onLibrary() {
    if (!enabled || running || _library.scanning) return;
    _kick?.cancel();
    _kick = Timer(const Duration(seconds: 4), _run);
  }

  /// One job per album (or per loose song) that has no cover yet.
  List<(String, String, List<Song>)> _jobs() {
    final jobs = <String, (String, String, List<Song>)>{};
    for (final s in _library.songs) {
      if (s.artKey != null || s.path.startsWith('http')) continue;
      final key = s.album.isNotEmpty ? 'a|${s.albumKey}' : 's|${s.artist.toLowerCase()}|${s.title.toLowerCase()}';
      if (_tried.contains(key)) continue;
      final term = s.album.isNotEmpty ? '${s.artist} ${s.album}' : '${s.artist} ${s.title}';
      jobs.putIfAbsent(key, () => (key, term.trim(), <Song>[])).$3.add(s);
    }
    return jobs.values.toList();
  }

  Future<void> _run() async {
    if (running || !enabled) return;
    final jobs = _jobs();
    if (jobs.isEmpty) return;
    running = true;
    notifyListeners();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    var changed = 0;
    try {
      for (final (key, term, songs) in jobs) {
        if (!enabled) break;
        try {
          final art = await _lookup(client, term, songs.first);
          if (art != null) {
            final bytes = await _download(client, art);
            if (bytes != null) {
              final name = 'net-${_hash(key)}';
              final ok = await _writeThumb(bytes, p.join(_library.artDir, '$name.jpg'));
              if (ok) {
                for (final s in songs) {
                  s.artKey = name;
                }
                found += songs.length;
                changed++;
                if (changed % 8 == 0) await _library.saveSongs();
              }
            }
          }
        } catch (_) {
          // Network hiccup or odd reply: just skip this one.
        }
        _tried.add(key);
        if (_tried.length % 10 == 0) await _save();
        // Be polite to the free API (~20 lookups a minute).
        await Future<void>.delayed(const Duration(milliseconds: 3200));
      }
    } finally {
      client.close();
      running = false;
      await _save();
      if (changed > 0) await _library.saveSongs();
      notifyListeners();
    }
  }

  Future<String?> _lookup(HttpClient client, String term, Song sample) async {
    if (term.length < 3) return null;
    final isAlbum = sample.album.isNotEmpty;
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'media': 'music',
      'entity': isAlbum ? 'album' : 'song',
      'limit': '5',
    });
    final req = await client.getUrl(uri);
    final res = await req.close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      return null;
    }
    final body = jsonDecode(await utf8.decoder.bind(res).join()) as Map;
    final results = (body['results'] as List?) ?? const [];
    final wantArtist = normalizeTitle(sample.artist);
    final wantName = normalizeTitle(isAlbum ? sample.album : sample.title);
    Map? best;
    var bestScore = 0;
    for (final r in results.cast<Map>()) {
      final artist = normalizeTitle((r['artistName'] as String?) ?? '');
      final name = normalizeTitle(((isAlbum ? r['collectionName'] : r['trackName']) as String?) ?? '');
      var score = 0;
      if (wantArtist.isNotEmpty && (artist.contains(wantArtist) || wantArtist.contains(artist))) score += 2;
      if (wantName.isNotEmpty && (name.contains(wantName) || wantName.contains(name))) score += 2;
      if (score > bestScore) {
        bestScore = score;
        best = r;
      }
    }
    // Need the name to match, and the artist too when we know it.
    if (best == null || bestScore < (wantArtist.isEmpty ? 2 : 4)) return null;
    final url = best['artworkUrl100'] as String?;
    return url?.replaceAll('100x100bb', '400x400bb');
  }

  Future<Uint8List?> _download(HttpClient client, String url) async {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      return null;
    }
    final b = BytesBuilder(copy: false);
    await for (final chunk in res) {
      b.add(chunk);
    }
    return b.takeBytes();
  }

  static Future<bool> _writeThumb(Uint8List bytes, String path) => Isolate.run(() {
        try {
          final d = img.decodeImage(bytes);
          if (d == null) return false;
          final small = img.copyResize(d, width: 300, interpolation: img.Interpolation.average);
          File(path).writeAsBytesSync(img.encodeJpg(small, quality: 85));
          return true;
        } catch (_) {
          return false;
        }
      });

  static String _hash(String s) {
    var h = 0xcbf29ce484222325;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return h.toUnsigned(64).toRadixString(16);
  }
}
