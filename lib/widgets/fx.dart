import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/beat.dart';
import 'clay.dart';

/// Points in a rendered set (windows, lamps, chimneys…) in 0..1 image
/// coordinates, exported from Blender alongside each plate.
class SetAnchors {
  SetAnchors(this.points);
  final Map<String, List<Offset>> points;

  List<Offset> operator [](String k) => points[k] ?? const [];

  static final Map<String, Future<SetAnchors>> _cache = {};

  static Future<SetAnchors> load(String themeId) => _cache.putIfAbsent(themeId, () async {
        try {
          final raw = jsonDecode(await rootBundle.loadString('assets/plates/$themeId.json')) as Map;
          return SetAnchors({
            for (final e in raw.entries)
              e.key as String: [for (final p in (e.value as List)) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())],
          });
        } catch (_) {
          return SetAnchors({});
        }
      });
}

/// Small grain tile shared by every frame (made once).
class _Grain {
  static ui.Image? image;
  static bool _making = false;

  static void ensure() {
    if (image != null || _making) return;
    _making = true;
    const n = 160;
    final px = Uint8List(n * n * 4);
    final r = math.Random(7);
    for (var i = 0; i < n * n; i++) {
      final v = (128 + (r.nextDouble() + r.nextDouble() + r.nextDouble() - 1.5) * 120).clamp(0, 255).toInt();
      px[i * 4] = v;
      px[i * 4 + 1] = v;
      px[i * 4 + 2] = v;
      px[i * 4 + 3] = 255;
    }
    ui.decodeImageFromPixels(px, n, n, ui.PixelFormat.rgba8888, (img) => image = img);
  }
}

/// Maps 0..1 coordinates of a square plate shown with BoxFit.cover.
Offset plateToScreen(Offset p, Size size) {
  final s = math.max(size.width, size.height);
  return Offset((size.width - s) / 2 + p.dx * s, (size.height - s) / 2 + p.dy * s);
}

/// Glows that belong *in* the set: windows and lamps flicker on their own
/// and swell with the bass; the moon or sun breathes with the song.
class SetGlowPainter extends CustomPainter {
  SetGlowPainter(this.theme, this.anchors, {required this.animate}) : super(repaint: StopMotion.instance);

  final String theme;
  final SetAnchors? anchors;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    final a = anchors;
    if (a == null) return;
    Beat.instance.step();
    final f = animate ? StopMotion.instance.frame : 0;
    final bass = Beat.instance.bass.clamp(0.0, 1.0);
    final unit = math.max(size.width, size.height) / 1000;
    final warm = theme == 'snow' ? const Color(0xFFFFC27A) : const Color(0xFFFFA24A);
    final p = Paint()..blendMode = BlendMode.plus;

    var i = 0;
    for (final w in a['window']) {
      final c = plateToScreen(w, size);
      final flick = 0.75 + 0.25 * clayNoise(i, f ~/ 2, 5);
      final r = unit * (26 + 18 * bass);
      p.shader = ui.Gradient.radial(c, r, [warm.withValues(alpha: (0.22 + 0.4 * bass) * flick), warm.withValues(alpha: 0)]);
      canvas.drawCircle(c, r, p);
      i++;
    }
    for (final l in a['lamp']) {
      final c = plateToScreen(l, size);
      final flick = 0.85 + 0.15 * clayNoise(i, f, 6);
      final r = unit * (60 + 40 * bass);
      p.shader = ui.Gradient.radial(c, r, [const Color(0xFFFFC870).withValues(alpha: (0.25 + 0.4 * bass) * flick), const Color(0x00FFA040)]);
      canvas.drawCircle(c, r, p);
      i++;
    }
    for (final key in ['moon', 'sun']) {
      for (final m in a[key]) {
        final c = plateToScreen(m, size);
        final r = unit * (220 + 120 * bass);
        final col = key == 'moon' ? const Color(0xFFB8D0FF) : const Color(0xFFFFB060);
        p.shader = ui.Gradient.radial(c, r, [col.withValues(alpha: 0.12 + 0.28 * bass), col.withValues(alpha: 0)]);
        canvas.drawCircle(c, r, p);
      }
    }
  }

  @override
  bool shouldRepaint(SetGlowPainter old) => old.anchors != anchors || old.theme != theme;
}

