import 'package:flutter/material.dart';

/// Paleta y escalas de Inspecta.
///
/// Diseñada para una azotea al sol y un sótano en penumbra, no para una
/// oficina (DISEÑO.md §6.0):
///
/// - **Sol** (tema por defecto): fondo blanco y texto casi negro, contraste AAA
///   en el texto principal. A pleno sol, un gris claro sobre blanco no se lee.
/// - **Sótano**: oscuro, para no deslumbrar en un cuarto de máquinas.
///
/// El estado de un ítem nunca va solo por color: siempre icono + texto + color
/// (✓ OK, ! Observación, ✕ Defecto, — N. A.), porque con reflejos o con
/// daltonismo el color solo no basta.
class InspectaColors {
  const InspectaColors._();

  // ── Sol (claro, por defecto) ───────────────────────────────────────────
  static const bgLight = Color(0xFFFFFFFF);
  static const surfaceLight = Color(0xFFF4F5F7);
  static const surfaceHighLight = Color(0xFFE8EAEE);
  static const borderLight = Color(0xFFC9CDD4);
  static const textLight = Color(0xFF0B0D12);
  static const textMutedLight = Color(0xFF454B57);

  // ── Sótano (oscuro) ─────────────────────────────────────────────────────
  static const bgDark = Color(0xFF0B0D12);
  static const surfaceDark = Color(0xFF151922);
  static const surfaceHighDark = Color(0xFF1F2430);
  static const borderDark = Color(0xFF343B4A);
  static const textDark = Color(0xFFF5F7FA);
  static const textMutedDark = Color(0xFFB4BBC8);

  // ── Acento: azul de servicio técnico ────────────────────────────────────
  /// Botones primarios. Con texto blanco encima supera el contraste AA de
  /// texto grande en los dos temas.
  static const accent = Color(0xFF0B5FD3);
  static const accentDim = Color(0xFF0A4CA8);
  static const accentOnDark = Color(0xFF5B9BFF);

  // ── Estado de un ítem del checklist ─────────────────────────────────────
  static const ok = Color(0xFF1B7F3B);
  static const okBg = Color(0xFFE3F4E8);
  static const observacion = Color(0xFF8A5A00);
  static const observacionBg = Color(0xFFFFF1D6);
  static const defecto = Color(0xFFB3261E);
  static const defectoBg = Color(0xFFFCE4E2);
  static const noAplica = Color(0xFF454B57);
  static const noAplicaBg = Color(0xFFE8EAEE);

  // ── Sincronización ───────────────────────────────────────────────────────
  /// Pendiente de subir o de procesar por la IA. No es un error: sin cobertura
  /// es lo normal, así que no se pinta en rojo.
  static const pending = Color(0xFF5B4BC4);
  static const pendingBg = Color(0xFFEDEAFB);

  /// Fallo real (bloqueado, archivo dañado). Lo único que va en rojo.
  static const danger = defecto;

  /// Dato propuesto por la IA y aún sin confirmar por el técnico.
  static const iaSinConfirmar = observacion;
}

/// Escala de espaciado. Múltiplos de 4: si un valor no está aquí, no se usa.
class Gap {
  const Gap._();
  static const xs = 4.0;
  static const sm = 8.0;

  /// Separación mínima entre objetivos táctiles en la app del técnico.
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class Radii {
  const Radii._();
  static const sm = Radius.circular(8);
  static const md = Radius.circular(12);
  static const lg = Radius.circular(18);

  static const brSm = BorderRadius.all(sm);
  static const brMd = BorderRadius.all(md);
  static const brLg = BorderRadius.all(lg);
}

/// Alturas mínimas de toque (DISEÑO.md §6.0).
///
/// Con guantes de trabajo, 44 dp se fallan. En la app del técnico ningún
/// objetivo baja de 56 dp; las acciones primarias van a 72 y la cámara y el
/// micrófono a 88. `test/tactil_56dp_test.dart` lo comprueba pantalla a
/// pantalla. El panel de oficina puede usar [Touch.oficina].
class Touch {
  const Touch._();

  /// Mínimo absoluto en la app del técnico.
  static const min = 56.0;

  /// Acciones primarias: Empezar visita, Compartir, Confirmar firma.
  static const primary = 72.0;

  /// Foto y voz: lo que más se pulsa con la otra mano ocupada.
  static const captura = 88.0;

  /// Panel de oficina en escritorio (ratón): estándar de accesibilidad.
  static const oficina = 44.0;
}

/// Tamaño base del texto en la app del técnico: 18 sp, legible a un brazo de
/// distancia y con el móvil en la mano.
const double textoBaseTecnico = 18;

/// Cifras de ancho fijo.
///
/// Sin esto, una columna de presiones o kilos "baila" horizontalmente al
/// cambiar de 9,8 a 10,2 porque el 1 es más estrecho que el 0.
const tabularFigures = <FontFeature>[FontFeature.tabularFigures()];
