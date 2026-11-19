import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_scope.dart';
import '../services/library.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import '../widgets/cover.dart';
import '../widgets/nav.dart';
import '../widgets/song_tile.dart';
import 'collection_screens.dart';
import 'home_shell.dart';

enum _View { songs, albums, artists }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();
  String _query = '';
  _View _view = _View.songs;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> get _words => _query.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.library, scope.prefs]),
      builder: (context, _) {
        final lib = scope.library;
        final words = _words;
        return Column(
          children: [
            ScreenHeader(
              title: 'Library',
              subtitle: lib.scanning ? (lib.status ?? 'Scanning…') : '${songCount(lib.songs.length)}  ·  ${lib.albums.length} albums  ·  ${lib.artists.length} artists',
              trailing: [
                if (_view == _View.songs)
                  PopupMenuButton<SortMode>(
                    tooltip: 'Sort',
                    icon: Icon(Icons.sort_rounded, color: Clay.bone),
                    initialValue: scope.prefs.sort,
                    onSelected: scope.prefs.setSort,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: SortMode.title, child: Text('Title')),
                      PopupMenuItem(value: SortMode.artist, child: Text('Artist')),
                      PopupMenuItem(value: SortMode.added, child: Text('Recently added')),
                    ],
                  ),
              ],
            ),
            if (lib.songs.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(color: Clay.bone),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, albums',
                    prefixIcon: Icon(Icons.search, color: Clay.ash),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: Icon(Icons.close, color: Clay.ash),
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Row(children: [
                  for (final v in _View.values) ...[
                    _Chip(
                      label: switch (v) { _View.songs => 'Songs', _View.albums => 'Albums', _View.artists => 'Artists' },
                      selected: _view == v,
                      seed: v.index + 300,
                      onTap: () => setState(() => _view = v),
                    ),
                    const SizedBox(width: 8),
                  ],
                ]),
              ),
            ],
            Expanded(
              child: lib.songs.isEmpty
                  ? _Empty(scanning: lib.scanning)
                  : switch (_view) {
                      _View.songs => _songs(lib, words),
                      _View.albums => _albums(lib, words),
                      _View.artists => _artists(lib, words),
                    },
            ),
          ],
        );
      },
    );
  }

  Widget _songs(Library lib, List<String> words) {
    final all = lib.sorted(AppScope.of(context).prefs.sort);
    final songs = words.isEmpty ? all : all.where((s) => words.every(s.searchKey.contains)).toList();
    if (songs.isEmpty) return _noMatch();
    final player = AppScope.of(context).player;
    return Scrollbar(
      child: ListView.builder(
        itemExtent: kSongRowHeight,
        itemCount: songs.length,
        itemBuilder: (context, i) => SongTile(song: songs[i], onTap: () => player.playSongs(songs, i)),
      ),
    );
  }

  Widget _albums(Library lib, List<String> words) {
    final albums = words.isEmpty
        ? lib.albums
        : lib.albums.where((a) => words.every('${a.name} ${a.artist}'.toLowerCase().contains)).toList();
    if (albums.isEmpty) return _noMatch();
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 170).floor().clamp(2, 8);
      final size = (c.maxWidth - 32 - (cols - 1) * 14) / cols;
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: 14, mainAxisSpacing: 16, mainAxisExtent: size + 50),
        itemCount: albums.length,
        itemBuilder: (context, i) => AlbumCard(album: albums[i], size: size),
      );
    });
  }

  Widget _artists(Library lib, List<String> words) {
    final artists = words.isEmpty ? lib.artists : lib.artists.where((a) => words.every(a.name.toLowerCase().contains)).toList();
    if (artists.isEmpty) return _noMatch();
    return ListView.builder(
      itemExtent: 70,
      itemCount: artists.length,
      itemBuilder: (context, i) {
        final a = artists[i];
        return ListTile(
          onTap: () => Nav.push(ArtistScreen(name: a.name)),
          leading: ClipOval(child: Cover(artKey: a.artKey, seedText: a.name, size: 50, radius: 25)),
          title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w600)),
          subtitle: Text(
            [songCount(a.songs.length), if (a.albums.isNotEmpty) '${a.albums.length} albums'].join('  ·  '),
            style: TextStyle(color: Clay.ash, fontSize: 12.5),
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: Clay.ash),
        );
      },
    );
  }

  Widget _noMatch() => Center(child: Text('Nothing matches "$_query"', style: Clay.book(17)));
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, required this.seed});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return Squish(
      onTap: onTap,
      child: ClayBox(
        color: selected ? Clay.pumpkin : Clay.bruise,
        seed: seed,
        squareness: 3,
        depth: 3,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Text(label, style: TextStyle(color: selected ? Clay.onAccent : Clay.bone, fontWeight: FontWeight.w700, fontSize: 13.5)),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.scanning});

  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final lib = AppScope.of(context).library;
    if (scanning) return Center(child: Text('Digging up your songs…', style: Clay.book(18)));
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
