import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'screens/home_shell.dart';
import 'services/app_scope.dart';
import 'services/eq.dart';
import 'services/library.dart';
import 'services/player_service.dart';
import 'services/playlists.dart';
import 'services/storage.dart';
import 'theme/palette.dart';
import 'widgets/clay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MpvAudioKit.ensureInitialized();

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Mystery Quest font'], await rootBundle.loadString('assets/fonts/OFL-MysteryQuest.txt'));
    yield LicenseEntryWithLineBreaks(['IM FELL English font'], await rootBundle.loadString('assets/fonts/OFL-IMFellEnglish.txt'));
  });

  final storage = await Storage.open();
  final prefs = AppPrefs(storage);
  final library = Library(storage);
  final playlists = PlaylistStore(storage);
  final player = PlayerService(library);
  final eq = EqController(storage);

  await prefs.init();
  await Future.wait([playlists.init(), player.init()]);
  await eq.init(player.player);

  runApp(AppScope(
    library: library,
    playlists: playlists,
    player: player,
    eq: eq,
    prefs: prefs,
    child: const StarloomApp(),
  ));

  // Loads the cached library instantly, then rescans in the background.
  unawaited(library.init());
}

class StarloomApp extends StatefulWidget {
  const StarloomApp({super.key});

  @override
  State<StarloomApp> createState() => _StarloomAppState();
}

class _StarloomAppState extends State<StarloomApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No animation work at all while the app is in the background; the
    // music keeps playing on its own.
    StopMotion.instance.foreground = state == AppLifecycleState.resumed;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Starloom',
      debugShowCheckedModeBanner: false,
      theme: Clay.theme(),
      builder: (context, child) {
        // Respect the system "Reduce Motion" setting too.
        final prefs = AppScope.of(context).prefs;
        StopMotion.instance.enabled = !prefs.reduceMotion && !MediaQuery.disableAnimationsOf(context);
        return child!;
      },
      home: const HomeShell(),
    );
  }
}
