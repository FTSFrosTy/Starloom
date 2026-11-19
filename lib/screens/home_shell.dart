import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import '../widgets/scenery.dart';
import 'eq_screen.dart';
import 'library_screen.dart';
import 'now_playing_screen.dart';
import 'playlists_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  late final ValueNotifier<String?> _errors;

  static const _tabs = [
    (Icons.library_music_rounded, 'Library'),
    (Icons.queue_music_rounded, 'Playlists'),
    (Icons.graphic_eq_rounded, 'EQ'),
    (Icons.settings_rounded, 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _errors = AppScope.of(context).player.errors;
    _errors.addListener(_showError);
  }

  @override
  void dispose() {
    _errors.removeListener(_showError);
    super.dispose();
  }

  void _showError() {
    final msg = _errors.value;
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    _errors.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wide ? 860 : double.infinity),
                    child: IndexedStack(
                      index: _tab,
                      children: const [LibraryScreen(), PlaylistsScreen(), EqScreen(), SettingsScreen()],
                    ),
                  ),
                ),
              ),
              const MiniPlayer(),
              _NavBar(tab: _tab, tabs: _tabs, onTap: (i) => setState(() => _tab = i)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.tab, required this.tabs, required this.onTap});

  final int tab;
  final List<(IconData, String)> tabs;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 6, 12, 8 + bottom * 0.6),
      child: ClayBox(
        color: const Color(0xFF241B35),
        seed: 404,
        squareness: 5,
        wobble: 0.7,
        depth: 8,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
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
                          style: TextStyle(fontSize: 11.5, color: i == tab ? Clay.candle : Clay.ash, fontWeight: FontWeight.w600),
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

/// The small now-playing bar above the tabs. Tap to open the full player.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final song = player.current;
        if (song == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Squish(
            onTap: () => openNowPlaying(context),
            child: ClayBox(
              color: Clay.plum,
              seed: 202,
              squareness: 4.5,
              depth: 6,
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(
                children: [
                  Pebble(seedText: song.album.isNotEmpty ? song.album : song.title, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: Clay.bone)),
                        Text(song.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Clay.ash)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: player.playing ? 'Pause' : 'Play',
                    icon: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Clay.bone, size: 30),
                    onPressed: player.togglePlay,
                  ),
                  IconButton(
                    tooltip: 'Next',
                    icon: const Icon(Icons.skip_next_rounded, color: Clay.bone, size: 28),
                    onPressed: player.next,
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

void openNowPlaying(BuildContext context) {
  Navigator.of(context).push(PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, a, b) => const NowPlayingScreen(),
    transitionsBuilder: (context, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
      child: child,
    ),
  ));
}

/// Shared screen header: big title plus optional trailing widgets.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.trailing = const []});

  final String title;
  final String? subtitle;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
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
