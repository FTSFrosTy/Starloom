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

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _text.text = data!.text!;
      _match();
    }
  }

  void _match() {
    final lib = AppScope.of(context).library;
    setState(() => _report = _text.text.trim().isEmpty ? null : importSpotifyList(_text.text, lib.songs));
  }

  Future<void> _save() async {
    final r = _report;
    if (r == null) return;
    final scope = AppScope.of(context);
    final nav = Navigator.of(context);
    final pl = await scope.playlists.create(
      _name.text.trim().isEmpty ? 'Imported playlist' : _name.text,
      songIds: r.matched,
      missing: [...r.missing, ...r.streaming],
    );
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
            'In Spotify on your PC: open the playlist, click a song, press Ctrl+A then Ctrl+C. '
            'Paste it here. Local songs are matched to your files by title, artist, album and length.',
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
              ClayButton(label: 'Paste', icon: Icons.content_paste_rounded, onTap: _paste, seed: 61),
              ClayButton(label: 'Match songs', icon: Icons.manage_search_rounded, onTap: _match, seed: 62),
            ],
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
                  _stat(Icons.cloud_rounded, Clay.ghost, '${r.streaming.length} Spotify-only songs (skipped)'),
                  if (r.skippedLines > 0) _stat(Icons.remove_circle_outline, Clay.ash, '${r.skippedLines} lines weren\'t Spotify links'),
                  const SizedBox(height: 14),
                  ClayButton(
                    label: 'Save playlist',
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