/// Living things and weather on top of the set, stepped at 12 fps like a
/// real stop-motion shoot, plus film grain, dust specks and gate weave.
class SceneFxPainter extends CustomPainter {
  SceneFxPainter(this.theme, this.anchors, {required this.animate}) : super(repaint: StopMotion.instance) {
    _Grain.ensure();
  }

  final String theme;
  final SetAnchors? anchors;
  final bool animate;

  double _u(int a, int b) => clayNoise(a, b, 31) * 0.5 + 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    Beat.instance.step();
    final f = animate ? StopMotion.instance.frame : 0;
    final t = f / 12.0;
    final w = size.width, h = size.height;
    final unit = math.max(w, h) / 1000;
    final bass = Beat.instance.bass.clamp(0.0, 1.0);

    switch (theme) {
      case 'gothic':
      case 'moonlit':
        _smoke(canvas, size, f, unit, const Color(0xFF8C93A8));
        for (var i = 0; i < (theme == 'gothic' ? 4 : 3); i++) {
          _bat(canvas, _flightPath(i, t, w, h * 0.42, 9 + i * 3), unit * (16 + i * 3), f + i, i);
        }
        _shootingStar(canvas, size, t, unit, 13);
        if (theme == 'gothic') _lightning(canvas, size, t, unit);
        _fog(canvas, size, t, const Color(0xFF9AB0D6));
      case 'western':
        _tumbleweed(canvas, size, t, unit);
        final sun = anchors?['sun'].firstOrNull;
        final c = sun == null ? Offset(w * 0.45, h * 0.3) : plateToScreen(sun, size);
        for (var i = 0; i < 2; i++) {
          final a = t * (0.35 + i * 0.1) + i * 2.5;
          final pos = c + Offset(math.cos(a) * w * (0.22 + i * 0.08), math.sin(a) * h * 0.06 - h * (0.12 + i * 0.05));
          _bird(canvas, pos, unit * (14 + i * 3), f + i * 3, const Color(0xFF1E1410), soar: true);
        }
        _dust(canvas, size, f, unit);
      case 'snow':
        _snow(canvas, size, f, unit);
        _smoke(canvas, size, f, unit, const Color(0xFFE8EEF8));
        _glints(canvas, size, f, unit);
      case 'harvest':
        _sunbeams(canvas, size, t, bass);
        _leaves(canvas, size, f, unit);
        for (var i = 0; i < 3; i++) {
          _bird(canvas, _flightPath(i + 7, t, w, h * 0.32, 11 + i * 4), unit * (13 + i * 2), f + i * 2, const Color(0xFF14121A));
        }
        _crowOnScarecrow(canvas, size, t, f, unit);
    }

