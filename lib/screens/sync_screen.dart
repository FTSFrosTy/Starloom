import 'dart:io';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../services/sync.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import '../widgets/nav.dart';
import 'home_shell.dart';

/// PC: turn on syncing and show the address + pairing code.
/// Phone: pair with the PC, then sync, copy songs, or stream the PC library.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _addr = TextEditingController();
  final _code = TextEditingController();
  List<RemoteSong>? _missingHere;
  List<Song>? _missingThere;
  String? _error;

  @override
  void dispose() {
    _addr.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _check(SyncService sync) async {
    setState(() => _error = null);
    try {
      await sync.loadPcLibrary();
      final here = await sync.missingHere();
      final there = await sync.missingOnPc();
      if (mounted) setState(() {
        _missingHere = here;
        _missingThere = there;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = AppScope.of(context).sync;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          const ScreenHeader(title: 'Sync'),
          if (sync.isHostPlatform) _host(sync) else _phone(sync),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children, int seed) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: ClayBox(
          color: Clay.panel,
          seed: seed,
          squareness: 5,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      );

  Widget _host(SyncService sync) {
    return Column(children: [
      _card([
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: Clay.candle,
          title: Text('Let my phone sync with this PC', style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w700)),
          subtitle: Text('Works on your home Wi-Fi while Starloom is open here.', style: TextStyle(color: Clay.ash, fontSize: 12.5)),
          value: sync.hostEnabled,
          onChanged: sync.setHostEnabled,
        ),
        if (sync.hostEnabled) ...[
          const SizedBox(height: 10),
          Text('On your iPhone: Starloom › Settings › Sync, then enter:', style: Clay.book(15)),
          const SizedBox(height: 10),
          _bigValue('PC address', sync.myAddresses.isEmpty ? 'Looking…' : sync.myAddresses.join('  or  ')),
          const SizedBox(height: 8),
          _bigValue('Pairing code', sync.code),
          const SizedBox(height: 8),
          TextButton(onPressed: sync.newCode, child: Text('Make a new code', style: TextStyle(color: Clay.candle))),
          Text(
            'If Windows asks whether to allow Starloom on networks, allow it on Private networks.',
            style: TextStyle(color: Clay.ash, fontSize: 12.5),
          ),
        ],
        if (sync.status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(sync.status!, style: TextStyle(color: Clay.rose))),
      ], 1201),
      _card([
        Text('What syncs', style: Clay.title(22)),
        const SizedBox(height: 6),
        Text(
          '• Playlists and liked songs, both ways (the newest change wins)\n'
          '• Songs the phone is missing can be copied from this PC\n'
          '• Songs only on the phone land in a "From iPhone" folder here\n'
          '• The phone can stream this PC\'s whole library over Wi-Fi',
          style: TextStyle(color: Clay.bone, height: 1.5),
        ),
      ], 1202),
    ]);
  }

  Widget _bigValue(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: TextStyle(color: Clay.ash, fontSize: 11, letterSpacing: 1.3, fontWeight: FontWeight.w700)),
        SelectableText(value, style: Clay.title(30, color: Clay.candle)),
      ]);

  Widget _phone(SyncService sync) {
    if (!sync.paired) {
      return _card([
        Text('Pair with your PC', style: Clay.title(24)),
        const SizedBox(height: 6),
        Text('On the PC: Starloom › Settings › Sync › turn on "Let my phone sync". It shows an address and a code.', style: Clay.book(15)),
        const SizedBox(height: 12),
        TextField(
          controller: _addr,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: Clay.bone),
          decoration: const InputDecoration(hintText: 'PC address, like 192.168.1.23'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          style: TextStyle(color: Clay.bone),
          decoration: const InputDecoration(hintText: 'Pairing code'),
        ),
        const SizedBox(height: 12),
        ClayButton(
          label: 'Connect',
          icon: Icons.link_rounded,
          color: Clay.pumpkin,
          onTap: () async {
            final err = await sync.pair(_addr.text, _code.text);
            if (mounted) setState(() => _error = err);
            if (err == null && mounted) _check(sync);
          },
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Clay.rose))),
      ], 1301);
    }

    final busy = sync.busy;
    return Column(children: [
      _card([
        Row(children: [
          Icon(Icons.computer_rounded, color: Clay.candle),
          const SizedBox(width: 10),
          Expanded(child: Text('Paired with ${sync.pcAddress}', style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w700))),
          TextButton(onPressed: sync.unpair, child: Text('Unpair', style: TextStyle(color: Clay.ash))),
        ]),
        if (sync.lastSyncMs != null)
          Text('Last synced ${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(sync.lastSyncMs!)).format(context)}', style: TextStyle(color: Clay.ash, fontSize: 12.5)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          ClayButton(
            label: 'Sync playlists & likes',
            icon: Icons.sync_rounded,
            color: Clay.pumpkin,
            onTap: busy
                ? null
                : () async {
                    final err = await sync.syncNow();
                    if (mounted) setState(() => _error = err);
                  },
          ),
          ClayButton(
            label: 'Stream PC library',
            icon: Icons.wifi_tethering_rounded,
            seed: 22,
            onTap: () => Nav.push(const PcLibraryScreen()),
          ),
        ]),
        if (sync.status != null) ...[
          const SizedBox(height: 10),
          Text(sync.status!, style: TextStyle(color: Clay.bone)),
          if (sync.progress != null) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: sync.progress, color: Clay.candle, backgroundColor: Clay.bruise),
          ],
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Clay.rose))),
      ], 1302),
      _card([
        Text('Songs', style: Clay.title(24)),
        const SizedBox(height: 8),
        if (_missingHere == null)
          ClayButton(label: 'Compare with PC', icon: Icons.compare_arrows_rounded, seed: 23, onTap: busy ? null : () => _check(sync))
        else ...[
          _songAction(
            '${_missingHere!.length} songs are on the PC but not here',
            'Copy to iPhone',
            Icons.download_rounded,
            busy || _missingHere!.isEmpty
                ? null
                : () async {
                    final err = await sync.copyFromPc(_missingHere!);
                    if (mounted) setState(() => _error = err);
                    _check(sync);
                  },
          ),
          const SizedBox(height: 10),
          _songAction(
            '${_missingThere!.length} songs are here but not on the PC',
            'Send to PC',
            Icons.upload_rounded,
            busy || _missingThere!.isEmpty
                ? null
                : () async {
                    final err = await sync.sendToPc(_missingThere!);
                    if (mounted) setState(() => _error = err);
                    _check(sync);
                  },
          ),
          const SizedBox(height: 8),
          Text(
            Platform.isIOS ? 'Copied songs go to Files › On My iPhone › Starloom › From PC.' : '',
            style: TextStyle(color: Clay.ash, fontSize: 12.5),
          ),
        ],
      ], 1303),
    ]);
  }

  Widget _songAction(String text, String button, IconData icon, VoidCallback? onTap) => Row(children: [
        Expanded(child: Text(text, style: TextStyle(color: Clay.bone))),
        const SizedBox(width: 10),
        ClayButton(label: button, icon: icon, seed: text.length, onTap: onTap),
      ]);
}

