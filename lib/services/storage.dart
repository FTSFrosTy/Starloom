import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Small JSON-file store in the app's private support folder.
class Storage {
  Storage._(this._dir);

  final Directory _dir;

  static Future<Storage> open() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'starloom'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return Storage._(dir);
  }

  File _file(String name) => File(p.join(_dir.path, name));

  Future<Object?> read(String name) async {
    final f = _file(name);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null; // corrupt file: start fresh rather than crash
    }
  }

  /// Latest data waiting to be written, per file, and the write in flight.
  final Map<String, Object?> _pending = {};
  final Map<String, Future<void>> _writing = {};

  /// Writes atomically (temp file + rename) so a crash can't leave half a
  /// file. Writes to one file never overlap: rapid saves (dragging the
  /// volume, say) collapse into one write of the newest data, so a later
  /// change can't be lost to a clash with an earlier one.
  Future<void> write(String name, Object? data) {
    _pending[name] = data;
    return _writing[name] ??= _drain(name);
  }

  Future<void> _drain(String name) async {
    try {
      while (_pending.containsKey(name)) {
        final data = _pending.remove(name);
        await _writeNow(name, data);
      }
    } finally {
      _writing.remove(name);
    }
  }

  Future<void> _writeNow(String name, Object? data) async {
    final f = _file(name);
    final text = jsonEncode(data);
    for (var attempt = 0; attempt < 4; attempt++) {
      final tmp = File('${f.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
      try {
        await tmp.writeAsString(text, flush: true);
        await tmp.rename(f.path);
        return;
      } catch (_) {
        // Windows: the file can be briefly locked (antivirus, a reader).
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
        await Future<void>.delayed(Duration(milliseconds: 60 * (attempt + 1)));
      }
    }
    // Last resort: write in place.
    try {
      await f.writeAsString(text, flush: true);
    } catch (_) {}
  }

  /// Waits for every pending write (before the app quits).
  Future<void> flush() => Future.wait(_writing.values.toList());
}
