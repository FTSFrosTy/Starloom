import 'package:flutter/material.dart';

import '../models/models.dart';
import '../screens/collection_screens.dart';
import '../services/app_scope.dart';
import '../theme/palette.dart';
import 'cover.dart';
import 'context_menu.dart';
import 'nav.dart';

const double kSongRowHeight = 64;

/// One song row: cover, title, artist, liked heart, length, menu.
/// Swipe right to add to the queue. Fixed height so long lists stay smooth.
class SongTile extends StatelessWidget {
  const SongTile({super.key, required this.song, required this.onTap, this.onRemove, this.leadingNumber});

  final Song song;
  final VoidCallback onTap;

  /// Shown as "Remove from this playlist" in the menu when set.
  final VoidCallback? onRemove;

  /// Show a track number instead of the cover (album pages).
  final int? leadingNumber;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final row = SizedBox(
      height: kSongRowHeight,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => showSongActions(context, song, onRemove: onRemove),
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Row(
            children: [
              if (leadingNumber != null)
                SizedBox(
                  width: 34,
                  child: Text('$leadingNumber', textAlign: TextAlign.center, style: TextStyle(color: Clay.ash, fontSize: 14)),
                )
              else
                Cover(artKey: song.artKey, seedText: song.album.isNotEmpty ? song.album : song.artist.isNotEmpty ? song.artist : song.title, size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: ValueListenableBuilder<String?>(
                  valueListenable: scope.player.currentId,
                  builder: (context, currentId, _) {
                    final isCurrent = currentId == song.id;
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isCurrent)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(Icons.graphic_eq_rounded, size: 15, color: Clay.candle),
                              ),
                            Expanded(
                              child: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: isCurrent ? Clay.candle : Clay.bone, fontSize: 15.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(song.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.ash, fontSize: 13)),
                      ],
                    );
                  },
                ),
              ),
              ListenableBuilder(
                listenable: scope.user,
                builder: (context, _) => scope.user.isLiked(song.id)
                    ? Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.favorite_rounded, size: 16, color: Clay.rose))
                    : const SizedBox.shrink(),
              ),
              if (song.durationMs > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(formatDuration(Duration(milliseconds: song.durationMs)), style: TextStyle(color: Clay.ash, fontSize: 12.5)),
                ),
              IconButton(
                icon: Icon(Icons.more_horiz_rounded, color: Clay.ash),
                tooltip: 'More',
                onPressed: () => showSongActions(context, song, onRemove: onRemove),
              ),
            ],
          ),
        ),
      ),
    );

    // Swipe right to queue, like Spotify. The row snaps back.
    // Right-click (PC) opens the full menu.
    return RightClick(
      onMenu: (at) => songMenu(context, at, song, onRemove: onRemove),
      child: Dismissible(
      key: const ValueKey('swipe'),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const {DismissDirection.startToEnd: 0.25},
      background: Container(
        color: Clay.moss.withValues(alpha: 0.85),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 22),
        child: Row(children: [
          Icon(Icons.queue_music_rounded, color: Clay.bone),
          const SizedBox(width: 10),
          Text('Add to queue', style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w700)),
        ]),
      ),
      confirmDismiss: (_) async {
        scope.player.addToQueue(song);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added "${song.title}" to the queue'), duration: const Duration(milliseconds: 1400)));
        return false;
      },
      child: row,
    ),
    );
  }
}

Future<void> showSongActions(BuildContext context, Song song, {VoidCallback? onRemove}) {
  final scope = AppScope.of(context);
  final liked = scope.user.isLiked(song.id);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(children: [
                Cover(artKey: song.artKey, seedText: song.album.isNotEmpty ? song.album : song.title, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(song.title, style: Clay.title(21), maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(song.subtitle, style: TextStyle(color: Clay.ash, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
            ),
            _action(sheet, liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, liked ? 'Remove from Liked Songs' : 'Like',
                () => scope.user.toggleLike(song.id), color: Clay.rose),
            _action(sheet, Icons.subdirectory_arrow_right_rounded, 'Play next', () => scope.player.playNext(song)),
            _action(sheet, Icons.queue_music_rounded, 'Add to queue', () => scope.player.addToQueue(song)),
            _action(sheet, Icons.playlist_add_rounded, 'Add to playlist…', () => showAddToPlaylist(context, [song])),
            if (song.album.isNotEmpty)
              _action(sheet, Icons.album_rounded, 'Go to album', () => Nav.push(AlbumScreen(albumKey: song.albumKey))),
            if (song.artist.isNotEmpty)
              _action(sheet, Icons.person_rounded, 'Go to artist', () => Nav.push(ArtistScreen(name: song.artist))),
            if (onRemove != null) _action(sheet, Icons.remove_circle_outline_rounded, 'Remove from this playlist', onRemove, color: Clay.rose),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(song.path, style: TextStyle(color: Clay.ash, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _action(BuildContext sheet, IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
      leading: Icon(icon, color: color ?? Clay.candle),
      title: Text(label, style: TextStyle(color: Clay.bone)),
      onTap: () {
        Navigator.pop(sheet);
        onTap();
      },
    );

Future<void> showAddToPlaylist(BuildContext context, List<Song> songs) {
  final store = AppScope.of(context).playlists;
  final messenger = ScaffoldMessenger.of(context);
  final ids = songs.map((s) => s.id).toList();
  final what = songs.length == 1 ? '"${songs.first.title}"' : '${songs.length} songs';
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Add $what to…', style: Clay.title(22))),
            ListTile(
              leading: Icon(Icons.add_rounded, color: Clay.candle),
              title: Text('New playlist', style: TextStyle(color: Clay.bone)),
              onTap: () async {
                Navigator.pop(sheet);
                final name = await promptText(context, title: 'New playlist', hint: 'Name');
                if (name == null) return;
                await store.create(name, songIds: ids);
                messenger.showSnackBar(SnackBar(content: Text('Added to $name')));
              },
            ),
            for (final pl in store.playlists)
              ListTile(
                leading: Icon(Icons.queue_music_rounded, color: Clay.ghost),
                title: Text(pl.name, style: TextStyle(color: Clay.bone)),
                subtitle: Text('${pl.songIds.length} songs', style: TextStyle(color: Clay.ash)),
                onTap: () {
                  Navigator.pop(sheet);
                  store.addSongs(pl, ids);
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
    useRootNavigator: true,
    builder: (dialog) => AlertDialog(
      title: Text(title, style: Clay.title(24)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(color: Clay.bone),
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
