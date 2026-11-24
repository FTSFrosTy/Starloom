import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/palette.dart';
import 'clay.dart';
import 'fx.dart';
import '../services/beat.dart';

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
        else ...[
          RepaintBoundary(child: CustomPaint(painter: _SetPainter(animate: moving))),
          IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: SceneFxPainter('moonlit', null, animate: moving)))),
        ],
        child,
      ],
    );
  }
}

/// A pre-rendered 3D clay set (made in Blender), shot like a stop-motion
/// film: the camera creeps in 12 fps steps, windows and lamps flicker and
/// pulse with the music, creatures and weather move through the set, and
/// grain plays over everything.
class _Plate extends StatefulWidget {
  const _Plate({required this.theme, required this.animate, required this.scrim});

  final StarTheme theme;
  final bool animate;
  final bool scrim;

  @override
  State<_Plate> createState() => _PlateState();
}

class _PlateState extends State<_Plate> {
  SetAnchors? _anchors;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_Plate old) {
    super.didUpdateWidget(old);
    if (old.theme.id != widget.theme.id) _load();
  }

  void _load() {
    final id = widget.theme.id;
    SetAnchors.load(id).then((a) {
      if (mounted && widget.theme.id == id) setState(() => _anchors = a);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final longest = (size.longestSide * dpr).clamp(600, 1440).round();
    final shade = theme.bg;
    final set = Stack(fit: StackFit.expand, children: [
      Image(
        image: ResizeImage(AssetImage(theme.plate!), width: longest, height: longest, policy: ResizeImagePolicy.fit),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      ),
      CustomPaint(painter: SetGlowPainter(theme.id, _anchors, animate: widget.animate)),
    ]);
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: _CameraDrift(animate: widget.animate, child: RepaintBoundary(child: set))),
        if (widget.scrim)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: theme.dark
                      ? [shade.withValues(alpha: 0.15), shade.withValues(alpha: 0.38), shade.withValues(alpha: 0.68)]
                      : [shade.withValues(alpha: 0.22), shade.withValues(alpha: 0.48), shade.withValues(alpha: 0.74)],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
        IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: SceneFxPainter(theme.id, _anchors, animate: widget.animate)))),
      ],
    );
  }
}

/// Slow push-in and sway, moved one stop-motion frame at a time.
class _CameraDrift extends StatelessWidget {
  const _CameraDrift({required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) return Transform.scale(scale: 1.04, child: child);
    return ListenableBuilder(
      listenable: StopMotion.instance,
      child: child,
      builder: (context, child) {
        final t = StopMotion.instance.frame / 12.0;
        final size = MediaQuery.sizeOf(context);
        return Transform.translate(
          offset: Offset(math.sin(t * 0.07) * size.width * 0.012, math.cos(t * 0.05) * size.height * 0.008),
          child: Transform.scale(scale: 1.05 + 0.015 * math.sin(t * 0.09), child: child),
        );
      },
    );
  }
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
    final stars = (w * h / 9000).round().clamp(46, 260);
    for (var i = 0; i < stars; i++) {
      final x = (clayNoise(i, 1, 5) * 0.5 + 0.5) * w;
      final y = (clayNoise(i, 2, 5) * 0.5 + 0.5) * h * 0.62;
      final on = (f + i * 3) % 17 != 0;
      star.color = Clay.bone.withValues(alpha: on ? 0.35 + 0.3 * (clayNoise(i, 3, 5) * 0.5 + 0.5) : 0.08);
      canvas.drawCircle(Offset(x, y), 0.8 + (clayNoise(i, 4, 5) * 0.5 + 0.5) * 1.1, star);
    }

    // Crooked moon with a glow.
    final mr = math.min(math.min(w, h) * 0.13, 120.0);
    final mc = Offset(w * 0.78, h * 0.13);
    canvas.drawCircle(
      mc,
      mr * 2.4,
      Paint()..shader = ui.Gradient.radial(mc, mr * (2.4 + Beat.instance.bass), [Clay.ghost.withValues(alpha: 0.18 + 0.3 * Beat.instance.bass), Clay.ghost.withValues(alpha: 0)]),
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
