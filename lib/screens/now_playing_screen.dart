import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart' show readMetadata;
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Loop;

import '../models/models.dart' show Song;
import '../services/app_scope.dart';
import '../services/player_service.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import '../widgets/cover.dart';
import '../widgets/nav.dart';
import '../widgets/scenery.dart';
import '../widgets/song_tile.dart';
import 'collection_screens.dart';
import 'eq_screen.dart';
import 'home_shell.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  bool _lyrics = false;
  double _dragY = 0;

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final player = scope.player;
    return Scaffold(
      backgroundColor: Clay.night,
      body: GestureDetector(
        // Swipe down to close, like Spotify.
        onVerticalDragUpdate: (d) => setState(() => _dragY = (_dragY + d.delta.dy).clamp(0.0, 400.0)),
        onVerticalDragEnd: (d) {
          if (_dragY > 120 || (d.primaryVelocity ?? 0) > 700) {
            _close();
          } else {
            setState(() => _dragY = 0);
          }
        },
        child: Transform.translate(
          offset: Offset(0, _dragY),
          child: Backdrop(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListenableBuilder(
                    listenable: Listenable.merge([player, scope.user]),
                    builder: (context, _) {
                      final song = player.current;
                      final liked = song != null && scope.user.isLiked(song.id);
                      final sleeping = player.sleepAt != null || player.sleepAfterSong;
                      return Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Close',
                                icon: Icon(Icons.keyboard_arrow_down_rounded, size: 34, color: Clay.bone),
                                onPressed: _close,
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(sleeping ? 'sleep timer on' : 'now playing', style: Clay.book(17, color: sleeping ? Clay.candle : null)),
                                ),
                              ),
                              if (song != null) _MoreMenu(song: song, onNavigate: _close) else const SizedBox(width: 48),
                            ],
                          ),
                          Expanded(
                            flex: 5,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: _lyrics && song != null
                                    ? _Lyrics(key: ValueKey('ly-${song.id}'), song: song)
                                    : Center(
                                        child: ClayRecord(
                                          spinning: player.playing,
                                          seedText: song?.album.isNotEmpty == true ? song!.album : (song?.title ?? 'starloom'),
                                          cover: _coverFor(context, song, player),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'Lyrics',
                                  icon: Icon(Icons.lyrics_rounded, color: _lyrics ? Clay.candle : Clay.ash),
                                  onPressed: () => setState(() => _lyrics = !_lyrics),
                                ),
                                Expanded(
                                  child: Column(children: [
                                    Text(
                                      song?.title ?? 'Nothing playing',
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Clay.title(29),
                                    ),
                                    const SizedBox(height: 4),
                                    GestureDetector(
                                      onTap: song == null || song.artist.isEmpty
                                          ? null
                                          : () {
                                              _close();
                                              Nav.push(ArtistScreen(name: song.artist));
                                            },
                                      child: Text(
                                        song?.subtitle ?? 'Pick a song from your library',
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Clay.book(17),
                                      ),
                                    ),
                                  ]),
                                ),
                                IconButton(
                                  tooltip: liked ? 'Unlike' : 'Like',
                                  icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: liked ? Clay.rose : Clay.ash, size: 28),
                                  onPressed: song == null ? null : () => scope.user.toggleLike(song.id),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: CandleVisualizer(player: player.player, height: 64),
                          ),
                          const SizedBox(height: 6),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Scrubber(player: player)),
                          const SizedBox(height: 8),
                          _Controls(player: player),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'Equalizer',
                                  icon: Icon(Icons.graphic_eq_rounded, color: Clay.candle),
                                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                                    builder: (_) => Scaffold(backgroundColor: Clay.night, body: const Backdrop(child: SafeArea(child: EqScreen(showBack: true)))),
                                  )),
                                ),
                                Expanded(child: VolumeSlider(player: player)),
                                IconButton(
                                  tooltip: 'Queue',
                                  icon: Icon(Icons.queue_music_rounded, color: Clay.bone),
                                  onPressed: () => showQueue(context),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Big cover from mpv if it has one, otherwise our thumbnail.
  ImageProvider? _coverFor(BuildContext context, Song? song, PlayerService player) {
    if (player.cover != null) return ResizeImage(player.cover!.image, width: 640);
    final path = AppScope.of(context).library.artPath(song?.artKey);
    return path == null ? null : FileImage(File(path));
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.song, required this.onNavigate});

  final Song song;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(Icons.more_horiz_rounded, color: Clay.bone),
      onSelected: (v) {
        switch (v) {
          case 'playlist':
            showAddToPlaylist(context, [song]);
          case 'album':
            onNavigate();
            Nav.push(AlbumScreen(albumKey: song.albumKey));
          case 'artist':
            onNavigate();
            Nav.push(ArtistScreen(name: song.artist));
          case 'sleep':
            showSleepTimer(context, player);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'playlist', child: Text('Add to playlist…')),
        if (song.album.isNotEmpty) const PopupMenuItem(value: 'album', child: Text('Go to album')),
        if (song.artist.isNotEmpty) const PopupMenuItem(value: 'artist', child: Text('Go to artist')),
        const PopupMenuItem(value: 'sleep', child: Text('Sleep timer…')),
      ],
    );
  }
}

