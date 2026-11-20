import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../models/models.dart' show Song;
import 'cast.dart';
import 'library.dart';
import 'player_service.dart';
import 'storage.dart';
import 'sync.dart';

/// What the other Starloom device (PC <-> phone) is up to.
class PeerStatus {
  PeerStatus({required this.name, required this.reachable, this.playing = false, this.title, this.artist});

  final String name;
  final bool reachable;
  final bool playing;
  final String? title;
  final String? artist;
}

/// "Connect to a device", like Spotify Connect:
///
/// * **Google Cast** — Google Home / Nest speakers, Chromecast, TVs. The
///   speaker pulls each song straight from this device over Wi-Fi. The
///   local player keeps running muted as the clock, so the queue, lock
///   screen, scrubber and media keys all keep working; the speaker is kept
///   in step with it.
/// * **Starloom on your other device** — hand the queue and position to
///   your PC or phone ("Switch to PC"), or pull what it's playing over here
///   ("Play here"). Songs the other side doesn't have stream over Wi-Fi.
class ConnectService extends ChangeNotifier {
  ConnectService(this._storage, this._library, this._player, this._sync);

  final Storage _storage;
  final Library _library;
  final PlayerService _player;
  final SyncService _sync;

  /// Speakers found on the Wi-Fi plus ones added by IP address.
  List<CastDevice> devices = [];
  final List<CastDevice> _manual = [];
  bool scanning = false;

  /// The speaker we're casting to, if any.
  CastDevice? casting;
  bool connecting = false;
  String? castState; // PLAYING / PAUSED / BUFFERING / IDLE

  CastClient? _client;
  _CastOutput? _output;
  Timer? _statusTimer;
  Timer? _volTimer;
  double? _pendingVol;
  DateTime _lastLoad = DateTime(2000);
  DateTime _lastCmd = DateTime(2000);
  bool _lastPlaying = false;
  String? _loadedId;
  bool _skippedOnError = false;

  /// Secret part of the song URLs we give speakers, so nothing else on the
  /// network can pull files without it.
  final String _token = List.generate(20, (_) => Random.secure().nextInt(36).toRadixString(36)).join();

  AppLifecycleListener? _life;

  String get deviceName => Platform.isIOS ? 'iPhone' : (Platform.isWindows ? 'PC (${Platform.localHostname})' : Platform.localHostname);

  Future<void> init() async {
    final raw = await _storage.read('cast.json');
    if (raw is Map) {
      for (final e in (raw['manual'] as List?) ?? const []) {
        _manual.add(CastDevice.fromJson((e as Map).cast<String, Object?>()));
      }
    }
    devices = List.of(_manual);
    _sync.extraHandler = _handle;
    _life = AppLifecycleListener(onResume: _announce);
    unawaited(_announce());
  }

  @override
  void dispose() {
    _life?.dispose();
    super.dispose();
  }

  void _say(String msg) => _player.errors.value = msg;

