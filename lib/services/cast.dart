import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:starloom_folders/starloom_folders.dart';

/// A Google Cast speaker or TV on the Wi-Fi (Google Home / Nest speakers,
/// Chromecast, TVs with Chromecast built in, speaker groups).
class CastDevice {
  const CastDevice({required this.name, required this.host, this.port = 8009, this.model = ''});

  final String name;
  final String host;
  final int port;
  final String model;

  /// Speakers vs screens, for the icon.
  bool get isSpeaker {
    final m = model.toLowerCase();
    return m.contains('home') || m.contains('nest audio') || m.contains('speaker') || m.contains('group') || m.contains('mini') || m.contains('audio');
  }

  String get id => '$host:$port';

  Map<String, Object?> toJson() => {'name': name, 'host': host, 'port': port, 'model': model};

  static CastDevice fromJson(Map<String, Object?> j) => CastDevice(
        name: (j['name'] as String?) ?? 'Speaker',
        host: j['host']! as String,
        port: (j['port'] as num?)?.toInt() ?? 8009,
        model: (j['model'] as String?) ?? '',
      );
}

// ===========================================================================
// Discovery
// ===========================================================================

/// Looks for Cast devices for about [seconds].
///
/// iOS: Bonjour through the native plugin (apps can't send raw multicast
/// there). Everywhere else: a one-shot mDNS question sent from an ordinary
/// UDP port, which devices answer straight back to us (RFC 6762 "legacy
/// unicast"), so we never have to share port 5353 with Windows.
Future<List<CastDevice>> discoverCast({double seconds = 3}) async {
  if (Platform.isIOS) {
    final raw = await StarloomFolders.browseCast(seconds: seconds);
    return [for (final m in raw) CastDevice.fromJson(m)]..sort((a, b) => a.name.compareTo(b.name));
  }
  return _mdnsDiscover(Duration(milliseconds: (seconds * 1000).round()));
}

const _service = '_googlecast._tcp.local';

