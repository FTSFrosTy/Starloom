import 'package:flutter/material.dart';

import '../services/app_scope.dart';
import '../services/eq.dart';
import '../theme/palette.dart';
import '../widgets/clay.dart';
import 'home_shell.dart';

class EqScreen extends StatelessWidget {
  const EqScreen({super.key, this.showBack = false});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final eq = AppScope.of(context).eq;
    return ListenableBuilder(
      listenable: eq,
      builder: (context, _) {
        final s = eq.settings;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: ScreenHeader(
                    title: 'Equalizer',
                    subtitle: s.enabled ? s.presetName : 'Off',
                    trailing: [
                      Switch(
                        value: s.enabled,
                        activeThumbColor: Clay.candle,
                        onChanged: eq.setEnabled,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: kPresets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final p = kPresets[i];
                  final selected = s.enabled && s.presetName == p.name;
                  return Squish(
                    onTap: () => eq.applyPreset(p),
                    child: ClayBox(
                      color: selected ? Clay.pumpkin : Clay.bruise,
                      seed: 700 + i,
                      squareness: 3,
                      depth: 3,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(p.name, style: TextStyle(color: selected ? Clay.onAccent : Clay.bone, fontWeight: FontWeight.w700)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Opacity(
              opacity: s.enabled ? 1 : 0.45,
              child: IgnorePointer(
                ignoring: !s.enabled,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: ClayBox(
                        color: Clay.panel,
                        seed: 901,
                        squareness: 5,
                        padding: const EdgeInsets.fromLTRB(6, 14, 6, 10),
                        child: SizedBox(
                          height: 250,
                          child: Row(
                            children: [
                              for (var i = 0; i < 10; i++)
                                Expanded(
                                  child: Column(
                                    children: [
                                      Text(_db(s.bands[i]), style: TextStyle(fontSize: 10.5, color: Clay.bone)),
                                      const SizedBox(height: 4),
                                      Expanded(
                                        child: ClaySlider(
                                          vertical: true,
                                          centerZero: true,
                                          thickness: 30,
                                          seed: 800 + i,
                                          color: Color.lerp(Clay.pumpkin, Clay.ghost, i / 9)!,
                                          value: (s.bands[i] - kBandMin) / (kBandMax - kBandMin),
                                          onChanged: (v) => eq.setBand(i, _snap(kBandMin + v * (kBandMax - kBandMin))),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(kEqLabels[i], style: TextStyle(fontSize: 10.5, color: Clay.ash)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _KnobRow(
                      label: 'Bass boost',
                      value: s.bass,
                      min: 0,
                      max: kBassMax,
                      color: Clay.pumpkin,
                      seed: 951,
                      onChanged: eq.setBass,
                    ),
                    _KnobRow(
                      label: 'Treble',
                      value: s.treble,
                      min: kTrebleMin,
                      max: kTrebleMax,
                      color: Clay.ghost,
                      seed: 952,
                      centerZero: true,
                      onChanged: eq.setTreble,
                    ),
                    _KnobRow(
                      label: 'Preamp',
                      value: s.preamp,
                      min: kPreampMin,
                      max: kPreampMax,
                      color: Clay.candle,
                      seed: 953,
                      centerZero: true,
                      onChanged: eq.setPreamp,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Text(
                        'Tip: if heavy bass sounds crunchy, lower Preamp a few dB. A limiter at the end keeps peaks from clipping.',
                        style: Clay.book(14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static double _snap(double v) => (v * 2).round() / 2; // half-dB steps

  static String _db(double v) {
    if (v.abs() < 0.05) return '0';
    final t = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
    return v > 0 ? '+$t' : t;
  }
}

class _KnobRow extends StatelessWidget {
  const _KnobRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.seed,
    required this.onChanged,
    this.centerZero = false,
  });

  final String label;
  final double value, min, max;
  final Color color;
  final int seed;
  final bool centerZero;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 92, child: Text(label, style: Clay.title(19))),
          Expanded(
            child: ClaySlider(
              value: (value - min) / (max - min),
              color: color,
              seed: seed,
              thickness: 34,
              centerZero: centerZero && min < 0,
              onChanged: (v) => onChanged(EqScreen._snap(min + v * (max - min))),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text('${EqScreen._db(value)} dB', textAlign: TextAlign.right, style: TextStyle(color: Clay.bone, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
