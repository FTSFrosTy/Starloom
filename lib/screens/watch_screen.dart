import 'package:flutter/material.dart';

import '../services/app_scope.dart';
import '../services/watch_bridge.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import 'home_shell.dart';

/// iPhone: choose which playlists live on the Apple Watch.
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  String? _busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).watch.refresh();
    });
  }

  String _mb(int bytes) => bytes <= 0 ? '' : '${(bytes / (1024 * 1024)).toStringAsFixed(bytes > 100 * 1024 * 1024 ? 0 : 1)} MB';

  Future<void> _toggle(WatchBridge w, String id, String name, bool on) async {
    setState(() => _busy = id);
    if (on) {
      final n = await w.put(id, name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(n == 0 ? '"$name" is on your watch.' : 'Copying $n songs to your watch. Keep the watch on its charger and near your phone to speed it up.'),
        ));
      }
    } else {
      await w.remove(id);
    }
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final w = scope.watch;
    return ListenableBuilder(
      listenable: Listenable.merge([w, scope.playlists, scope.user]),
      builder: (context, _) {
        final lists = <(String, String, int)>[
          ('all', 'Everything on this iPhone', w.songsOf('all').length),
          ('liked', 'Liked Songs', scope.user.liked.length),
          for (final pl in scope.playlists.playlists) (pl.id, pl.name, pl.songIds.length),
        ];
        return ListView(
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            const ScreenHeader(title: 'Apple Watch', subtitle: 'Music on your wrist'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: ClayBox(
                color: Clay.bruise,
                seed: 3301,
                squareness: 5,
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.watch_rounded, color: w.installed ? Clay.moss : Clay.ash),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_statusText(w), style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w700))),
                  ]),
                  if (w.pending > 0) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Expanded(child: Text('${w.pending} songs still copying', style: TextStyle(color: Clay.candle))),
                      TextButton(onPressed: w.cancelPending, child: Text('Stop', style: TextStyle(color: Clay.ash))),
                    ]),
                  ],
                  if (w.lastError != null) ...[
                    const SizedBox(height: 8),
                    Text(w.lastError!, style: TextStyle(color: Clay.rose, fontSize: 12.5)),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Turn on "Everything" to keep the watch in sync with every song on this phone, or pick playlists. '
                    'New songs copy over by themselves whenever Starloom is open. Then on the watch: open Starloom, connect AirPods, and play. '
                    'Copying goes faster with the watch on its charger. Ogg/Opus files are skipped (the watch can\'t play them).',
                    style: Clay.book(13.5),
                  ),
                  if (w.onWatch.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () async {
                        final n = await w.syncAll();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n == 0 ? 'Watch is up to date.' : 'Copying $n new songs.')));
                        }
                      },
                      icon: Icon(Icons.sync_rounded, color: Clay.candle, size: 18),
                      label: Text('Copy new songs in these playlists', style: TextStyle(color: Clay.candle)),
                    ),
                  ],
                ]),
              ),
            ),
            for (final (id, name, count) in lists)
              SwitchListTile(
                activeThumbColor: Clay.candle,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                secondary: _busy == id
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        switch (id) { 'liked' => Icons.favorite_rounded, 'all' => Icons.library_music_rounded, _ => Icons.queue_music_rounded },
                        color: id == 'liked' ? Clay.rose : (id == 'all' ? Clay.candle : Clay.ash),
                      ),
                title: Text(name, style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  [
                    '$count songs',
                    if (w.isOn(id) && w.bytesToSend(id) > 0) '${_mb(w.bytesToSend(id))} not copied yet',
                    if (!w.isOn(id)) _mb(w.songsOf(id).fold(0, (a, s) => a + s.size)),
                  ].where((t) => t.isNotEmpty).join(' · '),
                  style: TextStyle(color: Clay.ash, fontSize: 12.5),
                ),
                value: w.isOn(id),
                onChanged: _busy != null || !w.supported ? null : (v) => _toggle(w, id, name, v),
              ),
          ],
        );
      },
    );
  }

  String _statusText(WatchBridge w) {
    if (!w.supported) return 'This iPhone can\'t pair with an Apple Watch.';
    if (!w.paired) return 'No Apple Watch paired with this iPhone.';
    if (!w.installed) return 'Install Starloom on the watch: Watch app on your iPhone › My Watch › scroll to Available Apps › Starloom › Install.';
    return w.reachable ? 'Watch connected' : 'Watch paired · open Starloom on it to finish copying';
  }
}
