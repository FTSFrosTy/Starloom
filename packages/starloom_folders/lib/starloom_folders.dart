import 'package:flutter/services.dart';

/// A folder the user picked, plus the bookmark that re-opens it next launch.
class PickedFolder {
  const PickedFolder({required this.path, required this.name, required this.bookmark});

  final String path;
  final String name;

  /// Base64 bookmark data. Store it and pass it to [StarloomFolders.restore].
  final String bookmark;
}

class RestoredFolder {
  const RestoredFolder({required this.path, this.refreshedBookmark});

  final String path;

  /// Set when iOS reported the old bookmark as stale; save this one instead.
  final String? refreshedBookmark;
}

/// iOS only. Other platforms use their normal file system access.
class StarloomFolders {
  static const MethodChannel _channel = MethodChannel('starloom/folders');

  /// Shows the Files folder picker. Returns null if the user cancels.
  static Future<PickedFolder?> pick() async {
    final res = await _channel.invokeMapMethod<String, Object?>('pick');
    if (res == null) return null;
    return PickedFolder(
      path: res['path']! as String,
      name: res['name']! as String,
      bookmark: res['bookmark']! as String,
    );
  }

  /// Re-opens a folder from its bookmark and keeps access for this launch.
  static Future<RestoredFolder?> restore(String bookmark) async {
    final res = await _channel.invokeMapMethod<String, Object?>('restore', {'bookmark': bookmark});
    if (res == null) return null;
    return RestoredFolder(
      path: res['path']! as String,
      refreshedBookmark: res['refreshedBookmark'] as String?,
    );
  }
}
