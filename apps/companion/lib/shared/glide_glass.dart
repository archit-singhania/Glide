import 'dart:ui';

import 'package:flutter/material.dart';

/// Design tokens for Glide's glassmorphism look, layered on top of Material
/// 3's [ColorScheme] via [ThemeExtension] so every widget reads colours from
/// [Theme.of] rather than hard-coding them.
///
/// Deliberately static: nothing here animates. Widget tests drive the app
/// with `pumpAndSettle`, which never returns while a repeating animation is
/// running, so the premium look comes from layered blur and gradients, not
/// motion.
@immutable
class GlideTokens extends ThemeExtension<GlideTokens> {
  const GlideTokens({
    required this.backgroundGradient,
    required this.glowPrimary,
    required this.glowSecondary,
    required this.glassFill,
    required this.glassFillStrong,
    required this.glassBorder,
    required this.glassShadow,
  });

  /// Base wash behind every screen, top-left to bottom-right.
  final List<Color> backgroundGradient;

  /// Soft, blurred accent blobs that sit behind the glass surfaces.
  final Color glowPrimary;
  final Color glowSecondary;

  /// Frosted-glass fill for cards, inputs and the app bar.
  final Color glassFill;

  /// A slightly denser fill for surfaces that need more contrast (sheets,
  /// banners).
  final Color glassFillStrong;
  final Color glassBorder;
  final Color glassShadow;

  static const GlideTokens dark = GlideTokens(
    backgroundGradient: <Color>[
      Color(0xFF0A0D18),
      Color(0xFF141A30),
      Color(0xFF0A0D18),
    ],
    glowPrimary: Color(0xFF6E7BFF),
    glowSecondary: Color(0xFF2FE0C4),
    glassFill: Color(0x1AFFFFFF),
    glassFillStrong: Color(0x29FFFFFF),
    glassBorder: Color(0x2EFFFFFF),
    glassShadow: Color(0x66000000),
  );

  static const GlideTokens light = GlideTokens(
    backgroundGradient: <Color>[
      Color(0xFFEEF1FC),
      Color(0xFFE2E7FB),
      Color(0xFFF1EEFB),
    ],
    glowPrimary: Color(0xFF5865F2),
    glowSecondary: Color(0xFF19B79A),
    glassFill: Color(0xB3FFFFFF),
    glassFillStrong: Color(0xD9FFFFFF),
    glassBorder: Color(0x8AFFFFFF),
    glassShadow: Color(0x1F1A2340),
  );

  @override
  GlideTokens copyWith({
    List<Color>? backgroundGradient,
    Color? glowPrimary,
    Color? glowSecondary,
    Color? glassFill,
    Color? glassFillStrong,
    Color? glassBorder,
    Color? glassShadow,
  }) =>
      GlideTokens(
        backgroundGradient: backgroundGradient ?? this.backgroundGradient,
        glowPrimary: glowPrimary ?? this.glowPrimary,
        glowSecondary: glowSecondary ?? this.glowSecondary,
        glassFill: glassFill ?? this.glassFill,
        glassFillStrong: glassFillStrong ?? this.glassFillStrong,
        glassBorder: glassBorder ?? this.glassBorder,
        glassShadow: glassShadow ?? this.glassShadow,
      );

  @override
  GlideTokens lerp(ThemeExtension<GlideTokens>? other, double t) {
    if (other is! GlideTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    List<Color> stops(List<Color> a, List<Color> b) => <Color>[
          for (var i = 0; i < a.length; i++) c(a[i], b[i]),
        ];
    return GlideTokens(
      backgroundGradient: stops(backgroundGradient, other.backgroundGradient),
      glowPrimary: c(glowPrimary, other.glowPrimary),
      glowSecondary: c(glowSecondary, other.glowSecondary),
      glassFill: c(glassFill, other.glassFill),
      glassFillStrong: c(glassFillStrong, other.glassFillStrong),
      glassBorder: c(glassBorder, other.glassBorder),
      glassShadow: c(glassShadow, other.glassShadow),
    );
  }
}

/// Reads [GlideTokens] from the current theme, falling back to [dark] so a
/// stray context without the extension (unlikely) still renders sensibly.
GlideTokens glideTokens(BuildContext context) =>
    Theme.of(context).extension<GlideTokens>() ?? GlideTokens.dark;

/// Full-bleed backdrop: a soft gradient wash plus two blurred colour blobs.
/// Put this behind a screen's content, e.g.:
///
/// ```dart
/// Scaffold(
///   extendBodyBehindAppBar: true,
///   appBar: glassAppBar(context, title: 'Glide'),
///   body: GlideBackground(child: SafeArea(child: ...)),
/// )
/// ```
class GlideBackground extends StatelessWidget {
  const GlideBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = glideTokens(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: tokens.backgroundGradient,
            ),
          ),
        ),
        Positioned(top: -70, left: -60, child: _Glow(tokens.glowPrimary, 240)),
        Positioned(
          bottom: -90,
          right: -70,
          child: _Glow(tokens.glowSecondary, 300),
        ),
        child,
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow(this.color, this.diameter);

  final Color color;
  final double diameter;

  @override
  Widget build(BuildContext context) => ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.35),
          ),
        ),
      );
}

/// A frosted-glass panel: blurred backdrop, translucent fill, hairline
/// border and a soft shadow. The building block for every card-like surface
/// in the app.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.borderRadius = 24,
    this.strong = false,
    this.blurSigma = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;

  /// Uses the denser [GlideTokens.glassFillStrong] fill, for surfaces that
  /// need to stand out more (banners, sheets).
  final bool strong;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final tokens = glideTokens(context);
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.glassShadow,
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              color: strong ? tokens.glassFillStrong : tokens.glassFill,
              border: Border.all(color: tokens.glassBorder, width: 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A frosted app bar: blurred backdrop with a hairline bottom border,
/// letting [GlideBackground]'s glow show through instead of a flat colour.
/// Use with `Scaffold(extendBodyBehindAppBar: true, ...)`.
PreferredSizeWidget glassAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  Widget? leading,
}) {
  final tokens = glideTokens(context);
  return PreferredSize(
    preferredSize: const Size.fromHeight(kToolbarHeight),
    child: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.glassFill,
            border: Border(bottom: BorderSide(color: tokens.glassBorder)),
          ),
          child: AppBar(
            title: Text(title),
            actions: actions,
            leading: leading,
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
        ),
      ),
    ),
  );
}

/// A small filled dot used for connection/status indicators, with a soft
/// glow instead of a flat circle.
class StatusDot extends StatelessWidget {
  const StatusDot({required this.color, super.key, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: <BoxShadow>[
            BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
          ],
        ),
      );
}

/// Wraps [icon] in a small frosted chip, used for section markers.
class GlassIconBadge extends StatelessWidget {
  const GlassIconBadge({
    required this.icon,
    super.key,
    this.size = 44,
    this.color,
  });

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = glideTokens(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tokens.glassFillStrong,
        border: Border.all(color: tokens.glassBorder),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}
