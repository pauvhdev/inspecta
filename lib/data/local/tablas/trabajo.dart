import 'package:drift/drift.dart';

import '../conversores.dart';
import 'comunes.dart';

// DISEÑO.md §7.5 Trabajo.
//
// Borrados. Las órdenes y sus equipos llevan `deleted_at` (las borra la
// oficina). De la inspección y sus hijos, solo `fotos` y `notas_voz`: §6.0
// («Errores») pide «confirmación explícita solo para firmar, descartar una
// visita o borrar una foto», y T7/F2.4 ofrecen «¿Repetir la foto?». Una foto
// ya subida no se puede borrar de verdad: no hay política DELETE en tablas de
// informe (§7.10.2). Si se borrara solo en local, al firmar `n_fotos` contaría
// N-1, el servidor tendría N, el trigger de cierre (§7.10.3, «exactamente»)
// devolvería `IC001` sin hijos en la cola y el informe firmado quedaría
// bloqueado para siempre (§8.2). Con `deleted_at` el borrado es un UPDATE,
// que la política de hijos ya concede al técnico asignado mientras la
// inspección no esté firmada (§8.5), y baja a la oficina por el pull
// incremental. Después de la firma el candado lo impide como cualquier otro
// UPDATE. Las notas de voz siguen la misma regla (`n_notas`).
//
// [A VERIFICAR] Esto obliga a `schema.sql` y al resto de la app (día 9 y
// siguientes): el trigger de cierre cuenta solo `fotos`/`notas_voz` con
// `deleted_at is null` y solo los `incidencia_fotos` cuya foto no está
// borrada (la tabla puente sigue siendo de solo inserción); `n_fotos` y
// `n_notas` cuentan igual en la app; el PDF, `contenido_sha256` (§7.10.6) y la
// cola de IA ignoran lo borrado; borrar una foto de placa vacía
// `equipos.placa_foto_id`. **Descartar una visita** usa `inspecciones.estado
// = 'descartada'` (ver abajo). Quitar un equipo de una visita sin firmar no
// lo pide §6.0 y no se cubre: hoy solo se puede antes de subirlo.
//
// `ordenes_sugeridas` no lleva `deleted_at`: se «descarta» con su `estado`.

