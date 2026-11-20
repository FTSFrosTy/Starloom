import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import '../widgets/cover.dart';
import '../widgets/context_menu.dart';
import '../widgets/nav.dart';
import '../widgets/song_tile.dart';
import 'home_shell.dart';

/// Big header + Play/Shuffle + song list. Used by albums, artists,
/// playlists, Liked Songs and the "recently played" style lists.
class CollectionView extends StatelessWidget {
  const CollectionView({
    super.key,
    required this.title,
    required this.subtitle,
    required this.art,
    required this.songs,
    this.actions = const [],
    this.numbered = false,
    this.onRemove,
    this.footer,
    this.extraHeader,
    this.emptyText = 'No songs here yet.',
  });

  final String title;
  final String subtitle;
  final Widget art;
  final List<Song> songs;
  final List<Widget> actions;
  final bool numbered;

  /// When set, rows get "Remove from this playlist" (gets the row index).
  final void Function(int index)? onRemove;
  final Widget? footer;
  final Widget? extraHeader;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final wide = isWide(context);
    final canPop = Navigator.of(context).canPop();
    final menuArt = RightClick(onMenu: (at) => songsMenu(context, at, songs, title: title), child: art);
    final info = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClayTitle(title, size: wide ? 46 : 36),
        const SizedBox(height: 4),
        Text(subtitle, textAlign: wide ? TextAlign.start : TextAlign.center, style: Clay.book(16)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          alignment: wide ? WrapAlignment.start : WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ClayButton(
              label: 'Play',
              icon: Icons.play_arrow_rounded,
              color: Clay.pumpkin,
              onTap: songs.isEmpty ? null : () => scope.player.playSongs(songs, 0, from: title),
            ),
            ClayButton(
              label: 'Shuffle',
              icon: Icons.shuffle_rounded,
              seed: 8,
              onTap: songs.isEmpty ? null : () => scope.player.playSongs(songs, 0, shuffled: true, from: title),
            ),
            ...actions,
          ],
        ),
      ],
    );
    final header = Padding(
      padding: EdgeInsets.fromLTRB(wide ? 28 : 20, canPop ? 0 : 16, 20, 14),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [menuArt, const SizedBox(width: 26), Expanded(child: info)])
          : Column(children: [menuArt, const SizedBox(height: 16), info]),
    );

    return CustomScrollView(
      slivers: [
        if (canPop)
          SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 0, 0),
                child: IconButton(
                  tooltip: 'Back',
                  icon: Icon(Icons.arrow_back_ios_new_rounded, color: Clay.bone, size: 20),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(child: header),
        if (extraHeader != null) SliverToBoxAdapter(child: extraHeader),
        if (songs.isEmpty)
          SliverToBoxAdapter(
            child: Padding(padding: const EdgeInsets.all(32), child: Text(emptyText, textAlign: TextAlign.center, style: Clay.book(17))),
          ),
        SliverFixedExtentList(
          itemExtent: kSongRowHeight,
          delegate: SliverChildBuilderDelegate(
            (context, i) => SongTile(
              song: songs[i],
              leadingNumber: numbered ? (songs[i].trackNo > 0 ? songs[i].trackNo : i + 1) : null,
              onTap: () => scope.player.playSongs(songs, i, from: title),
              onRemove: onRemove == null ? null : () => onRemove!(i),
            ),
            childCount: songs.length,
          ),
        ),
        if (footer != null) SliverToBoxAdapter(child: footer),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

/// Remembers which collection was opened (for "Jump back in" on Home).
mixin _RecordsVisit<T extends StatefulWidget> on State<T> {
  String get visitKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).user.recordCollection(visitKey);
    });
  }
}

class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key, required this.albumKey});

  final String albumKey;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> with _RecordsVisit<AlbumScreen> {
  @override
  String get visitKey => 'album:${widget.albumKey}';

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.library,
      builder: (context, _) {
        final album = scope.library.albumByKey(widget.albumKey);
        if (album == null) return Center(child: Text('Album not found', style: Clay.book(18)));
        return CollectionView(
          title: album.name,
          subtitle: '${album.artist}  ·  ${songCount(album.songs.length)}  ·  ${totalLength(album.songs)}',
          art: Cover(artKey: album.artKey, seedText: album.name, size: isWide(context) ? 200 : 210),
          songs: album.songs,
          numbered: true,
          actions: [
            ClayButton(
              label: album.artist,
              icon: Icons.person_rounded,
              seed: 12,
              onTap: () => Nav.push(ArtistScreen(name: album.artist)),
            ),
          ],
        );
      },
    );
  }
}

class ArtistScreen extends StatefulWidget {
  const ArtistScreen({super.key, required this.name});

