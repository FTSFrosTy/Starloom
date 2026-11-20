import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';

/// The stop-motion clock. Real claymation is shot "on twos" (12 frames a
/// second), so every animated clay thing steps on this shared 12 fps beat
/// instead of the screen's 60/120 Hz. One timer for the whole app, and it
/// only runs while something is listening and the app is in the foreground.
class StopMotion implements Listenable {
  StopMotion._();
  static final StopMotion instance = StopMotion._();

  final List<VoidCallback> _listeners = [];
  Timer? _timer;
  int frame = 0;
  bool _enabled = true;
  bool _foreground = true;

  bool get enabled => _enabled;

  set enabled(bool v) {
    _enabled = v;
    _sync();
  }

  set foreground(bool v) {
    _foreground = v;
    _sync();
  }

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
    _sync();
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    _sync();
  }

  void _sync() {
    final shouldRun = _enabled && _foreground && _listeners.isNotEmpty;
    if (shouldRun && _timer == null) {
      _timer = Timer.periodic(const Duration(microseconds: 83333), (_) {
        frame++;
        for (final l in List<VoidCallback>.of(_listeners)) {
          l();
        }
      });
    } else if (!shouldRun && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }
}

/// Cheap deterministic noise in [-1, 1].
double clayNoise(int a, int b, int c) {
  var h = (a * 374761393 + b * 668265263 + c * 1442695041) & 0x7fffffff;
  h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
  h = h ^ (h >> 16);
  return (h & 0xffff) / 0xffff * 2 - 1;
}

Color shade(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

/// A lumpy, hand-pressed outline: a superellipse whose edge is nudged in and
/// out by noise. [boilFrame] cycles 3 poses, like the "boiling" outline of a
/// model that was touched between frames.
Path clayPath(Size size, {required int seed, double wobble = 1.0, double squareness = 4.0, int boilFrame = 0, int points = 28}) {
  final cx = size.width / 2;
  final cy = size.height / 2;
  final a = size.width / 2;
  final b = size.height / 2;
  final amp = math.min(size.width, size.height) * 0.022 * wobble;
  final e = 2 / squareness;
  final pts = <Offset>[];
  for (var i = 0; i < points; i++) {
    final t = i / points * math.pi * 2;
    final ct = math.cos(t);
    final st = math.sin(t);
    var x = cx + a * ct.sign * math.pow(ct.abs(), e);
    var y = cy + b * st.sign * math.pow(st.abs(), e);
    final n = clayNoise(seed, i, boilFrame % 3) * 0.65 + clayNoise(seed, i, 99) * 0.35;
    final dx = x - cx;
    final dy = y - cy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 0) {
      x += dx / len * amp * n;
      y += dy / len * amp * n;
    }
    pts.add(Offset(x, y));
  }
  return _smoothClosed(pts);
}