/// Browse and play the PC's library over Wi-Fi (nothing is copied).
class PcLibraryScreen extends StatefulWidget {
  const PcLibraryScreen({super.key});

  @override
  State<PcLibraryScreen> createState() => _PcLibraryScreenState();
}

class _PcLibraryScreenState extends State<PcLibraryScreen> {
  String _query = '';
  Future<List<RemoteSong>>? _load;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load ??= AppScope.of(context).sync.loadPcLibrary();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return FutureBuilder<List<RemoteSong>>(
      future: _load,
      builder: (context, snap) {
        if (snap.hasError) {
          return Column(children: [
            const ScreenHeader(title: 'PC library'),
            Padding(padding: const EdgeInsets.all(24), child: Text('Couldn\'t reach your PC: ${snap.error}', style: TextStyle(color: Clay.rose))),
          ]);
        }
        if (!snap.hasData) {
          return Column(children: [
            const ScreenHeader(title: 'PC library'),
            Padding(padding: const EdgeInsets.all(24), child: Text('Asking your PC…', style: Clay.book(17))),
          ]);
        }
        final all = snap.data!;
        final words = _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        final list = words.isEmpty ? all : all.where((s) => words.every('${s.title} ${s.artist} ${s.album}'.toLowerCase().contains)).toList();
        return Column(children: [
          ScreenHeader(title: 'PC library', subtitle: '${songCount(all.length)} · streaming over Wi-Fi'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              style: TextStyle(color: Clay.bone),
              decoration: InputDecoration(hintText: 'Search the PC', prefixIcon: Icon(Icons.search, color: Clay.ash)),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemExtent: 62,
              itemCount: list.length,
              itemBuilder: (context, i) {
                final s = list[i];
                return ListTile(
                  onTap: () => scope.player.playSongs(scope.sync.streamable(list), i),
                  leading: Pebble(seedText: s.album.isNotEmpty ? s.album : s.title, size: 42),
                  title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.bone, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    [s.artist, s.album].where((x) => x.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Clay.ash, fontSize: 12.5),
                  ),
                  trailing: Icon(Icons.wifi_rounded, color: Clay.ash, size: 18),
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}
