import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../theme/palette.dart';
import 'clay.dart';

const double kSongRowHeight = 66;

/// One song row. Fixed height so long lists scroll cheaply.
class SongTile extends StatelessWidget {
  const SongTile({super.key, required this.song, required this.onTap, this.onRemove, this.index});

  final Song song;
  final VoidCallback onTap;

  /// Shown as "Remove from playlist" in the actions sheet when set.
  final VoidCallback? onRemove;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return SizedBox(
      height: kSongRowHeight,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => showSongActions(context, song, onRemove: onRemove),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Pebble(seedText: song.album.isNotEmpty ? song.album : song.artist.isNotEmpty ? song.artist : song.title, glyph: song.title.isEmpty ? '?' : null),
              const SizedBox(width: 14),
              Expanded(
                child: ValueListenableBuilder<String?>(
                  valueListenable: player.currentId,
                  builder: (context, currentId, _) {
                    final isCurrent = currentId == song.id;
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent ? Clay.candle : Clay.bone,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Clay.ash, fontSize: 13),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (song.durationMs > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(formatDuration(Duration(milliseconds: song.durationMs)), style: const TextStyle(color: Clay.ash, fontSize: 12.5)),
                ),
              IconButton(
                icon: const Icon(Icons.more_vert, color: Clay.ash),
                tooltip: 'More',
                onPressed: () => showSongActions(context, song, onRemove: onRemove),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showSongActions(BuildContext context, Song song, {VoidCallback? onRemove}) {
  final scope = AppScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(song.title, style: Clay.title(22), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          ListTile(
            leading: const Icon(Icons.subdirectory_arrow_right, color: Clay.candle),
            title: const Text('Play next'),
            onTap: () {
              Navigator.pop(sheet);
              scope.player.playNext(song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music, color: Clay.candle),
            title: const Text('Add to queue'),
            onTap: () {
              Navigator.pop(sheet);
              scope.player.addToQueue(song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add, color: Clay.candle),
            title: const Text('Add to playlist…'),
            onTap: () {
              Navigator.pop(sheet);
              showAddToPlaylist(context, song);
            },
          ),
          if (onRemove != null)
            ListTile(
              leading: const Icon(Icons.remove_circle_outline, color: Clay.rose),
              title: const Text('Remove from this playlist'),
              onTap: () {
                Navigator.pop(sheet);
                onRemove();
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Text(song.path, style: const TextStyle(color: Clay.ash, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    ),
  );
}

Future<void> showAddToPlaylist(BuildContext context, Song song) {
  final store = AppScope.of(context).playlists;
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.add, color: Clay.candle),
              title: const Text('New playlist'),
              onTap: () async {
                Navigator.pop(sheet);
                final name = await promptText(context, title: 'New playlist', hint: 'Name');
                if (name == null) return;
                await store.create(name, songIds: [song.id]);
                messenger.showSnackBar(SnackBar(content: Text('Added to $name')));
              },
            ),
            for (final pl in store.playlists)
              ListTile(
                leading: const Icon(Icons.queue_music, color: Clay.ghost),
                title: Text(pl.name),
                subtitle: Text('${pl.songIds.length} songs', style: const TextStyle(color: Clay.ash)),
                onTap: () {
                  Navigator.pop(sheet);
                  store.addSong(pl, song.id);
                  messenger.showSnackBar(SnackBar(content: Text('Added to ${pl.name}')));
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Simple one-field dialog. Returns null on cancel.
Future<String?> promptText(BuildContext context, {required String title, String hint = '', String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title, style: Clay.title(24)),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(dialog, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(dialog, controller.text), child: const Text('OK')),
      ],
    ),
  );
}
