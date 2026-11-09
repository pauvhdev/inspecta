import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Temas de la app (DISEÑO.md §6.0).
///
/// [sol] es el principal: claro y de contraste máximo, para leerse a pleno sol.
/// [sotano] es el oscuro, para cuartos de máquinas en penumbra.
class InspectaTheme {
  const InspectaTheme._();

  static ThemeData get sotano => _build(
    brightness: Brightness.dark,
    bg: InspectaColors.bgDark,
    surface: InspectaColors.surfaceDark,
    surfaceHigh: InspectaColors.surfaceHighDark,
    border: InspectaColors.borderDark,
    text: InspectaColors.textDark,
    muted: InspectaColors.textMutedDark,
  );

  static ThemeData get sol => _build(
    brightness: Brightness.light,
    bg: InspectaColors.bgLight,
    surface: InspectaColors.surfaceLight,
    surfaceHigh: InspectaColors.surfaceHighLight,
    border: InspectaColors.borderLight,
    text: InspectaColors.textLight,
    muted: InspectaColors.textMutedLight,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color surfaceHigh,
    required Color border,
    required Color text,
    required Color muted,
  }) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? InspectaColors.accentOnDark : InspectaColors.accent,
      onPrimary: isDark ? InspectaColors.bgDark : Colors.white,
      primaryContainer: isDark
          ? InspectaColors.accentDim
          : const Color(0xFFDCE8FB),
      onPrimaryContainer: isDark ? Colors.white : const Color(0xFF062A5E),
      secondary: InspectaColors.pending,
      onSecondary: Colors.white,
      error: InspectaColors.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      surfaceContainerLowest: bg,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      onSurfaceVariant: muted,
      outline: border,
      outlineVariant: border,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            bodyLarge: base.textTheme.bodyLarge?.copyWith(
              fontSize: textoBaseTecnico,
            ),
            bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 16),
          )
          .apply(bodyColor: text, displayColor: text),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: text,
        // Tamaño explícito: `base.textTheme` aún no lleva la geometría de
        // `Typography` (se aplica en `Theme.of`) y el título salía a 14.
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontSize: 22,
          color: text,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.brMd,
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(Touch.min),
          shape: const RoundedRectangleBorder(borderRadius: Radii.brMd),
          textStyle: const TextStyle(
            fontSize: textoBaseTecnico,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(Touch.min),
          foregroundColor: text,
          side: BorderSide(color: border),
          shape: const RoundedRectangleBorder(borderRadius: Radii.brMd),
          textStyle: const TextStyle(
            fontSize: textoBaseTecnico,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // Iconos pulsables (incluida la flecha de volver) a 56 dp como todo lo
      // demás (§6.0, `tactil_56dp_test`).
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(Touch.min, Touch.min),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(Touch.min, Touch.min),
          foregroundColor: InspectaColors.accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.md,
        ),
        border: OutlineInputBorder(
          borderRadius: Radii.brMd,
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.brMd,
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: Radii.brMd,
          borderSide: BorderSide(color: InspectaColors.accent, width: 2),
        ),
        hintStyle: TextStyle(color: muted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: InspectaColors.accent.withValues(alpha: 0.18),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? InspectaColors.accent
                : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? InspectaColors.accent
                : muted,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: TextStyle(color: text),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: Radii.brMd),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        side: BorderSide(color: border),
        labelStyle: TextStyle(color: text, fontWeight: FontWeight.w600),
        shape: const RoundedRectangleBorder(borderRadius: Radii.brSm),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: text,
        shape: const RoundedRectangleBorder(borderRadius: Radii.brMd),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: InspectaColors.accent,
      ),
    );
  }
}

/// Estilos de texto para cifras. Siempre tabulares: en una tabla de presiones o
/// de kilos, las columnas tienen que quedar alineadas aunque cambien los dígitos.
extension InspectaTextStyles on TextTheme {
  /// La cifra grande que encabeza una pantalla.
  ///
  /// A este tamaño NO se usan cifras tabulares: al dar a todos los dígitos el
  /// ancho de un cero, un número como 11,1 se ve suelto y descolocado. Las
  /// tabulares son para columnas que deben alinearse.
  TextStyle get numberHero => TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.5,
    height: 1.05,
    color: bodyLarge?.color,
  );

  TextStyle get numberBig => TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    fontFeatures: tabularFigures,
    letterSpacing: -0.5,
    color: bodyLarge?.color,
  );

  TextStyle get numberCell => TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    fontFeatures: tabularFigures,
    color: bodyLarge?.color,
  );

  TextStyle get label => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: bodySmall?.color,
  );
}
