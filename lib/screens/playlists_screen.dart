import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import '../widgets/song_tile.dart';
import 'home_shell.dart';
import 'import_screen.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.playlists, scope.library]),
      builder: (context, _) {
        final lists = scope.playlists.playlists;
        return Column(
          children: [
            ScreenHeader(
              title: 'Playlists',
              subtitle: lists.isEmpty ? 'None yet' : '${lists.length} playlists',
              trailing: [
                ClayIconButton(
                  icon: Icons.add_rounded,
                  tooltip: 'New playlist',
                  size: 46,
                  seed: 41,
                  onTap: () async {
                    final name = await promptText(context, title: 'New playlist', hint: 'Name');
                    if (name != null) await scope.playlists.create(name);
                  },
                ),
                const SizedBox(width: 8),
                ClayIconButton(
                  icon: Icons.download_rounded,
                  tooltip: 'Import from Spotify',
                  size: 46,
                  seed: 42,
                  color: Clay.pumpkin,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ImportScreen())),
                ),
              ],
            ),
            Expanded(
              child: lists.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Make a playlist with +, or bring one over from Spotify with the import button.',
                          textAlign: TextAlign.center,
                          style: Clay.book(17),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: lists.length,
                      itemBuilder: (context, i) => _PlaylistCard(playlist: lists[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final lib = AppScope.of(context).library;
    final found = playlist.songIds.where((id) => lib.byId(id) != null).length;
    final missing = playlist.missing.where((m) => !m.streaming).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Squish(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaylistScreen(playlistId: playlist.id))),
        child: ClayBox(
          color: Clay.pebbles[(playlist.id.hashCode & 0x7fffffff) % Clay.pebbles.length].withValues(alpha: 1),
          seed: playlist.id.hashCode,
          squareness: 4.5,
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(playlist.name, style: Clay.title(24), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      [songCount(found), if (missing > 0) '$missing not found'].join('  ·  '),
                      style: const TextStyle(color: Clay.bone, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Clay.bone),
            ],
          ),
        ),
      ),
    );
  }
}

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      backgroundColor: Clay.night,
      bottomNavigationBar: const SafeArea(top: false, child: Padding(padding: EdgeInsets.only(bottom: 8), child: MiniPlayer())),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              final pl = scope.playlists.byId(playlistId);
              if (pl == null) return;
              if (v == 'rename') {
                final name = await promptText(context, title: 'Rename', initial: pl.name);
                if (name != null) await scope.playlists.rename(pl, name);
              } else if (v == 'delete') {
                final nav = Navigator.of(context);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: Text('Delete "${pl.name}"?', style: Clay.title(22)),
                    content: const Text('Your song files stay where they are.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) {
                  await scope.playlists.delete(pl);
                  nav.pop();
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([scope.playlists, scope.library]),
        builder: (context, _) {
          final pl = scope.playlists.byId(playlistId);
          if (pl == null) return const SizedBox.shrink();
          // Keep playlist positions so "remove" removes the right entry.
          final entries = <(int, Song)>[];
          for (var i = 0; i < pl.songIds.length; i++) {
            final s = scope.library.byId(pl.songIds[i]);
            if (s != null) entries.add((i, s));
          }
          final songs = [for (final e in entries) e.$2];
          final missing = pl.missing.where((m) => !m.streaming).toList();
          final streaming = pl.missing.where((m) => m.streaming).length;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClayTitle(pl.name, size: 38),
                      const SizedBox(height: 4),
                      Text(
                        [songCount(songs.length), if (songs.isNotEmpty) totalLength(songs)].join('  ·  '),
                        style: Clay.book(16),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          ClayButton(
                            label: 'Play',
                            icon: Icons.play_arrow_rounded,
                            color: Clay.pumpkin,
                            onTap: songs.isEmpty ? null : () => scope.player.playSongs(songs, 0),
                          ),
                          const SizedBox(width: 12),
                          ClayButton(
                            label: 'Shuffle',
                            icon: Icons.shuffle_rounded,
                            seed: 8,
                            onTap: songs.isEmpty ? null : () => scope.player.playSongs(songs, 0, shuffled: true),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverFixedExtentList(
                itemExtent: kSongRowHeight,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => SongTile(
                    song: entries[i].$2,
                    onTap: () => scope.player.playSongs(songs, i),
                    onRemove: () => scope.playlists.removeAt(pl, entries[i].$1),
                  ),
                  childCount: entries.length,
                ),
              ),
              if (missing.isNotEmpty || streaming > 0)
                SliverToBoxAdapter(
                  child: Padding(
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
                              leading: const Icon(Icons.help_outline, color: Clay.rose, size: 20),
                              title: Text(m.label, style: const TextStyle(color: Clay.bone)),
                              trailing: m.seconds > 0
                                  ? Text(formatDuration(Duration(seconds: m.seconds)), style: const TextStyle(color: Clay.ash))
                                  : null,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          );
        },
      ),
    );
  }
}
