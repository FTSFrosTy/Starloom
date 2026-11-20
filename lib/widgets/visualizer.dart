import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../theme/palette.dart';
import 'clay.dart';

/// Music visualizer that matches the theme, built like little clay props:
/// candles (Moonlit, Gothic Town), swinging oil lanterns (Ghost Town),
/// glowing icicles (Snow Village), singing jack-o'-lanterns (Harvest).
///
/// Motion is smooth (springs, fast rise / slow fall) while outlines still
/// "boil" on the 12 fps stop-motion beat, so it moves cleanly but looks
/// hand-made. Only runs while it's on screen.
class ThemeVisualizer extends StatefulWidget {
  const ThemeVisualizer({super.key, required this.player, this.height = 120});

  final Player player;
  final double height;

  @override
  State<ThemeVisualizer> createState() => _ThemeVisualizerState();
}

class _Spark {
  _Spark(this.x, this.y, this.vx, this.vy, this.size);
  double x, y, vx, vy, size, life = 1;
}

class _ThemeVisualizerState extends State<ThemeVisualizer> with SingleTickerProviderStateMixin {
  static const n = 9;
  final target = List<double>.filled(n, 0);
  final level = List<double>.filled(n, 0);
  final peak = List<double>.filled(n, 0);
  // squash-and-stretch spring per prop
  final bounce = List<double>.filled(n, 0);
  final bounceV = List<double>.filled(n, 0);
  final sparks = <_Spark>[];
  final rnd = math.Random();
  final repaint = ValueNotifier<int>(0);
  double bass = 0, bassTarget = 0, time = 0;
  StreamSubscription<FftFrame>? _sub;
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _sub = widget.player.stream.fft.listen(_onFrame);
    _ticker.start();
  }

  void _onFrame(FftFrame frame) {
    final d = frame.bands;
    if (d.isEmpty) return;
    for (var i = 0; i < n; i++) {
      final from = (i * d.length / n).floor();
      final to = math.max(from + 1, ((i + 1) * d.length / n).floor());
      var v = 0.0;
      for (var j = from; j < to && j < d.length; j++) {
        v = math.max(v, d[j]);
      }
      target[i] = (math.pow(v.clamp(0.0, 1.0), 0.7).toDouble() * (1 + i * 0.04)).clamp(0.0, 1.0);
    }
    bassTarget = d.length >= 3 ? (d[0] + d[1] + d[2]) / 3 : d[0];
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    time += dt;
    var active = false;
    for (var i = 0; i < n; i++) {
      final t = target[i];
      final jump = t - level[i];
      level[i] += jump * math.min(1.0, (jump > 0 ? 20.0 : 6.0) * dt);
      if (jump > 0.22) {
        bounceV[i] += jump * 9; // kick the spring on a hit
        if (sparks.length < 70) {
          for (var e = 0; e < 3; e++) {
            sparks.add(_Spark(i + 0.5 + (rnd.nextDouble() - 0.5) * 0.4, 0, (rnd.nextDouble() - 0.5) * 0.8, 1.0 + rnd.nextDouble() * 1.5 + t, 1 + rnd.nextDouble() * 1.8));
          }
        }
      }
      // damped spring back to rest
      bounceV[i] += (-90 * bounce[i] - 9 * bounceV[i]) * dt;
      bounce[i] += bounceV[i] * dt;
      peak[i] = level[i] > peak[i] ? level[i] : math.max(0.0, peak[i] - dt * 0.6);
      if (level[i] > 0.01 || t > 0.01 || bounce[i].abs() > 0.002) active = true;
    }
    bass += (bassTarget - bass) * math.min(1.0, (bassTarget > bass ? 16 : 5) * dt);
    for (final s in sparks) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vy *= 0.985;
      s.life -= dt * 0.85;
    }
    sparks.removeWhere((s) => s.life <= 0);
    if (active || sparks.isNotEmpty) repaint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: RepaintBoundary(child: CustomPaint(painter: _VisPainter(this, Clay.current.id))),
    );
  }
}

