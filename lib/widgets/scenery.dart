import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../theme/palette.dart';
import 'clay.dart';

/// The moonlit model set behind every screen: crooked moon, twinkling
/// stars, lumpy hills, a bare tree and a few moths, all stepping at 12 fps.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child, this.animate = true, this.scrim = true});

  final Widget child;
  final bool animate;

  /// Shade the scenery so text on top stays readable.
  final bool scrim;

  @override
  Widget build(BuildContext context) {
    final t = Clay.current;
    final moving = animate && StopMotion.instance.enabled;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (t.backdrop == BackdropKind.plate && t.plate != null)
          _Plate(theme: t, animate: moving, scrim: scrim)
        else
          RepaintBoundary(child: CustomPaint(painter: _SetPainter(animate: moving))),
        child,
      ],
    );
  }
}

/// A pre-rendered 3D clay set (made in Blender) with live stop-motion
/// touches on top: falling snow, leaves, dust or drifting fog, and the
/// faint light flicker you get between frames of a real stop-motion film.
class _Plate extends StatelessWidget {
  const _Plate({required this.theme, required this.animate, required this.scrim});

  final StarTheme theme;
  final bool animate;
  final bool scrim;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final longest = (size.longestSide * dpr).clamp(600, 1440).round();
    final shade = theme.bg;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: Image(
            image: ResizeImage(AssetImage(theme.plate!), width: longest, height: longest, policy: ResizeImagePolicy.fit),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
        ),
        RepaintBoundary(child: CustomPaint(painter: _PlateFx(theme.id, animate: animate))),
        if (scrim)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: theme.dark
                      ? [shade.withValues(alpha: 0.25), shade.withValues(alpha: 0.45), shade.withValues(alpha: 0.72)]
                      : [shade.withValues(alpha: 0.30), shade.withValues(alpha: 0.55), shade.withValues(alpha: 0.78)],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PlateFx extends CustomPainter {
  _PlateFx(this.themeId, {required this.animate}) : super(repaint: animate ? StopMotion.instance : null);

  final String themeId;
  final bool animate;

  double _u(int a, int b) => clayNoise(a, b, 31) * 0.5 + 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final f = animate ? StopMotion.instance.frame : 0;
    final w = size.width, h = size.height;
    switch (themeId) {
      case 'snow':
        final p = Paint()..color = Colors.white.withValues(alpha: 0.85);
        for (var i = 0; i < 70; i++) {
          final speed = 3 + _u(i, 1) * 5;
          final y = (_u(i, 2) * (h + 40) + f * speed) % (h + 40) - 20;
          final x = (_u(i, 3) * w + math.sin((f + i * 7) * 0.12) * 14) % w;
          canvas.drawCircle(Offset(x, y), 1.2 + _u(i, 4) * 2.6, p);
        }
      case 'harvest':
        final colors = [const Color(0xFFE07A1F), const Color(0xFFB0452E), const Color(0xFFD9A43A)];
        for (var i = 0; i < 16; i++) {
          final speed = 2 + _u(i, 1) * 3;
          final y = (_u(i, 2) * (h + 60) + f * speed) % (h + 60) - 30;
          final x = (_u(i, 3) * w + math.sin((f + i * 9) * 0.08) * 40 + f * 0.6) % w;
          canvas.save();
          canvas.translate(x, y);
          canvas.rotate((f * 0.25 + i) % (math.pi * 2));
          final leaf = Path()
            ..moveTo(0, -7)
            ..quadraticBezierTo(5, 0, 0, 7)
            ..quadraticBezierTo(-5, 0, 0, -7);
          canvas.drawPath(leaf, Paint()..color = colors[i % 3].withValues(alpha: 0.85));
          canvas.restore();
        }
      case 'western':
        final p = Paint()..color = const Color(0xFFFFD9A0).withValues(alpha: 0.35);
        for (var i = 0; i < 40; i++) {
          final x = (_u(i, 1) * w + f * (1.5 + _u(i, 2) * 2.5)) % w;
          final y = h * 0.35 + _u(i, 3) * h * 0.6 + math.sin((f + i * 5) * 0.1) * 6;
          canvas.drawCircle(Offset(x, y), 0.8 + _u(i, 4) * 1.6, p);
        }
      case 'gothic':
        for (var i = 0; i < 6; i++) {
          final x = (_u(i, 1) * w * 1.6 + f * (0.6 + _u(i, 2) * 0.8)) % (w * 1.6) - w * 0.3;
          final y = h * (0.45 + _u(i, 3) * 0.45);
          final r = w * (0.25 + _u(i, 4) * 0.25);
          canvas.drawOval(
            Rect.fromCenter(center: Offset(x, y), width: r * 2, height: r * 0.5),
            Paint()
              ..color = const Color(0xFF9AB0D6).withValues(alpha: 0.07)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
          );
        }
        final mote = Paint()..color = const Color(0xFFFFC27A).withValues(alpha: 0.5);
        for (var i = 0; i < 18; i++) {
          final x = (_u(i, 5) * w + math.sin((f + i * 11) * 0.07) * 20) % w;
          final y = (_u(i, 6) * h - f * (0.8 + _u(i, 7))) % h;
          canvas.drawCircle(Offset(x, y < 0 ? y + h : y), 1.1, mote);
        }
    }
    // Frame-to-frame light flicker, like real stop-motion lamps.
    final flick = clayNoise(f, 3, 9) * 0.012;
    if (flick > 0) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: flick));
    } else {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: -flick));
    }
  }

  @override
  bool shouldRepaint(_PlateFx old) => old.themeId != themeId || old.animate != animate;
}

