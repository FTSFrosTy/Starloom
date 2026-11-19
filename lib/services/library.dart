import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:audio_metadata_reader/audio_metadata_reader.dart' show readMetadata;
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
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

  /// Folder holding the small cover thumbnails made during scans.
  late final String artDir;

  List<Song> get songs => _songs;
  Song? byId(String id) => _byId[id];

  /// Bumps on every library change, so screens can cache derived lists.
  int version = 0;

  String? artPath(String? key) => key == null ? null : p.join(artDir, '$key.jpg');

  List<Album>? _albums;
  List<Artist>? _artists;

  List<Album> get albums => _albums ??= _buildAlbums();
  List<Artist> get artists => _artists ??= _buildArtists();

  List<Album> _buildAlbums() {
    final map = <String, List<Song>>{};
    for (final s in _songs) {
      if (s.albumKey.isEmpty) continue;
      map.putIfAbsent(s.albumKey, () => []).add(s);
    }
    final list = [
      for (final e in map.entries)
        Album(e.key, e.value.first.album, e.value.first.artist, e.value..sort(_byTrack)),
    ];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  static int _byTrack(Song a, Song b) {
    final c = a.trackNo.compareTo(b.trackNo);
    return c != 0 ? c : a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  List<Artist> _buildArtists() {
    final map = <String, List<Song>>{};
    for (final s in _songs) {
      if (s.artist.isEmpty) continue;
      map.putIfAbsent(s.artist.toLowerCase(), () => []).add(s);
    }
    final albumsByArtist = <String, List<Album>>{};
    for (final a in albums) {
      albumsByArtist.putIfAbsent(a.artist.toLowerCase(), () => []).add(a);
    }
    final list = [
      for (final e in map.entries)
        Artist(
          e.value.first.artist,
          e.value..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())),
          albumsByArtist[e.key] ?? const [],
        ),
    ];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Album? albumByKey(String key) => albums.where((a) => a.key == key).firstOrNull;
  Artist? artistByName(String name) => artists.where((a) => a.name.toLowerCase() == name.toLowerCase()).firstOrNull;

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
    final support = await getApplicationSupportDirectory();
    artDir = p.join(support.path, 'starloom', 'art');
    Directory(artDir).createSync(recursive: true);
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
    _albums = null;
    _artists = null;
    version++;
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
        status = 'Reading ${src.label}… (first scan also grabs cover art)';
        notifyListeners();
        final scanned = await _scanInBackground(src.path, src.id, cache, artDir);
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
        String root, String sourceId, Map<String, Map<String, Object?>> cache, String artDir) =>
    Isolate.run(() => scanFolder(root, sourceId, cache, artDir));

/// Runs in a background isolate. Lists [root] recursively and reads tags for
/// new or changed files; unchanged files reuse [cache] (keyed by song id).
List<Map<String, Object?>> scanFolder(String root, String sourceId, Map<String, Map<String, Object?>> cache, String artDir) {
  final out = <Map<String, Object?>>[];
  final artTried = <String, bool>{}; // art key -> thumbnail exists
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
    if (cached != null && cached['size'] == st.size && cached['modifiedMs'] == mtime && cached['v'] == kSongSchema) {
      out.add({...cached, 'path': e.path});
      continue;
    }

    final stem = p.basenameWithoutExtension(name);
    String title = stem;
    String artist = '';
    String album = '';
    int durationMs = 0;
    int trackNo = 0;
    String? artKey;
    bool hasTags = false;
    try {
      final m = readMetadata(e, getImage: true);
      final t = m.title?.trim();
      if (t != null && t.isNotEmpty) {
        title = t;
        hasTags = true;
      }
      artist = m.artist?.trim() ?? '';
      album = m.album?.trim() ?? '';
      durationMs = m.duration?.inMilliseconds ?? 0;
      trackNo = m.trackNumber ?? 0;
      if (m.pictures.isNotEmpty) {
        // One thumbnail per album (or per song when there's no album tag).
        final key = _fnv(album.isNotEmpty ? 'a|${album.toLowerCase()}|${artist.toLowerCase()}' : 's|$id');
        final ok = artTried[key] ??= _writeThumb(m.pictures.first.bytes, p.join(artDir, '$key.jpg'));
        if (ok) artKey = key;
      }
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
      'trackNo': trackNo,
      'artKey': artKey,
      'v': kSongSchema,
    });
  }
  return out;
}

/// Shrinks embedded cover art to a 200 px JPEG. Returns false if it can't.
bool _writeThumb(Uint8List bytes, String path) {
  final f = File(path);
  if (f.existsSync()) return true;
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return false;
    final small = decoded.width > decoded.height
        ? img.copyResize(decoded, height: 200, interpolation: img.Interpolation.average)
        : img.copyResize(decoded, width: 200, interpolation: img.Interpolation.average);
    f.writeAsBytesSync(img.encodeJpg(small, quality: 82));
    return true;
  } catch (_) {
    return false;
  }
}

/// Stable 64-bit FNV-1a hash as hex (String.hashCode isn't stable across runs).
String _fnv(String s) {
  var h = 0xcbf29ce484222325;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toUnsigned(64).toRadixString(16);
}