Future<List<CastDevice>> _mdnsDiscover(Duration wait) async {
  final found = <String, CastDevice>{};
  final sockets = <RawDatagramSocket>[];
  final query = _buildQuery(_service);
  final group = InternetAddress('224.0.0.251');

  // One socket per network card, so the question goes out on the Wi-Fi /
  // Ethernet card and not just whatever Windows picks (VPNs, Hyper-V…).
  final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
  final addrs = [
    for (final i in ifs)
      for (final a in i.addresses)
        if (!a.isLoopback && !a.address.startsWith('169.254')) a,
  ];
  for (final a in addrs.isEmpty ? [InternetAddress.anyIPv4] : addrs) {
    try {
      final s = await RawDatagramSocket.bind(a, 0);
      try {
        // IP_MULTICAST_IF: 9 on Windows and macOS, 32 on Linux.
        final opt = Platform.isLinux ? 32 : 9;
        s.setRawOption(RawSocketOption(RawSocketOption.levelIPv4, opt, Uint8List.fromList(a.rawAddress)));
      } catch (_) {}
      s.listen((e) {
        if (e != RawSocketEvent.read) return;
        Datagram? d;
        while ((d = s.receive()) != null) {
          try {
            for (final dev in _parseResponse(d!.data, d.address.address)) {
              found[dev.id] = dev;
            }
          } catch (_) {}
        }
      });
      sockets.add(s);
    } catch (_) {}
  }

  // Ask a few times; Wi-Fi drops multicast now and then.
  for (var i = 0; i < 3; i++) {
    for (final s in sockets) {
      try {
        s.send(query, group, 5353);
      } catch (_) {}
    }
    await Future<void>.delayed(wait ~/ 3);
  }
  for (final s in sockets) {
    s.close();
  }
  return found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

Uint8List _buildQuery(String name) {
  final b = BytesBuilder();
  b.add([0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]); // id 0, flags 0, 1 question
  for (final label in name.split('.')) {
    final bytes = utf8.encode(label);
    b.addByte(bytes.length);
    b.add(bytes);
  }
  b.addByte(0);
  b.add([0, 12, 0x80, 1]); // PTR, class IN with "unicast response please"
  return b.toBytes();
}

/// Reads a DNS name at [offset] (following compression pointers).
/// Returns the name and the offset just past it.
(String, int) _readName(Uint8List d, int offset) {
  final labels = <String>[];
  var pos = offset;
  int? after;
  var hops = 0;
  while (pos < d.length) {
    final len = d[pos];
    if (len == 0) {
      pos++;
      break;
    }
    if (len & 0xC0 == 0xC0) {
      if (pos + 1 >= d.length || ++hops > 20) break;
      after ??= pos + 2;
      pos = ((len & 0x3F) << 8) | d[pos + 1];
      continue;
    }
    if (pos + 1 + len > d.length) break;
    labels.add(utf8.decode(d.sublist(pos + 1, pos + 1 + len), allowMalformed: true));
    pos += 1 + len;
  }
  return (labels.join('.'), after ?? pos);
}

List<CastDevice> _parseResponse(Uint8List d, String from) {
  if (d.length < 12) return const [];
  int u16(int o) => (d[o] << 8) | d[o + 1];
  final qd = u16(4);
  final total = u16(6) + u16(8) + u16(10);
  var pos = 12;
  for (var i = 0; i < qd; i++) {
    pos = _readName(d, pos).$2 + 4;
  }
  final ptrs = <String>{};
  final srv = <String, (String, int)>{};
  final txt = <String, Map<String, String>>{};
  final a = <String, String>{};
  for (var i = 0; i < total && pos + 10 <= d.length; i++) {
    final (name, p) = _readName(d, pos);
    pos = p;
    final type = u16(pos);
    final rdlen = u16(pos + 8);
    final rd = pos + 10;
    if (rd + rdlen > d.length) break;
    final key = name.toLowerCase();
    switch (type) {
      case 12: // PTR
        if (key == _service) ptrs.add(_readName(d, rd).$1);
      case 33: // SRV
        srv[key] = (_readName(d, rd + 6).$1.toLowerCase(), u16(rd + 4));
      case 16: // TXT
        final m = <String, String>{};
        var t = rd;
        while (t < rd + rdlen) {
          final l = d[t];
          final s = utf8.decode(d.sublist(t + 1, math.min(t + 1 + l, rd + rdlen)), allowMalformed: true);
          final eq = s.indexOf('=');
          if (eq > 0) m[s.substring(0, eq)] = s.substring(eq + 1);
          t += 1 + l;
        }
        txt[key] = m;
      case 1: // A
        if (rdlen == 4) a[key] = d.sublist(rd, rd + 4).join('.');
    }
    pos = rd + rdlen;
  }
  final out = <CastDevice>[];
  final names = {...ptrs.map((p) => p.toLowerCase()), ...srv.keys, ...txt.keys}.where((n) => n.endsWith(_service));
  for (final n in names) {
    final s = srv[n];
    final t = txt[n] ?? const {};
    final host = (s == null ? null : a[s.$1]) ?? from;
    final fallback = n.substring(0, n.length - _service.length - 1);
    out.add(CastDevice(name: t['fn'] ?? fallback, host: host, port: s?.$2 ?? 8009, model: t['md'] ?? ''));
  }
  return out;
}

// ===========================================================================
// The Cast v2 protocol (TLS to port 8009, length-prefixed protobuf frames
// carrying JSON). Just enough of it to drive the Default Media Receiver.
// ===========================================================================

const _nsConnection = 'urn:x-cast:com.google.cast.tp.connection';
const _nsHeartbeat = 'urn:x-cast:com.google.cast.tp.heartbeat';
const _nsReceiver = 'urn:x-cast:com.google.cast.receiver';
const _nsMedia = 'urn:x-cast:com.google.cast.media';

/// Google's built-in player app on every Cast device.
const _defaultReceiver = 'CC1AD845';

/// What the speaker reports about playback.
class CastMediaStatus {
  CastMediaStatus(this.state, this.idleReason, this.currentTime);

  /// PLAYING, PAUSED, BUFFERING or IDLE.
  final String state;
  final String? idleReason;
  final double currentTime;
}

class CastClient {
  CastClient(this.device);

  final CastDevice device;

  /// Our address as the speaker sees it: the speaker fetches songs from here.
  InternetAddress? localAddress;

  void Function(CastMediaStatus status)? onMediaStatus;
  void Function(double level)? onVolume;

  /// Lost the speaker, or someone else took it over / stopped the app.
  void Function(String why)? onClosed;

  SecureSocket? _socket;
  final _rx = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);
  Timer? _heartbeat;
  int _requestId = 1;
  String? _transportId;
  String? _sessionId;
  int? mediaSessionId;
  bool _closed = false;
  Completer<void>? _launched;

  bool get connected => _socket != null && !_closed;

  Future<void> connect() async {
    final s = await SecureSocket.connect(device.host, device.port,
        timeout: const Duration(seconds: 6), onBadCertificate: (_) => true); // Cast devices use self-signed certs
    _socket = s;
    localAddress = s.address;
    s.listen(_onData, onDone: () => _lost('The speaker disconnected'), onError: (_) => _lost('Lost the connection to the speaker'));
    _send('receiver-0', _nsConnection, {'type': 'CONNECT'});
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) => _send('receiver-0', _nsHeartbeat, {'type': 'PING'}));

    _launched = Completer<void>();
    _send('receiver-0', _nsReceiver, {'type': 'LAUNCH', 'appId': _defaultReceiver, 'requestId': _requestId++});
    await _launched!.future.timeout(const Duration(seconds: 12), onTimeout: () => throw 'The speaker didn\'t answer');
    _send(_transportId!, _nsConnection, {'type': 'CONNECT', 'origin': <String, Object?>{}});
  }

  Future<void> load({
    required String url,
    required String contentType,
    required String title,
    String artist = '',
    String album = '',
    String? imageUrl,
    double startAt = 0,
    bool autoplay = true,
  }) async {
    if (_transportId == null) return;
    mediaSessionId = null;
    _send(_transportId!, _nsMedia, {
      'type': 'LOAD',
      'requestId': _requestId++,
      'sessionId': _sessionId,
      'autoplay': autoplay,
      'currentTime': startAt,
      'media': {
        'contentId': url,
        'contentUrl': url,
        'streamType': 'BUFFERED',
        'contentType': contentType,
        'metadata': {
          'metadataType': 3, // music track
          'title': title,
          'artist': artist,
          'albumName': album,
          'images': [if (imageUrl != null) {'url': imageUrl}],
        },
      },
    });
  }

  void _mediaCommand(String type, [Map<String, Object?> extra = const {}]) {
    if (_transportId == null || mediaSessionId == null) return;
    _send(_transportId!, _nsMedia, {'type': type, 'requestId': _requestId++, 'mediaSessionId': mediaSessionId, ...extra});
  }

  void play() => _mediaCommand('PLAY');
  void pause() => _mediaCommand('PAUSE');
  void seek(double seconds) => _mediaCommand('SEEK', {'currentTime': seconds});

  void requestStatus() {
    if (_transportId == null) return;
    _send(_transportId!, _nsMedia, {'type': 'GET_STATUS', 'requestId': _requestId++});
  }

  void setVolume(double level) =>
      _send('receiver-0', _nsReceiver, {'type': 'SET_VOLUME', 'requestId': _requestId++, 'volume': {'level': level.clamp(0.0, 1.0)}});

  /// Stops our app on the speaker and hangs up.
  Future<void> stop() async {
    if (_sessionId != null && connected) {
      _send('receiver-0', _nsReceiver, {'type': 'STOP', 'sessionId': _sessionId, 'requestId': _requestId++});
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await close();
  }

  Future<void> close() async {
    _closed = true;
    _heartbeat?.cancel();
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  void _lost(String why) {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    if (_launched != null && !_launched!.isCompleted) _launched!.completeError(why);
    onClosed?.call(why);
  }

  // ---- framing ----

  void _send(String dest, String ns, Map<String, Object?> payload) {
    final s = _socket;
    if (s == null || _closed) return;
    final msg = _encode('sender-0', dest, ns, jsonEncode(payload));
    final len = ByteData(4)..setUint32(0, msg.length);
    try {
      s.add(len.buffer.asUint8List());
      s.add(msg);
    } catch (_) {}
  }

  void _onData(Uint8List chunk) {
    _rx.add(_pending);
    _rx.add(chunk);
    var buf = _rx.takeBytes();
    var off = 0;
    while (buf.length - off >= 4) {
      final len = ByteData.sublistView(buf, off, off + 4).getUint32(0);
      if (buf.length - off - 4 < len) break;
      final frame = Uint8List.sublistView(buf, off + 4, off + 4 + len);
      off += 4 + len;
      try {
        _onMessage(_decode(frame));
      } catch (_) {}
    }
    _pending = Uint8List.fromList(buf.sublist(off));
    buf = Uint8List(0);
  }

  void _onMessage((String, String, String) m) {
    final (source, ns, payload) = m;
    final j = jsonDecode(payload);
    if (j is! Map) return;
    final type = j['type'];
    if (ns == _nsHeartbeat && type == 'PING') {
      _send(source, _nsHeartbeat, {'type': 'PONG'});
      return;
    }
    if (ns == _nsConnection && type == 'CLOSE') {
      _lost('The speaker closed the session');
      return;
    }
    if (ns == _nsReceiver && type == 'RECEIVER_STATUS') {
      final status = j['status'];
      if (status is! Map) return;
      final vol = status['volume'];
      if (vol is Map && vol['level'] is num) onVolume?.call((vol['level'] as num).toDouble());
      final apps = (status['applications'] as List?) ?? const [];
      final ours = apps.whereType<Map>().where((a) => a['appId'] == _defaultReceiver).firstOrNull;
      if (ours != null) {
        _transportId = ours['transportId'] as String?;
        _sessionId = ours['sessionId'] as String?;
        if (_launched != null && !_launched!.isCompleted && _transportId != null) _launched!.complete();
      } else if (_launched != null && _launched!.isCompleted && _sessionId != null) {
        _lost('Something else started playing on the speaker');
      }
      return;
    }
    if (ns == _nsReceiver && type == 'LAUNCH_ERROR') {
      if (_launched != null && !_launched!.isCompleted) _launched!.completeError('The speaker couldn\'t start the player');
      return;
    }
    if (ns == _nsMedia && type == 'MEDIA_STATUS') {
      final list = (j['status'] as List?) ?? const [];
      if (list.isEmpty) return;
      final st = list.first as Map;
      mediaSessionId = (st['mediaSessionId'] as num?)?.toInt() ?? mediaSessionId;
      onMediaStatus?.call(CastMediaStatus(
        (st['playerState'] as String?) ?? 'IDLE',
        st['idleReason'] as String?,
        (st['currentTime'] as num?)?.toDouble() ?? 0,
      ));
      return;
    }
    if (ns == _nsMedia && (type == 'LOAD_FAILED' || type == 'LOAD_CANCELLED' || type == 'INVALID_REQUEST')) {
      onMediaStatus?.call(CastMediaStatus('IDLE', 'ERROR', 0));
    }
  }
}

// ---- protobuf: CastMessage (all we need of it) ----

Uint8List _encode(String source, String dest, String ns, String payload) {
  final b = BytesBuilder();
  void varint(int v) {
    while (v >= 0x80) {
      b.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    b.addByte(v);
  }

  void str(int field, String s) {
    final bytes = utf8.encode(s);
    varint((field << 3) | 2);
    varint(bytes.length);
    b.add(bytes);
  }

  varint(1 << 3); // protocol_version
  varint(0); // CASTV2_1_0
  str(2, source);
  str(3, dest);
  str(4, ns);
  varint(5 << 3); // payload_type
  varint(0); // STRING
  str(6, payload);
  return b.toBytes();
}

(String, String, String) _decode(Uint8List d) {
  var pos = 0;
  int varint() {
    var v = 0, shift = 0;
    while (pos < d.length) {
      final byte = d[pos++];
      v |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) break;
      shift += 7;
    }
    return v;
  }

  var source = '', ns = '', payload = '';
  while (pos < d.length) {
    final key = varint();
    final field = key >> 3, wire = key & 7;
    if (wire == 0) {
      varint();
    } else if (wire == 2) {
      final len = varint();
      final end = math.min(pos + len, d.length);
      final s = Uint8List.sublistView(d, pos, end);
      pos = end;
      switch (field) {
        case 2:
          source = utf8.decode(s, allowMalformed: true);
        case 4:
          ns = utf8.decode(s, allowMalformed: true);
        case 6:
          payload = utf8.decode(s, allowMalformed: true);
      }
    } else if (wire == 5) {
      pos += 4;
    } else if (wire == 1) {
      pos += 8;
    } else {
      break;
    }
  }
  return (source, ns, payload);
}

/// The MIME type Cast devices expect for a file name.
String castContentType(String fileName) {
  final ext = fileName.toLowerCase().split('.').last;
  return switch (ext) {
    'mp3' => 'audio/mpeg',
    'm4a' || 'aac' || 'mp4' => 'audio/mp4',
    'flac' => 'audio/flac',
    'ogg' || 'oga' => 'audio/ogg',
    'opus' => 'audio/ogg',
    'wav' => 'audio/wav',
    'webm' => 'audio/webm',
    _ => 'audio/mpeg',
  };
}