class _SetPainter extends CustomPainter {
  _SetPainter({required this.animate}) : super(repaint: animate ? StopMotion.instance : null);

  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    final f = animate ? StopMotion.instance.frame : 0;
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, h), [Clay.night, Clay.dusk, const Color(0xFF231A36)], const [0, 0.6, 1]),
    );

    // Stars, each twinkling on its own beat.
    final star = Paint();
    for (var i = 0; i < 46; i++) {
      final x = (clayNoise(i, 1, 5) * 0.5 + 0.5) * w;
      final y = (clayNoise(i, 2, 5) * 0.5 + 0.5) * h * 0.62;
      final on = (f + i * 3) % 17 != 0;
      star.color = Clay.bone.withValues(alpha: on ? 0.35 + 0.3 * (clayNoise(i, 3, 5) * 0.5 + 0.5) : 0.08);
      canvas.drawCircle(Offset(x, y), 0.8 + (clayNoise(i, 4, 5) * 0.5 + 0.5) * 1.1, star);
    }

    // Crooked moon with a glow.
    final mr = math.min(w, h) * 0.13;
    final mc = Offset(w * 0.78, h * 0.13);
    canvas.drawCircle(
      mc,
      mr * 2.4,
      Paint()..shader = ui.Gradient.radial(mc, mr * 2.4, [Clay.ghost.withValues(alpha: 0.18), Clay.ghost.withValues(alpha: 0)]),
    );
    canvas.save();
    canvas.translate(mc.dx - mr, mc.dy - mr);
    final moon = clayPath(Size(mr * 2, mr * 2), seed: 77, wobble: 1.6, squareness: 2.0, boilFrame: f ~/ 2);
    canvas.drawPath(
      moon,
      Paint()
        ..shader = ui.Gradient.radial(Offset(mr * 0.7, mr * 0.6), mr * 1.6, [const Color(0xFFF4EBD9), const Color(0xFFB9C6D6)]),
    );
    final crater = Paint()..color = const Color(0xFF9AA8BB).withValues(alpha: 0.55);
    canvas.drawCircle(Offset(mr * 1.25, mr * 0.75), mr * 0.18, crater);
    canvas.drawCircle(Offset(mr * 0.7, mr * 1.3), mr * 0.12, crater);
    canvas.drawCircle(Offset(mr * 1.35, mr * 1.4), mr * 0.08, crater);
    canvas.restore();

    // Two layers of lumpy hills.
    _hills(canvas, size, h * 0.80, 0.07, 11, f, const Color(0xFF1E1730));
    _tree(canvas, Offset(w * 0.18, h * 0.83), h * 0.2, f);
    _hills(canvas, size, h * 0.88, 0.05, 23, f, const Color(0xFF130F1D));

    // Moths fluttering about the moon.
    final wing = Paint()..color = Clay.bone.withValues(alpha: 0.55);
    for (var i = 0; i < 5; i++) {
      final t = f * 0.09 + i * 1.7;
      final p = Offset(
        mc.dx + math.cos(t * (0.6 + i * 0.07)) * mr * (2.0 + i * 0.35) - w * 0.08 * (i % 2),
        mc.dy + math.sin(t * 0.8 + i) * mr * (1.4 + i * 0.2) + mr * 0.8,
      );
      final open = (f + i) % 2 == 0;
      final ww = open ? 4.0 : 1.8;
      canvas.drawOval(Rect.fromCenter(center: p.translate(-ww / 2 - 0.5, 0), width: ww, height: 4.5), wing);
      canvas.drawOval(Rect.fromCenter(center: p.translate(ww / 2 + 0.5, 0), width: ww, height: 4.5), wing);
    }
  }

  void _hills(Canvas canvas, Size size, double baseY, double amp, int seed, int f, Color color) {
    final w = size.width, h = size.height;
    final path = Path()..moveTo(0, h);
    const steps = 9;
    var prev = Offset(0, baseY + clayNoise(seed, 0, 0) * h * amp);
    path.lineTo(prev.dx, prev.dy);
    for (var i = 1; i <= steps; i++) {
      final x = w * i / steps;
      final y = baseY + clayNoise(seed, i, 0) * h * amp + clayNoise(seed, i, f % 3) * 1.5;
      final mid = Offset((prev.dx + x) / 2, math.min(prev.dy, y) - h * amp * 0.6);
      path.quadraticBezierTo(mid.dx, mid.dy, x, y);
      prev = Offset(x, y);
    }
    path
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _tree(Canvas canvas, Offset root, double height, int f) {
    final paint = Paint()
      ..color = const Color(0xFF120E1A)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    void branch(Offset from, double angle, double len, double width, int depth, int id) {
      if (depth == 0 || len < 4) return;
      final sway = clayNoise(id, depth, f % 3) * 0.03;
      final to = from + Offset(math.cos(angle + sway), math.sin(angle + sway)) * len;
      paint.strokeWidth = width;
      final ctrl = Offset.lerp(from, to, 0.5)! + Offset(clayNoise(id, 5, 0) * len * 0.25, 0);
      canvas.drawPath(Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, to.dx, to.dy), paint);
      branch(to, angle - 0.55 + clayNoise(id, 1, 1) * 0.3, len * 0.68, width * 0.62, depth - 1, id * 2 + 1);
      branch(to, angle + 0.45 + clayNoise(id, 2, 1) * 0.3, len * 0.62, width * 0.62, depth - 1, id * 2 + 2);
    }

    branch(root, -math.pi / 2 - 0.08, height * 0.45, height * 0.07, 5, 1);
  }

  @override
  bool shouldRepaint(_SetPainter old) => true; // cheap; also picks up theme switches
}

