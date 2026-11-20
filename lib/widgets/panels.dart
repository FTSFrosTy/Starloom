import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart' show readMetadata;
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../screens/collection_screens.dart';
import '../services/app_scope.dart';
import '../services/player_service.dart';
import '../theme/palette.dart';
import 'clay.dart';
import 'context_menu.dart';
import 'cover.dart';
import 'nav.dart';
import 'scenery.dart';
import 'song_tile.dart';
import 'visualizer.dart';

/// Which tab the right-hand panel shows on PC.
enum RightTab { nowPlaying, queue, lyrics }

/// Open/closed state of the PC side panels, shared by the shell and the
/// player bar's toggle buttons.
class Panels {
  Panels._();

  static final ValueNotifier<bool> leftCollapsed = ValueNotifier(false);
  static final ValueNotifier<bool> rightOpen = ValueNotifier(true);
  static final ValueNotifier<RightTab> rightTab = ValueNotifier(RightTab.nowPlaying);

  /// Player-bar buttons: open the panel on [tab], or close it if it's
  /// already showing that tab (Spotify does the same).
  static void toggle(RightTab tab) {
    if (rightOpen.value && rightTab.value == tab) {
      rightOpen.value = false;
    } else {
      rightTab.value = tab;
      rightOpen.value = true;
    }
  }
}

/// Saves whatever is in the queue as a new playlist.
Future<void> saveQueueAsPlaylist(BuildContext context) async {
  final scope = AppScope.of(context);
  final q = scope.player.queue;
  if (q.isEmpty) return;
  final name = await promptText(context, title: 'Save queue as playlist', initial: scope.player.playingFrom ?? 'My queue');
  if (name == null || name.trim().isEmpty) return;
  await scope.playlists.create(name.trim(), songIds: [for (final s in q) s.id]);
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Saved ${q.length} songs to "${name.trim()}"')));
  }
}

// ---------------------------------------------------------------------------
// Queue
// ---------------------------------------------------------------------------

/// The queue: drag to reorder, swipe to remove, tap to jump, right-click for
/// the song menu. Used by the bottom sheet and the PC side panel.
class QueueList extends StatefulWidget {
  const QueueList({super.key, this.compact = false});

  /// Smaller rows and header for the side panel.
  final bool compact;

  @override
  State<QueueList> createState() => _QueueListState();
}

