import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'library.dart';
import 'player_service.dart';
import 'playlists.dart';
import 'storage.dart';
import 'user_data.dart';

const int kSyncPort = 47811;

/// A song on the other device, as the sync protocol describes it.
class RemoteSong {
  RemoteSong(this.key, this.title, this.artist, this.album, this.durationMs, this.size, this.fileName);

  /// Same file on both devices = same key (file name + size).
  final String key;
  final String title, artist, album, fileName;
  final int durationMs, size;

  Map<String, Object?> toJson() =>
      {'key': key, 'title': title, 'artist': artist, 'album': album, 'durationMs': durationMs, 'size': size, 'fileName': fileName};

  static RemoteSong fromJson(Map<String, Object?> j) => RemoteSong(
        j['key']! as String,
        (j['title'] as String?) ?? '',
        (j['artist'] as String?) ?? '',
        (j['album'] as String?) ?? '',
        (j['durationMs'] as num?)?.toInt() ?? 0,
        (j['size'] as num?)?.toInt() ?? 0,
        (j['fileName'] as String?) ?? 'song',
      );
}

/// Starloom-to-Starloom sync over home Wi-Fi.
///
/// The PC runs a tiny HTTP service (only while "Let my phone sync" is on,
/// and only answering requests that carry the pairing code). The phone
/// connects to it to merge playlists and likes, copy songs either way, and
/// stream the PC's library.
class SyncService extends ChangeNotifier {
  SyncService(this._storage, this._library, this._playlists, this._user, this._player);

  final Storage _storage;
  final Library _library;
  final PlaylistStore _playlists;
  final UserData _user;
  final PlayerService _player;

  // ---- settings ----
  bool hostEnabled = false; // PC side
  String code = '';
  String? pcAddress; // phone side
  String? pcCode;
  int? lastSyncMs;

  // ---- runtime ----
  HttpServer? _server;
  List<String> myAddresses = [];
  bool busy = false;
  String? status;
  double? progress;
  List<RemoteSong>? pcLibrary;

  bool get isHostPlatform => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  bool get paired => pcAddress != null && pcCode != null;

  Future<void> init() async {
    final raw = await _storage.read('sync.json');
    if (raw is Map) {
      hostEnabled = (raw['hostEnabled'] as bool?) ?? false;
      code = (raw['code'] as String?) ?? '';
      pcAddress = raw['pcAddress'] as String?;
      pcCode = raw['pcCode'] as String?;
      lastSyncMs = (raw['lastSyncMs'] as num?)?.toInt();
    }
    if (code.isEmpty) code = _newCode();
    await _save();
    if (isHostPlatform && hostEnabled) await startHost();
    // Once songs arrive and get scanned, fill in synced playlist entries.
    _library.addListener(_resolve);
  }

  void _resolve() {
    if (_library.scanning) return;
    final byKey = {for (final s in _library.songs) keyOf(s): s.id};
    _playlists.resolvePending((k) => byKey[k]);
    final liked = List<String>.of(_user.liked);
    var changed = false;
    for (var i = 0; i < liked.length; i++) {
      if (liked[i].startsWith('key:')) {
        final real = byKey[liked[i].substring(4)];
        if (real != null) {
          liked[i] = real;
          changed = true;
        }
      }
    }
    if (changed) _user.replaceLikes(liked, _user.likesModifiedMs);
  }

  Future<void> _save() => _storage.write('sync.json', {
        'hostEnabled': hostEnabled,
        'code': code,
        'pcAddress': pcAddress,
        'pcCode': pcCode,
        'lastSyncMs': lastSyncMs,
      });

  static String _newCode() {
    final r = Random.secure();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }

  static String keyOf(Song s) => '${p.basename(s.path).toLowerCase()}|${s.size}';

  // =====================================================================
  // Shared state (playlists + likes) in a device-independent form
  // =====================================================================

  Map<String, Object?> _localState() {
    final keyById = {for (final s in _library.songs) s.id: keyOf(s)};
    String toKey(String id) => id.startsWith('key:') ? id : (keyById[id] != null ? 'key:${keyById[id]}' : id);
    return {
      'playlists': [
        for (final pl in _playlists.playlists)
          {...pl.toJson(), 'songIds': [for (final id in pl.songIds) toKey(id)]},
      ],
      'deleted': _playlists.deleted,
      'liked': [for (final id in _user.liked) toKey(id)],
      'likesModifiedMs': _user.likesModifiedMs,
    };
  }

