import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Loop;

import '../models/models.dart' show Song;
import '../services/app_scope.dart';
import '../services/player_service.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import '../widgets/context_menu.dart';
import '../widgets/devices.dart';
import '../widgets/panels.dart';
import '../widgets/ui_fx.dart';
import '../widgets/nav.dart';
import '../widgets/scenery.dart';
import '../widgets/song_tile.dart';
import '../widgets/visualizer.dart';
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
              child: LayoutBuilder(builder: (context, box) {
                final side = box.maxWidth >= 1000;
                final main = ConstrainedBox(
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
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    Text(
                                      sleeping ? 'sleep timer on' : (player.playingFrom == null ? 'now playing' : 'playing from'),
                                      style: Clay.book(player.playingFrom == null ? 17 : 13, color: sleeping ? Clay.candle : null),
                                    ),
                                    if (player.playingFrom != null)
                                      Text(player.playingFrom!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w800, fontSize: 14)),
                                    const CastBanner(),
                                  ]),
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
                                child: _lyrics && song != null && !side
                                    ? LyricsView(key: ValueKey('ly-${song.id}'), song: song)
                                    : RightClick(
                                        onMenu: (at) => song == null ? null : songMenu(context, at, song),
                                        child: Center(
                                        child: ClayRecord(
                                          spinning: player.playing,
                                          seedText: song?.album.isNotEmpty == true ? song!.album : (song?.title ?? 'starloom'),
                                          cover: _coverFor(context, song, player),
                                        ),
                                      ),
                                      ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                if (!side) IconButton(
                                  tooltip: 'Lyrics',
                                  icon: Icon(Icons.lyrics_rounded, color: _lyrics ? Clay.candle : Clay.ash),
                                  onPressed: () => setState(() => _lyrics = !_lyrics),
                                ),
                                Expanded(
                                  child: RightClick(
                                  onMenu: (at) => song == null ? null : songMenu(context, at, song),
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
                            child: ThemeVisualizer(player: player.player, height: 110),
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
                                const DevicesButton(),
                                Expanded(child: VolumeSlider(player: player)),
                                if (!side)
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
                );
                if (!side) return Center(child: main);
                return Row(children: [
                  Expanded(flex: 5, child: Center(child: main)),
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 16, 24, 16),
                      child: ClayBox(
                        color: Clay.panel.withValues(alpha: 0.92),
                        seed: 4242,
                        squareness: 6,
                        wobble: 0.5,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: _SideColumn(lyrics: _lyrics, onLyrics: (v) => setState(() => _lyrics = v)),
                      ),
                    ),
                  ),
                ]);
              }),
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
          case 'savequeue':
            saveQueueAsPlaylist(context);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'playlist', child: Text('Add to playlist…')),
        if (song.album.isNotEmpty) const PopupMenuItem(value: 'album', child: Text('Go to album')),
        if (song.artist.isNotEmpty) const PopupMenuItem(value: 'artist', child: Text('Go to artist')),
        const PopupMenuItem(value: 'sleep', child: Text('Sleep timer…')),
        const PopupMenuItem(value: 'savequeue', child: Text('Save queue as playlist…')),
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
        BeatGlow(
          player: player,
          spread: 1.3,
          child: ClayIconButton(
            icon: player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: player.playing ? 'Pause' : 'Play',
            size: 82,
            seed: 53,
            color: Clay.pumpkin,
            boil: true,
            onTap: player.togglePlay,
          ),
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


/// Wide windows: the full player gets a column for the queue or lyrics
/// beside it instead of empty space.
class _SideColumn extends StatelessWidget {
  const _SideColumn({required this.lyrics, required this.onLyrics});

  final bool lyrics;
  final ValueChanged<bool> onLyrics;

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    Widget tab(String label, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Squish(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(color: on ? Clay.candle : Clay.bruise.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(20)),
              child: Text(label, style: TextStyle(color: on ? Clay.onAccent : Clay.bone, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [tab('Up next', !lyrics, () => onLyrics(false)), tab('Lyrics', lyrics, () => onLyrics(true))]),
      const SizedBox(height: 10),
      Expanded(
        child: lyrics
            ? ValueListenableBuilder<String?>(
                valueListenable: player.currentId,
                builder: (context, _, _) {
                  final song = player.current;
                  if (song == null) return Center(child: Text('Nothing playing', style: Clay.book(16)));
                  return LyricsView(key: ValueKey(song.id), song: song, boxed: false);
                },
              )
            : const QueueList(compact: true),
      ),
    ]);
  }
}
