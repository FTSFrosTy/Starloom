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
import 'services/user_data.dart';
import 'theme/palette.dart';
import 'widgets/clay.dart';
import 'widgets/nav.dart';
import 'widgets/tap_fx.dart';

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
  final user = UserData(storage);

  await prefs.init();
  Squish.haptics = prefs.haptics;
  await Future.wait([playlists.init(), player.init(), user.init()]);
  await eq.init(player.player);
  await player.setVolume(prefs.volume);
  player.onSongStarted = user.recordPlay;

  runApp(AppScope(
    library: library,
    playlists: playlists,
    player: player,
    eq: eq,
    prefs: prefs,
    user: user,
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
  late final AppPrefs _prefs;
  late String _themeId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prefs = AppScope.of(context).prefs;
    _themeId = _prefs.themeId;
    _prefs.addListener(_onPrefs);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefs);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Theme colors are read straight from [Clay], so after a theme switch
  /// every widget is told to rebuild once (keeps all page/scroll state).
  void _onPrefs() {
    if (_prefs.themeId == _themeId) return;
    _themeId = _prefs.themeId;
    setState(() {});
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No animation work at all while the app is in the background; the
    // music keeps playing on its own.
    StopMotion.instance.foreground = state == AppLifecycleState.resumed;
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _prefs;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => MaterialApp(
        title: 'Starloom',
        debugShowCheckedModeBanner: false,
        navigatorKey: Nav.root,
        theme: Clay.theme(),
        builder: (context, child) {
          // Respect the system "Reduce Motion" setting too.
          StopMotion.instance.enabled = !prefs.reduceMotion && !MediaQuery.disableAnimationsOf(context);
          return TapFx(child: child!);
        },
        home: const HomeShell(),
      ),
    );
  }
}