class _QueueListState extends State<QueueList> {
  ScrollController? _scroll;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    final rowH = widget.compact ? 56.0 : 64.0;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final q = player.queue;
        _scroll ??= ScrollController(initialScrollOffset: ((player.index - 2).clamp(0, q.length) * rowH).toDouble());
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(widget.compact ? 4 : 20, 0, 4, 6),
              child: Row(children: [
                Expanded(child: Text('Queue', style: Clay.title(widget.compact ? 20 : 26))),
                if (player.queuedAhead > 0)
                  TextButton(onPressed: player.clearQueued, child: Text('Clear queue', style: TextStyle(color: Clay.candle, fontSize: 12.5)))
                else if (player.index < q.length - 1)
                  TextButton(onPressed: player.clearUpNext, child: Text('Clear up next', style: TextStyle(color: Clay.candle, fontSize: 12.5))),
                IconButton(
                  tooltip: 'Save queue as playlist',
                  icon: Icon(Icons.playlist_add_rounded, color: Clay.ash, size: 20),
                  onPressed: q.isEmpty ? null : () => saveQueueAsPlaylist(context),
                ),
              ]),
            ),
            Expanded(
              child: q.isEmpty
                  ? Center(child: Text('Nothing queued', style: Clay.book(17)))
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      scrollController: _scroll,
                      itemCount: q.length,
                      onReorder: (from, to) => player.moveInQueue(from, to),
                      itemBuilder: (context, i) => _row(context, player, q, i, rowH),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, PlayerService player, List<Song> q, int i, double rowH) {
    final s = q[i];
    final isCur = i == player.index;
    final played = i < player.index;
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
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (i == player.index) _header('Now playing'),
        if (i == player.index + 1 && player.queuedAhead > 0) _header('Next in queue'),
        if (i == player.index + 1 + player.queuedAhead && i < q.length) _header(player.playingFrom == null ? 'Next up' : 'Next from ${player.playingFrom}'),
        RightClick(
          onMenu: (at) => songMenu(context, at, s, onRemoveFromQueue: isCur ? null : () => player.removeFromQueue(i)),
          child: HoverRow(
            onTap: () => player.jumpTo(i),
            child: SizedBox(
              height: rowH,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.compact ? 4 : 16),
                child: Row(children: [
                  Opacity(
                    opacity: played ? 0.5 : 1,
                    child: Cover(artKey: s.artKey, seedText: s.album.isNotEmpty ? s.album : s.title, size: widget.compact ? 38 : 42),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCur ? Clay.candle : (played ? Clay.ash : Clay.bone),
                          fontWeight: isCur ? FontWeight.w700 : FontWeight.w500,
                          fontSize: widget.compact ? 13.5 : 15,
                        ),
                      ),
                      Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.ash, fontSize: 12)),
                    ]),
                  ),
                  if (isCur) Padding(padding: const EdgeInsets.only(right: 6), child: PlayingBars(color: Clay.candle)),
                  ReorderableDragStartListener(index: i, child: Icon(Icons.drag_handle_rounded, color: Clay.ash, size: 20)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _header(String text) => Padding(
        padding: EdgeInsets.fromLTRB(widget.compact ? 6 : 20, 12, 12, 2),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Clay.title(widget.compact ? 16 : 18, color: Clay.candle)),
      );
}

/// Bottom-sheet queue (phone, and the full-screen player).
void showQueue(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheet) => SizedBox(height: MediaQuery.sizeOf(sheet).height * 0.75, child: const QueueList()),
  );
}

// ---------------------------------------------------------------------------
// Lyrics
// ---------------------------------------------------------------------------

/// Lyrics embedded in the file's tags (or a matching .lrc next to it).
class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.song, this.boxed = true});

  final Song song;
  final bool boxed;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  late Future<String?> _text = loadLyrics(widget.song.path);

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (old.song.path != widget.song.path) _text = loadLyrics(widget.song.path);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _text,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
        final text = snap.data;
        final body = text == null
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lyrics_outlined, color: Clay.ash, size: 40),
                  const SizedBox(height: 8),
                  Text('No lyrics in this file.', style: Clay.book(18)),
                  const SizedBox(height: 4),
                  Text('Drop a .lrc with the same name next to it.', style: TextStyle(color: Clay.ash, fontSize: 12)),
                ]),
              )
            : SingleChildScrollView(
                child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Clay.bone, fontSize: 17, height: 1.6, fontWeight: FontWeight.w600)),
              );
        if (!widget.boxed) return body;
        return ClayBox(
          color: Clay.bruise.withValues(alpha: 0.92),
          seed: 515,
          squareness: 5,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: body,
        );
      },
    );
  }
}

