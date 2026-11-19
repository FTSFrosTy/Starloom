import 'dart:io';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import 'home_shell.dart';

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
                        child: ClayBox(
                          color: t.surface,
                          seed: t.id.hashCode,
                          squareness: 4,
                          depth: 4,
                          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [t.bg, t.accent2, t.accent]),
                                border: Border.all(color: scope.prefs.themeId == t.id ? t.accent : Colors.transparent, width: 2),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(t.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
                            if (scope.prefs.themeId == t.id) ...[const SizedBox(width: 6), Icon(Icons.check_rounded, size: 18, color: t.accent)],
                          ]),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Text('More 3D clay worlds are on the way: Gothic Town, Ghost Town, Snow Village, Harvest.', style: Clay.book(14)),
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