  /// Merge [remote] into this device: newer playlist wins, deletions stick,
  /// newer likes list wins. Song keys become local ids where we have the file.
  Future<void> _applyMerged(Map<String, Object?> remote) async {
    final local = _localState();
    final byKey = {for (final s in _library.songs) keyOf(s): s.id};
    String toLocal(String id) {
      if (!id.startsWith('key:')) return id;
      return byKey[id.substring(4)] ?? id;
    }

    final deleted = <String, int>{
      ...(local['deleted'] as Map).cast<String, int>(),
    };
    (remote['deleted'] as Map? ?? const {}).forEach((k, v) {
      final t = (v as num).toInt();
      if ((deleted[k as String] ?? 0) < t) deleted[k] = t;
    });

    final merged = <String, Map<String, Object?>>{};
    for (final src in [local['playlists'] as List, (remote['playlists'] as List?) ?? const []]) {
      for (final e in src) {
        final j = (e as Map).cast<String, Object?>();
        final id = j['id']! as String;
        final mod = (j['modifiedMs'] as num?)?.toInt() ?? 0;
        final cur = merged[id];
        if (cur == null || ((cur['modifiedMs'] as num?)?.toInt() ?? 0) < mod) merged[id] = j;
      }
    }
    final lists = <Playlist>[];
    for (final j in merged.values) {
      final id = j['id']! as String;
      final mod = (j['modifiedMs'] as num?)?.toInt() ?? 0;
      if ((deleted[id] ?? -1) >= mod) continue; // deleted after its last edit
      final pl = Playlist.fromJson(j);
      for (var i = 0; i < pl.songIds.length; i++) {
        pl.songIds[i] = toLocal(pl.songIds[i]);
      }
      lists.add(pl);
    }
    lists.sort((a, b) => b.createdMs.compareTo(a.createdMs));
    await _playlists.replaceAll(lists, deleted);

    final rLikesMs = (remote['likesModifiedMs'] as num?)?.toInt() ?? 0;
    if (rLikesMs > _user.likesModifiedMs) {
      final liked = [for (final id in ((remote['liked'] as List?) ?? const []).cast<String>()) toLocal(id)];
      _user.replaceLikes(liked, rLikesMs);
    }
  }

  List<RemoteSong> _myLibrary() => [
        for (final s in _library.songs)
          if (!s.path.startsWith('http'))
            RemoteSong(keyOf(s), s.title, s.artist, s.album, s.durationMs, s.size, p.basename(s.path)),
      ];

  // =====================================================================
  // PC side: the service
  // =====================================================================

  Future<void> setHostEnabled(bool v) async {
    hostEnabled = v;
    await _save();
    v ? await startHost() : await stopHost();
  }

  Future<void> newCode() async {
    code = _newCode();
    await _save();
    notifyListeners();
  }

