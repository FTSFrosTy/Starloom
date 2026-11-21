import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../models/models.dart' show Song;
import 'library.dart';

/// Wraps the mpv player: queue, transport, shuffle/repeat, lock screen.
/// Position is NOT pushed through notifyListeners (it changes many times a
/// second); widgets that need it listen to [positionStream] directly.
class PlayerService extends ChangeNotifier {
  PlayerService(this._library);

  final Library _library;

  /// Called when a new song starts (for play counts / recently played).
  void Function(String songId)? onSongStarted;
  final Player player = Player();
  final List<StreamSubscription<Object?>> _subs = [];

  /// Songs streamed from the PC (not in the local library), by id.
  final Map<String, Song> remote = {};

  List<Song> queue = const [];

  /// How many songs right after the current one were added by hand
  /// ("Add to queue" / "Play next"). They play before the rest of the
  /// album/playlist, in the order they were added.
  int queuedAhead = 0;

  /// Where the current queue came from ("Trip 3", "Liked Songs"…).
  String? playingFrom;
  int index = -1;
  bool playing = false;
  bool shuffle = false;
  Loop loop = Loop.off;
  Duration duration = Duration.zero;
  CoverArt? cover;
  double _volume = 100;

  /// Speaker volume while casting, otherwise this device's volume (0–100).
  double get volume => _output?.volume ?? _volume;

  RemoteOutput? _output;
  double _savedVolume = 100;

  /// Set while the sound goes to another speaker (Google Cast). The local
  /// player keeps running muted as the clock and the queue, so everything
  /// (lock screen, queue, scrubber) works the same.
  RemoteOutput? get output => _output;

  /// The speaker's volume or state changed.
  void outputChanged() => notifyListeners();

  Future<void> routeTo(RemoteOutput? out) async {
    if (out != null && _output == null) {
      _savedVolume = _volume;
      _output = out;
      await player.setVolume(0);
    } else if (out == null && _output != null) {
      _output = null;
      await player.setVolume(_savedVolume);
    } else {
      _output = out;
    }
    notifyListeners();
  }

  /// Id of the song playing now. Song rows listen to just this.
  final ValueNotifier<String?> currentId = ValueNotifier(null);

  /// When the sleep timer will pause playback, if set.
  DateTime? sleepAt;
  bool sleepAfterSong = false;
  Timer? _sleepTimer;

  /// Last playback error, shown once by the UI.
  final ValueNotifier<String?> errors = ValueNotifier(null);

  Song? get current => index >= 0 && index < queue.length ? queue[index] : null;
  Stream<Duration> get positionStream => player.stream.position;
  Duration get position => player.state.playback.position;

  Future<void> init() async {
    _subs.add(player.stream.playlist.listen(_onPlaylist));
    _subs.add(player.stream.playing.listen((v) {
      playing = v;
      notifyListeners();
    }));
    // [shuffle] is our own sticky mode (like Spotify's button), not mpv's
    // flag, which gets switched off and on while loading new lists.
    _subs.add(player.stream.loop.listen((v) {
      loop = v;
      notifyListeners();
    }));
    _subs.add(player.stream.duration.listen((v) {
      duration = v;
      notifyListeners();
    }));
    _subs.add(player.stream.coverArt.listen((v) {
      cover = v;
      notifyListeners();
    }));
    _subs.add(player.stream.volume.listen((v) {
      _volume = v;
      notifyListeners();
    }));
    _subs.add(player.stream.error.listen((e) {
      if (e is EndFileError) {
        errors.value = 'Couldn\'t play a song: ${e.message}';
      }
    }));

    // Visualizer feed: 20 bands, ~20 fps. The FFT only runs while the
    // visualizer is on screen (the stream is lazy).
    player.setSpectrum(const SpectrumSettings(
      bandCount: 20,
      bandLowHz: 40,
      bandHighHz: 16000,
      emitInterval: Duration(milliseconds: 50),
      attackSmoothing: 0.6,
      releaseSmoothing: 0.18,
    ));

    // Lock screen, Control Center, AirPods, Windows media keys.
    await player.setMediaSession(const MediaSession(
      appName: 'Starloom',
      actions: {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.next,
        MediaAction.previous,
        MediaAction.seek,
        MediaAction.setShuffle,
        MediaAction.setRepeatMode,
      },
    ));
  }

  void _onPlaylist(Playlist pl) {
    final songs = <Song>[];
    var newIndex = -1;
    for (var i = 0; i < pl.items.length; i++) {
      final id = pl.items[i].extras?['id'];
      final song = id is String ? (_library.byId(id) ?? remote[id]) : null;
      if (song == null) continue;
      if (i == pl.index) newIndex = songs.length;
      songs.add(song);
    }
    queue = songs;
    final before = currentId.value;
    final songChanged = newIndex != index || current?.id != before;
    index = newIndex;
    final now = current?.id;
    if (newIndex != index) {
      // Moving forward one step uses up a hand-queued song; jumping
      // anywhere else leaves the hand-queued block behind.
      if (newIndex == index + 1 && queuedAhead > 0) {
        queuedAhead--;
      } else if (newIndex != index + 1) {
        queuedAhead = 0;
      }
    }
    queuedAhead = queuedAhead.clamp(0, (songs.length - newIndex - 1).clamp(0, 1 << 20));
    if (songChanged && now != null && now != before) {
      if (sleepAfterSong && before != null) {
        sleepAfterSong = false;
        player.pause();
      }
      onSongStarted?.call(now);
    }
    currentId.value = now;
    notifyListeners();
  }

