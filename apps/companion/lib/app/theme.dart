import 'package:flutter/material.dart';

const Color _seed = Color(0xFF2A6BF2);

/// Material 3 theme for [brightness], derived from one seed colour.
ThemeData glideTheme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      ),
    );