/// Top-level so the isolate only captures the path.
Future<String?> loadLyrics(String path) => Isolate.run(() {
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

// ---------------------------------------------------------------------------
// Small shared bits
// ---------------------------------------------------------------------------

/// A row that lights up under the mouse, like Spotify's desktop lists.
class HoverRow extends StatefulWidget {
  const HoverRow({super.key, required this.child, this.onTap, this.selected = false, this.radius = 10});

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final double radius;

  @override
  State<HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? Clay.plum.withValues(alpha: 0.75)
        : _hover
            ? Clay.bone.withValues(alpha: 0.08)
            : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(widget.radius)),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Three little bouncing clay bars: "this is the one playing".
class PlayingBars extends StatelessWidget {
  const PlayingBars({super.key, required this.color, this.size = 14});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return ListenableBuilder(
      listenable: StopMotion.instance,
      builder: (context, _) {
        final f = StopMotion.instance.frame;
        final on = player.playing;
        return SizedBox(
          width: size,
          height: size,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: size / 4.2,
                  height: size * (on ? 0.3 + 0.7 * (clayNoise(i * 31, f, 3) * 0.5 + 0.5) : 0.3),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Left: Your Library
// ---------------------------------------------------------------------------

enum _Filter { playlists, albums, artists }

enum _Sort { recents, alphabetical }

/// One entry in Your Library.
class _Entry {
  _Entry({required this.kind, required this.key, required this.title, required this.subtitle, required this.cover, required this.open, required this.menu, this.pinned = false});

  final _Filter? kind; // null = Liked Songs
  final String key; // matches UserData.recentCollections
  final String title;
  final String subtitle;
  final Widget Function(double size) cover;
  final VoidCallback open;
  final void Function(BuildContext, Offset) menu;
  final bool pinned;
}

/// Spotify's left column: nav, then "Your Library" with filter chips,
/// search, sort, pinned items and collapsible sections. Collapses to an
/// icon rail.
class LibraryPanel extends StatefulWidget {
  const LibraryPanel({super.key, required this.tab, required this.tabs, required this.onTab});

  final int tab;
  final List<(IconData, String)> tabs;
  final ValueChanged<int> onTab;

  @override
  State<LibraryPanel> createState() => _LibraryPanelState();
}

class _LibraryPanelState extends State<LibraryPanel> {
  _Filter? _filter;
  _Sort _sort = _Sort.recents;
  bool _searching = false;
  String _query = '';
  final _search = TextEditingController();
  final Set<String> _closed = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _go(int tab, Widget page) {
    widget.onTab(tab);
    Nav.popToRoot();
    Nav.push(page);
  }

  List<_Entry> _entries(BuildContext context) {
    final scope = AppScope.of(context);
    final lib = scope.library;
    final out = <_Entry>[];
    for (final pl in scope.playlists.playlists) {
      final songs = [for (final id in pl.songIds) ?lib.byId(id)];
      out.add(_Entry(
        kind: _Filter.playlists,
        key: 'playlist:${pl.id}',
        title: pl.name,
        subtitle: 'Playlist · ${pl.songIds.length} songs',
        pinned: pl.pinned,
        cover: (size) => Mosaic(artKeys: [for (final s in songs) ?s.artKey], seedText: pl.name, size: size),
        open: () => _go(2, PlaylistScreen(playlistId: pl.id)),
        menu: (ctx, at) => playlistMenu(ctx, at, pl),
      ));
    }
    for (final a in lib.albums) {
      if (a.name.isEmpty) continue;
      out.add(_Entry(
        kind: _Filter.albums,
        key: 'album:${a.key}',
        title: a.name,
        subtitle: 'Album · ${a.artist.isEmpty ? 'Unknown artist' : a.artist}',
        cover: (size) => Cover(artKey: a.artKey, seedText: a.name, size: size, radius: 8),
        open: () => _go(1, AlbumScreen(albumKey: a.key)),
        menu: (ctx, at) => songsMenu(ctx, at, a.songs, albumArtist: a.artist, title: a.name),
      ));
    }
    for (final ar in lib.artists) {
      if (ar.name.isEmpty) continue;
      out.add(_Entry(
        kind: _Filter.artists,
        key: 'artist:${ar.name}',
        title: ar.name,
        subtitle: 'Artist · ${ar.songs.length} songs',
        cover: (size) => Cover(artKey: ar.artKey, seedText: ar.name, size: size, radius: size / 2),
        open: () => _go(1, ArtistScreen(name: ar.name)),
        menu: (ctx, at) => songsMenu(ctx, at, ar.songs, title: ar.name),
      ));
    }
    return out;
  }

  List<_Entry> _sorted(List<_Entry> list, List<String> recents) {
    final rank = {for (var i = 0; i < recents.length; i++) recents[i]: i};
    int byName(_Entry a, _Entry b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return List.of(list)
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        if (_sort == _Sort.recents) {
          final ra = rank[a.key] ?? (a.kind == _Filter.playlists ? 500 : 1000);
          final rb = rank[b.key] ?? (b.kind == _Filter.playlists ? 500 : 1000);
          if (ra != rb) return ra.compareTo(rb);
        }
        return byName(a, b);
      });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: Panels.leftCollapsed,
      builder: (context, collapsed, _) => AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: collapsed ? 84 : 300,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 10),
            child: ClayBox(
              color: Clay.panel,
              seed: 909,
              squareness: 6,
              wobble: 0.5,
              padding: EdgeInsets.fromLTRB(collapsed ? 6 : 10, 14, collapsed ? 6 : 10, 10),
              child: ListenableBuilder(
                listenable: Listenable.merge([scope.playlists, scope.library, scope.user, scope.player]),
                builder: (context, _) => collapsed ? _rail(context) : _full(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rail(BuildContext context) {
    final scope = AppScope.of(context);
    final entries = _sorted(_entries(context).where((e) => e.kind == _Filter.playlists || e.pinned).toList(), scope.user.recentCollections);
    return Column(children: [
      IconButton(
        tooltip: 'Expand Your Library',
        icon: Icon(Icons.menu_open_rounded, color: Clay.candle, textDirection: TextDirection.rtl),
        onPressed: () => Panels.leftCollapsed.value = false,
      ),
      const SizedBox(height: 6),
      for (var i = 0; i < widget.tabs.length; i++)
        Tooltip(
          message: widget.tabs[i].$2,
          child: HoverRow(
            selected: i == widget.tab,
            onTap: () => widget.onTab(i),
            child: SizedBox(height: 44, child: Center(child: Icon(widget.tabs[i].$1, color: i == widget.tab ? Clay.candle : Clay.ash))),
          ),
        ),
      Divider(color: Clay.ash.withValues(alpha: 0.25), height: 18),
      Expanded(
        child: ListView(padding: EdgeInsets.zero, children: [
          Tooltip(
            message: 'Liked Songs',
            child: HoverRow(
              onTap: () => _go(2, const LikedScreen()),
              child: Padding(padding: const EdgeInsets.all(6), child: _likedArt(44)),
            ),
          ),
          for (final e in entries)
            Tooltip(
              message: e.title,
              child: RightClick(
                onMenu: (at) => e.menu(context, at),
                child: HoverRow(
                  selected: scope.player.playingFrom == e.title,
                  onTap: e.open,
                  child: Padding(padding: const EdgeInsets.all(6), child: e.cover(44)),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _likedArt(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(colors: [Clay.plum, Clay.rose], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Icon(Icons.favorite_rounded, color: Clay.bone, size: size * 0.45),
      );

  Widget _full(BuildContext context) {
    final scope = AppScope.of(context);
    final words = _query.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    var entries = _entries(context);
    if (_filter != null) entries = entries.where((e) => e.kind == _filter).toList();
    if (words.isNotEmpty) entries = entries.where((e) => words.every('${e.title} ${e.subtitle}'.toLowerCase().contains)).toList();
    entries = _sorted(entries, scope.user.recentCollections);

    // Flatten into rows: section headers + entries. Sections only when
    // nothing is filtered, so it reads like Spotify's mixed list otherwise.
    final rows = <Object>[];
    final showLiked = (_filter == null || _filter == _Filter.playlists) && (words.isEmpty || 'liked songs'.contains(words.join(' ')));
    if (_filter == null && words.isEmpty) {
      final pinned = entries.where((e) => e.pinned).toList();
      void section(String name, List<_Entry> items, {bool liked = false}) {
        if (items.isEmpty && !liked) return;
        rows.add(name);
        if (_closed.contains(name)) return;
        if (liked) rows.add('liked');
        rows.addAll(items);
      }

      section('Pinned', pinned, liked: true);
      section('Playlists', entries.where((e) => e.kind == _Filter.playlists && !e.pinned).toList());
      section('Albums', entries.where((e) => e.kind == _Filter.albums).toList());
      section('Artists', entries.where((e) => e.kind == _Filter.artists).toList());
    } else {
      if (showLiked) rows.add('liked');
      rows.addAll(entries);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const SizedBox(width: 6),
          Icon(Icons.nightlight_round, color: Clay.candle, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text('Starloom', style: Clay.title(26))),
          IconButton(
            tooltip: 'Collapse',
            icon: Icon(Icons.menu_open_rounded, color: Clay.ash),
            onPressed: () => Panels.leftCollapsed.value = true,
          ),
        ]),
        const SizedBox(height: 6),
        for (var i = 0; i < widget.tabs.length; i++)
          HoverRow(
            selected: i == widget.tab,
            onTap: () => widget.onTab(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                Icon(widget.tabs[i].$1, size: 21, color: i == widget.tab ? Clay.candle : Clay.ash),
                const SizedBox(width: 12),
                Text(widget.tabs[i].$2, style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w700, fontSize: 14.5)),
              ]),
            ),
          ),
        Divider(color: Clay.ash.withValues(alpha: 0.25), height: 18),
        Row(children: [
          const SizedBox(width: 6),
          Icon(Icons.library_music_rounded, color: Clay.ash, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Your Library', style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w800, fontSize: 15))),
          IconButton(
            tooltip: 'Create playlist',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add_rounded, color: Clay.bone),
            onPressed: () async {
              final name = await promptText(context, title: 'New playlist', hint: 'Name');
              if (name == null || name.trim().isEmpty || !context.mounted) return;
              final pl = await scope.playlists.create(name.trim());
              _go(2, PlaylistScreen(playlistId: pl.id));
            },
          ),
        ]),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            if (_filter != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _Chip(label: '✕', on: false, onTap: () => setState(() => _filter = null)),
              ),
            for (final (f, label) in [(_Filter.playlists, 'Playlists'), (_Filter.albums, 'Albums'), (_Filter.artists, 'Artists')])
              if (_filter == null || _filter == f)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _Chip(label: label, on: _filter == f, onTap: () => setState(() => _filter = _filter == f ? null : f)),
                ),
          ]),
        ),
        const SizedBox(height: 4),
        Row(children: [
          if (_searching)
            Expanded(
              child: SizedBox(
                height: 34,
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(color: Clay.bone, fontSize: 13.5),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search in Your Library',
                    hintStyle: TextStyle(color: Clay.ash, fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: Clay.ash),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.close_rounded, size: 16, color: Clay.ash),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                        _searching = false;
                      }),
                    ),
                    filled: true,
                    fillColor: Clay.bruise.withValues(alpha: 0.7),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              ),
            )
          else ...[
            IconButton(
              tooltip: 'Search in Your Library',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.search_rounded, color: Clay.ash, size: 20),
              onPressed: () => setState(() => _searching = true),
            ),
            const Spacer(),
          ],
          PopupMenuButton<_Sort>(
            tooltip: 'Sort by',
            initialValue: _sort,
            color: Clay.dusk,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              PopupMenuItem(value: _Sort.recents, child: Text('Recents', style: TextStyle(color: Clay.bone))),
              PopupMenuItem(value: _Sort.alphabetical, child: Text('Alphabetical', style: TextStyle(color: Clay.bone))),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_sort == _Sort.recents ? 'Recents' : 'A–Z', style: TextStyle(color: Clay.ash, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Icon(Icons.sort_rounded, color: Clay.ash, size: 18),
              ]),
            ),
          ),
        ]),
        Expanded(
          child: rows.isEmpty
              ? Center(child: Text(words.isEmpty ? 'Nothing here yet' : 'No matches', style: Clay.book(15)))
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    if (r == 'liked') return _likedRow(context);
                    if (r is String) return _sectionHeader(r);
                    return _entryRow(context, r as _Entry);
                  },
                ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String name) {
    final closed = _closed.contains(name);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => closed ? _closed.remove(name) : _closed.add(name)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
        child: Row(children: [
          AnimatedRotation(
            turns: closed ? -0.25 : 0,
            duration: const Duration(milliseconds: 150),
            child: Icon(Icons.expand_more_rounded, size: 18, color: Clay.ash),
          ),
          const SizedBox(width: 4),
          Text(name.toUpperCase(), style: TextStyle(color: Clay.ash, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _likedRow(BuildContext context) {
    final scope = AppScope.of(context);
    final n = scope.user.liked.length;
    return _row(
      context,
      cover: _likedArt(46),
      title: 'Liked Songs',
      subtitle: 'Playlist · $n songs',
      pinned: true,
      active: scope.player.playingFrom == 'Liked Songs',
      onTap: () => _go(2, const LikedScreen()),
      onMenu: (at) => songsMenu(context, at, [for (final id in scope.user.liked) ?scope.library.byId(id)], title: 'Liked Songs'),
    );
  }

  Widget _entryRow(BuildContext context, _Entry e) => _row(
        context,
        cover: e.cover(46),
        title: e.title,
        subtitle: e.subtitle,
        pinned: e.pinned,
        active: AppScope.of(context).player.playingFrom == e.title,
        onTap: e.open,
        onMenu: (at) => e.menu(context, at),
      );

  Widget _row(BuildContext context,
      {required Widget cover,
      required String title,
      required String subtitle,
      required bool pinned,
      required bool active,
      required VoidCallback onTap,
      required void Function(Offset) onMenu}) {
    return RightClick(
      onMenu: onMenu,
      child: HoverRow(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(children: [
            cover,
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: active ? Clay.candle : Clay.bone, fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Row(children: [
                  if (pinned) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.push_pin_rounded, size: 12, color: Clay.moss)),
                  Expanded(child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.ash, fontSize: 12))),
                ]),
              ]),
            ),
            if (active) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.volume_up_rounded, size: 16, color: Clay.candle)),
          ]),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Squish(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? Clay.candle : Clay.bruise.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(color: on ? Clay.onAccent : Clay.bone, fontSize: 12.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right: Now playing / Queue / Lyrics
// ---------------------------------------------------------------------------

/// Spotify's right column, with tabs. Closes from its X or the player bar.
class RightPanel extends StatelessWidget {
  const RightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 12, 10),
        child: ClayBox(
          color: Clay.panel,
          seed: 1717,
          squareness: 6,
          wobble: 0.5,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: ValueListenableBuilder<RightTab>(
            valueListenable: Panels.rightTab,
            builder: (context, tab, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  for (final (t, label) in [(RightTab.nowPlaying, 'Playing'), (RightTab.queue, 'Queue'), (RightTab.lyrics, 'Lyrics')])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _Chip(label: label, on: tab == t, onTap: () => Panels.rightTab.value = t),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close panel',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, color: Clay.ash, size: 20),
                    onPressed: () => Panels.rightOpen.value = false,
                  ),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: switch (tab) {
                      RightTab.nowPlaying => const _NowPlayingTab(key: ValueKey('np')),
                      RightTab.queue => const QueueList(key: ValueKey('q'), compact: true),
                      RightTab.lyrics => const _LyricsTab(key: ValueKey('ly')),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LyricsTab extends StatelessWidget {
  const _LyricsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return ValueListenableBuilder<String?>(
      valueListenable: player.currentId,
      builder: (context, _, _) {
        final song = player.current;
        if (song == null) return Center(child: Text('Nothing playing', style: Clay.book(16)));
        return LyricsView(key: ValueKey(song.id), song: song, boxed: false);
      },
    );
  }
}

class _NowPlayingTab extends StatelessWidget {
  const _NowPlayingTab({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final player = scope.player;
    return ListenableBuilder(
      listenable: Listenable.merge([player, scope.user]),
      builder: (context, _) {
        final song = player.current;
        final liked = song != null && scope.user.isLiked(song.id);
        final upcoming = player.index >= 0 ? player.queue.skip(player.index + 1).take(5).toList() : const <Song>[];
        final art = scope.library.artPath(song?.artKey);
        final artist = song == null || song.artist.isEmpty ? null : scope.library.artistByName(song.artist);
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            if (player.playingFrom != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text('PLAYING FROM  ·  ${player.playingFrom!.toUpperCase()}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.ash, fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
              ),
            RightClick(
              onMenu: song == null ? (_) {} : (at) => songMenu(context, at, song),
              child: SizedBox(
                height: 236,
                child: Center(
                  child: ClayRecord(
                    spinning: player.playing,
                    seedText: song?.album.isNotEmpty == true ? song!.album : (song?.title ?? 'starloom'),
                    cover: player.cover != null ? ResizeImage(player.cover!.image, width: 480) : (art == null ? null : FileImage(File(art))),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            RightClick(
              onMenu: song == null ? (_) {} : (at) => songMenu(context, at, song),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(song?.title ?? 'Nothing playing', maxLines: 2, overflow: TextOverflow.ellipsis, style: Clay.title(22)),
                    GestureDetector(
                      onTap: song == null || song.artist.isEmpty ? null : () => Nav.push(ArtistScreen(name: song.artist)),
                      child: Text(song?.subtitle ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: Clay.book(15)),
                    ),
                  ]),
                ),
                if (song != null) ...[
                  IconButton(
                    tooltip: 'Add to playlist',
                    icon: Icon(Icons.add_circle_outline_rounded, color: Clay.ash),
                    onPressed: () => showAddToPlaylist(context, [song]),
                  ),
                  IconButton(
                    tooltip: liked ? 'Unlike' : 'Like',
                    icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: liked ? Clay.rose : Clay.ash),
                    onPressed: () => scope.user.toggleLike(song.id),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 8),
            ThemeVisualizer(player: player.player, height: 110),
            if (artist != null) ...[
              const SizedBox(height: 12),
              _AboutArtist(artist: artist),
            ],
            if (upcoming.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text(player.queuedAhead > 0 ? 'Next in queue' : 'Next up', style: Clay.title(18, color: Clay.candle))),
                TextButton(
                  onPressed: () => Panels.rightTab.value = RightTab.queue,
                  child: Text('Open queue', style: TextStyle(color: Clay.ash, fontSize: 12)),
                ),
              ]),
              for (var k = 0; k < upcoming.length; k++)
                RightClick(
                  onMenu: (at) => songMenu(context, at, upcoming[k], onRemoveFromQueue: () => player.removeFromQueue(player.index + 1 + k)),
                  child: HoverRow(
                    onTap: () => player.jumpTo(player.index + 1 + k),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                      child: Row(children: [
                        Cover(artKey: upcoming[k].artKey, seedText: upcoming[k].album.isNotEmpty ? upcoming[k].album : upcoming[k].title, size: 38),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(upcoming[k].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(upcoming[k].subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.ash, fontSize: 11.5)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// "About the artist" card: how much of them you have and a shortcut.
class _AboutArtist extends StatelessWidget {
  const _AboutArtist({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    return Squish(
      onTap: () => Nav.push(ArtistScreen(name: artist.name)),
      child: ClayBox(
        color: Clay.bruise.withValues(alpha: 0.9),
        seed: artist.name.hashCode,
        squareness: 5,
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Cover(artKey: artist.artKey, seedText: artist.name, size: 54, radius: 27),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ABOUT THE ARTIST', style: TextStyle(color: Clay.ash, fontSize: 10, letterSpacing: 1.3, fontWeight: FontWeight.w800)),
              Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Clay.title(19)),
              Text(
                '${artist.songs.length} songs · ${artist.albums.length} ${artist.albums.length == 1 ? 'album' : 'albums'} in your library',
                style: TextStyle(color: Clay.ash, fontSize: 12),
              ),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: Clay.ash),
        ]),
      ),
    );
  }
}