    _filmLayer(canvas, size, f, unit);
  }

  // ---- creatures --------------------------------------------------------

  /// Swoopy path across the sky; each creature takes [period] seconds.
  Offset _flightPath(int i, double t, double w, double maxY, double period) {
    final ph = ((t + i * 3.7) % period) / period;
    final dir = i.isEven ? 1 : -1;
    final x = dir > 0 ? -60 + ph * (w + 120) : w + 60 - ph * (w + 120);
    final y = maxY * (0.25 + 0.5 * _u(i, 3)) + math.sin(ph * math.pi * 4 + i) * maxY * 0.12;
    return Offset(x, y);
  }

  /// A clay bat: round body with a sheen, scalloped wings flapping on twos.
  void _bat(Canvas canvas, Offset p, double s, int frame, int seed) {
    final up = (frame ~/ 2).isEven;
    final body = const Color(0xFF17121F);
    final wing = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(s * 0.9, up ? -s * 1.0 : s * 0.1, s * 1.7, up ? -s * 0.5 : s * 0.55)
      ..quadraticBezierTo(s * 1.35, up ? -s * 0.1 : s * 0.75, s * 1.05, up ? 0 : s * 0.5)
      ..quadraticBezierTo(s * 0.8, up ? s * 0.15 : s * 0.75, s * 0.5, up ? s * 0.15 : s * 0.5)
      ..quadraticBezierTo(s * 0.3, s * 0.3, 0, s * 0.2)
      ..close();
    final paint = Paint()..color = body;
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.drawPath(wing, paint);
    canvas.scale(-1, 1);
    canvas.drawPath(wing, paint);
    canvas.restore();
    canvas.drawOval(Rect.fromCenter(center: p.translate(0, s * 0.15), width: s * 0.75, height: s * 0.9), paint);
    canvas.drawCircle(p.translate(-s * 0.12, -s * 0.05), s * 0.12, Paint()..color = Colors.white.withValues(alpha: 0.18));
    // ears
    canvas.drawPath(
        Path()
          ..moveTo(p.dx - s * 0.25, p.dy - s * 0.15)
          ..lineTo(p.dx - s * 0.18, p.dy - s * 0.5)
          ..lineTo(p.dx - s * 0.05, p.dy - s * 0.2)
          ..moveTo(p.dx + s * 0.25, p.dy - s * 0.15)
          ..lineTo(p.dx + s * 0.18, p.dy - s * 0.5)
          ..lineTo(p.dx + s * 0.05, p.dy - s * 0.2),
        paint);
  }

  /// Crow / buzzard: chunky body and wings in a V that flap (or glide).
  void _bird(Canvas canvas, Offset p, double s, int frame, Color color, {bool soar = false}) {
    final pose = soar ? ((frame ~/ 6) % 4 == 0 ? 1 : 0) : (frame ~/ 2) % 2;
    final lift = pose == 1 ? -s * 0.8 : s * 0.15;
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(p.dx - s * 1.6, p.dy + lift)
      ..quadraticBezierTo(p.dx - s * 0.7, p.dy - s * 0.35, p.dx, p.dy)
      ..quadraticBezierTo(p.dx + s * 0.7, p.dy - s * 0.35, p.dx + s * 1.6, p.dy + lift)
      ..quadraticBezierTo(p.dx + s * 0.7, p.dy + s * 0.05, p.dx, p.dy + s * 0.32)
      ..quadraticBezierTo(p.dx - s * 0.7, p.dy + s * 0.05, p.dx - s * 1.6, p.dy + lift)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawOval(Rect.fromCenter(center: p.translate(0, s * 0.1), width: s * 0.55, height: s * 0.8), paint);
  }

  void _crowOnScarecrow(Canvas canvas, Size size, double t, int f, double unit) {
    final perch = anchors?['scarecrow'].firstOrNull;
    if (perch == null) return;
    final c = plateToScreen(perch, size);
    final cycle = t % 16;
    final s = unit * 12;
    if (cycle < 11) {
      // sitting: bobs its head now and then
      final bob = ((f ~/ 4) % 5 == 0) ? s * 0.25 : 0.0;
      final paint = Paint()..color = const Color(0xFF14121A);
      canvas.drawOval(Rect.fromCenter(center: c.translate(0, -s * 0.9), width: s * 1.4, height: s * 1.0), paint);
      canvas.drawCircle(c.translate(s * 0.55, -s * 1.45 + bob), s * 0.42, paint);
      canvas.drawPath(
          Path()
            ..moveTo(c.dx + s * 0.9, c.dy - s * 1.5 + bob)
            ..lineTo(c.dx + s * 1.35, c.dy - s * 1.38 + bob)
            ..lineTo(c.dx + s * 0.9, c.dy - s * 1.3 + bob),
          Paint()..color = const Color(0xFF6A5A2A));
    } else {
      final k = (cycle - 11) / 5;
      _bird(canvas, c + Offset(k * size.width * 0.5, -k * size.height * 0.25), s, f, const Color(0xFF14121A));
    }
  }

  // ---- weather & props --------------------------------------------------

  void _smoke(Canvas canvas, Size size, int f, double unit, Color color) {
    final chimneys = anchors?['chimney'] ?? const <Offset>[];
    var ci = 0;
    for (final ch in chimneys.take(8)) {
      final c = plateToScreen(ch, size);
      for (var k = 0; k < 5; k++) {
        final age = ((f + k * 7 + ci * 5) % 35) / 35;
        final r = unit * (5 + 22 * age);
        final pos = c + Offset(unit * 30 * age + math.sin(age * 6 + ci) * unit * 6, -unit * 90 * age);
        canvas.drawCircle(pos, r, Paint()..color = color.withValues(alpha: 0.32 * (1 - age)));
      }
      ci++;
    }
  }

  void _fog(Canvas canvas, Size size, double t, Color color) {
    final w = size.width, h = size.height;
    for (var i = 0; i < 5; i++) {
      final x = (_u(i, 1) * w * 1.6 + t * (8 + _u(i, 2) * 10)) % (w * 1.6) - w * 0.3;
      final y = h * (0.5 + _u(i, 3) * 0.42);
      final r = w * (0.3 + _u(i, 4) * 0.25);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: r * 2, height: r * 0.45),
        Paint()
          ..color = color.withValues(alpha: 0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34),
      );
    }
  }

  void _shootingStar(Canvas canvas, Size size, double t, double unit, double every) {
    final ph = t % every;
    if (ph > 0.6) return;
    final k = ph / 0.6;
    final seed = (t / every).floor();
    final start = Offset(size.width * (0.2 + _u(seed, 1) * 0.6), size.height * (0.05 + _u(seed, 2) * 0.15));
    final dir = Offset(-0.8, 0.35);
    final head = start + dir * (k * size.width * 0.35);
    final tail = head - dir * (unit * 90);
    canvas.drawLine(
      tail,
      head,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = unit * 2.4
        ..shader = ui.Gradient.linear(tail, head, [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.9 * (1 - k))]),
    );
  }

  void _lightning(Canvas canvas, Size size, double t, double unit) {
    const every = 23.0;
    final ph = t % every;
    if (ph > 0.5) return;
    final seed = (t / every).floor();
    // two-step flash, like a lamp being flicked on a stop-motion stage
    final a = ph < 0.08 ? 0.35 : (ph > 0.2 && ph < 0.3 ? 0.22 : 0.0);
    if (a == 0) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFDDE8FF).withValues(alpha: a * 0.6));
    final x0 = size.width * (0.2 + _u(seed, 4) * 0.6);
    final bolt = Path()..moveTo(x0, 0);
    var x = x0, y = 0.0;
    for (var k = 1; k < 8; k++) {
      x += (_u(seed, k) - 0.5) * unit * 70;
      y += size.height * 0.045;
      bolt.lineTo(x, y);
    }
    canvas.drawPath(bolt, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 3
      ..color = Colors.white.withValues(alpha: a * 2));
  }

  void _tumbleweed(Canvas canvas, Size size, double t, double unit) {
    const every = 13.0;
    final k = (t % every) / every;
    final r = unit * 34;
    final x = -r * 2 + k * (size.width + r * 4);
    final hop = (math.sin(k * math.pi * 9)).abs() * unit * 40;
    final c = Offset(x, size.height * 0.86 - hop);
    canvas.drawOval(Rect.fromCenter(center: Offset(x, size.height * 0.86 + r * 0.9), width: r * 1.8, height: r * 0.3),
        Paint()..color = Colors.black.withValues(alpha: 0.25));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(k * 40);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 2.4
      ..color = const Color(0xFF8A6A3A);
    for (var i = 0; i < 9; i++) {
      canvas.drawArc(Rect.fromCircle(center: Offset(math.cos(i * 0.7) * r * 0.25, math.sin(i * 1.3) * r * 0.25), radius: r * (0.6 + 0.04 * i)), i * 0.8, 3.6, false, p);
    }
    canvas.restore();
  }

  void _dust(Canvas canvas, Size size, int f, double unit) {
    final p = Paint()..color = const Color(0xFFFFD9A0).withValues(alpha: 0.35);
    for (var i = 0; i < 40; i++) {
      final x = (_u(i, 1) * size.width + f * (1.5 + _u(i, 2) * 2.5)) % size.width;
      final y = size.height * (0.35 + _u(i, 3) * 0.6) + math.sin((f + i * 5) * 0.1) * 6;
      canvas.drawCircle(Offset(x, y), unit * (1 + _u(i, 4) * 2), p);
    }
  }

  void _snow(Canvas canvas, Size size, int f, double unit) {
    final w = size.width, h = size.height;
    // three depths: far small and slow, near big, soft and fast
    for (var layer = 0; layer < 3; layer++) {
      final n = [70, 40, 12][layer];
      final paint = Paint()..color = Colors.white.withValues(alpha: [0.6, 0.85, 0.75][layer]);
      if (layer == 2) paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      for (var i = 0; i < n; i++) {
        final id = i + layer * 100;
        final speed = [2.0, 4.5, 9.0][layer] * (0.7 + _u(id, 1) * 0.6);
        final y = (_u(id, 2) * (h + 40) + f * speed * unit) % (h + 40) - 20;
        final x = (_u(id, 3) * w + math.sin((f + id * 7) * 0.12) * 14 * (layer + 1)) % w;
        canvas.drawCircle(Offset(x, y), unit * [1.4, 2.6, 6.0][layer] * (0.7 + _u(id, 4) * 0.6), paint);
      }
    }
  }

  void _glints(Canvas canvas, Size size, int f, double unit) {
    final p = Paint()
      ..blendMode = BlendMode.plus
      ..strokeWidth = unit * 1.4
      ..color = Colors.white.withValues(alpha: 0.8);
    for (var i = 0; i < 14; i++) {
      if ((f + i * 5) % 17 > 2) continue;
      final c = Offset(_u(i, 7) * size.width, size.height * (0.62 + _u(i, 8) * 0.35));
      final r = unit * 6;
      canvas.drawLine(c.translate(-r, 0), c.translate(r, 0), p);
      canvas.drawLine(c.translate(0, -r), c.translate(0, r), p);
    }
  }

  void _leaves(Canvas canvas, Size size, int f, double unit) {
    final colors = [const Color(0xFFE07A1F), const Color(0xFFB0452E), const Color(0xFFD9A43A)];
    for (var i = 0; i < 22; i++) {
      final speed = 2 + _u(i, 1) * 3;
      final y = (_u(i, 2) * (size.height + 60) + f * speed * unit * 1.4) % (size.height + 60) - 30;
      final x = (_u(i, 3) * size.width + math.sin((f + i * 9) * 0.08) * 40 + f * 0.6) % size.width;
      final s = unit * (7 + _u(i, 5) * 6);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((f * 0.25 + i) % (math.pi * 2));
      canvas.scale(1, 0.4 + 0.6 * math.cos((f + i * 3) * 0.3).abs()); // tumbling
      final leaf = Path()
        ..moveTo(0, -s)
        ..quadraticBezierTo(s * 0.8, 0, 0, s)
        ..quadraticBezierTo(-s * 0.8, 0, 0, -s);
      canvas.drawPath(leaf, Paint()..color = colors[i % 3]);
      canvas.drawLine(Offset(0, -s), Offset(0, s), Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..strokeWidth = 0.8);
      canvas.restore();
    }
  }

  void _sunbeams(Canvas canvas, Size size, double t, double bass) {
    for (var i = 0; i < 4; i++) {
      final x = size.width * (0.1 + i * 0.22);
      final a = 0.05 + 0.04 * math.sin(t * 0.7 + i * 1.7) + 0.08 * bass;
      final path = Path()
        ..moveTo(x, -10)
        ..lineTo(x + size.width * 0.08, -10)
        ..lineTo(x + size.width * 0.32, size.height)
        ..lineTo(x + size.width * 0.14, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(Offset(x, 0), Offset(x, size.height), [const Color(0xFFFFE2A0).withValues(alpha: a.clamp(0.0, 0.3)), const Color(0x00FFE2A0)]),
      );
    }
  }

  // ---- film -------------------------------------------------------------

  /// Moving grain, a few dust specks and the odd hair, plus a faint
  /// frame-to-frame exposure flicker: it reads as photographed, not drawn.
  void _filmLayer(Canvas canvas, Size size, int f, double unit) {
    final g = _Grain.image;
    if (g != null) {
      final r = math.Random(f);
      final tx = r.nextDouble() * 160, ty = r.nextDouble() * 160;
      final m = Float64List.fromList([1.6, 0, 0, 0, 0, 1.6, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1]);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..blendMode = BlendMode.overlay
          ..color = Colors.white.withValues(alpha: 0.11)
          ..shader = ImageShader(g, TileMode.repeated, TileMode.repeated, m),
      );
    }
    final rr = math.Random(f * 31 + 7);
    final speck = Paint()..color = Colors.black.withValues(alpha: 0.35);
    for (var i = 0; i < 3; i++) {
      if (rr.nextDouble() < 0.4) canvas.drawCircle(Offset(rr.nextDouble() * size.width, rr.nextDouble() * size.height), unit * (0.8 + rr.nextDouble() * 1.6), speck);
    }
    if (f % 47 == 0) {
      final x = rr.nextDouble() * size.width, y = rr.nextDouble() * size.height;
      canvas.drawPath(
          Path()
            ..moveTo(x, y)
            ..quadraticBezierTo(x + unit * 30, y + unit * 10, x + unit * 18, y + unit * 55),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = unit * 1.1
            ..color = Colors.black.withValues(alpha: 0.4));
    }
    final flick = clayNoise(f, 3, 9) * 0.014;
    canvas.drawRect(Offset.zero & size, Paint()..color = (flick > 0 ? Colors.white : Colors.black).withValues(alpha: flick.abs()));
  }

  @override
  bool shouldRepaint(SceneFxPainter old) => old.anchors != anchors || old.theme != theme;
}