@DataClassName('OrdenTrabajo')
@TableIndex(name: 'ordenes_trabajo_instalacion', columns: {#instalacionId})
@TableIndex(
  name: 'ordenes_trabajo_tecnico_fecha',
  columns: {#tecnicoId, #fechaPrevista},
)
class OrdenesTrabajo extends Table with FilaSincronizada, BorradoLogico {
  TextColumn get empresaId => text()();
  TextColumn get instalacionId => text()();

  /// `miembros.id`. Nulo mientras la oficina no la asigna.
  TextColumn get tecnicoId => text().nullable()();
  DateTimeColumn get fechaPrevista =>
      dateTime().map(const SoloFecha()).nullable()();

  /// `preventivo|correctivo|control_fugas|recontrol_fugas|puesta_marcha`.
  TextColumn get tipoIntervencion => text()();

  /// `pendiente|en_curso|firmada|cancelada`. No lo escribe el técnico: lo
  /// derivan triggers y lo protege `orden_estado_protegido` (§7.5).
  TextColumn get estado => text().withDefault(const Constant('pendiente'))();

  /// P. ej. el control de fugas que la generó.
  TextColumn get origenId => text().nullable()();
  TextColumn get notasOficina => text().nullable()();
}

@DataClassName('OrdenEquipo')
@TableIndex(name: 'orden_equipos_orden', columns: {#ordenId})
@TableIndex(name: 'orden_equipos_equipo', columns: {#equipoId})
class OrdenEquipos extends Table with FilaSincronizada, BorradoLogico {
  TextColumn get empresaId => text()();
  TextColumn get ordenId => text()();
  TextColumn get equipoId => text()();
  TextColumn get plantillaId => text()();
}

/// Vacía en el MVP (el trigger que la llena es §4.2 A) y sin escritura para
/// `authenticated` (§7.5, §8.5): el móvil solo la baja (`tablasSoloBajada`
/// en `mapper.dart`). Con §4.2 A, la oficina cambiará su `estado`.
@DataClassName('OrdenSugerida')
@TableIndex(name: 'ordenes_sugeridas_equipo', columns: {#equipoId})
class OrdenesSugeridas extends Table with FilaSincronizada {
  TextColumn get empresaId => text()();
  TextColumn get equipoId => text()();
  TextColumn get controlOrigenId => text()();

  /// `recontrol_fugas`.
  TextColumn get tipo => text()();

  // Instantes, como `controles_fugas.recontrol_desde/hasta` de los que salen
  // (el nuevo control va a +24 h, no «al día siguiente»).
  DateTimeColumn get desde => dateTime()();
  DateTimeColumn get hasta => dateTime()();

  /// `pendiente|convertida|descartada`.
  TextColumn get estado => text().withDefault(const Constant('pendiente'))();
  TextColumn get ordenId => text().nullable()();
}

/// Una por visita: es el informe (§7.5).
@DataClassName('Inspeccion')
@TableIndex(name: 'inspecciones_orden', columns: {#ordenId})
class Inspecciones extends Table with FilaSincronizada {
  // Identidad.
  TextColumn get empresaId => text()();
  TextColumn get ordenId => text()();
  TextColumn get tecnicoId => text()();

  /// `AAAA-SERIE-LETRA-NNNN`. Nulo hasta la firma: se asigna en la misma
  /// transacción que la firma (§7.9) y después no cambia nunca.
  TextColumn get numero => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get rectificaA => text().nullable()();

  // Fechas.
  DateTimeColumn get iniciadaAt => dateTime()();
  DateTimeColumn get finalizadaAt => dateTime().nullable()();
  DateTimeColumn get firmadaAt => dateTime().nullable()();

  /// La pone el servidor; el mapper no la sube (ver `mapper.dart`).
  DateTimeColumn get sincronizadaAt => dateTime().nullable()();

  // GPS (jsonb): `{lat, lon, precision}` o `{motivo}` si no hubo señal.
  TextColumn get gpsInicio => text().map(const Jsonb()).nullable()();
  TextColumn get gpsFirma => text().map(const Jsonb()).nullable()();

  // Contenido.
  TextColumn get resumenTexto => text().nullable()();

  /// `determinista|ia_revisado`.
  TextColumn get resumenOrigen => text().nullable()();

  /// `en_curso|lista|firmada|descartada`.
  ///
  /// `descartada` es «descartar una visita» de §6.0: una visita ya subida no
  /// se puede borrar (sin política DELETE en tablas de informe, §7.10.2), así
  /// que se marca y deja de contar. [A VERIFICAR] §7.5 solo da
  /// `en_curso|lista|firmada`: `schema.sql` tiene que admitir `descartada`
  /// (solo desde `en_curso` o `lista`, nunca con `firmada_at`), y
  /// `orden_estado_desde_inspeccion` tiene que devolver la orden a
  /// `pendiente` cuando su inspección pasa a `descartada` (si no, sigue
  /// `en_curso` para siempre). Si `ordenes_trabajo 1─0..1 inspecciones`
  /// (§7.8) se impone con un `unique(orden_id)`, debe ser parcial
  /// (`where estado <> 'descartada'`) para poder empezar otra visita.
  TextColumn get estado => text().withDefault(const Constant('en_curso'))();

  // Comprobación del cierre (§7.10.3): nulos hasta que se cierra.
  IntColumn get nEquipos => integer().nullable()();
  IntColumn get nRespuestas => integer().nullable()();
  IntColumn get nIncidencias => integer().nullable()();
  IntColumn get nFotos => integer().nullable()();
  IntColumn get nEnlacesFotos => integer().nullable()();
  IntColumn get nNotas => integer().nullable()();
  IntColumn get nControles => integer().nullable()();
  IntColumn get nMovimientosGas => integer().nullable()();
  IntColumn get nResoluciones => integer().nullable()();

  // Evidencias.
  TextColumn get pdfRuta => text().nullable()();
  TextColumn get pdfSha256 => text().nullable()();
  TextColumn get contenidoSha256 => text().nullable()();
  TextColumn get normativaVersion => text().nullable()();
  TextColumn get appVersion => text().nullable()();

  /// jsonb: copia congelada de empresa, técnico, cliente e instalación.
  TextColumn get datosCabeceraJson => text().map(const Jsonb()).nullable()();
}

@DataClassName('InspeccionEquipo')
@TableIndex(name: 'inspeccion_equipos_inspeccion', columns: {#inspeccionId})
@TableIndex(name: 'inspeccion_equipos_equipo', columns: {#equipoId})
class InspeccionEquipos extends Table with FilaSincronizada {
  TextColumn get empresaId => text()();
  TextColumn get inspeccionId => text()();
  TextColumn get equipoId => text()();
  TextColumn get plantillaId => text()();

  /// jsonb: datos del equipo y cálculo F-gas en el momento de firmar.
  TextColumn get datosEquipoJson => text().map(const Jsonb()).nullable()();
}

@DataClassName('Respuesta')
@TableIndex(
  name: 'respuestas_inspeccion_equipo',
  columns: {#inspeccionEquipoId},
)
class Respuestas extends Table with FilaSincronizada {
  TextColumn get empresaId => text()();
  TextColumn get inspeccionEquipoId => text()();
  TextColumn get itemPlantillaId => text()();

  // Copias del ítem: el informe es autocontenido aunque la plantilla se
  // retire (§7.4).
  TextColumn get textoItem => text()();
  TextColumn get codigoNormativo => text().nullable()();

  /// `ok|observacion|defecto|na`. Nulo en los ítems `solo_valor`.
  TextColumn get estado => text().nullable()();
  RealColumn get valorNum => real().nullable()();
  TextColumn get unidad => text().nullable()();
  TextColumn get observacion => text().nullable()();

  /// `manual|ia`.
  TextColumn get origen => text().withDefault(const Constant('manual'))();
  TextColumn get propuestaIaId => text().nullable()();
}

@DataClassName('Incidencia')
@TableIndex(
  name: 'incidencias_inspeccion_equipo',
  columns: {#inspeccionEquipoId},
)
class Incidencias extends Table with FilaSincronizada {
  TextColumn get empresaId => text()();
  TextColumn get inspeccionEquipoId => text()();

  /// Solo al crearla, si la respuesta ya existe; nunca se actualiza (§8.2).
  TextColumn get respuestaId => text().nullable()();
  TextColumn get descripcion => text()();

  /// `leve|grave|muy_grave`. **Sin valor por defecto:** la elige una persona
  /// (principios de la IA, §9.1); nula mientras no la elige.
  TextColumn get gravedad => text().nullable()();
  TextColumn get accionRecomendada => text().nullable()();
  IntColumn get plazoDias => integer().nullable()();
  BoolColumn get paraEquipo => boolean().withDefault(const Constant(false))();

  /// `manual|ia`.
  TextColumn get origen => text().withDefault(const Constant('manual'))();
  TextColumn get propuestaIaId => text().nullable()();
  TextColumn get decididaPor => text().nullable()();
  DateTimeColumn get decididaAt => dateTime().nullable()();
}

/// Tabla puente, solo inserción: se encola cuando ya existen la foto y la
/// incidencia (§7.5).
@DataClassName('IncidenciaFoto')
@TableIndex(name: 'incidencia_fotos_inspeccion', columns: {#inspeccionId})
@TableIndex(name: 'incidencia_fotos_incidencia', columns: {#incidenciaId})
class IncidenciaFotos extends Table with FilaSincronizada {
  TextColumn get empresaId => text()();
  TextColumn get inspeccionId => text()();
  TextColumn get incidenciaId => text()();
  TextColumn get fotoId => text()();
}

/// Solo inserción; hija de la inspección **que resuelve** (§7.5).
@DataClassName('ResolucionIncidencia')
@TableIndex(
  name: 'resoluciones_incidencia_inspeccion',
  columns: {#inspeccionId},
)
@TableIndex(
  name: 'resoluciones_incidencia_incidencia',
  columns: {#incidenciaId},
)
class ResolucionesIncidencia extends Table with FilaSincronizada {
  TextColumn get empresaId => text()();

  /// Sin clave foránea en Drift a propósito (§7.5): la incidencia puede ser
  /// de una visita de hace más de 60 días que no está en local.
  TextColumn get incidenciaId => text()();
  TextColumn get inspeccionId => text()();
  TextColumn get inspeccionEquipoId => text()();
  TextColumn get nota => text().nullable()();
  DateTimeColumn get resueltaAt => dateTime()();
}

@DataClassName('ControlFugas')
@TableIndex(
  name: 'controles_fugas_inspeccion_equipo',
  columns: {#inspeccionEquipoId},
)
@TableIndex(name: 'controles_fugas_origen', columns: {#controlOrigenId})
class ControlesFugas extends Table with FilaSincronizada {
  TextColumn get empresaId => text()();
  TextColumn get inspeccionEquipoId => text()();
  TextColumn get metodo => text().nullable()();
  TextColumn get detectorModelo => text().nullable()();

  /// Fecha de la última calibración del detector. [A VERIFICAR] §7.5 no da
  /// el tipo; se toma como `date`.
  DateTimeColumn get detectorCalibracion =>
      dateTime().map(const SoloFecha()).nullable()();

  /// `sin_fuga|fuga`.
  TextColumn get resultado => text()();
  TextColumn get localizacion => text().nullable()();
  BoolColumn get reparada => boolean().nullable()();

  /// Instante, no `date`, pese al prefijo `fecha_`: de él sale
  /// `recontrol_desde` a +24 h (§12, día 2). [A VERIFICAR] el tipo en
  /// `schema.sql`.
  DateTimeColumn get fechaReparacion => dateTime().nullable()();
  DateTimeColumn get recontrolDesde => dateTime().nullable()();
  DateTimeColumn get recontrolHasta => dateTime().nullable()();
  TextColumn get controlOrigenId => text().nullable()();

  /// Solo en la fila del nuevo control (la que tiene `control_origen_id`).
  BoolColumn get eficaz => boolean().nullable()();
}

@DataClassName('MovimientoGas')
@TableIndex(
  name: 'movimientos_gas_inspeccion_equipo',
  columns: {#inspeccionEquipoId},
)
class MovimientosGas extends Table with FilaSincronizada {
  TextColumn get empresaId => text()();
  TextColumn get inspeccionEquipoId => text()();

  /// `carga|recuperacion|desmantelamiento`.
  TextColumn get tipo => text()();
  TextColumn get refrigerante => text()();
  RealColumn get kg => real()();

  /// `virgen|reciclado|regenerado`. Nulo en recuperación y desmantelamiento.
  TextColumn get origenGas => text().nullable()();

  // Regenerado (art. 12.7).
  TextColumn get regeneradoLote => text().nullable()();

  /// Referencia blanda a `fotos.id`, sin clave foránea (§8.2).
  TextColumn get regeneradoEtiquetaFotoId => text().nullable()();

  // Reciclado.
  /// `propia_empresa|para_esta_empresa`.
  TextColumn get recicladoRecuperadoPor => text().nullable()();
  BoolColumn get recicladoDeclaracion => boolean().nullable()();

  TextColumn get gestorNombre => text().nullable()();
  TextColumn get gestorDocumento => text().nullable()();

  /// `mantenimiento|fuga`.
  TextColumn get motivo => text().nullable()();

  /// [A VERIFICAR] §7.5 no da el tipo: se toma como bool («se avisó del PCG»).
  BoolColumn get avisoPcg => boolean().nullable()();

  /// `13.4|13.3_aviso|ninguna`: lo calcula `fgas.dart`, nunca la IA.
  TextColumn get reglaAplicada => text().nullable()();
}

@DataClassName('Foto')
@TableIndex(name: 'fotos_inspeccion', columns: {#inspeccionId})
@TableIndex(name: 'fotos_inspeccion_equipo', columns: {#inspeccionEquipoId})
class Fotos extends Table with FilaSincronizada, BorradoLogico {
  TextColumn get empresaId => text()();
  TextColumn get inspeccionId => text()();

  // (`inspeccion_equipo_id`, `item_plantilla_id`) identifican la respuesta
  // sin apuntar a ella, que nace después (§8.2).
  TextColumn get inspeccionEquipoId => text().nullable()();
  TextColumn get itemPlantillaId => text().nullable()();

  /// `item|placa|incidencia|general|etiqueta_gas`.
  TextColumn get proposito => text()();
  TextColumn get ruta => text()();
  TextColumn get rutaMiniatura => text().nullable()();
  TextColumn get sha256 => text()();
  IntColumn get ancho => integer().nullable()();
  IntColumn get alto => integer().nullable()();

  /// `ok|borrosa|oscura`.
  TextColumn get calidadLocal => text().nullable()();

  // Las «dos métricas» de `calidad_local` (§8.3): varianza del laplaciano y
  // brillo medio sobre la miniatura. [A VERIFICAR] §7.5 no las nombra; estos
  // nombres deben repetirse en `schema.sql`.
  RealColumn get calidadNitidez => real().nullable()();
  RealColumn get calidadBrillo => real().nullable()();

  DateTimeColumn get tomadaAt => dateTime()();

  /// jsonb: `{lat, lon, precision}` o `{motivo}`.
  TextColumn get gps => text().map(const Jsonb()).nullable()();
}

/// Sin `transcripcion` ni su estado: llegan después de firmar y la fila está
/// bajo el candado (regla 7); el texto se lee de `propuestas_ia`.
@DataClassName('NotaVoz')
@TableIndex(name: 'notas_voz_inspeccion', columns: {#inspeccionId})
class NotasVoz extends Table with FilaSincronizada, BorradoLogico {
  TextColumn get empresaId => text()();
  TextColumn get inspeccionId => text()();
  TextColumn get inspeccionEquipoId => text().nullable()();
  TextColumn get ruta => text()();

  /// `audio/mp4` en Android; `audio/webm` u `audio/wav` en web.
  TextColumn get mime => text()();
  TextColumn get sha256 => text()();
  RealColumn get duracionS => real().nullable()();
  DateTimeColumn get grabadaAt => dateTime()();
}

/// Sin `puntos_json`: no se guardan puntos, tiempos ni presión (§10).
@DataClassName('Firma')
@TableIndex(name: 'firmas_inspeccion', columns: {#inspeccionId})
class Firmas extends Table with FilaSincronizada {
  TextColumn get empresaId => text()();
  TextColumn get inspeccionId => text()();

  /// `cliente|tecnico`.
  TextColumn get rol => text()();
  TextColumn get nombre => text()();
  TextColumn get cargo => text().nullable()();
  TextColumn get rutaPng => text()();
  TextColumn get sha256 => text()();
  DateTimeColumn get firmadaAt => dateTime()();

  /// jsonb: `{lat, lon, precision}` o `{motivo}`.
  TextColumn get gps => text().map(const Jsonb()).nullable()();
}

/// Solo inserción, fuera del contenido firmado (§7.10.5).
@DataClassName('Comparticion')
@TableIndex(name: 'comparticiones_inspeccion', columns: {#inspeccionId})
class Comparticiones extends Table with FilaSincronizada {
  TextColumn get empresaId => text()();
  TextColumn get inspeccionId => text()();

  /// `whatsapp|correo|descarga`.
  TextColumn get canal => text()();
  DateTimeColumn get at => dateTime()();

  /// `miembros.id`.
  TextColumn get por => text()();
}
