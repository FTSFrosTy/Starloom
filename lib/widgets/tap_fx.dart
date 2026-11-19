import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../theme/palette.dart';
import 'clay.dart';

/// A little clay "puff" wherever you touch: a squashed ring plus a few
/// crumbs flicking outward. It's drawn on top of everything and never
/// blocks the tap, so the app stays instant.
class TapFx extends StatefulWidget {
  const TapFx({super.key, required this.child});

  final Widget child;

  @override
  State<TapFx> createState() => _TapFxState();
}

class _Puff {
  _Puff(this.at, this.seed, this.born);
  final Offset at;
  final int seed;
  final Duration born;
}

class _TapFxState extends State<TapFx> with SingleTickerProviderStateMixin {
  static const _life = Duration(milliseconds: 360);
  final List<_Puff> _puffs = [];
  final ValueNotifier<Duration> _now = ValueNotifier(Duration.zero);
  late final Ticker _ticker = createTicker(_onTick);
  int _seed = 0;

  void _onTick(Duration elapsed) {
    _now.value = elapsed;
    _puffs.removeWhere((p) => elapsed - p.born > _life);
    if (_puffs.isEmpty) _ticker.stop();
  }

  void _down(PointerDownEvent e) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    if (!_ticker.isActive) {
      _now.value = Duration.zero;
      _ticker.start();
    }
    _puffs.add(_Puff(box.globalToLocal(e.position), _seed++, _now.value));
    if (_puffs.length > 6) _puffs.removeAt(0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(child: CustomPaint(painter: _PuffPainter(_puffs, _now, _life))),
            ),
          ),
        ],
      ),
    );
  }
}

class _PuffPainter extends CustomPainter {
  _PuffPainter(this.puffs, this.now, this.life) : super(repaint: now);

  final List<_Puff> puffs;
  final ValueNotifier<Duration> now;
  final Duration life;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in puffs) {
      final raw = ((now.value - p.born).inMicroseconds / life.inMicroseconds).clamp(0.0, 1.0);
      // Step at 24 fps for a hand-animated feel without looking laggy.
      final t = (raw * 9).floor() / 9;
      final ease = 1 - math.pow(1 - t, 3).toDouble();
      final fade = 1 - t;

      // Squashed clay ring.
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2 * fade + 0.6
        ..color = Clay.candle.withValues(alpha: 0.55 * fade);
      final r = 8 + 22 * ease;
      canvas.drawOval(Rect.fromCenter(center: p.at, width: r * 2.2, height: r * 1.7), ring);

      // Crumbs.
      final crumb = Paint()..color = Clay.pumpkin.withValues(alpha: 0.8 * fade);
      for (var i = 0; i < 6; i++) {
        final a = i / 6 * math.pi * 2 + clayNoise(p.seed, i, 1) * 0.5;
        final dist = (14 + 16 * (clayNoise(p.seed, i, 2) * 0.5 + 0.5)) * ease;
        final c = p.at + Offset(math.cos(a), math.sin(a) * 0.8) * dist + Offset(0, 6 * t * t);
        canvas.drawCircle(c, 2.4 * fade + 0.6, crumb);
      }
    }
  }

  @override
  bool shouldRepaint(_PuffPainter old) => true;
}
