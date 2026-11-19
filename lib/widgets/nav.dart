import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'scenery.dart';

/// Navigation inside the app shell. Each tab has its own page stack, so
/// opening an album keeps the tab bar and player visible (like Spotify).
class Nav {
  static final List<GlobalKey<NavigatorState>> tabs = List.generate(5, (_) => GlobalKey<NavigatorState>());
  static int currentTab = 0;

  /// Root navigator (full-screen pages like Now Playing).
  static final GlobalKey<NavigatorState> root = GlobalKey<NavigatorState>();

  static NavigatorState? get _current => tabs[currentTab].currentState;

  /// Pushed pages get their own copy of the scenery so the page underneath
  /// doesn't show through during the slide.
  static Future<T?> push<T>(Widget page) => _current?.push<T>(quickRoute<T>(Backdrop(child: page))) ?? Future.value();

  static void popToRoot() => _current?.popUntil((r) => r.isFirst);
}

/// On iPhone: the native slide with swipe-back. Elsewhere: a short fade with
/// a small slide. Snappy, not flashy.
Route<T> quickRoute<T>(Widget page) => Platform.isIOS
    ? CupertinoPageRoute<T>(builder: (_) => page)
    : PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 190),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, a, b) => page,
      transitionsBuilder: (context, anim, sec, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    );
