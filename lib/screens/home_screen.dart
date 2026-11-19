import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import '../widgets/cover.dart';
import '../widgets/nav.dart';
import 'collection_screens.dart';
import 'home_shell.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Up late';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.library, scope.playlists, scope.user]),
      builder: (context, _) {
        final lib = scope.library;
        final user = scope.user;
        final wide = isWide(context);

        if (lib.songs.isEmpty) {
          return ListView(children: [
            ScreenHeader(title: _greeting()),
            Padding(
              padding: const EdgeInsets.all(24),
              child: ClayBox(
                color: Clay.bruise,
                seed: 88,
                boil: true,
                padding: const EdgeInsets.all(22),
                child: Column(children: [
                  Text(lib.scanning ? 'Digging up your songs…' : 'No songs yet', style: Clay.title(28)),
                  const SizedBox(height: 10),
                  Text(
                    lib.scanning
                        ? (lib.status ?? '')
                        : 'Add the folder your music lives in from Library or Settings. '
                            'On PC, pick something like Desktop › Spotify Phone.',
                    textAlign: TextAlign.center,
                    style: Clay.book(16, color: Clay.bone),
                  ),
                  if (!lib.scanning) ...[
                    const SizedBox(height: 16),
                    ClayButton(
                      label: 'Add a music folder',
                      icon: Icons.create_new_folder_rounded,
                      color: Clay.pumpkin,
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final err = await lib.addFolder();
                        if (err != null) messenger.showSnackBar(SnackBar(content: Text(err)));
                      },
                    ),
                  ],
                ]),
              ),
            ),
          ]);
        }

        final recentSongs = [for (final id in user.recent.take(50)) ?lib.byId(id)];
        final topSongs = [for (final id in user.mostPlayed()) ?lib.byId(id)];
        final liked = [for (final id in user.liked) ?lib.byId(id)];

        // Quick tiles: Liked, Recently played, Most played, then recent stuff.
        final tiles = <_QuickTile>[
          _QuickTile('Liked Songs', null, Icons.favorite_rounded, () => Nav.push(const LikedScreen())),
          if (recentSongs.isNotEmpty)
            _QuickTile('Recently played', recentSongs.first.artKey, Icons.history_rounded,
                () => Nav.push(SongListScreen(title: 'Recently played', songs: recentSongs, icon: Icons.history_rounded))),
          if (topSongs.isNotEmpty)
            _QuickTile('Most played', topSongs.first.artKey, Icons.local_fire_department_rounded,
                () => Nav.push(SongListScreen(title: 'Most played', songs: topSongs, icon: Icons.local_fire_department_rounded))),
          for (final key in user.recentCollections) ?_tileFor(context, key),
          for (final pl in scope.playlists.playlists) _playlistTile(context, pl),
        ];
        final seen = <String>{};
        final uniqueTiles = [for (final t in tiles) if (seen.add(t.title)) t].take(wide ? 8 : 6).toList();

        final albums = lib.albums;
        final recentAlbums = List<Album>.of(albums)
          ..sort((a, b) => b.songs.map((s) => s.modifiedMs).reduce((x, y) => x > y ? x : y).compareTo(a.songs.map((s) => s.modifiedMs).reduce((x, y) => x > y ? x : y)));

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ScreenHeader(
              title: _greeting(),
              subtitle: '${songCount(lib.songs.length)}${liked.isNotEmpty ? '  ·  ${liked.length} liked' : ''}',
              trailing: [
                ClayIconButton(
                  icon: Icons.shuffle_rounded,
                  tooltip: 'Shuffle everything',
                  size: 48,
                  color: Clay.pumpkin,
                  seed: 31,
                  boil: true,
                  onTap: () => scope.player.playSongs(lib.songs, 0, shuffled: true),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth > 700 ? 4 : 2;
                final w = (c.maxWidth - (cols - 1) * 10) / cols;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [for (final t in uniqueTiles) SizedBox(width: w, child: _QuickTileView(tile: t))],
                );
              }),
            ),
            if (recentSongs.isNotEmpty) _SongRow(title: 'Jump back in', songs: recentSongs.take(20).toList()),
            if (recentAlbums.isNotEmpty) AlbumRow(title: 'Recently added', albums: recentAlbums.take(20).toList()),
            if (topSongs.length >= 5) _SongRow(title: 'On repeat', songs: topSongs.take(20).toList()),
            if (albums.length > 4) AlbumRow(title: 'Your albums', albums: albums.take(30).toList()),
          ],
        );
      },
    );
  }

  _QuickTile? _tileFor(BuildContext context, String key) {
    final scope = AppScope.of(context);
    if (key.startsWith('playlist:')) {
      final pl = scope.playlists.byId(key.substring(9));
      return pl == null ? null : _playlistTile(context, pl);
    }
    if (key.startsWith('album:')) {
      final a = scope.library.albumByKey(key.substring(6));
      return a == null ? null : _QuickTile(a.name, a.artKey, Icons.album_rounded, () => Nav.push(AlbumScreen(albumKey: a.key)));
    }
    if (key.startsWith('artist:')) {
      final a = scope.library.artistByName(key.substring(7));
      return a == null ? null : _QuickTile(a.name, a.artKey, Icons.person_rounded, () => Nav.push(ArtistScreen(name: a.name)));
    }
    return null;
  }

  _QuickTile _playlistTile(BuildContext context, Playlist pl) {
    final lib = AppScope.of(context).library;
    final art = pl.songIds.map(lib.byId).map((s) => s?.artKey).whereType<String>().firstOrNull;
    return _QuickTile(pl.name, art, Icons.queue_music_rounded, () => Nav.push(PlaylistScreen(playlistId: pl.id)));
  }
}

class _QuickTile {
  _QuickTile(this.title, this.artKey, this.icon, this.onTap);
  final String title;
  final String? artKey;
  final IconData icon;
  final VoidCallback onTap;
}

class _QuickTileView extends StatelessWidget {
  const _QuickTileView({required this.tile});

  final _QuickTile tile;

  @override
  Widget build(BuildContext context) {
    return Squish(
      onTap: tile.onTap,
      child: ClayBox(
        color: Clay.bruise,
        seed: tile.title.hashCode,
        squareness: 5,
        depth: 4,
        padding: const EdgeInsets.all(6),
        child: Row(children: [
          tile.artKey != null
              ? Cover(artKey: tile.artKey, seedText: tile.title, size: 44)
              : Mosaic(artKeys: const [], seedText: tile.title, size: 44, icon: tile.icon),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tile.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w700, fontSize: 13.5)),
          ),
        ]),
      ),
    );
  }
}

/// Horizontal row of song cards; tapping plays from that song.
class _SongRow extends StatelessWidget {
  const _SongRow({required this.title, required this.songs});

  final String title;
  final List<Song> songs;

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 8), child: Text(title, style: Clay.title(24))),
        SizedBox(
          height: 186,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: songs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final s = songs[i];
              return SizedBox(
                width: 130,
                child: Squish(
                  onTap: () => player.playSongs(songs, i),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Cover(artKey: s.artKey, seedText: s.album.isNotEmpty ? s.album : s.title, size: 130),
                      const SizedBox(height: 8),
                      Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(s.artist.isEmpty ? 'Unknown artist' : s.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.ash, fontSize: 12)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
