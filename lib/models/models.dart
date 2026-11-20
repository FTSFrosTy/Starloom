/// Plain data types. Everything here round-trips through JSON.
library;

/// Bump when the scan reads new fields, so old cache entries get re-read.
const int kSongSchema = 3;

class Song {
  Song({
    required this.id,
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.size,
    required this.modifiedMs,
    required this.hasTags,
    this.trackNo = 0,
    this.artKey,
    String? stem,
  })  : stem = stem ?? title,
        searchKey = '$title $artist $album ${stem ?? ''}'.toLowerCase();

  /// Stable id: `sourceId::path/relative/to/the/source/folder`.
  /// Survives the app's container path changing between installs.
  final String id;
  String path;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final int size;
  final int modifiedMs;

  /// False when the file had no title tag (title is the file name).
  final bool hasTags;
  final String searchKey;

  /// Track number inside its album (0 if unknown).
  final int trackNo;

  /// Name of the cached cover thumbnail (in the art folder): from the
  /// file's own artwork, or looked up online.
  String? artKey;

  /// File name without extension (what Spotify calls untagged songs).
  final String stem;

  /// Groups songs into albums: same album name + artist.
  String get albumKey => album.isEmpty ? '' : '${album.toLowerCase()}|${artist.toLowerCase()}';

  String get subtitle {
    if (artist.isEmpty && album.isEmpty) return 'Unknown artist';
    if (album.isEmpty) return artist;
    if (artist.isEmpty) return album;
    return '$artist  ·  $album';
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'path': path,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
        'size': size,
        'modifiedMs': modifiedMs,
        'hasTags': hasTags,
        'trackNo': trackNo,
        'artKey': artKey,
        'stem': stem,
        'v': kSongSchema,
      };

  static Song fromJson(Map<String, Object?> j) => Song(
        id: j['id']! as String,
        path: j['path']! as String,
        title: j['title']! as String,
        artist: (j['artist'] as String?) ?? '',
        album: (j['album'] as String?) ?? '',
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        size: (j['size'] as num?)?.toInt() ?? 0,
        modifiedMs: (j['modifiedMs'] as num?)?.toInt() ?? 0,
        hasTags: (j['hasTags'] as bool?) ?? false,
        trackNo: (j['trackNo'] as num?)?.toInt() ?? 0,
        artKey: j['artKey'] as String?,
        stem: j['stem'] as String?,
      );
}

enum SourceKind { appFolder, picked }

/// A folder the library reads from.
class LibrarySource {
  LibrarySource({
    required this.id,
    required this.kind,
    required this.label,
    required this.path,
    this.bookmark,
  });

  final String id;
  final SourceKind kind;
  String label;

  /// Current absolute path. For picked iOS folders this is refreshed from
  /// the bookmark on every launch.
  String path;

  /// iOS bookmark (base64) for picked folders.
  String? bookmark;

  /// Set at runtime when the folder can't be opened.
  String? error;

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'label': label,
        'path': path,
        'bookmark': bookmark,
      };

  static LibrarySource fromJson(Map<String, Object?> j) => LibrarySource(
        id: j['id']! as String,
        kind: SourceKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => SourceKind.picked),
        label: j['label']! as String,
        path: j['path']! as String,
        bookmark: j['bookmark'] as String?,
      );
}

/// An entry from an imported Spotify list that has no file.
class MissingEntry {
  const MissingEntry({required this.title, required this.artist, required this.album, required this.seconds, required this.streaming});

  final String title;
  final String artist;
  final String album;
  final int seconds;

  /// True for open.spotify.com/track links (streaming songs, not files).
  final bool streaming;

  String get label {
    if (streaming) return title;
    final who = [artist, album].where((s) => s.isNotEmpty).join(' · ');
    final t = title.isEmpty ? '(no title)' : title;
    return who.isEmpty ? t : '$t — $who';
  }

  Map<String, Object?> toJson() => {'title': title, 'artist': artist, 'album': album, 'seconds': seconds, 'streaming': streaming};

  static MissingEntry fromJson(Map<String, Object?> j) => MissingEntry(
        title: (j['title'] as String?) ?? '',
        artist: (j['artist'] as String?) ?? '',
        album: (j['album'] as String?) ?? '',
        seconds: (j['seconds'] as num?)?.toInt() ?? 0,
        streaming: (j['streaming'] as bool?) ?? false,
      );
}

class Playlist {
  Playlist({
    required this.id,
    required this.name,
    required this.songIds,
    List<MissingEntry>? missing,
    int? createdMs,
    int? modifiedMs,
    this.pinned = false,
  })  : missing = missing ?? [],
        createdMs = createdMs ?? DateTime.now().millisecondsSinceEpoch,
        modifiedMs = modifiedMs ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  String name;
  final List<String> songIds;
  final List<MissingEntry> missing;
  final int createdMs;

  /// Last change, for syncing between devices.
  int modifiedMs;

  /// Pinned to the top of Your Library.
  bool pinned;

  void touch() => modifiedMs = DateTime.now().millisecondsSinceEpoch;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'songIds': songIds,
        'missing': missing.map((m) => m.toJson()).toList(),
        'createdMs': createdMs,
        'modifiedMs': modifiedMs,
        'pinned': pinned,
      };

  static Playlist fromJson(Map<String, Object?> j) => Playlist(
        id: j['id']! as String,
        name: j['name']! as String,
        songIds: ((j['songIds'] as List?) ?? const []).cast<String>().toList(),
        missing: ((j['missing'] as List?) ?? const [])
            .map((e) => MissingEntry.fromJson((e as Map).cast<String, Object?>()))
            .toList(),
        createdMs: (j['createdMs'] as num?)?.toInt(),
        modifiedMs: (j['modifiedMs'] as num?)?.toInt(),
        pinned: (j['pinned'] as bool?) ?? false,
      );
}

String formatDuration(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// An album, built from the songs that share an album name and artist.
class Album {
  Album(this.key, this.name, this.artist, this.songs);

  final String key;
  final String name;
  final String artist;
  final List<Song> songs;

  String? get artKey => songs.map((s) => s.artKey).whereType<String>().firstOrNull;
}

/// An artist with their songs and albums.
class Artist {
  Artist(this.name, this.songs, this.albums);

  final String name;
  final List<Song> songs;
  final List<Album> albums;

  String? get artKey => albums.map((a) => a.artKey).whereType<String>().firstOrNull ?? songs.map((s) => s.artKey).whereType<String>().firstOrNull;
}
