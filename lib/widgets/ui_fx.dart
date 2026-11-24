import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../services/beat.dart';
import '../services/player_service.dart';
import '../theme/palette.dart';
import 'clay.dart';

/// Music-reactive layer drawn over the whole app (never blocks input):
///
/// * themed motes drifting across the screen — embers, fireflies, dust,
///   snow or falling leaves — that get kicked by the kick drum,
/// * a warm glow breathing in from the screen edges with the bass,
/// * a clay splat + flash when the song changes,
/// * a little trail of clay crumbs behind the mouse on PC.
///
/// Runs only while music plays or something is still settling, so a
/// paused app costs nothing.
class UiFx extends StatefulWidget {
  const UiFx({super.key, required this.player, required this.child});

  final PlayerService player;
  final Widget child;

  @override
  State<UiFx> createState() => _UiFxState();
}

class _Mote {
  _Mote(this.x, this.y, this.vx, this.vy, this.size, this.seed);
  double x, y, vx, vy, size;
  double spin = 0;
  final int seed;
}

class _Burst {
  _Burst(this.at, this.seed);
  final Offset at;
  final int seed;
  double t = 0; // 0..1
}

class _Crumb {
  _Crumb(this.at, this.seed);
  final Offset at;
  final int seed;
  double life = 1;
}