  // =====================================================================
  // Google Cast
  // =====================================================================

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    notifyListeners();
    try {
      final found = await discoverCast(seconds: 3);
      final byId = {for (final d in _manual) d.id: d, for (final d in found) d.id: d};
      devices = byId.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (_) {
      // Leave the old list; the sheet offers "Add by IP address".
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  /// For networks where discovery is blocked: connect by IP address.
  Future<String?> addByAddress(String host) async {
    host = host.trim();
    if (host.isEmpty) return 'Type the speaker\'s IP address';
    final dev = CastDevice(name: 'Speaker at $host', host: host);
    _manual.removeWhere((d) => d.host == host);
    _manual.add(dev);
    await _storage.write('cast.json', {'manual': [for (final d in _manual) d.toJson()]});
    if (!devices.any((d) => d.id == dev.id)) devices = [...devices, dev];
    notifyListeners();
    return startCast(dev);
  }

  Future<void> forgetDevice(CastDevice dev) async {
    _manual.removeWhere((d) => d.id == dev.id);
    devices = devices.where((d) => d.id != dev.id).toList();
    await _storage.write('cast.json', {'manual': [for (final d in _manual) d.toJson()]});
    notifyListeners();
  }

  /// Starts playing through [dev]. Returns an error message, or null.
  Future<String?> startCast(CastDevice dev) async {
    if (casting?.id == dev.id) return null;
    if (casting != null) await stopCast(keepPlaying: true);
    connecting = true;
    casting = dev;
    notifyListeners();
    final client = CastClient(dev);
    try {
      await client.connect();
    } catch (e) {
      await client.close();
      connecting = false;
      casting = null;
      notifyListeners();
      return 'Couldn\'t connect to ${dev.name}. Is it on the same Wi-Fi?';
    }
    _client = client;
    final out = _output = _CastOutput(dev.name, this);
    client.onVolume = (level) {
      out._volume = level * 100;
      _player.outputChanged();
    };
    client.onMediaStatus = _onStatus;
    client.onClosed = (why) => _lost(why);
    await _sync.holdServer('cast');
    await _player.routeTo(out);
    _lastPlaying = _player.playing;
    _player.currentId.addListener(_onSong);
    _player.addListener(_onPlayer);
    _statusTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _client?.requestStatus());
    connecting = false;
    notifyListeners();
    _loadedId = null;
    await _loadCurrent();
    return null;
  }

  /// Back to this device. [keepPlaying]: carry on here from the same spot
  /// (picking "This device"); otherwise pause (speaker lost, etc.).
  Future<void> stopCast({bool keepPlaying = true}) async {
    final client = _client;
    if (client == null && casting == null) return;
    _detach();
    await client?.stop();
    if (!keepPlaying) await _player.player.pause();
    await _player.routeTo(null);
    await _sync.releaseServer('cast');
    casting = null;
    castState = null;
    notifyListeners();
  }

  void _detach() {
    _statusTimer?.cancel();
    _statusTimer = null;
    _player.currentId.removeListener(_onSong);
    _player.removeListener(_onPlayer);
    _client = null;
    _output = null;
  }

  void _lost(String why) {
    if (casting == null) return;
    final name = casting!.name;
    _detach();
    unawaited(() async {
      await _player.player.pause();
      await _player.routeTo(null);
      await _sync.releaseServer('cast');
      casting = null;
      castState = null;
      notifyListeners();
      _say('Disconnected from $name. $why');
    }());
  }

  void _setVolume(double v) {
    _pendingVol = v;
    _output?._volume = v;
    _volTimer ??= Timer(const Duration(milliseconds: 120), () {
      _volTimer = null;
      final pv = _pendingVol;
      if (pv != null) _client?.setVolume(pv / 100);
    });
  }

  void _seek(Duration d) {
    _lastCmd = DateTime.now();
    _client?.seek(d.inMilliseconds / 1000);
  }

  void _onSong() {
    if (_player.currentId.value != _loadedId) unawaited(_loadCurrent());
  }

  void _onPlayer() {
    final c = _client;
    if (c == null) return;
    if (_player.playing != _lastPlaying) {
      _lastPlaying = _player.playing;
      _lastCmd = DateTime.now();
      _player.playing ? c.play() : c.pause();
    }
  }

  Future<void> _loadCurrent({Duration? at}) async {
    final c = _client;
    final song = _player.current;
    if (c == null || song == null) return;
    final local = c.localAddress?.address;
    if (local == null) return;
    _loadedId = song.id;
    _lastLoad = DateTime.now();
    _skippedOnError = false;
    final base = 'http://$local:$kSyncPort/cast/$_token';
    final String url;
    final String fileName;
    if (song.path.startsWith('http')) {
      url = song.path; // streamed from the PC: the speaker can fetch it there directly
      fileName = (Uri.tryParse(song.path)?.queryParameters['key'] ?? 'song.mp3').split('|').first;
    } else {
      url = '$base/song?id=${Uri.encodeQueryComponent(song.id)}';
      fileName = p.basename(song.path);
    }
    final art = _library.artPath(song.artKey);
    await c.load(
      url: url,
      contentType: castContentType(fileName),
      title: song.title,
      artist: song.artist,
      album: song.album,
      imageUrl: art != null && File(art).existsSync() ? '$base/art?key=${Uri.encodeQueryComponent(song.artKey!)}' : null,
      startAt: (at ?? _player.position).inMilliseconds / 1000,
      autoplay: _player.playing,
    );
  }

  /// Keeps the speaker and the muted local player in step, and follows
  /// changes made on the speaker itself ("Hey Google, pause").
  void _onStatus(CastMediaStatus st) {
    castState = st.state;
    notifyListeners();
    final now = DateTime.now();
    final sinceCmd = now.difference(_lastCmd);
    final sinceLoad = now.difference(_lastLoad);
    final local = _player.position.inMilliseconds / 1000;
    final total = _player.duration.inMilliseconds / 1000;

    if (st.state == 'IDLE' && st.idleReason == 'ERROR') {
      if (!_skippedOnError) {
        _skippedOnError = true;
        _say('${casting?.name ?? 'The speaker'} can\'t play "${_player.current?.title ?? 'this song'}" (file type?). Skipping.');
        unawaited(_player.next());
      }
      return;
    }
    if (st.state == 'PAUSED' && _player.playing && sinceCmd.inMilliseconds > 2500 && sinceLoad.inSeconds > 4) {
      _lastPlaying = false;
      unawaited(_player.player.pause());
      return;
    }
    if (st.state == 'PLAYING' && !_player.playing && sinceCmd.inMilliseconds > 2500) {
      _lastPlaying = true;
      unawaited(_player.player.play());
      return;
    }
    if (st.state == 'PLAYING' && _player.playing) {
      final diff = st.currentTime - local;
      if (sinceLoad.inSeconds < 6) {
        // Speaker is a beat behind after buffering: hold the clock back.
        if (diff.abs() > 0.6) unawaited(_player.player.seek(Duration(milliseconds: (st.currentTime * 1000).round())));
      } else if (diff.abs() > 2.0 && sinceCmd.inMilliseconds > 2000) {
        _client?.seek(local);
      }
      return;
    }
    // Speaker stopped but we're still mid-song (repeat-one, a hiccup): reload.
    if (st.state == 'IDLE' && _player.playing && sinceLoad.inSeconds > 5 && total - local > 3) {
      unawaited(_loadCurrent());
    }
  }

  // =====================================================================
  // Starloom <-> Starloom handoff
  // =====================================================================

  String? get peerAddress => _sync.peerAddress;
  bool get hasPeer => _sync.peerAddress != null && _sync.sharedCode != null;

  String get peerLabel => _sync.isHostPlatform ? (_sync.phoneName ?? 'iPhone') : 'your PC';

  /// Phone: tell the PC where we are so it can hand music over.
  Future<void> _announce() async {
    if (_sync.isHostPlatform || !_sync.paired) return;
    await _sync.holdServer('peer');
    try {
      await _peer('POST', '/connect/announce', {'name': deviceName}, 3);
    } catch (_) {}
  }

  Future<Object?> _peer(String method, String path, [Object? body, double timeout = 4]) async {
    final addr = _sync.peerAddress, code = _sync.sharedCode;
    if (addr == null || code == null) throw 'Not paired';
    final client = HttpClient()..connectionTimeout = Duration(milliseconds: (timeout * 1000).round());
    try {
      final req = await client.openUrl(method, Uri(scheme: 'http', host: addr, port: kSyncPort, path: path));
      req.headers.set('x-starloom-code', code);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(Duration(milliseconds: (timeout * 2000).round()));
      if (res.statusCode == 401) throw 'The pairing code doesn\'t match anymore';
      if (res.statusCode != 200) throw 'Answered ${res.statusCode}';
      return jsonDecode(await utf8.decoder.bind(res).join());
    } finally {
      client.close(force: true);
    }
  }

  Future<PeerStatus?> checkPeer() async {
    if (!hasPeer) return null;
    try {
      final j = (await _peer('GET', '/connect/now', null, 2) as Map).cast<String, Object?>();
      return PeerStatus(
        name: (j['name'] as String?) ?? peerLabel,
        reachable: true,
        playing: j['playing'] == true,
        title: j['title'] as String?,
        artist: j['artist'] as String?,
      );
    } catch (_) {
      return PeerStatus(name: peerLabel, reachable: false);
    }
  }

  /// Send what's playing here to the other device, then go quiet here.
  Future<String?> handOff() async {
    if (_player.current == null) return 'Nothing is playing';
    if (casting != null) await stopCast(keepPlaying: true);
    try {
      await _peer('POST', '/connect/handoff', _snapshot(), 6);
      await _player.player.pause();
      return null;
    } catch (e) {
      return _friendly(e);
    }
  }

  /// Pull what the other device is playing over here.
  Future<String?> takeOver() async {
    try {
      final j = (await _peer('POST', '/connect/takeover', <String, Object?>{}, 6) as Map).cast<String, Object?>();
      if ((j['songs'] as List?)?.isEmpty ?? true) return 'Nothing is playing there';
      await _apply(j, _sync.peerAddress!);
      return null;
    } catch (e) {
      return _friendly(e);
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('TimeoutException') || s.contains('timed out') || s.contains('refused')) {
      return _sync.isHostPlatform
          ? 'Can\'t reach your iPhone. Open Starloom on it (same Wi-Fi) and try again.'
          : 'Can\'t reach your PC. Is Starloom open there with "Let my phone sync" on?';
    }
    return s;
  }

  Map<String, Object?> _describe(Song s) {
    final sep = s.id.indexOf('::');
    final streamed = s.path.startsWith('http') && sep > 0;
    final key = streamed ? s.id.substring(sep + 2) : SyncService.keyOf(s);
    return RemoteSong(key, s.title, s.artist, s.album, s.durationMs, s.size, streamed ? key.split('|').first : p.basename(s.path)).toJson();
  }

  Map<String, Object?> _snapshot() => {
        'songs': [for (final s in _player.queue) _describe(s)],
        'index': _player.index,
        'positionMs': _player.position.inMilliseconds,
        'playing': _player.playing,
        'from': _player.playingFrom,
      };

  /// Start playing a snapshot from [sender]; songs we don't have stream
  /// from the sender.
  Future<void> _apply(Map<String, Object?> j, String sender) async {
    final code = _sync.sharedCode;
    final byKey = {for (final s in _library.songs) SyncService.keyOf(s): s};
    final list = <Song>[];
    for (final e in (j['songs'] as List?) ?? const []) {
      final r = RemoteSong.fromJson((e as Map).cast<String, Object?>());
      final mine = byKey[r.key];
      if (mine != null) {
        list.add(mine);
        continue;
      }
      if (code == null) continue;
      final s = Song(
        id: 'peer::${r.key}',
        path: Uri(scheme: 'http', host: sender, port: kSyncPort, path: '/file', queryParameters: {'key': r.key, 'code': code}).toString(),
        title: r.title,
        artist: r.artist,
        album: r.album,
        durationMs: r.durationMs,
        size: r.size,
        modifiedMs: 0,
        hasTags: true,
      );
      _player.remote[s.id] = s;
      list.add(s);
    }
    if (list.isEmpty) return;
    final index = ((j['index'] as num?)?.toInt() ?? 0).clamp(0, list.length - 1);
    final pos = Duration(milliseconds: (j['positionMs'] as num?)?.toInt() ?? 0);
    await _player.playSongs(list, index, from: j['from'] as String?);
    for (var i = 0; i < 40; i++) {
      if (_player.currentId.value == list[index].id && _player.duration > Duration.zero) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (pos > const Duration(seconds: 1)) await _player.seek(pos);
    if (j['playing'] == false) await _player.player.pause();
  }

  // =====================================================================
  // Web routes (on the same little service as sync)
  // =====================================================================

  Future<bool> _handle(HttpRequest req, bool authed) async {
    final path = req.uri.path;
    final res = req.response;

    // Speakers: no code (they can't send one), but the secret token.
    if (path.startsWith('/cast/')) {
      final parts = path.split('/'); // ['', 'cast', token, what]
      if (parts.length < 4 || parts[2] != _token || casting == null) {
        res.statusCode = HttpStatus.forbidden;
        await res.close();
        return true;
      }
      if (parts[3] == 'song') {
        final id = req.uri.queryParameters['id'] ?? '';
        final song = _library.byId(id) ?? _player.remote[id];
        final file = song == null || song.path.startsWith('http') ? null : File(song.path);
        final type = song == null ? null : castContentType(p.basename(song.path)).split('/');
        await _sync.serveFile(req, res, file, type: type == null ? null : ContentType(type[0], type[1]));
      } else if (parts[3] == 'art') {
        final key = req.uri.queryParameters['key'];
        final art = _library.artPath(key);
        await _sync.serveFile(req, res, art == null ? null : File(art), type: ContentType('image', 'jpeg'));
      } else {
        res.statusCode = HttpStatus.notFound;
        await res.close();
      }
      return true;
    }

    if (!path.startsWith('/connect/')) return false;
    if (!authed) return false; // falls through to the 401
    Future<void> json(Object? data) async {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(data));
      await res.close();
    }

    final remote = req.connectionInfo?.remoteAddress.address;
    switch ((req.method, path)) {
      case ('GET', '/connect/now'):
        final s = _player.current;
        await json({'name': deviceName, 'playing': _player.playing && casting == null, 'title': s?.title, 'artist': s?.artist});
      case ('POST', '/connect/announce'):
        final body = jsonDecode(await utf8.decoder.bind(req).join());
        if (remote != null) await _sync.rememberPhone(remote, ((body is Map ? body['name'] : null) as String?) ?? 'iPhone');
        await json({'name': deviceName});
        notifyListeners();
      case ('POST', '/connect/handoff'):
        final body = (jsonDecode(await utf8.decoder.bind(req).join()) as Map).cast<String, Object?>();
        await json({'ok': true});
        if (casting != null) await stopCast(keepPlaying: true);
        if (remote != null) await _apply(body, remote);
      case ('POST', '/connect/takeover'):
        await utf8.decoder.bind(req).join();
        final snap = _player.current == null ? {'songs': <Object>[]} : _snapshot();
        await json(snap);
        if (casting != null) await stopCast(keepPlaying: false);
        await _player.player.pause();
      default:
        res.statusCode = HttpStatus.notFound;
        await res.close();
    }
    return true;
  }
}

class _CastOutput implements RemoteOutput {
  _CastOutput(this.name, this._svc);

  @override
  final String name;
  final ConnectService _svc;
  double _volume = 50;

  @override
  double get volume => _volume;

  @override
  void setVolume(double v) => _svc._setVolume(v);

  @override
  void seek(Duration d) => _svc._seek(d);
}