/// Catmull-Rom through the points, as cubic Beziers.
Path _smoothClosed(List<Offset> p) {
  final path = Path();
  final n = p.length;
  path.moveTo(p[0].dx, p[0].dy);
  for (var i = 0; i < n; i++) {
    final p0 = p[(i - 1 + n) % n];
    final p1 = p[i];
    final p2 = p[(i + 1) % n];
    final p3 = p[(i + 2) % n];
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  path.close();
  return path;
}

/// Paints one piece of shaded plasticine.
class ClayPainter extends CustomPainter {
  ClayPainter({
    required this.color,
    required this.seed,
    this.wobble = 1.0,
    this.squareness = 4.0,
    this.depth = 6,
    this.boil = false,
    this.pressed = 0,
  }) : super(repaint: boil ? StopMotion.instance : null);

  final Color color;
  final int seed;
  final double wobble;
  final double squareness;
  final double depth;
  final bool boil;

  /// 0..1, flattens the highlight a bit when pressed.
  final double pressed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final frame = boil ? StopMotion.instance.frame : 0;
    final path = clayPath(size, seed: seed, wobble: wobble, squareness: squareness, boilFrame: frame);
    final rect = Offset.zero & size;

    // Contact shadow.
    if (depth > 0) {
      canvas.drawPath(
        path.shift(Offset(0, depth * (0.7 - pressed * 0.4))),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, depth * 0.6),
      );
    }

    // Body: lit from the top left like a desk lamp on a model set.
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [shade(color, 0.08), color, shade(color, -0.14)],
          const [0.0, 0.45, 1.0],
        ),
    );

    // Soft sheen.
    final hl = Offset(size.width * 0.32, size.height * 0.24);
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          hl,
          math.max(size.width, size.height) * 0.6,
          [Colors.white.withValues(alpha: 0.16 * (1 - pressed * 0.5)), Colors.white.withValues(alpha: 0)],
        ),
    );

    // Darker rim where the clay curls under.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = shade(color, -0.22).withValues(alpha: 0.6),
    );

    // Thumbprints: a few faint arcs pressed into the surface.
    final printPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = Colors.white.withValues(alpha: 0.05);
    canvas.save();
    canvas.clipPath(path);
    for (var k = 0; k < 3; k++) {
      final px = (clayNoise(seed, k, 7) * 0.5 + 0.5) * size.width;
      final py = (clayNoise(seed, k, 11) * 0.5 + 0.5) * size.height;
      final r = 6.0 + (clayNoise(seed, k, 13) * 0.5 + 0.5) * 10;
      for (var ring = 0; ring < 3; ring++) {
        canvas.drawArc(Rect.fromCircle(center: Offset(px, py), radius: r + ring * 3), 0.4 + k, 1.6, false, printPaint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ClayPainter old) =>
      old.color != color ||
      old.seed != seed ||
      old.wobble != wobble ||
      old.squareness != squareness ||
      old.depth != depth ||
      old.boil != boil ||
      old.pressed != pressed;
}

/// A clay slab with content on it.
class ClayBox extends StatelessWidget {
  const ClayBox({
    super.key,
    required this.child,
    this.color,
    this.seed = 1,
    this.wobble = 1.0,
    this.squareness = 4.0,
    this.depth = 6,
    this.boil = false,
    this.padding = const EdgeInsets.all(14),
    this.pressed = 0,
  });

  final Widget child;
  final Color? color;
  final int seed;
  final double wobble;
  final double squareness;
  final double depth;
  final bool boil;
  final EdgeInsets padding;
  final double pressed;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Clay.bruise;
    if (!ClayBox.sculpted) {
      return RepaintBoundary(
        child: CustomPaint(
          painter: ClayPainter(color: c, seed: seed, wobble: wobble, squareness: squareness, depth: depth, boil: boil, pressed: pressed),
          child: Padding(padding: padding, child: child),
        ),
      );
    }
    // Real sculpted clay (rendered in Blender), tinted to the theme color.
    // The piece is nine-sliced at a scale worked out from the box's real
    // size, so small chips get small rounded ends instead of giant
    // overlapping ones.
    final kind = squareness < 3 ? _Sculpt.round : (squareness <= 3.5 ? _Sculpt.pill : _Sculpt.panel);
    final tint = Color.lerp(c, Colors.white, 0.16)!;
    Widget slab(int frame) => DecoratedBox(
          decoration: _SculptDecoration(kind, kind.asset(frame + seed.abs() % 3), tint, depth),
          child: Padding(padding: padding, child: child),
        );
    if (!boil) return RepaintBoundary(child: slab(0));
    return RepaintBoundary(
      child: ListenableBuilder(listenable: StopMotion.instance, builder: (context, _) => slab(StopMotion.instance.frame ~/ 2)),
    );
  }

  /// Use the rendered clay pieces (true) or the drawn ones (false).
  static bool sculpted = true;
}

enum _Sculpt {
  round,
  pill,
  panel;

  String asset(int frame) => switch (this) {
        _Sculpt.round => 'assets/clay/round_${frame % 3}.png',
        _Sculpt.pill => 'assets/clay/pill_${frame % 3}.png',
        _Sculpt.panel => 'assets/clay/panel.png',
      };

  Rect? get slice => switch (this) {
        _Sculpt.round => null,
        _Sculpt.pill => const Rect.fromLTRB(110, 40, 256, 75),
        _Sculpt.panel => const Rect.fromLTRB(72, 72, 290, 291),
      };

  /// Image-pixels per screen-pixel for a box of [size], so the rounded
  /// ends always fit: pills match the box height (and shrink further if the
  /// box is short), panels get corners about a quarter of the short side.
  double scaleFor(Size size) {
    if (size.isEmpty) return 1;
    switch (this) {
      case _Sculpt.round:
        return 1;
      case _Sculpt.pill:
        // Image is 115 px tall with 40 px top/bottom edges and ~110 px ends.
        return math.max(115 / size.height, 222 / (size.width * 0.96)).clamp(0.25, 12.0);
      case _Sculpt.panel:
        final corner = (size.shortestSide * 0.24).clamp(14.0, 64.0);
        return math.max(72 / corner, 146 / size.shortestSide).clamp(0.5, 12.0);
    }
  }
}

