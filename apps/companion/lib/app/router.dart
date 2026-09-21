import 'package:glide_protocol/glide_protocol.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/home/scanner_screen.dart';
import '../features/session/pair_screen.dart';
import '../features/session/session_screen.dart';

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
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/scan',
          builder: (context, state) => const ScannerScreen(),
        ),
        GoRoute(
          path: '/pair',
          redirect: (context, state) =>
              state.extra is PairingPayload ? null : '/',
          builder: (context, state) =>
              PairScreen(payload: state.extra! as PairingPayload),
        ),
        GoRoute(
          path: '/session',
          builder: (context, state) => const SessionScreen(),
        ),
      ],
    );