  final String name;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> with _RecordsVisit<ArtistScreen> {
  @override
  String get visitKey => 'artist:${widget.name}';

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.library, scope.user]),
      builder: (context, _) {
        final artist = scope.library.artistByName(widget.name);
        if (artist == null) return Center(child: Text('Artist not found', style: Clay.book(18)));
        // Most played first, like an artist's "Popular" list.
        final songs = List<Song>.of(artist.songs)
          ..sort((a, b) => (scope.user.plays[b.id] ?? 0).compareTo(scope.user.plays[a.id] ?? 0));
        return CollectionView(
          title: artist.name,
          subtitle: [songCount(artist.songs.length), if (artist.albums.isNotEmpty) '${artist.albums.length} albums'].join('  ·  '),
          art: ClipOval(child: Cover(artKey: artist.artKey, seedText: artist.name, size: 190, radius: 95)),
          songs: songs,
          extraHeader: artist.albums.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AlbumRow(title: 'Albums', albums: artist.albums),
                ),
        );
      },
    );
  }
}

class LikedScreen extends StatefulWidget {
  const LikedScreen({super.key});

  @override
  State<LikedScreen> createState() => _LikedScreenState();
}

class _LikedScreenState extends State<LikedScreen> with _RecordsVisit<LikedScreen> {
  @override
  String get visitKey => 'liked';

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.library, scope.user]),
      builder: (context, _) {
        final songs = [for (final id in scope.user.liked) ?scope.library.byId(id)];
        return CollectionView(
          title: 'Liked Songs',
          subtitle: songCount(songs.length),
          art: Mosaic(artKeys: const [], seedText: 'liked', size: 190, icon: Icons.favorite_rounded),
          songs: songs,
          emptyText: 'Tap the heart on any song to save it here.',
        );
      },
    );
  }
}

/// A plain list of songs with a title (Recently played, Most played…).
class SongListScreen extends StatelessWidget {
  const SongListScreen({super.key, required this.title, required this.songs, required this.icon});

