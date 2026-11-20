import 'package:flutter/material.dart';

import '../models/models.dart';
import '../screens/collection_screens.dart';
import '../services/app_scope.dart';
import '../theme/palette.dart';
import 'nav.dart';
import 'song_tile.dart';

/// Spotify-style right-click menus for PC (long-press still opens the
/// bottom sheet on the phone).
Future<void> _menu(BuildContext context, Offset at, List<(IconData, String, VoidCallback, bool)> items) async {
  final overlay = Overlay.of(context, rootOverlay: true).context.findRenderObject() as RenderBox;
  final choice = await showMenu<int>(
    context: context,
    useRootNavigator: true,
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    color: Clay.dusk,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    items: [
      for (var i = 0; i < items.length; i++)
        PopupMenuItem<int>(
          value: i,
          height: 40,
          child: Row(children: [
            Icon(items[i].$1, size: 18, color: items[i].$4 ? Clay.rose : Clay.candle),
            const SizedBox(width: 12),
            Text(items[i].$2, style: TextStyle(color: Clay.bone, fontSize: 14)),
          ]),
        ),
    ],
  );
  if (choice != null) items[choice].$3();
}

Future<void> songMenu(BuildContext context, Offset at, Song song, {VoidCallback? onRemove, VoidCallback? onRemoveFromQueue}) {
  final scope = AppScope.of(context);
  final liked = scope.user.isLiked(song.id);
  return _menu(context, at, [
    (Icons.play_arrow_rounded, 'Play', () => scope.player.playSongs([song], 0), false),
    (Icons.subdirectory_arrow_right_rounded, 'Play next', () => scope.player.playNext(song), false),
    (Icons.queue_music_rounded, 'Add to queue', () => scope.player.addToQueue(song), false),
    (Icons.playlist_add_rounded, 'Add to playlist…', () => showAddToPlaylist(context, [song]), false),
    (liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, liked ? 'Remove from Liked Songs' : 'Save to Liked Songs', () => scope.user.toggleLike(song.id), false),
    if (song.album.isNotEmpty) (Icons.album_rounded, 'Go to album', () => Nav.push(AlbumScreen(albumKey: song.albumKey)), false),
    if (song.artist.isNotEmpty) (Icons.person_rounded, 'Go to artist', () => Nav.push(ArtistScreen(name: song.artist)), false),
    if (onRemove != null) (Icons.remove_circle_outline_rounded, 'Remove from this playlist', onRemove, true),
    if (onRemoveFromQueue != null) (Icons.playlist_remove_rounded, 'Remove from queue', onRemoveFromQueue, true),
  ]);
}

Future<void> songsMenu(BuildContext context, Offset at, List<Song> songs,
    {String? albumArtist, String? title, VoidCallback? onRename, VoidCallback? onDelete, VoidCallback? onPin, bool pinned = false}) {
  final scope = AppScope.of(context);
  return _menu(context, at, [
    (Icons.play_arrow_rounded, 'Play', () => scope.player.playSongs(songs, 0, from: title), false),
    (Icons.shuffle_rounded, 'Shuffle play', () => scope.player.playSongs(songs, 0, shuffled: true, from: title), false),
    (Icons.queue_music_rounded, 'Add to queue', () async {
      for (final s in songs) {
        await scope.player.addToQueue(s);
      }
    }, false),
    (Icons.playlist_add_rounded, 'Add to playlist…', () => showAddToPlaylist(context, songs), false),
    if (albumArtist != null && albumArtist.isNotEmpty) (Icons.person_rounded, 'Go to artist', () => Nav.push(ArtistScreen(name: albumArtist)), false),
    if (onPin != null) (pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded, pinned ? 'Unpin' : 'Pin to top', onPin, false),
    if (onRename != null) (Icons.edit_rounded, 'Rename', onRename, false),
    if (onDelete != null) (Icons.delete_outline_rounded, 'Delete', onDelete, true),
  ]);
}

/// Wraps anything so a right-click (or two-finger click) opens a menu.
class RightClick extends StatelessWidget {
  const RightClick({super.key, required this.child, required this.onMenu});

  final Widget child;
  final void Function(Offset globalPosition) onMenu;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: (d) => onMenu(d.globalPosition),
      child: child,
    );
  }
}

/// Menu for a whole playlist: play, queue, pin, rename, delete.
Future<void> playlistMenu(BuildContext context, Offset at, Playlist pl) {
  final scope = AppScope.of(context);
  final songs = [for (final id in pl.songIds) ?scope.library.byId(id)];
  return songsMenu(context, at, songs,
      title: pl.name,
      pinned: pl.pinned,
      onPin: () => scope.playlists.togglePin(pl),
      onRename: () async {
        final name = await promptText(context, title: 'Rename', initial: pl.name);
        if (name != null) await scope.playlists.rename(pl, name);
      },
      onDelete: () => scope.playlists.delete(pl));
}
