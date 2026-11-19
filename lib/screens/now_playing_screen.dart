import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../models/models.dart' show formatDuration;
import '../services/app_scope.dart';
import '../services/player_service.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import '../widgets/scenery.dart';
import 'eq_screen.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListenableBuilder(
                listenable: player,
                builder: (context, _) {
                  final song = player.current;
                  return Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Close',
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 34, color: Clay.bone),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          Expanded(child: Center(child: Text('now playing', style: Clay.book(17)))),
                          IconButton(
                            tooltip: 'Queue',
                            icon: const Icon(Icons.queue_music_rounded, color: Clay.bone),
                            onPressed: () => _showQueue(context, player),
                          ),
                        ],
                      ),
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 8),
                          child: Center(
                            child: ClayRecord(
                              spinning: player.playing,
                              seedText: song?.album.isNotEmpty == true ? song!.album : (song?.title ?? 'starloom'),
                              cover: player.cover == null ? null : ResizeImage(player.cover!.image, width: 512),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            Text(
                              song?.title ?? 'Nothing playing',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Clay.title(30),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              song?.subtitle ?? 'Pick a song from your library',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Clay.book(17),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: CandleVisualizer(player: player.player, height: 76),
                      ),
                      const SizedBox(height: 6),
                      _Scrubber(player: player),
                      const SizedBox(height: 8),
                      _Controls(player: player),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => const Scaffold(backgroundColor: Clay.night, body: SafeArea(child: EqScreen(showBack: true))),
                              )),
                              icon: const Icon(Icons.graphic_eq_rounded, color: Clay.candle),
                              label: const Text('Equalizer', style: TextStyle(color: Clay.candle)),
                            ),
                            const SizedBox(width: 8),
                            if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) ...[
                              const Icon(Icons.volume_down_rounded, color: Clay.ash),
                              Expanded(
                                child: ClaySlider(
                                  value: player.volume / 100,
                                  thickness: 28,
                                  color: Clay.ghost,
                                  seed: 71,
                                  onChanged: (v) => player.setVolume(v * 100),
                                ),
                              ),
                              const Icon(Icons.volume_up_rounded, color: Clay.ash),
                            ],
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
    );
  }

  void _showQueue(BuildContext context, PlayerService player) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SizedBox(
        height: MediaQuery.sizeOf(sheet).height * 0.7,
        child: ListenableBuilder(
          listenable: player,
          builder: (context, _) {
            final q = player.queue;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Up next', style: Clay.title(24)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemExtent: 56,
                    itemCount: q.length,
                    // Start scrolled near the current song.
                    controller: ScrollController(initialScrollOffset: ((player.index - 2).clamp(0, q.length) * 56).toDouble()),
                    itemBuilder: (context, i) {
                      final s = q[i];
                      final isCur = i == player.index;
                      return ListTile(
                        leading: Text('${i + 1}', style: TextStyle(color: isCur ? Clay.candle : Clay.ash)),
                        title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isCur ? Clay.candle : Clay.bone)),
                        subtitle: Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Clay.ash)),
                        onTap: () => player.jumpTo(i),
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
}

class _Scrubber extends StatefulWidget {
  const _Scrubber({required this.player});

  final PlayerService player;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final total = widget.player.duration;
    return StreamBuilder<Duration>(
      stream: widget.player.positionStream,
      initialData: widget.player.position,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final totalMs = total.inMilliseconds;
        final frac = _drag ?? (totalMs > 0 ? pos.inMilliseconds / totalMs : 0.0);
        final shown = _drag != null ? Duration(milliseconds: (_drag! * totalMs).round()) : pos;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              ClaySlider(
                value: frac.clamp(0.0, 1.0),
                thickness: 32,
                seed: 17,
                onChanged: (v) => setState(() => _drag = v),
                onChangeEnd: (v) {
                  setState(() => _drag = null);
                  if (totalMs > 0) widget.player.seek(Duration(milliseconds: (v * totalMs).round()));
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    Text(formatDuration(shown), style: const TextStyle(color: Clay.ash, fontSize: 12.5)),
                    const Spacer(),
                    Text(formatDuration(total), style: const TextStyle(color: Clay.ash, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
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
          size: 84,
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
