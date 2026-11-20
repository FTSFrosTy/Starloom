
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Loop;

import '../models/models.dart' show Song, formatDuration;
import '../services/app_scope.dart';
import '../services/player_service.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import '../widgets/context_menu.dart';
import '../widgets/cover.dart';
import '../widgets/nav.dart';
import '../widgets/panels.dart';
import '../widgets/ui_fx.dart';
import '../widgets/scenery.dart';
import '../widgets/visualizer.dart';
import 'eq_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'now_playing_screen.dart';
import 'playlists_screen.dart';
import 'settings_screen.dart';

/// Wide windows (PC) get the sidebar + bottom player bar layout.
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 860;

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  late final ValueNotifier<String?> _errors;

  static const _tabs = [
    (Icons.home_rounded, 'Home'),
    (Icons.library_music_rounded, 'Library'),
    (Icons.queue_music_rounded, 'Playlists'),
    (Icons.graphic_eq_rounded, 'EQ'),
    (Icons.settings_rounded, 'Settings'),
  ];

  static const _roots = [HomeScreen(), LibraryScreen(), PlaylistsScreen(), EqScreen(), SettingsScreen()];

  @override
  void initState() {
    super.initState();
    _errors = AppScope.of(context).player.errors;
    _errors.addListener(_showError);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    _errors.removeListener(_showError);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  void _showError() {
    final msg = _errors.value;
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    _errors.value = null;
  }

  /// PC shortcuts: Space play/pause, Ctrl+→/← next/previous.
  /// Ignored while typing in a text field.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final focusCtx = FocusManager.instance.primaryFocus?.context;
    if (focusCtx != null && focusCtx.findAncestorWidgetOfExactType<EditableText>() != null) return false;
    final player = AppScope.of(context).player;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (e.logicalKey == LogicalKeyboardKey.space) {
      player.togglePlay();
      return true;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.arrowRight) {
      player.next();
      return true;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      player.previous();
      return true;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.arrowUp) {
      final v = (player.volume + 5).clamp(0.0, 100.0);
      player.setVolume(v);
      AppScope.of(context).prefs.rememberVolume(v);
      return true;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.arrowDown) {
      final v = (player.volume - 5).clamp(0.0, 100.0);
      player.setVolume(v);
      AppScope.of(context).prefs.rememberVolume(v);
      return true;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.keyS) {
      player.toggleShuffle();
      return true;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.keyR) {
      player.cycleLoop();
      return true;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.keyL) {
      final id = player.current?.id;
      if (id != null) AppScope.of(context).user.toggleLike(id);
      return true;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.keyF) {
      if (_tab != 1) _select(1);
      Nav.popToRoot();
      Nav.searchFocus.requestFocus();
      return true;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.keyB) {
      Panels.leftCollapsed.value = !Panels.leftCollapsed.value;
      return true;
    }
    return false;
  }

  void _select(int i) {
    if (i == _tab) {
      Nav.popToRoot(); // tapping the current tab again goes back to its top
      return;
    }
    setState(() => _tab = i);
    Nav.currentTab = i;
  }

  Widget _content() => IndexedStack(
        index: _tab,
        children: [
          for (var i = 0; i < _roots.length; i++)
            HeroControllerScope.none(
              child: Navigator(
                key: Nav.tabs[i],
                onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => _roots[i]),
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return Scaffold(
      backgroundColor: Clay.night,
      body: Backdrop(
        child: SafeArea(
          bottom: false,
          child: wide
              ? Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          LibraryPanel(tab: _tab, tabs: _tabs, onTab: _select),
                          Expanded(child: _content()),
                          if (MediaQuery.sizeOf(context).width >= 1100)
                            ValueListenableBuilder<bool>(
                              valueListenable: Panels.rightOpen,
                              builder: (context, open, _) => AnimatedSize(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.centerRight,
                                child: open ? const RightPanel() : const SizedBox(height: double.infinity),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const PlayerBar(),
                  ],
                )
              : Column(
                  children: [
                    Expanded(child: _content()),
                    const MiniPlayer(),
                    _NavBar(tab: _tab, tabs: _tabs, onTap: _select),
                  ],
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phone: bottom tabs
// ---------------------------------------------------------------------------

class _NavBar extends StatelessWidget {
  const _NavBar({required this.tab, required this.tabs, required this.onTap});

  final int tab;
  final List<(IconData, String)> tabs;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 6, 10, 8 + bottom * 0.6),
      child: ClayBox(
        color: Clay.panel,
        seed: 404,
        squareness: 5,
        wobble: 0.7,
        depth: 8,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: Squish(
                  onTap: () => onTap(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(tabs[i].$1, color: i == tab ? Clay.candle : Clay.ash, size: 24),
                        const SizedBox(height: 2),
                        Text(
                          tabs[i].$2,
                          style: TextStyle(fontSize: 11, color: i == tab ? Clay.candle : Clay.ash, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The small now-playing bar above the phone tabs. Tap to open the full
/// player; a thin line shows progress.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final player = scope.player;
    return ListenableBuilder(
      listenable: Listenable.merge([player, scope.user]),
      builder: (context, _) {
        final song = player.current;
        if (song == null) return const SizedBox.shrink();
        final liked = scope.user.isLiked(song.id);
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
          child: Squish(
            onTap: () => openNowPlaying(context),
            child: ClayBox(
              color: Clay.plum,
              seed: 202,
              squareness: 4.5,
              depth: 6,
              padding: const EdgeInsets.fromLTRB(8, 7, 4, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Cover(artKey: song.artKey, seedText: song.album.isNotEmpty ? song.album : song.title, size: 42),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: Clay.bone)),
                            Text(song.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Clay.ash)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: liked ? 'Unlike' : 'Like',
                        icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: liked ? Clay.rose : Clay.bone, size: 24),
                        onPressed: () => scope.user.toggleLike(song.id),
                      ),
                      IconButton(
                        tooltip: player.playing ? 'Pause' : 'Play',
                        icon: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Clay.bone, size: 30),
                        onPressed: player.togglePlay,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _ProgressLine(player: player),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.player});

  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snap) {
        final total = player.duration.inMilliseconds;
        final v = total > 0 ? ((snap.data ?? Duration.zero).inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
        return ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: v,
            minHeight: 2.5,
            backgroundColor: Colors.black.withValues(alpha: 0.25),
            valueColor: AlwaysStoppedAnimation(Clay.candle),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// PC: sidebar + bottom player bar
// ---------------------------------------------------------------------------

/// Spotify-style bar along the bottom on PC: song on the left, controls
/// and scrubber in the middle, like/queue/volume on the right.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final player = scope.player;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ClayBox(
        color: Clay.panel,
        seed: 707,
        squareness: 7,
        wobble: 0.4,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: SizedBox(
          height: 74,
          child: ListenableBuilder(
            listenable: Listenable.merge([player, scope.user]),
            builder: (context, _) {
              final song = player.current;
              final liked = song != null && scope.user.isLiked(song.id);
              return Row(
                children: [
                  // Left: song.
                  Expanded(
                    flex: 3,
                    child: song == null
                        ? Text('Nothing playing', style: Clay.book(16))
                        : RightClick(
                            onMenu: (at) => songMenu(context, at, song),
                            child: InkWell(
                            onTap: () => openNowPlaying(context),
                            borderRadius: BorderRadius.circular(10),
                            child: Row(children: [
                              Cover(artKey: song.artKey, seedText: song.album.isNotEmpty ? song.album : song.title, size: 58),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w700, fontSize: 15)),
                                    Text(song.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.ash, fontSize: 12.5)),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: liked ? 'Unlike' : 'Like',
                                icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: liked ? Clay.rose : Clay.ash, size: 20),
                                onPressed: () => scope.user.toggleLike(song.id),
                              ),
                              if (MediaQuery.sizeOf(context).width >= 1250)
                                SizedBox(width: 110, child: ThemeVisualizer(player: player.player, height: 52)),
                            ]),
                          ),
                          ),
                  ),
                  // Middle: controls + scrubber.
                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _barIcon(Icons.shuffle_rounded, 'Shuffle', player.toggleShuffle, on: player.shuffle),
                            _barIcon(Icons.skip_previous_rounded, 'Previous', player.previous, size: 28),
                            const SizedBox(width: 6),
                            BeatGlow(
                              player: player,
                              child: ClayIconButton(
                                icon: player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                tooltip: player.playing ? 'Pause' : 'Play',
                                size: 42,
                                seed: 53,
                                color: Clay.pumpkin,
                                onTap: player.togglePlay,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _barIcon(Icons.skip_next_rounded, 'Next', player.next, size: 28),
                            _barIcon(
                              player.loop == Loop.file ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                              'Repeat',
                              player.cycleLoop,
                              on: player.loop != Loop.off,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Scrubber(player: player, compact: true),
                      ],
                    ),
                  ),
                  // Right: queue, full player, volume.
                  Expanded(
                    flex: 3,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ..._panelToggles(context),
                        _barIcon(Icons.open_in_full_rounded, 'Full screen player', () => openNowPlaying(context), size: 19),
                        const SizedBox(width: 4),
                        Flexible(child: SizedBox(width: 160, child: VolumeSlider(player: player))),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Now playing / Lyrics / Queue toggles for the right panel. On narrower
  /// windows (no room for the panel) they open the sheet or full player.
  List<Widget> _panelToggles(BuildContext context) {
    final roomy = MediaQuery.sizeOf(context).width >= 1100;
    if (!roomy) {
      return [_barIcon(Icons.queue_music_rounded, 'Queue', () => showQueue(context))];
    }
    return [
      ValueListenableBuilder<bool>(
        valueListenable: Panels.rightOpen,
        builder: (context, open, _) => ValueListenableBuilder<RightTab>(
          valueListenable: Panels.rightTab,
          builder: (context, tab, _) => Row(mainAxisSize: MainAxisSize.min, children: [
            _barIcon(Icons.slideshow_rounded, 'Now playing view', () => Panels.toggle(RightTab.nowPlaying), on: open && tab == RightTab.nowPlaying, size: 20),
            _barIcon(Icons.lyrics_rounded, 'Lyrics', () => Panels.toggle(RightTab.lyrics), on: open && tab == RightTab.lyrics, size: 20),
            _barIcon(Icons.queue_music_rounded, 'Queue', () => Panels.toggle(RightTab.queue), on: open && tab == RightTab.queue),
          ]),
        ),
      ),
    ];
  }

  Widget _barIcon(IconData icon, String tip, VoidCallback onTap, {bool on = false, double size = 22}) => IconButton(
        tooltip: tip,
        onPressed: onTap,
        icon: Icon(icon, size: size, color: on ? Clay.candle : Clay.bone),
      );
}

/// Seek bar with times. Listens to position on its own, so only it redraws.
class Scrubber extends StatefulWidget {
  const Scrubber({super.key, required this.player, this.compact = false});

  final PlayerService player;
  final bool compact;

  @override
  State<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<Scrubber> {
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
        final slider = ClaySlider(
          value: frac.clamp(0.0, 1.0),
          thickness: widget.compact ? 20 : 32,
          seed: 17,
          onChanged: (v) => setState(() => _drag = v),
          onChangeEnd: (v) {
            setState(() => _drag = null);
            if (totalMs > 0) widget.player.seek(Duration(milliseconds: (v * totalMs).round()));
          },
        );
        final timeStyle = TextStyle(color: Clay.ash, fontSize: 12);
        if (widget.compact) {
          return Row(children: [
            SizedBox(width: 44, child: Text(formatDuration(shown), textAlign: TextAlign.right, style: timeStyle)),
            const SizedBox(width: 8),
            Expanded(child: slider),
            const SizedBox(width: 8),
            SizedBox(width: 44, child: Text(formatDuration(total), style: timeStyle)),
          ]);
        }
        return Column(children: [
          slider,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(children: [Text(formatDuration(shown), style: timeStyle), const Spacer(), Text(formatDuration(total), style: timeStyle)]),
          ),
        ]);
      },
    );
  }
}

/// The app's own volume (works on iPhone and PC; the phone's volume buttons
/// still set the overall level).
class VolumeSlider extends StatelessWidget {
  const VolumeSlider({super.key, required this.player});

  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    final prefs = AppScope.of(context).prefs;
    final v = player.volume;
    return Row(children: [
      IconButton(
        tooltip: v == 0 ? 'Unmute' : 'Mute',
        icon: Icon(v == 0 ? Icons.volume_off_rounded : v < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded, color: Clay.ash, size: 22),
        onPressed: () {
          final next = v == 0 ? (prefs.volume > 0 ? prefs.volume : 70.0) : 0.0;
          player.setVolume(next);
          if (next > 0) prefs.rememberVolume(next);
        },
      ),
      Expanded(
        child: ClaySlider(
          value: v / 100,
          thickness: 22,
          color: Clay.ghost,
          seed: 71,
          onChanged: (x) => player.setVolume(x * 100),
          onChangeEnd: (x) => prefs.rememberVolume(x * 100),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

void openNowPlaying(BuildContext context) {
  Nav.root.currentState?.push(PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, a, b) => const NowPlayingScreen(),
    transitionsBuilder: (context, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ));
}

/// Shared screen header: back button (when there's somewhere to go back
/// to), big title, optional subtitle and trailing actions.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.trailing = const []});

  final String title;
  final String? subtitle;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Padding(
      padding: EdgeInsets.fromLTRB(canPop ? 4 : 20, 14, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (canPop)
            IconButton(
              tooltip: 'Back',
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: Clay.bone, size: 20),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClayTitle(title),
                if (subtitle != null) Text(subtitle!, style: Clay.book(15)),
              ],
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

String songCount(int n) => n == 1 ? '1 song' : '$n songs';

String totalLength(Iterable<Song> songs) {
  final ms = songs.fold<int>(0, (a, s) => a + s.durationMs);
  final d = Duration(milliseconds: ms);
  if (d.inHours > 0) return '${d.inHours} hr ${d.inMinutes % 60} min';
  return '${d.inMinutes} min';
}