/// Paints a sculpted clay piece, nine-sliced at a size-aware scale.
class _SculptDecoration extends Decoration {
  const _SculptDecoration(this.kind, this.asset, this.tint, this.depth);

  final _Sculpt kind;
  final String asset;
  final Color tint;
  final double depth;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _SculptPainter(this, onChanged);

  @override
  bool operator ==(Object other) => other is _SculptDecoration && other.kind == kind && other.asset == asset && other.tint == tint && other.depth == depth;

  @override
  int get hashCode => Object.hash(kind, asset, tint, depth);
}

class _SculptPainter extends BoxPainter {
  _SculptPainter(this.d, super.onChanged);

  final _SculptDecoration d;
  DecorationImagePainter? _painter;
  double _scale = -1;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    // Round to a few steps so resizing doesn't make a new painter per frame.
    final scale = (d.kind.scaleFor(size) * 16).roundToDouble() / 16;
    if (_painter == null || scale != _scale) {
      _painter?.dispose();
      _scale = scale;
      _painter = DecorationImage(
        image: AssetImage(d.asset),
        fit: BoxFit.fill,
        centerSlice: d.kind.slice,
        scale: scale,
        filterQuality: FilterQuality.medium,
        colorFilter: ColorFilter.mode(d.tint, BlendMode.modulate),
      ).createPainter(onChanged ?? () {});
    }
    final rect = offset & size;
    // Soft contact shadow shaped like the piece (so no dark square corners).
    if (d.depth > 0) {
      final r = switch (d.kind) {
        _Sculpt.round => size.shortestSide / 2,
        _Sculpt.pill => size.height / 2,
        _Sculpt.panel => 72 / scale * 0.8,
      };
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.shift(Offset(0, d.depth * 0.55)).deflate(1), Radius.circular(r)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.42)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, d.depth * 0.55),
      );
    }
    _painter!.paint(canvas, rect, null, configuration);
  }

  @override
  void dispose() {
    _painter?.dispose();
    super.dispose();
  }
}

/// Squishes like soft clay when pressed.
class Squish extends StatefulWidget {
  const Squish({super.key, required this.child, this.onTap, this.onLongPress, this.enabled = true});

  /// A light tick on every press (set from the user's settings).
  static bool haptics = true;

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  @override
  State<Squish> createState() => _SquishState();
}

class _SquishState extends State<Squish> with SingleTickerProviderStateMixin {
  // Unbounded so the elastic release can overshoot into a little jiggle.
  late final AnimationController _c = AnimationController.unbounded(vsync: this);
  bool _hover = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down() {
    if (Squish.haptics) HapticFeedback.selectionClick();
    _c.animateTo(1, duration: const Duration(milliseconds: 90), curve: Curves.easeOut);
  }

  void _up() {
    _c.animateBack(0, duration: const Duration(milliseconds: 520), curve: Curves.elasticOut);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && (widget.onTap != null || widget.onLongPress != null);
    final gesture = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: active ? (_) => _down() : null,
      onTapUp: active ? (_) => _up() : null,
      onTapCancel: active ? _up : null,
      onTap: active ? widget.onTap : null,
      onLongPress: active ? widget.onLongPress : null,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final v = _c.value;
          return Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.diagonal3Values(1 + v * 0.07, 1 - v * 0.09, 1),
            child: child,
          );
        },
        child: Opacity(opacity: widget.enabled ? 1 : 0.4, child: widget.child),
      ),
    );
    if (!active) return gesture;
    // PC: lift and tilt a touch under the mouse, like picking up clay.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.045 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: AnimatedRotation(
          turns: _hover ? 0.004 : 0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutBack,
          child: gesture,
        ),
      ),
    );
  }
}

/// Round clay button holding an icon.
class ClayIconButton extends StatelessWidget {
  const ClayIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 48,
    this.color,
    this.iconColor,
    this.seed = 3,
    this.boil = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final Color? iconColor;
  final int seed;
  final bool boil;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget w = Squish(
      onTap: onTap,
      enabled: onTap != null,
      child: SizedBox(
        width: size,
        height: size,
        child: ClayBox(
          color: color,
          seed: seed,
          squareness: 2.2,
          wobble: 1.6,
          depth: size * 0.12,
          boil: boil,
          padding: EdgeInsets.zero,
          child: Center(child: Icon(icon, color: iconColor ?? (color == null ? Clay.bone : _onColor(color!)), size: size * 0.46)),
        ),
      ),
    );
    if (tooltip != null) w = Tooltip(message: tooltip!, child: w);
    return Semantics(button: true, label: tooltip, child: w);
  }
}