class _UiFxState extends State<UiFx> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _repaint = ValueNotifier<int>(0);
  final _rnd = math.Random();
  final List<_Mote> _motes = [];
  final List<_Burst> _bursts = [];
  final List<_Crumb> _trail = [];
  Duration _last = Duration.zero;
  Size _size = Size.zero;
  double _show = 0; // motes fade in while playing, out when paused
  double _flash = 0;
  double _prevBass = 0;
  double _kick = 0;
  String? _lastSong;
  Offset? _lastMouse;

  bool get _motion => StopMotion.instance.enabled;

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_wake);
    widget.player.currentId.addListener(_songChanged);
    _lastSong = widget.player.currentId.value;
    _wake();
  }

  @override
  void dispose() {
    widget.player.removeListener(_wake);
    widget.player.currentId.removeListener(_songChanged);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _wake() {
    if (!_ticker.isActive && _motion && (widget.player.playing || _busy)) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  bool get _busy => _show > 0.01 || _bursts.isNotEmpty || _trail.isNotEmpty || _flash > 0.01;

  void _songChanged() {
    final id = widget.player.currentId.value;
    if (id == null || id == _lastSong) return;
    _lastSong = id;
    if (!_motion || _size == Size.zero) return;
    final wide = _size.width >= 860;
    _bursts.add(_Burst(Offset(_size.width / 2, _size.height - (wide ? 52 : 140)), _rnd.nextInt(1 << 20)));
    if (_bursts.length > 3) _bursts.removeAt(0);
    _flash = 1;
    for (final m in _motes) {
      m.vy -= 40 + _rnd.nextDouble() * 50; // everything jumps
    }
    _wake();
  }

  void _hover(PointerHoverEvent e) {
    if (e.kind != ui.PointerDeviceKind.mouse || !_motion) return;
    final p = e.localPosition;
    if (_lastMouse != null && (p - _lastMouse!).distance < 9) return;
    _lastMouse = p;
    _trail.add(_Crumb(p, _rnd.nextInt(1 << 20)));
    if (_trail.length > 16) _trail.removeAt(0);
    _wake();
  }

  void _seed(Size size) {
    // Same density on a phone and a 1440p monitor (more motes on big screens).
    final n = (size.width * size.height / 26000).round().clamp(18, 110);
    _motes.clear();
    for (var i = 0; i < n; i++) {
      _motes.add(_spawn(size, anywhere: true));
    }
  }

  _Mote _spawn(Size size, {bool anywhere = false}) {
    final theme = Clay.current.id;
    final falls = theme == 'snow' || theme == 'harvest';
    final sideways = theme == 'western';
    final x = _rnd.nextDouble() * size.width;
    final y = anywhere
        ? _rnd.nextDouble() * size.height
        : falls
            ? -10.0
            : size.height + 10;
    final vx = sideways ? 14 + _rnd.nextDouble() * 22 : (_rnd.nextDouble() - 0.5) * 12;
    final vy = falls ? 14 + _rnd.nextDouble() * 22 : (sideways ? (_rnd.nextDouble() - 0.5) * 6 : -(10 + _rnd.nextDouble() * 22));
    final big = (size.shortestSide / 700).clamp(1.0, 2.0);
    final sz = (theme == 'harvest' ? 4.0 + _rnd.nextDouble() * 3 : 1.4 + _rnd.nextDouble() * 2.4) * big;
    return _Mote(x, y, vx, vy, sz, _rnd.nextInt(1 << 20));
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 1 / 60 : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    if (_size == Size.zero) return;
    if (_motes.isEmpty) _seed(_size);

    Beat.instance.step();
    final bass = Beat.instance.bass.clamp(0.0, 1.0);
    final energy = Beat.instance.energy.clamp(0.0, 1.0);
    if (bass - _prevBass > 0.1) _kick = 1;
    _prevBass = bass;
    _kick = math.max(0.0, _kick - dt * 3);

    final playing = widget.player.playing && _motion;
    _show += ((playing ? 1.0 : 0.0) - _show) * math.min(1.0, dt * (playing ? 1.5 : 2.5));
    _flash = math.max(0.0, _flash - dt * 2.2);

    final theme = Clay.current.id;
    final speed = 0.6 + energy * 1.6;
    for (var i = 0; i < _motes.length; i++) {
      final m = _motes[i];
      final sway = math.sin(m.seed * 0.01 + now.inMilliseconds / 900.0) * 10;
      m.x += (m.vx + sway) * dt * speed;
      m.y += m.vy * dt * speed - (_kick * 30 * dt * (theme == 'snow' ? -0.4 : 1));
      m.spin += dt * (1 + m.size * 0.2);
      // Ease kicks back toward drifting speed.
      final base = theme == 'snow' || theme == 'harvest' ? 20.0 : (theme == 'western' ? 0.0 : -18.0);
      m.vy += (base - m.vy) * dt * 0.8;
      if (m.y < -20 || m.y > _size.height + 20 || m.x < -20 || m.x > _size.width + 20) {
        _motes[i] = _spawn(_size);
        if (theme == 'western') _motes[i].x = -10;
      }
    }

    for (final b in _bursts) {
      b.t += dt / 0.7;
    }
    _bursts.removeWhere((b) => b.t >= 1);
    for (final c in _trail) {
      c.life -= dt / 0.45;
    }
    _trail.removeWhere((c) => c.life <= 0);

    _repaint.value++;
    if (!playing && !_busy) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: _hover,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: LayoutBuilder(builder: (context, box) {
                final s = box.biggest;
                if (s != _size) {
                  _size = s;
                  if (_motes.isNotEmpty) _seed(s);
                }
                return RepaintBoundary(child: CustomPaint(painter: _FxPainter(this)));
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _FxPainter extends CustomPainter {
  _FxPainter(this.s) : super(repaint: s._repaint);

  final _UiFxState s;

  @override
  void paint(Canvas canvas, Size size) {
    final theme = Clay.current.id;
    final bass = Beat.instance.bass.clamp(0.0, 1.0);
    final accent = Clay.candle;
    final boil = StopMotion.instance.frame % 3;

    // Edge glow breathing with the bass (and a little on every kick).
    final glow = s._show * (0.05 + 0.2 * bass + 0.1 * s._kick);
    if (glow > 0.005) {
      final w = (70 + 50 * bass) * (size.shortestSide / 800).clamp(1.0, 2.2);
      void edge(Rect r, Alignment from, Alignment to) {
        canvas.drawRect(
          r,
          Paint()
            ..blendMode = Clay.current.dark ? BlendMode.plus : BlendMode.srcOver
            ..shader = ui.Gradient.linear(from.withinRect(r), to.withinRect(r), [accent.withValues(alpha: glow), accent.withValues(alpha: 0)]),
        );
      }

      edge(Rect.fromLTWH(0, 0, w, size.height), Alignment.centerLeft, Alignment.centerRight);
      edge(Rect.fromLTWH(size.width - w, 0, w, size.height), Alignment.centerRight, Alignment.centerLeft);
      edge(Rect.fromLTWH(0, size.height - w * 0.8, size.width, w * 0.8), Alignment.bottomCenter, Alignment.topCenter);
    }

    // Song-change flash.
    if (s._flash > 0.01) {
      canvas.drawRect(Offset.zero & size, Paint()..color = accent.withValues(alpha: 0.07 * s._flash));
    }

    // Motes.
    if (s._show > 0.01) {
      final glowPaint = Paint()..blendMode = Clay.current.dark ? BlendMode.plus : BlendMode.srcOver;
      final body = Paint();
      for (final m in s._motes) {
        final tw = 0.55 + 0.45 * math.sin(m.seed * 0.37 + m.spin * 2.3);
        final a = s._show * (0.35 + 0.5 * tw) * (0.7 + 0.6 * bass).clamp(0.0, 1.0);
        final at = Offset(m.x, m.y);
        switch (theme) {
          case 'snow':
            body.color = const Color(0xFFFFFFFF).withValues(alpha: a * 0.9);
            canvas.drawCircle(at, m.size * 1.2, body);
          case 'harvest':
            canvas.save();
            canvas.translate(m.x, m.y);
            canvas.rotate(m.spin + m.seed);
            body.color = (m.seed.isEven ? Clay.pumpkin : Clay.rose).withValues(alpha: a * 0.85);
            canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: m.size * 2.2, height: m.size * (1.0 + 0.4 * math.sin(m.spin * 3))), body);
            canvas.restore();
          case 'western':
            body.color = Clay.bone.withValues(alpha: a * 0.45);
            canvas.drawCircle(at, m.size, body);
          default:
            // Embers / fireflies: soft halo plus a hot core.
            final c = theme == 'moonlit' && m.seed % 3 == 0 ? Clay.ghost : accent;
            glowPaint.shader = ui.Gradient.radial(at, m.size * 5, [c.withValues(alpha: a * 0.45), c.withValues(alpha: 0)]);
            canvas.drawCircle(at, m.size * 5, glowPaint);
            body.color = Color.lerp(c, const Color(0xFFFFF6D8), 0.5)!.withValues(alpha: a);
            canvas.drawCircle(at, m.size * (0.8 + 0.2 * boil), body);
        }
      }
    }

    // Song-change clay splat: squashed ring + crumbs, stepped at 24 fps.
    for (final b in s._bursts) {
      final t = (b.t * 17).floor() / 17;
      final ease = 1 - math.pow(1 - t, 3).toDouble();
      final fade = 1 - t;
      final r = 20 + 140 * ease;
      canvas.drawOval(
        Rect.fromCenter(center: b.at, width: r * 2.4, height: r * 1.1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 * fade + 1
          ..color = accent.withValues(alpha: 0.5 * fade),
      );
      final crumb = Paint();
      for (var i = 0; i < 16; i++) {
        final a = -math.pi * (0.05 + 0.9 * (i / 15)) + clayNoise(b.seed, i, 1) * 0.15;
        final dist = (60 + 90 * (clayNoise(b.seed, i, 2) * 0.5 + 0.5)) * ease * (size.width / 900).clamp(1.0, 2.2);
        final c = b.at + Offset(math.cos(a) * dist * 1.6, math.sin(a) * dist) + Offset(0, 60 * t * t);
        crumb.color = (i.isEven ? accent : Clay.pumpkin).withValues(alpha: 0.85 * fade);
        canvas.drawOval(Rect.fromCenter(center: c, width: 7 * fade + 2, height: 5 * fade + 2), crumb);
      }
    }

    // Mouse trail: little clay crumbs that shrink away.
    if (s._trail.isNotEmpty) {
      final p = Paint();
      for (final c in s._trail) {
        final j = Offset(clayNoise(c.seed, boil, 1), clayNoise(c.seed, boil, 2)) * 0.8;
        p.color = accent.withValues(alpha: 0.5 * c.life);
        canvas.drawCircle(c.at + j + Offset(0, (1 - c.life) * 6), 1 + 3 * c.life, p);
      }
    }
  }

  @override
  bool shouldRepaint(_FxPainter old) => true;
}

/// A warm halo behind [child] that throbs with the bass while music plays —
/// used behind the play buttons.
class BeatGlow extends StatefulWidget {
  const BeatGlow({super.key, required this.player, required this.child, this.spread = 1.6});

  final PlayerService player;
  final Widget child;
  final double spread;

  @override
  State<BeatGlow> createState() => _BeatGlowState();
}

class _BeatGlowState extends State<BeatGlow> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) {
    Beat.instance.step();
    _level.value = widget.player.playing ? Beat.instance.bass.clamp(0.0, 1.0) : _level.value * 0.9;
    if (!widget.player.playing && _level.value < 0.01) _ticker.stop();
  });
  final _level = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (widget.player.playing && StopMotion.instance.enabled && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    widget.player.removeListener(_sync);
    _ticker.dispose();
    _level.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GlowPainter(_level, widget.spread),
      child: widget.child,
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.level, this.spread) : super(repaint: level);

  final ValueNotifier<double> level;
  final double spread;

  @override
  void paint(Canvas canvas, Size size) {
    final l = level.value;
    if (l < 0.01) return;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 * (spread + 0.5 * l);
    canvas.drawCircle(
      c,
      r,
      Paint()..shader = ui.Gradient.radial(c, r, [Clay.candle.withValues(alpha: 0.55 * l), Clay.pumpkin.withValues(alpha: 0.2 * l), Clay.pumpkin.withValues(alpha: 0)], const [0.3, 0.6, 1]),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => false;
}
