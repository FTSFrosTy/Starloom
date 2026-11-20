import 'dart:async';
import 'dart:math' as math;

import 'package:mpv_audio_kit/mpv_audio_kit.dart';

/// The music's pulse for the scenery: smoothed bass and overall energy,
/// read by the backdrop so windows, lamps and the moon throb with the song.
class Beat {
  Beat._();
  static final Beat instance = Beat._();

  double bass = 0;
  double energy = 0;
  double _bassT = 0, _energyT = 0;
  StreamSubscription<FftFrame>? _sub;
  DateTime _last = DateTime.now();

  void attach(Player player) {
    _sub?.cancel();
    _sub = player.stream.fft.listen((f) {
      final d = f.bands;
      if (d.isEmpty) return;
      _bassT = d.length >= 3 ? (d[0] + d[1] + d[2]) / 3 : d[0];
      var e = 0.0;
      for (final v in d) {
        e += v;
      }
      _energyT = e / d.length;
    });
  }

  /// Call once per animation frame; eases toward the latest values
  /// (fast attack, slow release) and decays to calm when music stops.
  void step() {
    final now = DateTime.now();
    final dt = (now.difference(_last).inMicroseconds / 1e6).clamp(0.0, 0.2);
    _last = now;
    _bassT *= math.pow(0.4, dt).toDouble();
    _energyT *= math.pow(0.4, dt).toDouble();
    bass += (_bassT - bass) * math.min(1.0, (_bassT > bass ? 14 : 4) * dt);
    energy += (_energyT - energy) * math.min(1.0, (_energyT > energy ? 10 : 3) * dt);
  }
}