/// A shelf of clay candles whose flames leap with the music.
///
/// Each candle follows a slice of the spectrum. Flames are drawn in three
/// layers (deep orange, gold, white-hot core) on a warm additive glow, the
/// whole shelf brightens with the bass, and loud hits flick embers upward.
/// Runs at full frame rate only while it's on screen and music is moving.
class CandleVisualizer extends StatefulWidget {
  const CandleVisualizer({super.key, required this.player, this.height = 120});

  final Player player;
  final double height;

  @override
  State<CandleVisualizer> createState() => _CandleVisualizerState();
}

class _Ember {
  _Ember(this.x, this.y, this.vx, this.vy, this.life, this.size);
  double x, y, vx, vy, life, size;
}

class _CandleVisualizerState extends State<CandleVisualizer> with SingleTickerProviderStateMixin {
  static const count = 12;
  final _target = List<double>.filled(count, 0);
  final _level = List<double>.filled(count, 0);
  final _peak = List<double>.filled(count, 0);
  final _embers = <_Ember>[];
  final _rnd = math.Random();
  final _repaint = ValueNotifier<int>(0);
  double _bass = 0, _bassTarget = 0, _time = 0;
  StreamSubscription<FftFrame>? _sub;
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    // Subscribing starts the FFT; cancelling (leaving the screen) stops it.
    _sub = widget.player.stream.fft.listen(_onFrame);
    _ticker.start();
  }

  void _onFrame(FftFrame frame) {
    final data = frame.bands;
    if (data.isEmpty) return;
    for (var i = 0; i < count; i++) {
      final from = (i * data.length / count).floor();
      final to = math.max(from + 1, ((i + 1) * data.length / count).floor());
      var v = 0.0;
      for (var j = from; j < to && j < data.length; j++) {
        v = math.max(v, data[j]);
      }
      // Lift quiet treble so the right-hand candles still dance.
      _target[i] = math.pow(v.clamp(0.0, 1.0), 0.75).toDouble() * (1 + i * 0.03);
    }
    _bassTarget = data.length >= 3 ? (data[0] + data[1] + data[2]) / 3 : data[0];
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    _time += dt;
    var moving = false;
    for (var i = 0; i < count; i++) {
      // Fast rise, slower fall: reads clearly as a beat, then settles.
      final t = _target[i];
      final k = t > _level[i] ? 22.0 : 7.0;
      _level[i] += (t - _level[i]) * math.min(1.0, k * dt);
      if (_level[i] > _peak[i]) {
        // A sharp jump throws a couple of embers.
        if (_level[i] - _peak[i] > 0.18 && _embers.length < 60) {
          for (var e = 0; e < 2 + _rnd.nextInt(3); e++) {
            _embers.add(_Ember(i + 0.5 + (_rnd.nextDouble() - 0.5) * 0.4, 0, (_rnd.nextDouble() - 0.5) * 0.9,
                1.2 + _rnd.nextDouble() * 1.6 + _level[i], 1, 1.2 + _rnd.nextDouble() * 1.8));
          }
        }
        _peak[i] = _level[i];
      } else {
        _peak[i] = math.max(0.0, _peak[i] - dt * 0.6);
      }
      if (_level[i] > 0.01 || t > 0.01) moving = true;
    }
    _bass += (_bassTarget - _bass) * math.min(1.0, (_bassTarget > _bass ? 18 : 5) * dt);
    for (final e in _embers) {
      e.x += e.vx * dt + math.sin(_time * 6 + e.size * 10) * 0.25 * dt;
      e.y += e.vy * dt;
      e.vy *= 0.985;
      e.life -= dt * 0.9;
    }
    _embers.removeWhere((e) => e.life <= 0);
    if (moving || _embers.isNotEmpty) _repaint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: RepaintBoundary(child: CustomPaint(painter: _CandlePainter(this))),
    );
  }
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.s) : super(repaint: s._repaint);

  final _CandleVisualizerState s;

  static const _deep = Color(0xFFD9441A);
  static const _orange = Color(0xFFFF8A1F);
  static const _gold = Color(0xFFFFC94A);
  static const _core = Color(0xFFFFF6D8);

  @override
  void paint(Canvas canvas, Size size) {
    const count = _CandleVisualizerState.count;
    final slot = size.width / count;
    final shelfY = size.height - 10;
    final waxW = slot * 0.46;
    final bass = s._bass.clamp(0.0, 1.0);

    // Warm backlight that swells with the bass, so the flames read on any theme.
    final glowRect = Rect.fromLTWH(-size.width * 0.1, size.height * 0.05, size.width * 1.2, size.height * 1.4);
    canvas.drawOval(
      glowRect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width / 2, shelfY),
          size.width * 0.62,
          [const Color(0xFF3A1606).withValues(alpha: 0.55 + 0.25 * bass), const Color(0xFF3A1606).withValues(alpha: 0)],
        ),
    );
    canvas.drawOval(
      glowRect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          Offset(size.width / 2, shelfY - size.height * 0.2),
          size.width * (0.42 + 0.18 * bass),
          [_orange.withValues(alpha: 0.10 + 0.32 * bass), _orange.withValues(alpha: 0)],
        ),
    );

    // Clay shelf the candles stand on, lit warm from above.
    final shelf = RRect.fromRectAndRadius(Rect.fromLTWH(4, shelfY - 2, size.width - 8, 12), const Radius.circular(6));
    canvas.drawRRect(
      shelf,
      Paint()..shader = ui.Gradient.linear(Offset(0, shelfY - 2), Offset(0, shelfY + 10), [const Color(0xFF6A3A1E), const Color(0xFF2A1408)]),
    );

    final glow = Paint()..blendMode = BlendMode.plus;
    final wax = Paint();
    for (var i = 0; i < count; i++) {
      final level = s._level[i].clamp(0.0, 1.2);
      final cx = slot * (i + 0.5);
      final waxH = size.height * (0.22 + 0.08 * (clayNoise(i, 3, 3) * 0.5 + 0.5));
      final top = shelfY - waxH;

      // Wax, lit from the flame side.
      wax.shader = ui.Gradient.linear(Offset(cx - waxW / 2, 0), Offset(cx + waxW / 2, 0),
          [const Color(0xFFF8EEDA), Color.lerp(const Color(0xFFCDBEA4), const Color(0xFFFFD8A0), level * 0.6)!]);
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(cx - waxW / 2, top, waxW, waxH),
            topLeft: Radius.circular(waxW * 0.45), topRight: Radius.circular(waxW * 0.3)),
        wax,
      );
      canvas.drawCircle(Offset(cx - waxW * 0.22, top + waxW * 0.6), waxW * 0.15, Paint()..color = const Color(0xFFEFE4CE));
      canvas.drawLine(Offset(cx, top), Offset(cx, top - 4), Paint()
        ..color = const Color(0xFF2A1A10)
        ..strokeWidth = 1.6);

      // Flame: tall and wide when loud, a small bead when quiet.
      final fh = size.height * (0.10 + 0.52 * level);
      final fw = waxW * (0.55 + 0.55 * level);
      final sway = math.sin(s._time * (7 + i) + i) * fw * 0.18 * (0.4 + level);
      final base = Offset(cx, top - 3);
      final tip = Offset(cx + sway, base.dy - fh);

      // Halo.
      glow.shader = ui.Gradient.radial(Offset(cx, base.dy - fh * 0.4), fw * (1.6 + level * 1.4),
          [_gold.withValues(alpha: 0.22 + 0.45 * level), _orange.withValues(alpha: 0)]);
      canvas.drawCircle(Offset(cx, base.dy - fh * 0.4), fw * (1.6 + level * 1.4), glow);

      _flame(canvas, base, tip, fw, Paint()..color = _deep.withValues(alpha: 0.95));
      _flame(canvas, base.translate(0, -1), Offset.lerp(base, tip, 0.82)!, fw * 0.72, Paint()..color = _orange);
      _flame(canvas, base.translate(0, -2), Offset.lerp(base, tip, 0.58)!, fw * 0.46, Paint()..color = _gold);
      _flame(canvas, base.translate(0, -2), Offset.lerp(base, tip, 0.32)!, fw * 0.24, Paint()..color = _core);

      // Peak marker: a tiny spark that hangs at the recent high, then sinks.
      final peakY = base.dy - size.height * (0.10 + 0.52 * s._peak[i].clamp(0.0, 1.2)) - 6;
      if (s._peak[i] > 0.08) {
        canvas.drawCircle(Offset(cx, peakY), 1.8, Paint()
          ..blendMode = BlendMode.plus
          ..color = _gold.withValues(alpha: 0.8));
      }
    }

    // Embers rising off loud hits.
    final ember = Paint()..blendMode = BlendMode.plus;
    for (final e in s._embers) {
      final x = e.x * slot;
      final y = shelfY - size.height * 0.35 - e.y * size.height * 0.45;
      ember.color = Color.lerp(_deep, _gold, e.life)!.withValues(alpha: (e.life * 1.2).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), e.size * (0.5 + e.life * 0.5), ember);
    }
  }

  void _flame(Canvas canvas, Offset base, Offset tip, double w, Paint paint) {
    final h = base.dy - tip.dy;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..cubicTo(tip.dx + w * 0.25, tip.dy + h * 0.35, base.dx + w * 0.75, base.dy - h * 0.35, base.dx, base.dy)
      ..cubicTo(base.dx - w * 0.75, base.dy - h * 0.35, tip.dx - w * 0.25, tip.dy + h * 0.35, tip.dx, tip.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CandlePainter old) => false;
}

