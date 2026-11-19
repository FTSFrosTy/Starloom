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

  /// Writes atomically (temp file + rename) so a crash can't leave half a file.
  Future<void> write(String name, Object? data) async {
    final f = _file(name);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(f.path);
  }
}
