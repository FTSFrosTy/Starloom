import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_scope.dart';
import '../services/playlists.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import '../widgets/nav.dart';
import '../widgets/scenery.dart';
import 'collection_screens.dart';
import 'home_shell.dart';

/// Paste a Spotify playlist (open it in Spotify desktop, Ctrl+A, Ctrl+C) and
/// match every line to a file in the library.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _name = TextEditingController();
  final _text = TextEditingController();
  ImportReport? _report;
  String? _busy;
  String? _note;

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    // A single playlist link: read the playlist from Spotify.
    if (!text.contains('\n') && text.contains('open.spotify.com/playlist')) {
      await _fromLink(text);
      return;
    }
    _text.text = text;
    await _match();
  }

  /// Paste a Spotify playlist link (Share › Copy link) and read it.
  Future<void> _fromLink([String? link]) async {
    link ??= (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (link == null || !link.contains('spotify.com/playlist')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Copy a playlist link first: in Spotify, playlist ⋯ › Share › Copy link to playlist.'),
        ));
      }
      return;
    }
    setState(() {
      _busy = 'Reading the playlist from Spotify…';
      _note = null;
    });
    try {
      final page = await fetchSpotifyPlaylist(link);
      if (_name.text.trim().isEmpty) _name.text = page.name;
      _text.text = page.lines.join('\n');
      _note = 'Spotify showed ${page.lines.length} songs from "${page.name}". '
          'Local files in a Spotify playlist don\'t show up through a link; for those, copy the playlist in Spotify on the PC (Ctrl+A, Ctrl+C) and paste that instead.';
      await _match();
    } catch (e) {
      if (mounted) setState(() => _note = '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _match() async {
    final lib = AppScope.of(context).library;
    final text = _text.text;
    if (text.trim().isEmpty) {
      setState(() => _report = null);
      return;
    }
    // Spotify songs (not local files): look up their titles so they can
    // still match files you have.
    final ids = spotifyTrackIds(text);
    var titles = const <String, String>{};
    if (ids.isNotEmpty) {
      setState(() => _busy = 'Looking up ${ids.length} Spotify songs…');
      titles = await fetchSpotifyTitles(ids, progress: (n) {
        if (mounted && n % 10 == 0) setState(() => _busy = 'Looking up Spotify songs… $n/${ids.length}');
      });
    }
    if (!mounted) return;
    setState(() {
      _busy = null;
      _report = importSpotifyList(text, lib.songs, trackTitles: titles);
    });
  }

  Future<void> _save() async {
    final r = _report;
    if (r == null) return;
    final scope = AppScope.of(context);
    final nav = Navigator.of(context);
    final name = _name.text.trim().isEmpty ? 'Imported playlist' : _name.text.trim();
    // Same name as one you have: update it instead of making a copy.
    final existing = scope.playlists.byName(name);
    final pl = existing ?? await scope.playlists.create(name, songIds: r.matched, missing: [...r.missing, ...r.streaming]);
    if (existing != null) await scope.playlists.replaceSongs(existing, r.matched, [...r.missing, ...r.streaming]);
    nav.pushReplacement(quickRoute<void>(Backdrop(child: PlaylistScreen(playlistId: pl.id))));
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const ScreenHeader(title: 'Import from Spotify'),
          Text(
            'Two ways:\n'
            '• Phone or PC: in Spotify, playlist ⋯ › Share › Copy link, then tap "From a link" here.\n'
            '• PC (includes local files): open the playlist in Spotify, click a song, Ctrl+A then Ctrl+C, and paste it here.\n'
            'Songs are matched to your files by title, artist, album and length. Importing a playlist with the same name updates it.',
            style: Clay.book(16, color: Clay.bone),
          ),
          const SizedBox(height: 14),
          TextField(controller: _name, style: TextStyle(color: Clay.bone), decoration: const InputDecoration(hintText: 'Playlist name (e.g. Trip 3)')),
          const SizedBox(height: 10),
          TextField(
            controller: _text,
            minLines: 6,
            maxLines: 10,
            style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Clay.bone),
            decoration: const InputDecoration(hintText: 'https://open.spotify.com/local/…'),
            onChanged: (_) => setState(() => _report = null),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ClayButton(label: 'From a link', icon: Icons.link_rounded, color: Clay.moss, onTap: _busy != null ? null : () => _fromLink(), seed: 60),
              ClayButton(label: 'Paste', icon: Icons.content_paste_rounded, onTap: _busy != null ? null : _paste, seed: 61),
              ClayButton(label: 'Match songs', icon: Icons.manage_search_rounded, onTap: _busy != null ? null : _match, seed: 62),
            ],
          ),
          if (_busy != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Expanded(child: Text(_busy!, style: TextStyle(color: Clay.candle))),
              ]),
            ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_note!, style: TextStyle(color: Clay.ash, fontSize: 13)),
            ),
          if (r != null) ...[
            const SizedBox(height: 20),
            ClayBox(
              color: Clay.bruise,
              seed: 63,
              boil: true,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What I found', style: Clay.title(24)),
                  const SizedBox(height: 10),
                  _stat(Icons.check_circle_rounded, Clay.moss, '${r.matched.length} matched to your files'),
                  _stat(Icons.help_rounded, Clay.rose, '${r.missing.length} not found in your folders'),
                  _stat(Icons.cloud_rounded, Clay.ghost, '${r.streaming.length} Spotify songs you don\'t have as files'),
                  if (r.skippedLines > 0) _stat(Icons.remove_circle_outline, Clay.ash, '${r.skippedLines} lines weren\'t Spotify links'),
                  const SizedBox(height: 14),
                  ClayButton(
                    label: AppScope.of(context).playlists.byName(_name.text) != null ? 'Update playlist' : 'Save playlist',
                    icon: Icons.save_rounded,
                    color: Clay.pumpkin,
                    onTap: r.matched.isEmpty && r.missing.isEmpty ? null : _save,
                  ),
                ],
              ),
            ),
            if (r.missing.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Not found', style: Clay.title(22)),
              const SizedBox(height: 6),
              for (final m in r.missing.take(300))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('•  ${m.label}', style: TextStyle(color: Clay.ash, fontSize: 13)),
                ),
              if (r.missing.length > 300) Text('…and ${r.missing.length - 300} more', style: TextStyle(color: Clay.ash)),
            ],
          ],
        ],
    );
  }

  Widget _stat(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: Clay.bone, fontSize: 15))),
        ]),
      );
}