  Future<void> startHost() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, kSyncPort, shared: true);
      _server!.listen(_handle, onError: (_) {});
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      myAddresses = [
        for (final i in ifs)
          for (final a in i.addresses)
            if (!a.isLoopback && !a.address.startsWith('169.254')) a.address,
      ];
      status = null;
    } catch (e) {
      status = 'Couldn\'t start sync: $e';
    }
    notifyListeners();
  }

  Future<void> stopHost() async {
    await _server?.close(force: true);
    _server = null;
    notifyListeners();
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final given = req.headers.value('x-starloom-code') ?? req.uri.queryParameters['code'];
      if (given != code) {
        res.statusCode = HttpStatus.unauthorized;
        await res.close();
        return;
      }
      switch ((req.method, req.uri.path)) {
        case ('GET', '/hello'):
          await _json(res, {'app': 'starloom', 'name': Platform.localHostname, 'songs': _library.songs.length});
        case ('GET', '/library'):
          await _json(res, [for (final s in _myLibrary()) s.toJson()]);
        case ('GET', '/state'):
          await _json(res, _localState());
        case ('POST', '/state'):
          final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, Object?>;
          await _applyMerged(body);
          await _json(res, _localState());
        case ('GET', '/file'):
          await _sendFile(req, res, req.uri.queryParameters['key'] ?? '');
        case ('PUT', '/file'):
          await _receiveFile(req, res);
        default:
          res.statusCode = HttpStatus.notFound;
          await res.close();
      }
    } catch (e) {
      try {
        res.statusCode = HttpStatus.internalServerError;
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> _json(HttpResponse res, Object? data) async {
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(data));
    await res.close();
  }

  /// Serves a song file, with byte ranges so streaming can seek.
  Future<void> _sendFile(HttpRequest req, HttpResponse res, String key) async {
    final song = _library.songs.where((s) => keyOf(s) == key).firstOrNull;
    final file = song == null ? null : File(song.path);
    if (file == null || !await file.exists()) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final len = await file.length();
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    res.headers.contentType = ContentType.binary;
    final range = req.headers.value(HttpHeaders.rangeHeader);
    var start = 0, end = len - 1;
    if (range != null && range.startsWith('bytes=')) {
      final parts = range.substring(6).split('-');
      start = int.tryParse(parts[0]) ?? 0;
      if (parts.length > 1 && parts[1].isNotEmpty) end = min(int.tryParse(parts[1]) ?? end, len - 1);
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$len');
    }
    res.contentLength = end - start + 1;
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }
    await res.addStream(file.openRead(start, end + 1));
    await res.close();
  }

  Future<void> _receiveFile(HttpRequest req, HttpResponse res) async {
    final name = p.basename(req.uri.queryParameters['name'] ?? 'song.mp3');
    final dir = await inboxDir();
    var target = File(p.join(dir.path, name));
    if (await target.exists()) {
      target = File(p.join(dir.path, '${p.basenameWithoutExtension(name)} (from phone)${p.extension(name)}'));
    }
    final sink = target.openWrite();
    await sink.addStream(req);
    await sink.close();
    res.statusCode = HttpStatus.created;
    await res.close();
    _scheduleRescan();
  }

  Timer? _rescanTimer;
  void _scheduleRescan() {
    _rescanTimer?.cancel();
    _rescanTimer = Timer(const Duration(seconds: 3), _library.rescan);
  }

  /// Where songs from the other device go. iPhone: the app's own folder
  /// (Files > On My iPhone > Starloom > From PC). PC: a "From iPhone"
  /// folder inside your first music folder.
  Future<Directory> inboxDir() async {
    final Directory dir;
    if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      dir = Directory(p.join(docs.path, 'From PC'));
    } else {
      final first = _library.sources.where((s) => s.kind == SourceKind.picked && s.error == null).firstOrNull;
      final base = first?.path ?? p.join((await getApplicationDocumentsDirectory()).path, 'Starloom');
      dir = Directory(p.join(base, 'From iPhone'));
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // =====================================================================
  // Phone side: talking to the PC
  // =====================================================================

  Uri _uri(String path, [Map<String, String>? q]) => Uri(scheme: 'http', host: pcAddress, port: kSyncPort, path: path, queryParameters: q);

  Future<Object?> _get(String path) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(_uri(path));
      req.headers.set('x-starloom-code', pcCode!);
      final res = await req.close();
      if (res.statusCode == 401) throw 'Wrong pairing code';
      if (res.statusCode != 200) throw 'PC answered ${res.statusCode}';
      return jsonDecode(await utf8.decoder.bind(res).join());
    } finally {
      client.close();
    }
  }

  Future<Object?> _post(String path, Object body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.postUrl(_uri(path));
      req.headers.set('x-starloom-code', pcCode!);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close();
      if (res.statusCode != 200) throw 'PC answered ${res.statusCode}';
      return jsonDecode(await utf8.decoder.bind(res).join());
    } finally {
      client.close();
    }
  }

  /// Saves the PC's address + code after checking they work.
  Future<String?> pair(String address, String pairCode) async {
    final oldA = pcAddress, oldC = pcCode;
    pcAddress = address.trim();
    pcCode = pairCode.trim();
    try {
      final hello = await _get('/hello') as Map;
      if (hello['app'] != 'starloom') throw 'That isn\'t a Starloom PC';
      await _save();
      notifyListeners();
      return null;
    } catch (e) {
      pcAddress = oldA;
      pcCode = oldC;
      return _friendly(e);
    }
  }

  Future<void> unpair() async {
    pcAddress = null;
    pcCode = null;
    pcLibrary = null;
    await _save();
    notifyListeners();
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('timed out') || s.contains('Connection refused')) {
      return 'Can\'t reach the PC. Same Wi-Fi? Is "Let my phone sync" on in Starloom on the PC?';
    }
    return s;
  }

  void _setStatus(String? s, {double? prog}) {
    status = s;
    progress = prog;
    notifyListeners();
  }

  /// Merge playlists + likes both ways.
  Future<String?> syncNow() async {
    if (!paired || busy) return null;
    busy = true;
    _setStatus('Syncing playlists and likes…');
    try {
      final remote = (await _get('/state') as Map).cast<String, Object?>();
      await _applyMerged(remote);
      await _post('/state', _localState()); // PC merges the same way
      lastSyncMs = DateTime.now().millisecondsSinceEpoch;
      await _save();
      _setStatus('Synced');
      return null;
    } catch (e) {
      _setStatus(null);
      return _friendly(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<List<RemoteSong>> loadPcLibrary() async {
    final list = (await _get('/library') as List).map((e) => RemoteSong.fromJson((e as Map).cast<String, Object?>())).toList();
    list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    pcLibrary = list;
    notifyListeners();
    return list;
  }

  Set<String> _myKeys() => {for (final s in _library.songs) keyOf(s)};

  /// Songs on the PC that this phone doesn't have.
  Future<List<RemoteSong>> missingHere() async {
    final pc = pcLibrary ?? await loadPcLibrary();
    final mine = _myKeys();
    return [for (final s in pc) if (!mine.contains(s.key)) s];
  }

  /// Songs on this phone that the PC doesn't have.
  Future<List<Song>> missingOnPc() async {
    final pc = pcLibrary ?? await loadPcLibrary();
    final theirs = {for (final s in pc) s.key};
    return [for (final s in _library.songs) if (!s.path.startsWith('http') && !theirs.contains(keyOf(s))) s];
  }

  /// Download songs from the PC into this phone's Starloom folder.
  Future<String?> copyFromPc(List<RemoteSong> songs) async {
    if (busy) return null;
    busy = true;
    final dir = await inboxDir();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    var done = 0;
    try {
      for (final s in songs) {
        _setStatus('Copying ${done + 1} of ${songs.length}: ${s.title}', prog: done / songs.length);
        final req = await client.getUrl(_uri('/file', {'key': s.key}));
        req.headers.set('x-starloom-code', pcCode!);
        final res = await req.close();
        if (res.statusCode != 200) {
          await res.drain<void>();
          continue;
        }
        final tmp = File(p.join(dir.path, '.${s.fileName}.part'));
        await res.pipe(tmp.openWrite());
        await tmp.rename(p.join(dir.path, s.fileName));
        done++;
      }
      _setStatus('Copied $done songs from your PC');
      await _library.rescan();
      return null;
    } catch (e) {
      _setStatus('Copied $done songs, then stopped');
      return _friendly(e);
    } finally {
      client.close();
      busy = false;
      notifyListeners();
    }
  }

  /// Upload songs from this phone to the PC ("From iPhone" folder there).
  Future<String?> sendToPc(List<Song> songs) async {
    if (busy) return null;
    busy = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    var done = 0;
    try {
      for (final s in songs) {
        _setStatus('Sending ${done + 1} of ${songs.length}: ${s.title}', prog: done / songs.length);
        final req = await client.putUrl(_uri('/file', {'name': p.basename(s.path)}));
        req.headers.set('x-starloom-code', pcCode!);
        req.contentLength = await File(s.path).length();
        await req.addStream(File(s.path).openRead());
        final res = await req.close();
        await res.drain<void>();
        if (res.statusCode == 201) done++;
      }
      _setStatus('Sent $done songs to your PC');
      return null;
    } catch (e) {
      _setStatus('Sent $done songs, then stopped');
      return _friendly(e);
    } finally {
      client.close();
      busy = false;
      notifyListeners();
    }
  }

  /// Turn PC songs into playable [Song]s that stream over Wi-Fi.
  List<Song> streamable(List<RemoteSong> list) {
    final songs = [
      for (final r in list)
        Song(
          id: 'pc::${r.key}',
          path: _uri('/file', {'key': r.key, 'code': pcCode!}).toString(),
          title: r.title,
          artist: r.artist,
          album: r.album,
          durationMs: r.durationMs,
          size: r.size,
          modifiedMs: 0,
          hasTags: true,
        ),
    ];
    for (final s in songs) {
      _player.remote[s.id] = s;
    }
    return songs;
  }
}
