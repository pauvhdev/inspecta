import 'package:drift/drift.dart';

import '../conversores.dart';
import 'comunes.dart';

// DISEÑO.md §7.6 IA. `ai_usage`, `ia_cupos` y `ai_usage_reservas` son
// [servidor]: no tienen espejo local.

/// La escribe la Edge Function con `service_role`; el móvil solo la baja.
@DataClassName('PropuestaIa')
@TableIndex(name: 'propuestas_ia_objetivo', columns: {#objetivoId})
class PropuestasIa extends Table with FilaSincronizada {
  TextColumn get empresaId => text()();

  /// `foto|placa|voz|resumen`.
  TextColumn get tipo => text()();

  /// Siempre la foto o la nota (en el resumen, la inspección), nunca el equipo.
  TextColumn get objetivoId => text()();
  TextColumn get entradaSha256 => text()();

  /// El modelo que respondió de verdad (principal o reserva, §9.2).
  TextColumn get modelo => text()();
  TextColumn get versionPrompt => text()();

  /// jsonb validado en el servidor.
  TextColumn get resultadoJson => text().map(const Jsonb())();
  IntColumn get tokensEntrada => integer().nullable()();
  IntColumn get tokensSalida => integer().nullable()();
  TextColumn get reservaId => text().nullable()();
}

/// Solo inserción (§7.6). La `tardia` lleva id determinista (UUID v5 de
/// `propuesta_id` + `indice`).
@DataClassName('DecisionIa')
@TableIndex(name: 'decisiones_ia_propuesta', columns: {#propuestaId})
@TableIndex(name: 'decisiones_ia_inspeccion', columns: {#inspeccionId})
class DecisionesIa extends Table with FilaSincronizada {
  TextColumn get empresaId => text()();
  TextColumn get inspeccionId => text()();
  TextColumn get propuestaId => text()();
  IntColumn get indice => integer()();

  /// `aceptada|editada|descartada|tardia`.
  TextColumn get decision => text()();

  /// jsonb: lo que el técnico dejó (nulo si descartó).
  TextColumn get valorFinalJson => text().map(const Jsonb()).nullable()();
  TextColumn get decididaPor => text()();
  DateTimeColumn get decididaAt => dateTime()();
}