/// A hand-pressed clay record that turns (in 12 fps steps) while playing,
/// with the song's cover art pressed into its label.
class ClayRecord extends StatefulWidget {
  const ClayRecord({super.key, required this.spinning, this.cover, required this.seedText});

  final bool spinning;
  final ImageProvider? cover;
  final String seedText;

  @override
  State<ClayRecord> createState() => _ClayRecordState();
}

class _ClayRecordState extends State<ClayRecord> {
  double _turns = 0;
  bool _listening = false;

  void _tick() => setState(() => _turns += 1 / 36);

  void _syncListening() {
    final want = widget.spinning && StopMotion.instance.enabled;
    if (want && !_listening) {
      StopMotion.instance.addListener(_tick);
      _listening = true;
    } else if (!want && _listening) {
      StopMotion.instance.removeListener(_tick);
      _listening = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _syncListening();
  }

  @override
  void didUpdateWidget(ClayRecord old) {
    super.didUpdateWidget(old);
    _syncListening();
  }

  @override
  void dispose() {
    if (_listening) StopMotion.instance.removeListener(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final d = math.min(c.maxWidth, c.maxHeight);
      final label = d * 0.42;
      return SizedBox(
        width: d,
        height: d,
        child: Transform.rotate(
          angle: _turns * math.pi * 2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  size: Size(d, d),
                  painter: _RecordPainter(seed: widget.seedText.hashCode & 0x7fffffff),
                ),
              ),
              ClipPath(
                clipper: _BlobClipper(seed: widget.seedText.hashCode & 0x7fffffff),
                child: SizedBox(
                  width: label,
                  height: label,
                  child: widget.cover != null
                      ? Image(image: widget.cover!, fit: BoxFit.cover, gaplessPlayback: true)
                      : DecoratedBox(
                          decoration: BoxDecoration(color: Clay.pumpkin),
                          child: Center(child: Icon(Icons.nightlight_round, color: Clay.night.withValues(alpha: 0.7), size: label * 0.4)),
                        ),
                ),
              ),
              // Spindle hole.
              Container(width: d * 0.035, height: d * 0.035, decoration: BoxDecoration(color: Clay.night, shape: BoxShape.circle)),
            ],
          ),
        ),
      );
    });
  }
}

class _RecordPainter extends CustomPainter {
  _RecordPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    ClayPainter(color: const Color(0xFF221A2E), seed: seed, wobble: 1.2, squareness: 2.0, depth: size.width * 0.04).paint(canvas, size);
    final c = size.center(Offset.zero);
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var r = size.width * 0.24; r < size.width * 0.47; r += 4.5) {
      groove.color = Colors.white.withValues(alpha: 0.035 + 0.03 * (clayNoise(seed, r.toInt(), 1) * 0.5 + 0.5));
      final start = clayNoise(seed, r.toInt(), 2) * math.pi;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, math.pi * 1.6, false, groove);
    }
    // A sheen that turns with the disc (it's painted onto the clay).
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: size.width * 0.38),
      -2.4,
      0.9,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.12
        ..color = Colors.white.withValues(alpha: 0.04),
    );
  }

  @override
  bool shouldRepaint(_RecordPainter old) => old.seed != seed;
}

class _BlobClipper extends CustomClipper<Path> {
  _BlobClipper({required this.seed});

  final int seed;

  @override
  Path getClip(Size size) => clayPath(size, seed: seed, wobble: 1.8, squareness: 2.0);

  @override
  bool shouldReclip(_BlobClipper old) => old.seed != seed;
}
