import 'dart:io';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import '../widgets/nav.dart';
import 'home_shell.dart';
import 'sync_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.library, scope.prefs]),
      builder: (context, _) {
        final lib = scope.library;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const ScreenHeader(title: 'Settings'),
            _Section(
              title: 'Music folders',
              seed: 1001,
              children: [
                for (final src in lib.sources)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      src.kind == SourceKind.appFolder ? Icons.phone_iphone_rounded : Icons.folder_rounded,
                      color: src.error != null ? Clay.rose : Clay.candle,
                    ),
                    title: Text(src.label, style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      src.error ??
                          '${songCount(lib.songs.where((s) => s.id.startsWith('${src.id}::')).length)}'
                              '${src.kind == SourceKind.appFolder ? '  ·  Files › On My iPhone › Starloom' : ''}',
                      style: TextStyle(color: src.error != null ? Clay.rose : Clay.ash, fontSize: 12.5),
                    ),
                    trailing: src.kind == SourceKind.appFolder
                        ? null
                        : IconButton(
                            tooltip: 'Remove folder',
                            icon: Icon(Icons.close_rounded, color: Clay.ash),
                            onPressed: () => lib.removeSource(src.id),
                          ),
                  ),
                if (lib.sources.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('No folders yet.', style: Clay.book(15)),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ClayButton(
                      label: 'Add folder',
                      icon: Icons.create_new_folder_rounded,
                      color: Clay.pumpkin,
                      seed: 1002,
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final err = await lib.addFolder();
                        if (err != null) messenger.showSnackBar(SnackBar(content: Text(err)));
                      },
                    ),
                    ClayButton(
                      label: lib.scanning ? 'Scanning…' : 'Rescan',
                      icon: Icons.refresh_rounded,
                      seed: 1003,
                      onTap: lib.scanning ? null : lib.rescan,
                    ),
                  ],
                ),
                if (lib.status != null && !lib.scanning)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text(lib.status!, style: TextStyle(color: Clay.rose))),
                if (Platform.isIOS)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Two ways to get music in:\n'
                      '• Add folder → pick a folder that already has songs (for example On My iPhone › Spotify).\n'
                      '• Or copy songs from your PC with Apple Devices: your iPhone → Files → Starloom, then drag songs in.',
                      style: Clay.book(14.5),
                    ),
                  ),
              ],
            ),
            _Section(
              title: Platform.isIOS ? 'Sync with your PC' : 'Sync with your phone',
              seed: 1005,
              children: [
                Text(
                  'Playlists and likes sync both ways over Wi-Fi. Copy songs either direction, or stream your PC library on the phone.',
                  style: Clay.book(14.5),
                ),
                const SizedBox(height: 10),
                ClayButton(
                  label: 'Open sync',
                  icon: Icons.sync_rounded,
                  color: Clay.pumpkin,
                  seed: 1006,
                  onTap: () => Nav.push(const SyncScreen()),
                ),
              ],
            ),
            _Section(
              title: 'Look & feel',
              seed: 1010,
              children: [
                Text('Theme', style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final t in kThemes)
                      Squish(
                        onTap: () => scope.prefs.setTheme(t.id),
                        child: SizedBox(
                          width: 132,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              width: 132,
                              height: 132,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: scope.prefs.themeId == t.id ? Clay.candle : Colors.transparent, width: 3),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 4))],
                                gradient: t.plate == null ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [t.bg, t.surfaceHi]) : null,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: t.plate != null
                                  ? Image.asset(t.plate!, fit: BoxFit.cover, cacheWidth: 300)
                                  : Center(child: Icon(Icons.nightlight_round, color: t.accent, size: 44)),
                            ),
                            const SizedBox(height: 6),
                            Row(children: [
                              Expanded(child: Text(t.name, style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w700))),
                              if (scope.prefs.themeId == t.id) Icon(Icons.check_circle_rounded, size: 18, color: Clay.candle),
                            ]),
                            Text(t.blurb, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.ash, fontSize: 11.5)),
                          ]),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Text('Moonlit is the original. The others are real 3D clay sets, built and lit in Blender.', style: Clay.book(14)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: Clay.candle,
                  title: Text('Haptics', style: TextStyle(color: Clay.bone)),
                  subtitle: Text('A light tick when you press clay buttons.', style: TextStyle(color: Clay.ash, fontSize: 12.5)),
                  value: scope.prefs.haptics,
                  onChanged: (v) {
                    Squish.haptics = v;
                    scope.prefs.setHaptics(v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: Clay.candle,
                  title: Text('Reduce motion', style: TextStyle(color: Clay.bone)),
                  subtitle: Text('Stops the stop-motion wobble and spinning. Saves a little battery.', style: TextStyle(color: Clay.ash, fontSize: 12.5)),
                  value: scope.prefs.reduceMotion,
                  onChanged: scope.prefs.setReduceMotion,
                ),
              ],
            ),
            _Section(
              title: 'About',
              seed: 1020,
              children: [
                Text('Starloom 0.2', style: Clay.title(22)),
                const SizedBox(height: 4),
                Text('Plays your own music files. Audio engine: mpv (LGPL).', style: Clay.book(15)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => showLicensePage(context: context, applicationName: 'Starloom'),
                  child: Text('Open-source licenses', style: TextStyle(color: Clay.candle)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, required this.seed});

  final String title;
  final List<Widget> children;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: ClayBox(
        color: Clay.panel,
        seed: seed,
        squareness: 5,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Clay.title(24, color: Clay.candle)),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}
