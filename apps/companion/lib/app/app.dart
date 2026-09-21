import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'theme.dart';

/// Root widget. Owns the router so rebuilding the app never resets navigation.
class GlideCompanionApp extends StatefulWidget {
  const GlideCompanionApp({super.key});

  @override
  State<GlideCompanionApp> createState() => _GlideCompanionAppState();
}

class _GlideCompanionAppState extends State<GlideCompanionApp> {
  late final GoRouter _router = createRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Glide',
        theme: glideTheme(Brightness.light),
        darkTheme: glideTheme(Brightness.dark),
        routerConfig: _router,
      );
}
