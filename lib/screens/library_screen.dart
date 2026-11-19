import 'dart:io';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../services/library.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import '../widgets/song_tile.dart';
import 'home_shell.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Song> _filter(List<Song> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    final words = q.split(RegExp(r'\s+'));
    return all.where((s) => words.every(s.searchKey.contains)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.library, scope.prefs]),
      builder: (context, _) {
        final lib = scope.library;
        final songs = _filter(lib.sorted(scope.prefs.sort));
        return Column(
          children: [
            ScreenHeader(
              title: 'Library',
              subtitle: lib.scanning ? (lib.status ?? 'Scanning…') : songCount(lib.songs.length),
              trailing: [
                PopupMenuButton<SortMode>(
                  tooltip: 'Sort',
                  icon: const Icon(Icons.sort_rounded, color: Clay.bone),
                  initialValue: scope.prefs.sort,
                  onSelected: scope.prefs.setSort,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: SortMode.title, child: Text('Title')),
                    PopupMenuItem(value: SortMode.artist, child: Text('Artist')),
                    PopupMenuItem(value: SortMode.added, child: Text('Recently added')),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ClayIconButton(
                    icon: Icons.shuffle_rounded,
                    tooltip: 'Shuffle all',
                    size: 46,
                    color: Clay.pumpkin,
                    seed: 31,
                    boil: true,
                    onTap: songs.isEmpty ? null : () => scope.player.playSongs(songs, 0, shuffled: true),
                  ),
                ),
              ],
            ),
            if (lib.songs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, albums',
                    prefixIcon: const Icon(Icons.search, color: Clay.ash),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, color: Clay.ash),
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                          ),
                  ),
                ),
              ),
            Expanded(
              child: lib.songs.isEmpty
                  ? _Empty(scanning: lib.scanning)
                  : songs.isEmpty
                      ? Center(child: Text('Nothing matches "$_query"', style: Clay.book(17)))
                      : Scrollbar(
                          child: ListView.builder(
                            itemExtent: kSongRowHeight,
                            itemCount: songs.length,
                            itemBuilder: (context, i) => SongTile(
                              song: songs[i],
                              onTap: () => scope.player.playSongs(songs, i),
                            ),
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.scanning});

  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final lib = AppScope.of(context).library;
    if (scanning) {
      return Center(child: Text('Digging up your songs…', style: Clay.book(18)));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ClayBox(
          color: Clay.bruise,
          seed: 88,
          boil: true,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No songs yet', style: Clay.title(28)),
              const SizedBox(height: 10),
              Text(
                Platform.isIOS
                    ? 'Pick the folder your music is in (for example On My iPhone › Spotify), '
                        'or copy songs into On My iPhone › Starloom.'
                    : 'Pick the folder your music is in.',
                textAlign: TextAlign.center,
                style: Clay.book(16, color: Clay.bone),
              ),
              const SizedBox(height: 18),
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
          ),
        ),
      ),
    );
  }
}
