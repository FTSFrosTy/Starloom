import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_scope.dart';
import '../services/cast.dart';
import '../services/connect.dart';
import '../theme/palette.dart';
import 'song_tile.dart' show promptText;

/// The "Connect to a device" button. Lights up while casting.
class DevicesButton extends StatelessWidget {
  const DevicesButton({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    final connect = AppScope.of(context).connect;
    return ListenableBuilder(
      listenable: connect,
      builder: (context, _) {
        final on = connect.casting != null;
        return IconButton(
          tooltip: on ? 'Playing on ${connect.casting!.name}' : 'Connect to a device',
          icon: Icon(on ? Icons.cast_connected_rounded : Icons.cast_rounded, size: size, color: on ? Clay.candle : Clay.bone),
          onPressed: () => showDevices(context),
        );
      },
    );
  }
}

/// "Playing on Living Room speaker" strip, shown only while casting.
class CastBanner extends StatelessWidget {
  const CastBanner({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final connect = AppScope.of(context).connect;
    return ListenableBuilder(
      listenable: connect,
      builder: (context, _) {
        final dev = connect.casting;
        if (dev == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => showDevices(context),
          child: Padding(
            padding: EdgeInsets.only(top: compact ? 2 : 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(dev.isSpeaker ? Icons.speaker_rounded : Icons.tv_rounded, size: compact ? 13 : 15, color: Clay.candle),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  connect.connecting ? 'Connecting to ${dev.name}…' : 'Playing on ${dev.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Clay.candle, fontWeight: FontWeight.w700, fontSize: compact ? 11.5 : 13),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

void showDevices(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheet) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.8),
      child: const _DevicesSheet(),
    ),
  );
}

class _DevicesSheet extends StatefulWidget {
  const _DevicesSheet();

  @override
  State<_DevicesSheet> createState() => _DevicesSheetState();
}

class _DevicesSheetState extends State<_DevicesSheet> {
  PeerStatus? _peer;
  bool _checkingPeer = false;
  String? _busy; // id of the row that's working

  ConnectService get _connect => AppScope.of(context).connect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _connect.scan();
      _refreshPeer();
    });
  }

  Future<void> _refreshPeer() async {
    if (!_connect.hasPeer) return;
    setState(() => _checkingPeer = true);
    final p = await _connect.checkPeer();
    if (mounted) {
      setState(() {
        _peer = p;
        _checkingPeer = false;
      });
    }
  }

  Future<void> _run(String id, Future<String?> Function() job, {bool close = true}) async {
    setState(() => _busy = id);
    final err = await job();
    if (!mounted) return;
    setState(() => _busy = null);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else if (close) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final connect = scope.connect;
    final here = Platform.isIOS ? 'This iPhone' : 'This computer';
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([connect, scope.player]),
        builder: (context, _) {
          final casting = connect.casting;
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text('Connect to a device', style: Clay.title(26)),
              ),

              // ---- this device ----
              _tile(
                icon: Platform.isIOS ? Icons.phone_iphone_rounded : Icons.computer_rounded,
                title: here,
                subtitle: casting == null ? (scope.player.playing ? 'Playing here' : 'Listening here') : 'Tap to bring the music back here',
                selected: casting == null,
                busy: _busy == 'here',
                onTap: casting == null ? null : () => _run('here', () async {
                      await connect.stopCast(keepPlaying: true);
                      return null;
                    }),
              ),

              // ---- the other Starloom ----
              if (connect.hasPeer) ...[
                _header('Starloom on your devices'),
                _peerTile(connect),
              ] else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                  child: Text(
                    Platform.isIOS
                        ? 'Pair with your PC in Settings › Open sync to switch music between them.'
                        : 'Turn on "Let my phone sync" in Settings › Open sync and pair your iPhone to switch music between them.',
                    style: TextStyle(color: Clay.ash, fontSize: 12.5),
                  ),
                ),

              // ---- speakers & TVs ----
              _header('Speakers & TVs', trailing: connect.scanning
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      tooltip: 'Look again',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.refresh_rounded, color: Clay.ash, size: 20),
                      onPressed: connect.scan,
                    )),
              if (connect.devices.isEmpty && !connect.scanning)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Text(
                    'No Google Home, Nest or Chromecast found. Make sure it\'s on the same Wi-Fi'
                    '${Platform.isWindows ? ', and that Windows Firewall lets Starloom use private networks' : Platform.isIOS ? ', and that Local Network is on for Starloom in iPhone Settings' : ''}.',
                    style: TextStyle(color: Clay.ash, fontSize: 12.5),
                  ),
                ),
              for (final d in connect.devices) _castTile(connect, d),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final ip = await promptText(context, title: 'Speaker IP address', hint: 'e.g. 192.168.1.42 (Google Home app › device › settings › Device information)');
                    if (ip == null || !mounted) return;
                    await _run('ip', () => connect.addByAddress(ip));
                  },
                  icon: Icon(Icons.add_rounded, color: Clay.candle, size: 18),
                  label: Text('Add a speaker by IP address', style: TextStyle(color: Clay.candle)),
                ),
              ),
              if (casting != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    'The speaker plays your original files, so the EQ doesn\'t apply there. '
                    '${Platform.isIOS ? 'Keep Starloom running: the speaker gets each song from this phone.' : 'Keep Starloom open: the speaker gets each song from this computer.'}',
                    style: TextStyle(color: Clay.ash, fontSize: 12),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
        child: Row(children: [
          Expanded(child: Text(text.toUpperCase(), style: TextStyle(color: Clay.ash, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w800))),
          ?trailing,
        ]),
      );

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    bool selected = false,
    bool busy = false,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Material(
      color: selected ? Clay.plum.withValues(alpha: 0.6) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: busy ? null : onTap,
        leading: Icon(icon, color: selected ? Clay.candle : Clay.bone, size: 28),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? Clay.candle : Clay.bone, fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Clay.ash, fontSize: 12.5)),
        trailing: busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : (trailing ?? (selected ? Icon(Icons.volume_up_rounded, color: Clay.candle) : null)),
      ),
    );
  }

  Widget _peerTile(ConnectService connect) {
    final p = _peer;
    final scope = AppScope.of(context);
    final name = p?.name ?? connect.peerLabel;
    final String subtitle;
    if (_checkingPeer && p == null) {
      subtitle = 'Checking…';
    } else if (p == null || !p.reachable) {
      subtitle = Platform.isIOS ? 'Not reachable. Is Starloom open on your PC?' : 'Not reachable. Open Starloom on your iPhone.';
    } else if (p.playing) {
      subtitle = 'Playing ${p.title ?? 'something'}${p.artist?.isNotEmpty == true ? ' · ${p.artist}' : ''}';
    } else {
      subtitle = scope.player.current == null ? 'Ready' : 'Tap to move what\'s playing there';
    }
    return _tile(
      icon: Platform.isIOS ? Icons.computer_rounded : Icons.phone_iphone_rounded,
      title: name,
      subtitle: subtitle,
      busy: _busy == 'peer',
      onTap: scope.player.current == null || p == null || !p.reachable ? _refreshPeer : () => _run('peer', connect.handOff),
      trailing: p != null && p.reachable && p.playing
          ? TextButton(
              onPressed: () => _run('peer', connect.takeOver),
              child: Text('Play here', style: TextStyle(color: Clay.candle, fontWeight: FontWeight.w800)),
            )
          : null,
    );
  }

  Widget _castTile(ConnectService connect, CastDevice d) {
    final on = connect.casting?.id == d.id;
    final working = _busy == d.id || (on && connect.connecting);
    return GestureDetector(
      onLongPress: () => connect.forgetDevice(d),
      child: _tile(
        icon: d.isSpeaker ? Icons.speaker_rounded : Icons.tv_rounded,
        title: d.name,
        subtitle: on
            ? (connect.castState == 'BUFFERING' ? 'Loading…' : 'Playing here · tap to disconnect')
            : (d.model.isEmpty ? d.host : d.model),
        selected: on,
        busy: working,
        onTap: on
            ? () => _run(d.id, () async {
                  await connect.stopCast(keepPlaying: true);
                  return null;
                })
            : () => _run(d.id, () => connect.startCast(d)),
      ),
    );
  }
}