class _VisPainter extends CustomPainter {
  _VisPainter(this.s, this.theme) : super(repaint: s.repaint);

  final _ThemeVisualizerState s;
  final String theme;

  static const _deep = Color(0xFFD9441A);
  static const _orange = Color(0xFFFF8A1F);
  static const _gold = Color(0xFFFFC94A);
  static const _core = Color(0xFFFFF6D8);

  int get _boil => StopMotion.instance.frame % 3;

  @override
  void paint(Canvas canvas, Size size) {
    switch (theme) {
      case 'western':
        _lanterns(canvas, size);
      case 'snow':
        _icicles(canvas, size);
      case 'harvest':
        _pumpkins(canvas, size);
      default:
        _candles(canvas, size);
    }
  }

  // ---- shared bits -------------------------------------------------------

  void _backGlow(Canvas canvas, Size size, Color color, double y) {
    final b = s.bass.clamp(0.0, 1.0);
    canvas.drawOval(
      Rect.fromLTWH(-size.width * 0.1, 0, size.width * 1.2, size.height * 1.3),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(Offset(size.width / 2, y), size.width * (0.4 + 0.2 * b),
            [color.withValues(alpha: 0.08 + 0.3 * b), color.withValues(alpha: 0)]),
    );
  }

  /// Shaded clay blob: lit top-left, darker rim, a faint thumbprint.
  void _clay(Canvas canvas, Rect r, Color c, int seed, {double wobble = 1.4, double squareness = 2.4}) {
    canvas.save();
    canvas.translate(r.left, r.top);
    final path = clayPath(r.size, seed: seed, wobble: wobble, squareness: squareness, boilFrame: _boil);
    canvas.drawPath(
      path,
      Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(r.width, r.height), [shade(c, 0.12), c, shade(c, -0.18)], const [0, 0.45, 1]),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(Offset(r.width * 0.3, r.height * 0.25), math.max(r.width, r.height) * 0.6,
            [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0)]),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = shade(c, -0.25).withValues(alpha: 0.7),
    );
    canvas.restore();
  }

  void _flame(Canvas canvas, Offset base, Offset tip, double w, Paint paint) {
    final h = base.dy - tip.dy;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..cubicTo(tip.dx + w * 0.25, tip.dy + h * 0.35, base.dx + w * 0.75, base.dy - h * 0.35, base.dx, base.dy)
        ..cubicTo(base.dx - w * 0.75, base.dy - h * 0.35, tip.dx - w * 0.25, tip.dy + h * 0.35, tip.dx, tip.dy)
        ..close(),
      paint,
    );
  }

  void _layeredFlame(Canvas canvas, Offset base, double level, double width, double maxH, int i) {
    final fh = maxH * (0.12 + 0.88 * level);
    final fw = width * (0.6 + 0.6 * level);
    final sway = math.sin(s.time * (7 + i) + i) * fw * 0.18 * (0.4 + level);
    final tip = Offset(base.dx + sway, base.dy - fh);
    canvas.drawCircle(
      Offset(base.dx, base.dy - fh * 0.4),
      fw * (1.5 + level * 1.5),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(Offset(base.dx, base.dy - fh * 0.4), fw * (1.5 + level * 1.5),
            [_gold.withValues(alpha: 0.25 + 0.45 * level), _orange.withValues(alpha: 0)]),
    );
    _flame(canvas, base, tip, fw, Paint()..color = _deep);
    _flame(canvas, base.translate(0, -1), Offset.lerp(base, tip, 0.82)!, fw * 0.72, Paint()..color = _orange);
    _flame(canvas, base.translate(0, -2), Offset.lerp(base, tip, 0.58)!, fw * 0.46, Paint()..color = _gold);
    _flame(canvas, base.translate(0, -2), Offset.lerp(base, tip, 0.32)!, fw * 0.24, Paint()..color = _core);
  }

  void _sparks(Canvas canvas, Size size, double slot, double baseY, Color hot, Color cool, {double up = 1}) {
    final p = Paint()..blendMode = BlendMode.plus;
    for (final e in s.sparks) {
      p.color = Color.lerp(cool, hot, e.life)!.withValues(alpha: (e.life * 1.2).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(e.x * slot, baseY - up * e.y * size.height * 0.45), e.size * (0.5 + e.life * 0.5), p);
    }
  }

  // ---- candles (Moonlit, Gothic) ----------------------------------------

  void _candles(Canvas canvas, Size size) {
    const n = _ThemeVisualizerState.n;
    final slot = size.width / n;
    final shelfY = size.height - 10;
    _backGlow(canvas, size, _orange, shelfY - size.height * 0.2);
    _clay(canvas, Rect.fromLTWH(2, shelfY - 4, size.width - 4, 16), const Color(0xFF5A3420), 77, wobble: 0.6, squareness: 6);
    for (var i = 0; i < n; i++) {
      final lv = s.level[i];
      final cx = slot * (i + 0.5);
      final squash = s.bounce[i].clamp(-0.3, 0.3);
      final baseW = slot * 0.46;
      final baseH = size.height * (0.2 + 0.1 * (clayNoise(i, 3, 3) * 0.5 + 0.5));
      final w = baseW * (1 + squash * 0.6);
      final h = baseH * (1 - squash);
      final top = shelfY - h;
      _clay(canvas, Rect.fromLTWH(cx - w / 2, top, w, h + 4), Color.lerp(const Color(0xFFE8DCC4), const Color(0xFFFFD39A), lv * 0.7)!, 300 + i, wobble: 1.0, squareness: 3);
      // drip
      _clay(canvas, Rect.fromLTWH(cx - w * 0.38, top + 2, w * 0.22, h * 0.35), const Color(0xFFF1E6D0), 400 + i, wobble: 1.5);
      canvas.drawLine(Offset(cx, top + 2), Offset(cx, top - 4), Paint()
        ..color = const Color(0xFF2A1A10)
        ..strokeWidth = 1.6);
      _layeredFlame(canvas, Offset(cx, top - 3), lv, baseW, size.height * 0.62, i);
    }
    _sparks(canvas, size, slot, shelfY - size.height * 0.35, _gold, _deep);
  }

  // ---- oil lanterns on a rope (Ghost Town) -------------------------------

  void _lanterns(Canvas canvas, Size size) {
    const n = _ThemeVisualizerState.n;
    final slot = size.width / n;
    // sagging rope
    final rope = Path()..moveTo(0, 10);
    rope.quadraticBezierTo(size.width / 2, 34 + s.bass * 10, size.width, 10);
    canvas.drawPath(rope, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF6A4A2A));
    _backGlow(canvas, size, const Color(0xFFFFA040), size.height * 0.6);
    for (var i = 0; i < n; i++) {
      final lv = s.level[i];
      final cx = slot * (i + 0.5);
      final t = cx / size.width;
      final hookY = 10 + 4 * (34 + s.bass * 10 - 10) * t * (1 - t);
      final swing = (math.sin(s.time * 2.2 + i * 0.9) * 0.08 + s.bounce[i] * 0.6).clamp(-0.5, 0.5);
      canvas.save();
      canvas.translate(cx, hookY);
      canvas.rotate(swing);
      final w = slot * 0.52, h = size.height * 0.5;
      // wire + cap
      canvas.drawLine(Offset.zero, Offset(0, h * 0.18), Paint()
        ..strokeWidth = 1.5
        ..color = const Color(0xFF3A2A1A));
      _clay(canvas, Rect.fromLTWH(-w * 0.45, h * 0.16, w * 0.9, h * 0.18), const Color(0xFF8A5A2A), 500 + i, squareness: 3);
      // glass globe glowing with the music
      final glass = Rect.fromLTWH(-w / 2, h * 0.32, w, h * 0.5);
      canvas.drawOval(glass.inflate(w * (0.4 + lv)), Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(glass.center, w * (1.2 + lv * 1.4), [const Color(0xFFFFB347).withValues(alpha: 0.2 + 0.55 * lv), const Color(0x00FF8A1F)]));
      canvas.drawOval(glass, Paint()..color = Color.lerp(const Color(0xFF4A2A10), const Color(0xFFFFC870), 0.25 + lv * 0.75)!.withValues(alpha: 0.9));
      _layeredFlame(canvas, Offset(0, glass.bottom - h * 0.06), lv * 0.8, w * 0.32, h * 0.32, i);
      canvas.drawOval(glass, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF3A2410));
      // base
      _clay(canvas, Rect.fromLTWH(-w * 0.5, h * 0.8, w, h * 0.14), const Color(0xFF7A4E24), 600 + i, squareness: 4);
      canvas.restore();
    }
    _sparks(canvas, size, slot, size.height * 0.75, _gold, _deep);
  }

  // ---- glowing icicles under a snowy eave (Snow Village) -----------------

  void _icicles(Canvas canvas, Size size) {
    const n = _ThemeVisualizerState.n;
    final slot = size.width / n;
    const ice = Color(0xFFBFE6FF);
    _backGlow(canvas, size, const Color(0xFF7FC8FF), size.height * 0.25);
    // the eave: a wooden beam under a fat roll of snow
    _clay(canvas, Rect.fromLTWH(0, 6, size.width, 16), const Color(0xFF6A4630), 701, wobble: 0.5, squareness: 6);
    _clay(canvas, Rect.fromLTWH(-6, -6, size.width + 12, 20), const Color(0xFFF4F7FC), 702, wobble: 1.4, squareness: 4);
    for (var i = 0; i < n; i++) {
      final lv = s.level[i];
      final cx = slot * (i + 0.5);
      final len = size.height * (0.22 + 0.62 * lv) * (1 + s.bounce[i].clamp(-0.2, 0.2));
      final w = slot * (0.34 + 0.1 * lv);
      final top = 20.0;
      final path = Path()
        ..moveTo(cx - w / 2, top)
        ..quadraticBezierTo(cx - w * 0.35, top + len * 0.5, cx + clayNoise(i, 1, StopMotion.instance.frame % 3) * 2, top + len)
        ..quadraticBezierTo(cx + w * 0.35, top + len * 0.5, cx + w / 2, top)
        ..close();
      canvas.drawCircle(Offset(cx, top + len * 0.6), w * (1.2 + lv * 1.6), Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(Offset(cx, top + len * 0.6), w * (1.2 + lv * 1.6), [ice.withValues(alpha: 0.12 + 0.5 * lv), ice.withValues(alpha: 0)]));
      canvas.drawPath(path, Paint()
        ..shader = ui.Gradient.linear(Offset(cx - w / 2, 0), Offset(cx + w / 2, 0),
            [const Color(0xFFE8F6FF).withValues(alpha: 0.95), Color.lerp(const Color(0xFF8EC7EE), Colors.white, lv)!.withValues(alpha: 0.9)]));
      // bright core
      canvas.drawLine(Offset(cx - w * 0.1, top + 3), Offset(cx, top + len * 0.8), Paint()
        ..blendMode = BlendMode.plus
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2 + lv * 2
        ..color = Colors.white.withValues(alpha: 0.35 + 0.5 * lv));
    }
    // sparkle drops fall instead of rising
    final p = Paint()..blendMode = BlendMode.plus;
    for (final e in s.sparks) {
      p.color = Colors.white.withValues(alpha: (e.life).clamp(0.0, 1.0));
      final pos = Offset(e.x * slot, 24 + e.y * size.height * 0.5);
      canvas.drawCircle(pos, e.size * 0.8, p);
      canvas.drawLine(pos.translate(-e.size * 2, 0), pos.translate(e.size * 2, 0), p..strokeWidth = 0.8);
    }
  }

  // ---- singing jack-o'-lanterns (Harvest) --------------------------------

  void _pumpkins(Canvas canvas, Size size) {
    const n = _ThemeVisualizerState.n;
    final slot = size.width / n;
    final groundY = size.height - 6;
    _backGlow(canvas, size, const Color(0xFFFFA030), groundY - size.height * 0.3);
    for (var i = 0; i < n; i++) {
      final lv = s.level[i];
      final cx = slot * (i + 0.5);
      final b = s.bounce[i].clamp(-0.35, 0.35);
      // squash on landing, stretch on the way up
      final w = slot * 0.82 * (1 + b * 0.5);
      final h = slot * 0.66 * (1 - b * 0.6);
      final hop = math.max(0.0, -b) * size.height * 0.5 + lv * 6;
      final r = Rect.fromLTWH(cx - w / 2, groundY - h - hop, w, h);
      // shadow
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, groundY), width: w * (0.9 - hop / size.height), height: 6),
          Paint()..color = Colors.black.withValues(alpha: 0.3));
      _clay(canvas, r, Color.lerp(const Color(0xFFD9661A), const Color(0xFFFF8A2A), lv)!, 800 + i, wobble: 1.2, squareness: 2.2);
      // ribs
      final rib = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFF8A3A0A).withValues(alpha: 0.6);
      for (final k in [-0.22, 0.22]) {
        canvas.drawArc(Rect.fromCenter(center: r.center, width: w * (0.5 + k.abs()), height: h * 0.95), -math.pi / 2, math.pi, false, rib);
      }
      // stem
      _clay(canvas, Rect.fromLTWH(cx - 3, r.top - 8, 6, 11), const Color(0xFF4A6A2A), 900 + i, squareness: 3);
      // carved face glowing from inside: eyes + a mouth that opens with the music
      final glow = Color.lerp(const Color(0xFF6A3A08), const Color(0xFFFFE070), 0.2 + lv * 0.8)!;
      final face = Paint()..color = glow;
      final eyeY = r.top + h * 0.38;
      for (final dx in [-0.2, 0.2]) {
        final ex = cx + dx * w;
        canvas.drawPath(Path()
          ..moveTo(ex - w * 0.08, eyeY + h * 0.08)
          ..lineTo(ex, eyeY - h * 0.08)
          ..lineTo(ex + w * 0.08, eyeY + h * 0.08)
          ..close(), face);
      }
      final mouthH = h * (0.06 + 0.24 * lv);
      final mouth = Path()..moveTo(cx - w * 0.28, r.top + h * 0.62);
      for (var k = 0; k <= 6; k++) {
        final x = cx - w * 0.28 + k * w * 0.56 / 6;
        mouth.lineTo(x, r.top + h * 0.62 + (k.isOdd ? -mouthH * 0.25 : 0));
      }
      mouth.quadraticBezierTo(cx, r.top + h * 0.62 + mouthH * 2.2, cx - w * 0.28, r.top + h * 0.62);
      canvas.drawPath(mouth, face);
      if (lv > 0.05) {
        canvas.drawCircle(Offset(cx, r.top + h * 0.55), w * (0.35 + lv * 0.5), Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(Offset(cx, r.top + h * 0.55), w * (0.35 + lv * 0.5), [const Color(0xFFFFC040).withValues(alpha: 0.4 * lv), const Color(0x00FFA020)]));
      }
    }
    _sparks(canvas, size, slot, groundY - size.height * 0.3, const Color(0xFFFFD060), const Color(0xFFB0451A));
  }

  @override
  bool shouldRepaint(_VisPainter old) => old.theme != theme;
}
