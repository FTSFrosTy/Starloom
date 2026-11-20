import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'screens/home_shell.dart';
import 'services/app_scope.dart';
import 'services/beat.dart';
import 'services/cover_finder.dart';
import 'services/eq.dart';
import 'services/library.dart';
import 'services/player_service.dart';
import 'services/playlists.dart';
import 'services/storage.dart';
import 'services/sync.dart';
import 'services/user_data.dart';
import 'theme/palette.dart';
import 'widgets/clay.dart';
import 'widgets/nav.dart';
import 'widgets/tap_fx.dart';
import 'widgets/ui_fx.dart';

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
  Beat.instance.attach(player.player);
  final sync = SyncService(storage, library, playlists, user, player);
  final covers = CoverFinder(storage, library);

  runApp(AppScope(
    library: library,
    playlists: playlists,
    player: player,
    eq: eq,
    prefs: prefs,
    user: user,
    sync: sync,
    covers: covers,
    child: const StarloomApp(),
  ));

  // Loads the cached library instantly, then rescans in the background.
  unawaited(library.init().then((_) async {
    await sync.init();
    await covers.init();
  }));
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

  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    // Load the sculpted clay pieces up front so buttons never pop in.
    for (final n in ['round_0', 'round_1', 'round_2', 'pill_0', 'pill_1', 'pill_2', 'panel']) {
      precacheImage(AssetImage('assets/clay/$n.png'), context);
    }
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
          // Dark status bar icons on the light themes.
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: Clay.current.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            child: TapFx(child: UiFx(player: AppScope.of(context).player, child: child!)),
          );
        },
        home: const HomeShell(),
      ),
    );
  }
}
