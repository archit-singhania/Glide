import 'package:flutter/material.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/home/scanner_screen.dart';
import '../features/session/pair_screen.dart';
import '../features/session/session_screen.dart';

/// Wraps [child] in a short fade-through-and-rise transition, so moving
/// between Glide's screens feels like one continuous surface rather than a
/// stock platform push. Deliberately a single, finite `Curves.easeOutCubic`
/// tween (220ms): it settles well inside `pumpAndSettle`'s window, unlike a
/// repeating animation, which would never let a widget test return.
CustomTransitionPage<T> _glideTransition<T>({
  required LocalKey key,
  required Widget child,
}) =>
    CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );

/// Routes:
///
/// - `/` start screen
/// - `/scan` QR scanner
/// - `/pair` confirmation; needs a [PairingPayload] as `extra`, and returns
///   to `/` when it is missing (for example after the app was restored)
/// - `/session` dashboard for a paired session
GoRouter createRouter() => GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => _glideTransition(
            key: state.pageKey,
            child: const HomeScreen(),
          ),
        ),
        GoRoute(
          path: '/scan',
          pageBuilder: (context, state) => _glideTransition(
            key: state.pageKey,
            child: const ScannerScreen(),
          ),
        ),
        GoRoute(
          path: '/pair',
          redirect: (context, state) =>
              state.extra is PairingPayload ? null : '/',
          pageBuilder: (context, state) => _glideTransition(
            key: state.pageKey,
            child: PairScreen(payload: state.extra! as PairingPayload),
          ),
        ),
        GoRoute(
          path: '/session',
          pageBuilder: (context, state) => _glideTransition(
            key: state.pageKey,
            child: const SessionScreen(),
          ),
        ),
      ],
    );
