import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_scope.dart';
import '../theme/palette.dart';
import 'clay.dart';

/// Album art thumbnail, or a clay pebble when the song has none.
class Cover extends StatelessWidget {
  const Cover({super.key, required this.artKey, required this.seedText, this.size = 48, this.radius});

  final String? artKey;
  final String seedText;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final path = AppScope.of(context).library.artPath(artKey);
    if (path == null) return Pebble(seedText: seedText, size: size);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final r = radius ?? size * 0.18;
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: size * 0.08, offset: Offset(0, size * 0.04))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: Image.file(
            File(path),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * dpr).round(),
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, _, _) => Pebble(seedText: seedText, size: size),
          ),
        ),
      ),
    );
  }
}

/// 2×2 grid of covers for a playlist, like Spotify. Falls back to one big
/// pebble when there are fewer than 4 different covers.
class Mosaic extends StatelessWidget {
  const Mosaic({super.key, required this.artKeys, required this.seedText, this.size = 64, this.icon});

  final List<String> artKeys;
  final String seedText;
  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final keys = artKeys.toSet().take(4).toList();
    if (icon != null) {
      return SizedBox(
        width: size,
        height: size,
        child: ClayBox(
          color: Clay.plum,
          seed: seedText.hashCode,
          squareness: 4,
          depth: size * 0.06,
          padding: EdgeInsets.zero,
          child: Center(child: Icon(icon, color: Clay.candle, size: size * 0.45)),
        ),
      );
    }
    if (keys.isEmpty) return Pebble(seedText: seedText, size: size);
    if (keys.length < 4) return Cover(artKey: keys.first, seedText: seedText, size: size);
    final half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.14),
      child: SizedBox(
        width: size,
        height: size,
        child: Wrap(
          children: [for (final k in keys) Cover(artKey: k, seedText: k, size: half, radius: 0)],
        ),
      ),
    );
  }
}