  final String title;
  final List<Song> songs;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CollectionView(
      title: title,
      subtitle: songCount(songs.length),
      art: Mosaic(artKeys: const [], seedText: title, size: 170, icon: icon),
      songs: songs,
    );
  }
}

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> with _RecordsVisit<PlaylistScreen> {
  bool _editing = false;

  @override
  String get visitKey => 'playlist:${widget.playlistId}';

  Future<void> _rename(Playlist pl) async {
    final name = await promptText(context, title: 'Rename', initial: pl.name);
    if (name != null && mounted) await AppScope.of(context).playlists.rename(pl, name);
  }

  Future<void> _delete(Playlist pl) async {
    final scope = AppScope.of(context);
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (d) => AlertDialog(
        title: Text('Delete "${pl.name}"?', style: Clay.title(22)),
        content: Text('Your song files stay where they are.', style: TextStyle(color: Clay.bone)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await scope.playlists.delete(pl);
      nav.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.playlists, scope.library]),
      builder: (context, _) {
        final pl = scope.playlists.byId(widget.playlistId);
        if (pl == null) return const SizedBox.shrink();
        // Keep playlist positions so "remove" removes the right entry.
        final positions = <int>[];
        final songs = <Song>[];
        for (var i = 0; i < pl.songIds.length; i++) {
          final s = scope.library.byId(pl.songIds[i]);
          if (s != null) {
            positions.add(i);
            songs.add(s);
          }
        }
        if (_editing) return _EditList(playlist: pl, songs: songs, positions: positions, onDone: () => setState(() => _editing = false));

        final missing = pl.missing.where((m) => !m.streaming).toList();
        final streaming = pl.missing.where((m) => m.streaming).length;
        return CollectionView(
          title: pl.name,
          subtitle: [songCount(songs.length), if (songs.isNotEmpty) totalLength(songs)].join('  ·  '),
          art: Mosaic(artKeys: [for (final s in songs) ?s.artKey], seedText: pl.id, size: isWide(context) ? 200 : 210),
          songs: songs,
          onRemove: (i) => scope.playlists.removeAt(pl, positions[i]),
          emptyText: 'Empty playlist. Tap "Add songs" to fill it.',
          actions: [
            ClayButton(label: 'Add songs', icon: Icons.add_rounded, seed: 14, onTap: () => showSongPicker(context, pl)),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(Icons.more_horiz_rounded, color: Clay.bone),
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    setState(() => _editing = true);
                  case 'rename':
                    _rename(pl);
                  case 'delete':
                    _delete(pl);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Reorder songs')),
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
              ],
            ),
          ],
          footer: missing.isEmpty && streaming == 0
              ? null
              : Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      iconColor: Clay.ash,
                      collapsedIconColor: Clay.ash,
                      title: Text(
                        [
                          if (missing.isNotEmpty) '${missing.length} not found in your folders',
                          if (streaming > 0) '$streaming were Spotify-only songs',
                        ].join('  ·  '),
                        style: Clay.book(16),
                      ),
                      children: [
                        for (final m in missing)
                          ListTile(
                            dense: true,
                            leading: Icon(Icons.help_outline, color: Clay.rose, size: 20),
                            title: Text(m.label, style: TextStyle(color: Clay.bone)),
                            trailing: m.seconds > 0 ? Text(formatDuration(Duration(seconds: m.seconds)), style: TextStyle(color: Clay.ash)) : null,
                          ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// Drag-to-reorder mode for a playlist.
class _EditList extends StatelessWidget {
  const _EditList({required this.playlist, required this.songs, required this.positions, required this.onDone});

  final Playlist playlist;
  final List<Song> songs;
  final List<int> positions;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).playlists;
    return Column(
      children: [
        ScreenHeader(
          title: 'Reorder',
          subtitle: 'Drag the handles. Swipe left to remove.',
          trailing: [ClayButton(label: 'Done', icon: Icons.check_rounded, color: Clay.pumpkin, onTap: onDone)],
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: songs.length,
            onReorder: (from, to) => store.move(playlist, positions[from], to >= positions.length ? playlist.songIds.length : positions[to]),
            itemBuilder: (context, i) {
              final s = songs[i];
              return Dismissible(
                key: ValueKey('edit-$i-${s.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Clay.rose,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 22),
                  child: Icon(Icons.delete_rounded, color: Clay.bone),
                ),
                onDismissed: (_) => store.removeAt(playlist, positions[i]),
                child: ListTile(
                  leading: Cover(artKey: s.artKey, seedText: s.album.isNotEmpty ? s.album : s.title, size: 42),
                  title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.bone)),
                  subtitle: Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.ash)),
                  trailing: ReorderableDragStartListener(index: i, child: Icon(Icons.drag_handle_rounded, color: Clay.ash)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Search the library and tick songs to add to [pl].
Future<void> showSongPicker(BuildContext context, Playlist pl) {
  final scope = AppScope.of(context);
  final picked = <String>{};
  var query = '';
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (context, setState) {
        final all = scope.library.sorted(scope.prefs.sort);
        final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        final songs = words.isEmpty ? all : all.where((s) => words.every(s.searchKey.contains)).toList();
        return SizedBox(
          height: MediaQuery.sizeOf(sheet).height * 0.85,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(children: [
                  Expanded(child: Text('Add to ${pl.name}', style: Clay.title(22), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ClayButton(
                    label: picked.isEmpty ? 'Done' : 'Add ${picked.length}',
                    color: Clay.pumpkin,
                    onTap: () {
                      Navigator.pop(sheet);
                      if (picked.isNotEmpty) scope.playlists.addSongs(pl, [for (final s in all) if (picked.contains(s.id)) s.id]);
                    },
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  style: TextStyle(color: Clay.bone),
                  decoration: InputDecoration(hintText: 'Search your library', prefixIcon: Icon(Icons.search, color: Clay.ash)),
                  onChanged: (v) => setState(() => query = v),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.builder(
                  itemExtent: 60,
                  itemCount: songs.length,
                  itemBuilder: (context, i) {
                    final s = songs[i];
                    final on = picked.contains(s.id);
                    return ListTile(
                      onTap: () => setState(() => on ? picked.remove(s.id) : picked.add(s.id)),
                      leading: Cover(artKey: s.artKey, seedText: s.album.isNotEmpty ? s.album : s.title, size: 40),
                      title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.bone)),
                      subtitle: Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.ash, fontSize: 12)),
                      trailing: Icon(on ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, color: on ? Clay.candle : Clay.ash),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Horizontal row of album cards with a heading.
class AlbumRow extends StatelessWidget {
  const AlbumRow({super.key, required this.title, required this.albums});

  final String title;
  final List<Album> albums;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), child: Text(title, style: Clay.title(24))),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: albums.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) => AlbumCard(album: albums[i]),
          ),
        ),
      ],
    );
  }
}

class AlbumCard extends StatelessWidget {
  const AlbumCard({super.key, required this.album, this.size = 140});

  final Album album;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: RightClick(
        onMenu: (at) => songsMenu(context, at, album.songs, albumArtist: album.artist),
        child: Squish(
        onTap: () => Nav.push(AlbumScreen(albumKey: album.key)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Cover(artKey: album.artKey, seedText: album.name, size: size),
            const SizedBox(height: 8),
            Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w700, fontSize: 13.5)),
            Text(album.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.ash, fontSize: 12)),
          ],
        ),
      ),
      ),
    );
  }
}