  Media _media(Song s) => Media(
        s.path.startsWith('http') ? s.path : Uri.file(s.path, windows: Platform.isWindows).toString(),
        extras: {'id': s.id, 'title': s.title, 'artist': s.artist, 'album': s.album},
      );

  /// Shuffle/repeat changed: remember them for next launch.
  void Function(bool shuffle, Loop loop)? onModesChanged;

  /// Puts back the shuffle/repeat buttons from last time.
  Future<void> restoreModes({required bool shuffle, required Loop loop}) async {
    this.shuffle = shuffle;
    this.loop = loop;
    await player.setLoop(loop);
    notifyListeners();
  }

  /// Replace the queue with [songs] and start at [start]. With shuffle on,
  /// that song plays first and the rest come in random order; turning
  /// shuffle off later puts the list back in order.
  Future<void> playSongs(List<Song> songs, int start, {bool shuffled = false, String? from}) async {
    if (songs.isEmpty) return;
    playingFrom = from;
    if (shuffled && !shuffle) {
      shuffle = true;
      onModesChanged?.call(shuffle, loop);
    }
    final at = shuffled ? Random().nextInt(songs.length) : start.clamp(0, songs.length - 1);
    // mpv's own shuffle flag would scramble the list as it loads.
    if (player.state.playback.shuffle) await player.setShuffle(false);
    queuedAhead = 0;
    await player.openAll(songs.map(_media).toList(), index: at, play: true);
    if (shuffle) await _shuffleAroundCurrent();
    notifyListeners();
  }

  /// Shuffles the queue but keeps the playing song first, so every other
  /// song is still ahead of you.
  Future<void> _shuffleAroundCurrent() async {
    final id = current?.id ?? currentId.value;
    await player.setShuffle(true);
    queuedAhead = 0;
    // The new order arrives from mpv a moment later.
    for (var t = 0; t < 10; t++) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final items = player.state.playback.playlist.items;
      final i = items.indexWhere((m) => m.extras?['id'] == id);
      if (i >= 0) {
        if (i > 0) await player.move(i, 0);
        return;
      }
    }
  }

  Future<void> togglePlay() async {
    if (current == null) return;
    playing ? await player.pause() : await player.play();
  }

  Future<void> next() async {
    await player.next();
  }

  /// Like most players: restart the song if we're past 3 s, else go back.
  Future<void> previous() async {
    if (position > const Duration(seconds: 3) || index <= 0) {
      await seek(Duration.zero);
    } else {
      await player.previous();
    }
  }

  Future<void> seek(Duration d) {
    _output?.seek(d);
    return player.seek(d);
  }

  Future<void> jumpTo(int i) => player.jump(i);

  Future<void> toggleShuffle() async {
    shuffle = !shuffle;
    notifyListeners();
    onModesChanged?.call(shuffle, loop);
    if (queue.isEmpty) return;
    if (shuffle) {
      await _shuffleAroundCurrent();
    } else {
      queuedAhead = 0;
      await player.setShuffle(false); // back to the original order
    }
  }

  Future<void> cycleLoop() async {
    final nextLoop = switch (loop) {
      Loop.off => Loop.playlist,
      Loop.playlist => Loop.file,
      _ => Loop.off,
    };
    loop = nextLoop;
    notifyListeners();
    onModesChanged?.call(shuffle, loop);
    await player.setLoop(nextLoop);
  }

  /// Straight after the current song, ahead of anything already queued.
  Future<void> playNext(Song s) async {
    if (current == null) return playSongs([s], 0);
    queuedAhead++;
    await player.insert(player.state.playback.playlist.index + 1, _media(s));
  }

  /// After the current song and the songs you already queued, but before
  /// the rest of the album/playlist.
  Future<void> addToQueue(Song s) async {
    if (current == null) return playSongs([s], 0);
    final at = player.state.playback.playlist.index + 1 + queuedAhead;
    queuedAhead++;
    if (at >= queue.length) {
      await player.add(_media(s));
    } else {
      await player.insert(at, _media(s));
    }
  }

  Future<void> setVolume(double v) async {
    final out = _output;
    if (out != null) {
      out.setVolume(v.clamp(0, 100).toDouble());
      notifyListeners();
      return;
    }
    await player.setVolume(v.clamp(0, 100).toDouble());
  }

  /// Queue editing. Indexes are positions in [queue], which matches mpv's
  /// playlist as long as every entry is a library song.
  Future<void> moveInQueue(int from, int to) async {
    if (from == to) return;
    await player.move(from, to);
  }

  Future<void> removeFromQueue(int i) {
    if (i > index && i <= index + queuedAhead) queuedAhead--;
    return player.remove(i);
  }

  Future<void> clearUpNext() async {
    queuedAhead = 0;
    for (var i = queue.length - 1; i > index; i--) {
      await player.remove(i);
    }
  }

  /// Clears only the songs you queued by hand.
  Future<void> clearQueued() async {
    for (var i = index + queuedAhead; i > index; i--) {
      await player.remove(i);
    }
    queuedAhead = 0;
    notifyListeners();
  }

  /// Pause after [d], or at the end of the current song when [endOfSong].
  void setSleepTimer(Duration? d, {bool endOfSong = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepAt = null;
    sleepAfterSong = endOfSong;
    if (d != null) {
      sleepAt = DateTime.now().add(d);
      _sleepTimer = Timer(d, () {
        player.pause();
        sleepAt = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}

/// Another speaker playing in sync with the (muted) local player.
abstract class RemoteOutput {
  String get name;

  /// 0–100.
  double get volume;
  void setVolume(double v);
  void seek(Duration d);
}