/// Clay pill button with a label.
class ClayButton extends StatelessWidget {
  const ClayButton({super.key, required this.label, required this.onTap, this.icon, this.color, this.seed = 5});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? color;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return Squish(
      onTap: onTap,
      enabled: onTap != null,
      child: ClayBox(
        color: color ?? Clay.plum,
        seed: seed,
        squareness: 3.0,
        depth: 5,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 18, color: _onColor(color ?? Clay.plum)), const SizedBox(width: 8)],
            Text(label, style: TextStyle(color: _onColor(color ?? Clay.plum), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// A tiny static clay pebble used as a song's "cover" in long lists.
/// No shadow blur, no boil: cheap enough for a thousand rows.
class Pebble extends StatelessWidget {
  const Pebble({super.key, required this.seedText, this.size = 44, this.glyph});

  final String seedText;
  final double size;
  final String? glyph;

  @override
  Widget build(BuildContext context) {
    final h = seedText.hashCode & 0x7fffffff;
    final color = Clay.pebbles[h % Clay.pebbles.length];
    return SizedBox(
      width: size,
      height: size,
      child: ClayBox(
        color: color,
        seed: h,
        wobble: 2.4,
        squareness: 2.4,
        depth: 0,
        padding: EdgeInsets.zero,
        child: Center(
          child: Text(
            glyph ?? (seedText.isEmpty ? '?' : seedText.characters.first.toUpperCase()),
            style: Clay.title(size * 0.42, color: Clay.bone.withValues(alpha: 0.85)),
          ),
        ),
      ),
    );
  }
}

/// A horizontal or vertical clay slider: a pressed groove and a lump of clay
/// you drag. Values are 0..1; callers map to their own range.
class ClaySlider extends StatefulWidget {
  const ClaySlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.vertical = false,
    this.color,
    this.thickness = 36,
    this.centerZero = false,
    this.seed = 9,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final bool vertical;
  final Color? color;
  final double thickness;

  /// Fill from the middle (for +/- dB sliders) instead of from the start.
  final bool centerZero;
  final int seed;

  @override
  State<ClaySlider> createState() => _ClaySliderState();
}

class _ClaySliderState extends State<ClaySlider> {
  bool _dragging = false;
  Offset? _last;

  double _valueAt(Offset local, Size size) {
    final knob = widget.thickness * 0.8;
    if (widget.vertical) {
      final usable = size.height - knob;
      return (1 - (local.dy - knob / 2) / usable).clamp(0.0, 1.0);
    }
    final usable = size.width - knob;
    return ((local.dx - knob / 2) / usable).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = Size(
        widget.vertical ? widget.thickness : c.maxWidth,
        widget.vertical ? c.maxHeight : widget.thickness,
      );
      void update(Offset p) => widget.onChanged(_valueAt(p, size));
      void end(Offset? p) {
        setState(() => _dragging = false);
        widget.onChangeEnd?.call(p == null ? widget.value : _valueAt(p, size));
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          setState(() => _dragging = true);
          update(d.localPosition);
        },
        onTapUp: (d) => end(d.localPosition),
        onVerticalDragStart: widget.vertical
            ? (d) {
                setState(() => _dragging = true);
                update(d.localPosition);
              }
            : null,
        onVerticalDragUpdate: widget.vertical
            ? (d) {
                _last = d.localPosition;
                update(d.localPosition);
              }
            : null,
        onVerticalDragEnd: widget.vertical ? (_) => end(_last) : null,
        onHorizontalDragStart: widget.vertical
            ? null
            : (d) {
                setState(() => _dragging = true);
                update(d.localPosition);
              },
        onHorizontalDragUpdate: widget.vertical
            ? null
            : (d) {
                _last = d.localPosition;
                update(d.localPosition);
              },
        onHorizontalDragEnd: widget.vertical ? null : (_) => end(_last),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ClaySliderPainter(
                value: widget.value.clamp(0.0, 1.0),
                vertical: widget.vertical,
                color: widget.color ?? Clay.candle,
                knob: widget.thickness * 0.8,
                centerZero: widget.centerZero,
                active: _dragging,
                seed: widget.seed,
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _ClaySliderPainter extends CustomPainter {
  _ClaySliderPainter({
    required this.value,
    required this.vertical,
    required this.color,
    required this.knob,
    required this.centerZero,
    required this.active,
    required this.seed,
  });

  final double value;
  final bool vertical;
  final Color color;
  final double knob;
  final bool centerZero;
  final bool active;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final groove = knob * 0.34;
    final start = knob / 2;
    final len = (vertical ? size.height : size.width) - knob;
    Offset at(double v) => vertical ? Offset(size.width / 2, size.height - start - v * len) : Offset(start + v * len, size.height / 2);

    // Groove pressed into the clay.
    final a = at(0), b = at(1);
    final groovePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..strokeWidth = groove
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, groovePaint);
    canvas.drawLine(
      a + const Offset(0, 1.5),
      b + const Offset(0, 1.5),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..strokeWidth = groove * 0.6
        ..strokeCap = StrokeCap.round,
    );

    // Filled part: a rolled snake of colored clay.
    final from = at(centerZero ? 0.5 : 0);
    final to = at(value);
    canvas.drawLine(
      from,
      to,
      Paint()
        ..shader = ui.Gradient.linear(from, to, [shade(color, -0.12), color])
        ..strokeWidth = groove * 0.8
        ..strokeCap = StrokeCap.round,
    );

    // The knob.
    final k = knob * (active ? 1.12 : 1.0);
    canvas.save();
    canvas.translate(to.dx - k / 2, to.dy - k / 2);
    ClayPainter(color: shade(color, active ? 0.06 : 0), seed: seed, wobble: 2.0, squareness: 2.2, depth: k * 0.14)
        .paint(canvas, Size(k, k));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ClaySliderPainter old) =>
      old.value != value || old.active != active || old.color != color || old.centerZero != centerZero;
}

/// Big title in the hand-cut display face.
/// Big hand-made title: the letters drop in one by one when the page
/// opens, then "boil" (jiggle a hair on twos) like hand-placed clay type.
class ClayTitle extends StatefulWidget {
  const ClayTitle(this.text, {super.key, this.size = 34});

  final String text;
  final double size;

  @override
  State<ClayTitle> createState() => _ClayTitleState();
}

class _ClayTitleState extends State<ClayTitle> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void initState() {
    super.initState();
    if (StopMotion.instance.enabled) {
      _in.forward();
    } else {
      _in.value = 1;
    }
  }

  @override
  void didUpdateWidget(ClayTitle old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text && StopMotion.instance.enabled) _in.forward(from: 0);
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Clay.title(widget.size).copyWith(
      shadows: const [Shadow(color: Colors.black54, offset: Offset(0, 3), blurRadius: 6)],
    );
    // Very long titles just get the plain (still styled) text.
    if (widget.text.length > 40) return Text(widget.text, style: style);
    final chars = widget.text.characters.toList();
    final seed = widget.text.hashCode;
    return ListenableBuilder(
      listenable: Listenable.merge([StopMotion.instance, _in]),
      builder: (context, _) {
        final f = StopMotion.instance.frame ~/ 2; // "on twos"
        final t = _in.value;
        final spans = <InlineSpan>[];
        var word = <Widget>[];
        void flush() {
          if (word.isEmpty) return;
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: word),
          ));
          word = <Widget>[];
        }

        for (var i = 0; i < chars.length; i++) {
          final c = chars[i];
          if (c == ' ') {
            flush();
            spans.add(TextSpan(text: ' ', style: style));
            continue;
          }
          // Staggered drop-in with a little squash on landing.
          final local = ((t * (chars.length * 0.35 + 1)) - i * 0.35).clamp(0.0, 1.0);
          final drop = Curves.easeOutBack.transform(local);
          final dy = (1 - drop) * -widget.size * 0.5 + clayNoise(seed, i * 7 + f, 1) * 0.9;
          final dx = clayNoise(seed, i * 7 + f, 2) * 0.7;
          final rot = clayNoise(seed, i * 13 + f, 3) * 0.035;
          word.add(Opacity(
            opacity: local,
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.translationValues(dx, dy, 0)..rotateZ(rot),
              child: Text(c, style: style),
            ),
          ));
        }
        flush();
        return Text.rich(TextSpan(children: spans));
      },
    );
  }
}

/// Light or dark text, whichever reads on [c].
Color _onColor(Color c) => c.computeLuminance() > 0.45 ? const Color(0xFF1A1410) : const Color(0xFFFFF6E8);
