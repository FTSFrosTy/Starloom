import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import '../widgets/cover.dart';
import '../widgets/context_menu.dart';
import '../widgets/nav.dart';
import '../widgets/song_tile.dart';
import 'collection_screens.dart';
import 'home_shell.dart';
import 'import_screen.dart';

export 'collection_screens.dart' show PlaylistScreen;

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.playlists, scope.library, scope.user]),
      builder: (context, _) {
        final lists = scope.playlists.playlists;
        final likedCount = scope.user.liked.where((id) => scope.library.byId(id) != null).length;
        return Column(
          children: [
            ScreenHeader(
              title: 'Playlists',
              subtitle: '${lists.length} playlists',
              trailing: [
                ClayIconButton(
                  icon: Icons.add_rounded,
                  tooltip: 'New playlist',
                  size: 46,
                  seed: 41,
                  onTap: () async {
                    final name = await promptText(context, title: 'New playlist', hint: 'Name');
                    if (name == null) return;
                    final pl = await scope.playlists.create(name);
                    Nav.push(PlaylistScreen(playlistId: pl.id));
                  },
                ),
                const SizedBox(width: 8),
                ClayIconButton(
                  icon: Icons.download_rounded,
                  tooltip: 'Import from Spotify',
                  size: 46,
                  seed: 42,
                  color: Clay.pumpkin,
                  onTap: () => Nav.push(const ImportScreen()),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  _PlaylistCard(
                    title: 'Liked Songs',
                    subtitle: songCount(likedCount),
                    art: Mosaic(artKeys: const [], seedText: 'liked', size: 62, icon: Icons.favorite_rounded),
                    seed: 1,
                    onTap: () => Nav.push(const LikedScreen()),
                  ),
                  for (final pl in lists) _card(context, pl),
                  if (lists.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Make a playlist with +, or bring one over from Spotify with the import button.',
                        textAlign: TextAlign.center,
                        style: Clay.book(17),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _card(BuildContext context, Playlist pl) {
    final lib = AppScope.of(context).library;
    final songs = [for (final id in pl.songIds) ?lib.byId(id)];
    final missing = pl.missing.where((m) => !m.streaming).length;
    return _PlaylistCard(
      onMenu: (at) => playlistMenu(context, at, pl),
      title: pl.name,
      subtitle: [songCount(songs.length), if (missing > 0) '$missing not found'].join('  ·  '),
      art: Mosaic(artKeys: [for (final s in songs) ?s.artKey], seedText: pl.id, size: 62),
      seed: pl.id.hashCode,
      onTap: () => Nav.push(PlaylistScreen(playlistId: pl.id)),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.title, required this.subtitle, required this.art, required this.seed, required this.onTap, this.onMenu});

  final void Function(Offset)? onMenu;

  final String title;
  final String subtitle;
  final Widget art;
  final int seed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RightClick(
        onMenu: (at) => onMenu?.call(at),
        child: Squish(
        onTap: onTap,
        child: ClayBox(
          color: Clay.bruise,
          seed: seed,
          squareness: 4.5,
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Row(
            children: [
              art,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Clay.title(23), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(subtitle, style: TextStyle(color: Clay.ash, fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Clay.bone),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