void showSleepTimer(BuildContext context, PlayerService player) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheet) {
      Widget opt(String label, VoidCallback onTap) => ListTile(
            title: Text(label, style: TextStyle(color: Clay.bone)),
            onTap: () {
              Navigator.pop(sheet);
              onTap();
            },
          );
      final on = player.sleepAt != null || player.sleepAfterSong;
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              player.sleepAt != null
                  ? 'Sleep timer: pausing at ${TimeOfDay.fromDateTime(player.sleepAt!).format(sheet)}'
                  : player.sleepAfterSong
                      ? 'Sleep timer: pausing after this song'
                      : 'Sleep timer',
              style: Clay.title(22),
            ),
          ),
          for (final m in [5, 15, 30, 45, 60]) opt('$m minutes', () => player.setSleepTimer(Duration(minutes: m))),
          opt('End of this song', () => player.setSleepTimer(null, endOfSong: true)),
          if (on) opt('Turn off', () => player.setSleepTimer(null)),
        ]),
      );
    },
  );
}

/// The queue: drag to reorder, swipe to remove, tap to jump.
void showQueue(BuildContext context) {
  final player = AppScope.of(context).player;
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheet) => SizedBox(
      height: MediaQuery.sizeOf(sheet).height * 0.75,
      child: ListenableBuilder(
        listenable: player,
        builder: (context, _) {
          final q = player.queue;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(children: [
                  Expanded(child: Text('Queue', style: Clay.title(26))),
                  if (player.index < q.length - 1)
                    TextButton(onPressed: player.clearUpNext, child: Text('Clear up next', style: TextStyle(color: Clay.candle))),
                ]),
              ),
              Expanded(
                child: q.isEmpty
                    ? Center(child: Text('Nothing queued', style: Clay.book(17)))
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        scrollController: ScrollController(initialScrollOffset: ((player.index - 2).clamp(0, q.length) * 64).toDouble()),
                        itemCount: q.length,
                        onReorder: (from, to) => player.moveInQueue(from, to),
                        itemBuilder: (context, i) {
                          final s = q[i];
                          final isCur = i == player.index;
                          return Dismissible(
                            key: ValueKey('q-$i-${s.id}'),
                            direction: isCur ? DismissDirection.none : DismissDirection.endToStart,
                            background: Container(
                              color: Clay.rose,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 22),
                              child: Icon(Icons.delete_rounded, color: Clay.bone),
                            ),
                            onDismissed: (_) => player.removeFromQueue(i),
                            child: SizedBox(
                              height: 64,
                              child: ListTile(
                                onTap: () => player.jumpTo(i),
                                leading: Cover(artKey: s.artKey, seedText: s.album.isNotEmpty ? s.album : s.title, size: 42),
                                title: Text(
                                  s.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: isCur ? Clay.candle : Clay.bone, fontWeight: isCur ? FontWeight.w700 : FontWeight.w500),
                                ),
                                subtitle: Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.ash, fontSize: 12)),
                                trailing: ReorderableDragStartListener(index: i, child: Icon(Icons.drag_handle_rounded, color: Clay.ash)),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _Controls extends StatelessWidget {
  const _Controls({required this.player});

  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    final loopIcon = player.loop == Loop.file ? Icons.repeat_one_rounded : Icons.repeat_rounded;
    final loopOn = player.loop != Loop.off;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ClayIconButton(
          icon: Icons.shuffle_rounded,
          tooltip: 'Shuffle',
          size: 46,
          seed: 51,
          color: player.shuffle ? Clay.moss : Clay.bruise,
          iconColor: player.shuffle ? Clay.bone : Clay.ash,
          onTap: player.toggleShuffle,
        ),
        ClayIconButton(icon: Icons.skip_previous_rounded, tooltip: 'Previous', size: 58, seed: 52, onTap: player.previous),
        ClayIconButton(
          icon: player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: player.playing ? 'Pause' : 'Play',
          size: 82,
          seed: 53,
          color: Clay.pumpkin,
          boil: true,
          onTap: player.togglePlay,
        ),
        ClayIconButton(icon: Icons.skip_next_rounded, tooltip: 'Next', size: 58, seed: 54, onTap: player.next),
        ClayIconButton(
          icon: loopIcon,
          tooltip: switch (player.loop) {
            Loop.off => 'Repeat: off',
            Loop.playlist => 'Repeat: all',
            Loop.file => 'Repeat: one',
          },
          size: 46,
          seed: 55,
          color: loopOn ? Clay.moss : Clay.bruise,
          iconColor: loopOn ? Clay.bone : Clay.ash,
          onTap: player.cycleLoop,
        ),
      ],
    );
  }
}

/// Lyrics embedded in the file's tags (or a matching .lrc next to it).
class _Lyrics extends StatefulWidget {
  const _Lyrics({super.key, required this.song});

  final Song song;

  @override
  State<_Lyrics> createState() => _LyricsState();
}

class _LyricsState extends State<_Lyrics> {
  late final Future<String?> _text = _loadLyrics(widget.song.path);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _text,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
        final text = snap.data;
        return ClayBox(
          color: Clay.bruise.withValues(alpha: 0.92),
          seed: 515,
          squareness: 5,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: text == null
              ? Center(child: Text('No lyrics in this file.', style: Clay.book(18)))
              : SingleChildScrollView(
                  child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Clay.bone, fontSize: 17, height: 1.6, fontWeight: FontWeight.w600)),
                ),
        );
      },
    );
  }
}

/// Top-level so the isolate only captures the path.
Future<String?> _loadLyrics(String path) => Isolate.run(() {
      String? raw;
      final dot = path.lastIndexOf('.');
      final lrc = File('${dot > 0 ? path.substring(0, dot) : path}.lrc');
      if (lrc.existsSync()) {
        raw = lrc.readAsStringSync();
      } else {
        try {
          raw = readMetadata(File(path)).lyrics;
        } catch (_) {}
      }
      if (raw == null || raw.trim().isEmpty) return null;
      // Drop LRC timestamps like [01:23.45] and tag lines like [ar:...].
      return raw.split(RegExp(r'\r?\n')).map((l) => l.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim()).join('\n').trim();
    });
