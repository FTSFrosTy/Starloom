import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:starloom_folders/starloom_folders.dart';

import '../models/models.dart';
import 'storage.dart';

const Set<String> kAudioExtensions = {
  '.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.opus', '.mp4', '.alac', '.aiff', '.aif', '.wma',
};

enum SortMode { title, artist, added }

/// Owns the folders the library reads from and the scanned song list.
class Library extends ChangeNotifier {
  Library(this._storage);

  final Storage _storage;

  final List<LibrarySource> sources = [];
  List<Song> _songs = [];
  Map<String, Song> _byId = {};
  final Map<SortMode, List<Song>> _sorted = {};

  bool scanning = false;
  String? status;

  List<Song> get songs => _songs;
  Song? byId(String id) => _byId[id];

  List<Song> sorted(SortMode mode) {
    return _sorted.putIfAbsent(mode, () {
      final list = List<Song>.of(_songs);
      switch (mode) {
        case SortMode.title:
          list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        case SortMode.artist:
          list.sort((a, b) {
            final c = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
            return c != 0 ? c : a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
        case SortMode.added:
          list.sort((a, b) => b.modifiedMs.compareTo(a.modifiedMs));
      }
      return list;
    });
  }

  Future<void> init() async {
    final rawSources = await _storage.read('sources.json');
    if (rawSources is List) {
      for (final s in rawSources) {
        sources.add(LibrarySource.fromJson((s as Map).cast<String, Object?>()));
      }
    }
    final rawSongs = await _storage.read('library.json');
    if (rawSongs is List) {
      _setSongs(rawSongs.map((e) => Song.fromJson((e as Map).cast<String, Object?>())).toList());
    }

    // On iPhone the app's own folder (Files > On My iPhone > Starloom) is
    // always a source. Its real path changes between installs, so refresh it.
    if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      final existing = sources.where((s) => s.kind == SourceKind.appFolder).firstOrNull;
      if (existing == null) {
        sources.insert(0, LibrarySource(id: 'app', kind: SourceKind.appFolder, label: 'Starloom folder', path: docs.path));
      } else {
        existing.path = docs.path;
      }
      for (final s in sources.where((s) => s.kind == SourceKind.picked && s.bookmark != null)) {
        try {
          final r = await StarloomFolders.restore(s.bookmark!);
          if (r != null) {
            s.path = r.path;
            if (r.refreshedBookmark != null) s.bookmark = r.refreshedBookmark;
            s.error = null;
          }
        } catch (e) {
          s.error = 'Can\'t open this folder anymore. Remove it and pick it again.';
        }
      }
    }
    _relinkPaths();
    await _saveSources();
    notifyListeners();
    // Pick up new/changed files in the background.
    rescan();
  }

  /// Song ids are relative to their folder, so if a folder's absolute path
  /// moved (new install), point every song at the new location.
  void _relinkPaths() {
    final roots = {for (final s in sources) s.id: s.path};
    for (final song in _songs) {
      final sep = song.id.indexOf('::');
      if (sep < 0) continue;
      final root = roots[song.id.substring(0, sep)];
      if (root == null) continue;
      song.path = p.joinAll([root, ...song.id.substring(sep + 2).split('/')]);
    }
  }

  void _setSongs(List<Song> list) {
    _songs = list;
    _byId = {for (final s in list) s.id: s};
    _sorted.clear();
  }

  Future<void> _saveSources() => _storage.write('sources.json', sources.map((s) => s.toJson()).toList());

  /// Ask the user for a folder. Returns an error message, or null on success/cancel.
  Future<String?> addFolder() async {
    try {
      final LibrarySource src;
      final id = _newId();
      if (Platform.isIOS) {
        final picked = await StarloomFolders.pick();
        if (picked == null) return null;
        src = LibrarySource(id: id, kind: SourceKind.picked, label: picked.name, path: picked.path, bookmark: picked.bookmark);
      } else {
        final path = await fs.getDirectoryPath(confirmButtonText: 'Use this folder');
        if (path == null) return null;
        src = LibrarySource(id: id, kind: SourceKind.picked, label: p.basename(path), path: path);
      }
      if (sources.any((s) => s.path == src.path)) return 'That folder is already in your library.';
      sources.add(src);
      await _saveSources();
      notifyListeners();
      await rescan();
      return null;
    } catch (e) {
      return 'Couldn\'t add that folder: $e';
    }
  }

  Future<void> removeSource(String id) async {
    sources.removeWhere((s) => s.id == id);
    _setSongs(_songs.where((s) => !s.id.startsWith('$id::')).toList());
    await _saveSources();
    await _storage.write('library.json', _songs.map((s) => s.toJson()).toList());
    notifyListeners();
  }

  Future<void> rescan() async {
    if (scanning) return;
    scanning = true;
    status = 'Digging through your folders…';
    notifyListeners();
    try {
      final result = <Song>[];
      for (final src in sources) {
        if (src.error != null) {
          // Keep the old songs so playlists don't lose them; they just won't play.
          result.addAll(_songs.where((s) => s.id.startsWith('${src.id}::')));
          continue;
        }
        final cache = <String, Map<String, Object?>>{
          for (final s in _songs.where((s) => s.id.startsWith('${src.id}::'))) s.id: s.toJson(),
        };
        final scanned = await _scanInBackground(src.path, src.id, cache);
        result.addAll(scanned.map(Song.fromJson));
      }
      _setSongs(result);
      await _storage.write('library.json', result.map((s) => s.toJson()).toList());
      status = null;
    } catch (e) {
      status = 'Scan failed: $e';
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  static String _newId() {
    final r = Random();
    return List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join();
  }
}

/// Tag reading is synchronous file IO, so it runs off the UI thread. This is a
/// top-level function so the isolate closure captures only these arguments.
Future<List<Map<String, Object?>>> _scanInBackground(
        String root, String sourceId, Map<String, Map<String, Object?>> cache) =>
    Isolate.run(() => scanFolder(root, sourceId, cache));

/// Runs in a background isolate. Lists [root] recursively and reads tags for
/// new or changed files; unchanged files reuse [cache] (keyed by song id).
List<Map<String, Object?>> scanFolder(String root, String sourceId, Map<String, Map<String, Object?>> cache) {
  final out = <Map<String, Object?>>[];
  final dir = Directory(root);
  if (!dir.existsSync()) return out;

  Iterable<FileSystemEntity> entries;
  try {
    entries = dir.listSync(recursive: true, followLinks: false);
  } catch (_) {
    return out;
  }

  for (final e in entries) {
    if (e is! File) continue;
    final name = p.basename(e.path);
    if (name.startsWith('.')) continue;
    final ext = p.extension(name).toLowerCase();
    if (!kAudioExtensions.contains(ext)) continue;

    final rel = p.split(p.relative(e.path, from: root)).join('/');
    final id = '$sourceId::$rel';
    FileStat st;
    try {
      st = e.statSync();
    } catch (_) {
      continue;
    }
    final mtime = st.modified.millisecondsSinceEpoch;

    final cached = cache[id];
    if (cached != null && cached['size'] == st.size && cached['modifiedMs'] == mtime) {
      out.add({...cached, 'path': e.path});
      continue;
    }

    final stem = p.basenameWithoutExtension(name);
    String title = stem;
    String artist = '';
    String album = '';
    int durationMs = 0;
    bool hasTags = false;
    try {
      final m = readMetadata(e, getImage: false);
      final t = m.title?.trim();
      if (t != null && t.isNotEmpty) {
        title = t;
        hasTags = true;
      }
      artist = m.artist?.trim() ?? '';
      album = m.album?.trim() ?? '';
      durationMs = m.duration?.inMilliseconds ?? 0;
    } catch (_) {
      // Unreadable tags: keep the file name as the title.
    }
    out.add({
      'id': id,
      'path': e.path,
      'title': title,
      'artist': artist,
      'album': album,
      'durationMs': durationMs,
      'size': st.size,
      'modifiedMs': mtime,
      'hasTags': hasTags,
    });
  }
  return out;
}
