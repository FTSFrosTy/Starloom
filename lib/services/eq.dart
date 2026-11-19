import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'storage.dart';

const List<double> kEqFrequencies = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
const List<String> kEqLabels = ['31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];
const double kBandMin = -12, kBandMax = 12;
const double kBassMax = 12;
const double kTrebleMin = -6, kTrebleMax = 9;
const double kPreampMin = -12, kPreampMax = 6;

class EqPreset {
  const EqPreset(this.name, this.bands, {this.bass = 0, this.treble = 0, this.preamp = 0});
  final String name;
  final List<double> bands;
  final double bass;
  final double treble;
  final double preamp;
}

const List<EqPreset> kPresets = [
  EqPreset('Flat', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  EqPreset('Bass Boost', [6, 5, 4, 2, 0, 0, 0, 0, 0, 0], bass: 3, preamp: -3),
  EqPreset('Bass Max', [9, 8, 6, 3, 0, -1, 0, 0, 0, 0], bass: 6, preamp: -6),
  EqPreset('Hip-Hop', [5, 4, 2, 1, -1, -1, 1, 1, 2, 3], bass: 2, preamp: -3),
  EqPreset('Rock', [4, 3, 1, 0, -1, 0, 2, 3, 4, 4], preamp: -3),
  EqPreset('Vocals', [-2, -2, -1, 1, 3, 4, 3, 2, 0, -1], preamp: -2),
  EqPreset('Treble', [0, 0, 0, 0, 0, 1, 2, 4, 5, 6], treble: 2, preamp: -3),
  EqPreset('V-Shape', [5, 4, 2, 0, -2, -2, 0, 2, 4, 5], preamp: -3),
  EqPreset('Late Night', [-2, -1, 0, 1, 2, 2, 1, 0, -2, -4]),
];

class EqSettings {
  EqSettings({
    this.enabled = true,
    List<double>? bands,
    this.bass = 0,
    this.treble = 0,
    this.preamp = 0,
    this.presetName = 'Flat',
  }) : bands = bands ?? List<double>.filled(10, 0);

  bool enabled;
  final List<double> bands;
  double bass;
  double treble;
  double preamp;
  String presetName;

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'bands': bands,
        'bass': bass,
        'treble': treble,
        'preamp': preamp,
        'presetName': presetName,
      };

  static EqSettings fromJson(Map<String, Object?> j) {
    final raw = (j['bands'] as List?)?.map((e) => (e as num).toDouble()).toList();
    return EqSettings(
      enabled: (j['enabled'] as bool?) ?? true,
      bands: raw != null && raw.length == 10 ? raw : null,
      bass: (j['bass'] as num?)?.toDouble() ?? 0,
      treble: (j['treble'] as num?)?.toDouble() ?? 0,
      preamp: (j['preamp'] as num?)?.toDouble() ?? 0,
      presetName: (j['presetName'] as String?) ?? 'Custom',
    );
  }

  /// The filter chain. The structure never changes (only values and
  /// `enabled`), so mpv updates it live without audio dropouts.
  List<AudioEffect> toEffects() {
    final on = enabled;
    return [
      for (var i = 0; i < 10; i++)
        EqualizerEffect(
          enabled: on,
          frequency: kEqFrequencies[i],
          gain: bands[i],
          width: 1.0,
          widthType: EqualizerWidthType.o, // one octave per band
        ),
      BassEffect(enabled: on, frequency: 80, gain: bass),
      TrebleEffect(enabled: on, frequency: 6000, gain: treble),
      // Last stage: catches peaks so heavy bass boost doesn't crackle.
      const AlimiterEffect(limit: 0.97, level: false),
    ];
  }
}

/// Holds the EQ state, saves it, and pushes it to the player.
class EqController extends ChangeNotifier {
  EqController(this._storage);

  final Storage _storage;
  EqSettings settings = EqSettings();
  Player? _player;

  bool _applying = false;
  bool _dirty = false;

  Future<void> init(Player player) async {
    _player = player;
    final raw = await _storage.read('eq.json');
    if (raw is Map) settings = EqSettings.fromJson(raw.cast<String, Object?>());
    await _apply();
  }

  void setEnabled(bool v) {
    settings.enabled = v;
    _changed();
  }

  void setBand(int i, double gain) {
    settings.bands[i] = gain;
    settings.presetName = 'Custom';
    _changed();
  }

  void setBass(double v) {
    settings.bass = v;
    settings.presetName = 'Custom';
    _changed();
  }

  void setTreble(double v) {
    settings.treble = v;
    settings.presetName = 'Custom';
    _changed();
  }

  void setPreamp(double v) {
    settings.preamp = v;
    _changed();
  }

  void applyPreset(EqPreset p) {
    for (var i = 0; i < 10; i++) {
      settings.bands[i] = p.bands[i];
    }
    settings.bass = p.bass;
    settings.treble = p.treble;
    settings.preamp = p.preamp;
    settings.presetName = p.name;
    settings.enabled = true;
    _changed();
  }

  void _changed() {
    notifyListeners();
    _apply();
    _storage.write('eq.json', settings.toJson());
  }

  /// Slider drags fire many updates; keep one apply in flight and send only
  /// the latest values after it finishes.
  Future<void> _apply() async {
    final player = _player;
    if (player == null) return;
    if (_applying) {
      _dirty = true;
      return;
    }
    _applying = true;
    try {
      do {
        _dirty = false;
        await player.setAudioEffects(settings.toEffects());
        await player.setVolumeGain(settings.enabled ? settings.preamp : 0);
      } while (_dirty);
    } catch (e) {
      debugPrint('EQ apply failed: $e');
    } finally {
      _applying = false;
    }
  }
}
