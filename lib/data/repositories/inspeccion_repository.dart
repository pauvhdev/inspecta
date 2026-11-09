import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../dominio/estados.dart';
import '../../dominio/fgas.dart';
import '../../dominio/normativa.dart'
    show DiaCalendario, OrigenGas, enHoraLocal;
import '../../informe/datos_informe.dart';
import '../../dominio/plantillas.dart' show TipoIntervencion;
import '../../dominio/rite.dart';
import '../../dominio/tipos.dart';
import '../local/app_database.dart';
import '../sync/mapper.dart';
import '../sync/outbox.dart';
import 'modelos_checklist.dart';

export 'modelos_checklist.dart';

// Repositorio de la visita (DISEÑO.md §8.2, «Contrato»; patrón de
// `session_repository.dart` de Forja).
//
// Toda escritura va a Drift y se encola en la misma transacción: ninguna
// pantalla espera a la red. El estado de la orden y `estado_equipo` no se
// escriben nunca desde aquí hacia el servidor (los derivan triggers, §7.5 y
// §7.2): se calculan en local para enseñarlos (`dominio/estados.dart`).
//
// Orden de la cola (§8.2): una fila encolada solo apunta a filas que nacen
// antes que ella. La inspección se encola antes que sus `inspeccion_equipos`,
// y un equipo dado de alta en campo antes que su `inspeccion_equipos`.

/// Quién está usando la app: su empresa y su fila de `miembros`.
class Sesion {
  const Sesion({required this.empresaId, required this.miembroId});
  final String empresaId;
  final String miembroId;
}

/// Se intentó escribir en una inspección firmada o descartada (§7.10.1: el
/// repositorio rechaza y la interfaz es de solo lectura, doble barrera).
class InspeccionCerrada implements Exception {
  const InspeccionCerrada(this.mensaje);
  final String mensaje;
  @override
  String toString() => 'InspeccionCerrada: $mensaje';
}

/// Una tarjeta de T1 Hoy.
class TarjetaOrden {
  const TarjetaOrden({
    required this.orden,
    required this.cliente,
    required this.instalacion,
    required this.nEquipos,
    required this.estado,
    required this.inspeccion,
    required this.sinSubir,
    required this.esDeHoy,
  });

  final OrdenTrabajo orden;
  final Cliente? cliente;
  final Instalacion? instalacion;
  final int nEquipos;

  /// Derivado en local ([estadoOrdenLocal]).
  final EstadoOrden estado;

  /// La inspección activa o firmada de la orden, si la hay.
  final Inspeccion? inspeccion;

  /// La inspección firmada todavía tiene cambios en la cola (T1: «Lo firmado
  /// pendiente de subir, en *pending*»).
  final bool sinSubir;

  /// Prevista para hoy (las demás son de días anteriores sin terminar).
  final bool esDeHoy;

  TipoIntervencion get tipo => TipoIntervencion.desde(orden.tipoIntervencion);
}

/// Un equipo dentro de T2 Visita.
class EquipoEnVisita {
  const EquipoEnVisita({
    required this.equipo,
    required this.plantilla,
    required this.inspeccionEquipoId,
    required this.respondidas,
    required this.totalItems,
    required this.obligatoriosPendientes,
    required this.hechos,
    required this.anadidoEnCampo,
  });

  final Equipo equipo;
  final Plantilla? plantilla;

  /// Null mientras no ha empezado la visita.
  final String? inspeccionEquipoId;
  final int respondidas;
  final int totalItems;
  final int obligatoriosPendientes;

  /// `estado_equipo` del equipo, o null si nunca tuvo una visita firmada.
  final HechosEquipo? hechos;

  /// Dado de alta en esta visita (no viene de `orden_equipos`).
  final bool anadidoEnCampo;
}

/// Una incidencia abierta de visitas anteriores, en T2.
class IncidenciaEnVisita {
  const IncidenciaEnVisita({
    required this.equipo,
    required this.incidencia,
    required this.resolucionId,
  });
  final Equipo equipo;
  final IncidenciaAbierta incidencia;

  /// La fila de `resoluciones_incidencia` de **esta** visita, si ya se marcó
  /// «Resuelta en esta visita».
  final String? resolucionId;
}

/// Todo lo que enseña T2 Visita.
class VistaVisita {
  const VistaVisita({
    required this.orden,
    required this.estado,
    required this.cliente,
    required this.instalacion,
    required this.inspeccion,
    required this.equipos,
    required this.equiposInstalacion,
    required this.incidencias,
  });

  final OrdenTrabajo orden;
  final EstadoOrden estado;
  final Cliente? cliente;
  final Instalacion instalacion;
  final Inspeccion? inspeccion;
  final List<EquipoEnVisita> equipos;

  /// Todos los equipos de la instalación (no solo los de la orden): con ellos
  /// se calcula su potencia (§7.2).
  final List<Equipo> equiposInstalacion;
  final List<IncidenciaEnVisita> incidencias;

  TipoIntervencion get tipo => TipoIntervencion.desde(orden.tipoIntervencion);

  bool get empezada => inspeccion != null;

  /// Se puede escribir en la visita (empezada y ni firmada ni descartada).
  bool get editable =>
      inspeccion != null &&
      inspeccion!.firmadaAt == null &&
      (inspeccion!.estado == EstadoInspeccion.enCurso.wire ||
          inspeccion!.estado == EstadoInspeccion.lista.wire);

  int get obligatoriosPendientes =>
      equipos.fold(0, (s, e) => s + e.obligatoriosPendientes);

  /// Potencia de la instalación (§7.2) con sus equipos actuales.
  PotenciaInstalacion get potencia =>
      potenciaDe(instalacion, equiposInstalacion);
}

/// Lo que enseña T3 Ficha del equipo.
class FichaEquipo {
  const FichaEquipo({
    required this.equipo,
    required this.instalacion,
    required this.equiposInstalacion,
    required this.hechos,
    required this.textosItem,
  });

  final Equipo equipo;
  final Instalacion instalacion;
  final List<Equipo> equiposInstalacion;
  final HechosEquipo? hechos;

  /// Texto de un ítem por su `clave`, para rotular los últimos valores.
  final Map<String, String> textosItem;
}

/// Potencia de una instalación con sus equipos (`rite.dart`).
PotenciaInstalacion potenciaDe(Instalacion i, Iterable<Equipo> equipos) =>
    potenciaInstalacion(
      declaradaFrioKw: i.potenciaFrioKw,
      declaradaCalorKw: i.potenciaCalorKw,
      equipos: [
        for (final e in equipos)
          PotenciaEquipo(frioKw: e.potenciaFrioKw, calorKw: e.potenciaCalorKw),
      ],
    );

/// `estado_equipo` → [HechosEquipo].
HechosEquipo hechosDe(EstadoDeEquipo e) => HechosEquipo.desdeColumnas(
  ultimoPreventivoAt: e.ultimoPreventivoAt,
  ultimaInspeccionId: e.ultimaInspeccionId,
  ultimoControlFugasAt: e.ultimoControlFugasAt,
  ultimoResultadoFugas: e.ultimoResultadoFugas,
  ultimosValoresJson: e.ultimosValoresJson,
  incidenciasAbiertasJson: e.incidenciasAbiertasJson,
);

/// Todo lo que enseña T12 Revisar y firmar.
class RevisionVisita {
  const RevisionVisita({
    required this.visita,
    required this.checklists,
    required this.pendientes,
  });
  final VistaVisita visita;
  final List<ChecklistEquipo> checklists;
  final List<PendienteFirma> pendientes;
}

class InspeccionRepository {
  InspeccionRepository(
    this._db,
    this._outbox, {
    required this.sesion,
    DateTime Function()? ahora,
  }) : _ahora = ahora ?? DateTime.now;

  final AppDatabase _db;
  final Outbox _outbox;
  final Sesion sesion;
  final DateTime Function() _ahora;

  DateTime get _now => _ahora().toUtc();

  // -------------------------------------------------------------------------
  // Lectura
  // -------------------------------------------------------------------------

  /// T1 Hoy: las órdenes del técnico previstas para hoy, más las de días
  /// anteriores que siguen sin firmar (pendientes o en curso). Primero las en
  /// curso, luego las pendientes y al final las firmadas y canceladas.
  Stream<List<TarjetaOrden>> watchHoy() => _observar([
    _db.ordenesTrabajo,
    _db.ordenEquipos,
    _db.inspecciones,
    _db.clientes,
    _db.instalaciones,
    _db.outboxEntries,
  ], _cargarHoy);

  Future<List<TarjetaOrden>> _cargarHoy() async {
    final d = DiaCalendario.deInstante(_ahora());
    final hoy = DateTime.utc(d.anio, d.mes, d.dia);
    final ordenes =
        await (_db.select(_db.ordenesTrabajo)..where(
              (o) =>
                  o.tecnicoId.equals(sesion.miembroId) &
                  o.empresaId.equals(sesion.empresaId) &
                  o.deletedAt.isNull(),
            ))
            .get();
    if (ordenes.isEmpty) return const [];

    final ids = [for (final o in ordenes) o.id];
    final inspecciones = await (_db.select(
      _db.inspecciones,
    )..where((i) => i.ordenId.isIn(ids))).get();
    final porOrden = <String, List<Inspeccion>>{};
    for (final i in inspecciones) {
      (porOrden[i.ordenId] ??= []).add(i);
    }
    final equiposPorOrden = <String, int>{};
    for (final oe in await (_db.select(
      _db.ordenEquipos,
    )..where((x) => x.ordenId.isIn(ids) & x.deletedAt.isNull())).get()) {
      equiposPorOrden[oe.ordenId] = (equiposPorOrden[oe.ordenId] ?? 0) + 1;
    }
    final ieDeInspeccion = <String, int>{};
    if (inspecciones.isNotEmpty) {
      for (final ie
          in await (_db.select(_db.inspeccionEquipos)..where(
                (x) =>
                    x.inspeccionId.isIn([for (final i in inspecciones) i.id]),
              ))
              .get()) {
        ieDeInspeccion[ie.inspeccionId] =
            (ieDeInspeccion[ie.inspeccionId] ?? 0) + 1;
      }
    }
    final instalaciones = {
      for (final i
          in await (_db.select(_db.instalaciones)..where(
                (x) => x.id.isIn({for (final o in ordenes) o.instalacionId}),
              ))
              .get())
        i.id: i,
    };
    final clientes = {
      for (final c
          in await (_db.select(_db.clientes)..where(
                (x) => x.id.isIn({
                  for (final i in instalaciones.values) i.clienteId,
                }),
              ))
              .get())
        c.id: c,
    };
    final pendientes = await _outbox.pendingRowIds('inspecciones');

    final tarjetas = <TarjetaOrden>[];
    for (final o in ordenes) {
      final insp = porOrden[o.id] ?? const [];
      final estado = _estadoDe(o, insp);
      final fecha = o.fechaPrevista;
      final esDeHoy = fecha != null && fecha == hoy;
      final atrasada =
          fecha != null &&
          fecha.isBefore(hoy) &&
          (estado == EstadoOrden.pendiente || estado == EstadoOrden.enCurso);
      if (!esDeHoy && !atrasada && estado != EstadoOrden.enCurso) continue;
      final activa = _inspeccionVisible(insp);
      final instalacion = instalaciones[o.instalacionId];
      tarjetas.add(
        TarjetaOrden(
          orden: o,
          cliente: instalacion == null ? null : clientes[instalacion.clienteId],
          instalacion: instalacion,
          nEquipos: activa != null
              ? ieDeInspeccion[activa.id] ?? 0
              : equiposPorOrden[o.id] ?? 0,
          estado: estado,
          inspeccion: activa,
          sinSubir:
              activa != null &&
              activa.firmadaAt != null &&
              pendientes.contains(activa.id),
          esDeHoy: esDeHoy,
        ),
      );
    }
    int rango(EstadoOrden e) => switch (e) {
      EstadoOrden.enCurso => 0,
      EstadoOrden.pendiente => 1,
      EstadoOrden.firmada => 2,
      EstadoOrden.cancelada => 3,
    };
    tarjetas.sort((a, b) {
      final r = rango(a.estado).compareTo(rango(b.estado));
      if (r != 0) return r;
      final fa = a.orden.fechaPrevista, fb = b.orden.fechaPrevista;
      if (fa != null && fb != null && fa != fb) return fa.compareTo(fb);
      return (a.cliente?.razonSocial ?? '').compareTo(
        b.cliente?.razonSocial ?? '',
      );
    });
    return tarjetas;
  }

  /// T2 Visita de una orden; null si la orden no existe (o se borró).
  Stream<VistaVisita?> watchVisita(String ordenId) => _observar([
    _db.ordenesTrabajo,
    _db.ordenEquipos,
    _db.inspecciones,
    _db.inspeccionEquipos,
    _db.respuestas,
    _db.equipos,
    _db.estadoEquipo,
    _db.resolucionesIncidencia,
    _db.instalaciones,
    _db.clientes,
    _db.plantillas,
    _db.itemsPlantilla,
  ], () => cargarVisita(ordenId));

  Future<VistaVisita?> cargarVisita(String ordenId) async {
    final orden =
        await (_db.select(_db.ordenesTrabajo)
              ..where((o) => o.id.equals(ordenId) & o.deletedAt.isNull()))
            .getSingleOrNull();
    if (orden == null) return null;
    final instalacion = await (_db.select(
      _db.instalaciones,
    )..where((i) => i.id.equals(orden.instalacionId))).getSingleOrNull();
    if (instalacion == null) return null;
    final cliente = await (_db.select(
      _db.clientes,
    )..where((c) => c.id.equals(instalacion.clienteId))).getSingleOrNull();
    final inspecciones = await (_db.select(
      _db.inspecciones,
    )..where((i) => i.ordenId.equals(ordenId))).get();
    final inspeccion = _inspeccionVisible(inspecciones);

    final equiposInstalacion =
        await (_db.select(_db.equipos)
              ..where(
                (e) =>
                    e.instalacionId.equals(instalacion.id) &
                    e.deletedAt.isNull(),
              )
              ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]))
            .get();
    final porId = {for (final e in equiposInstalacion) e.id: e};

    final ordenEquipos = await (_db.select(
      _db.ordenEquipos,
    )..where((x) => x.ordenId.equals(ordenId) & x.deletedAt.isNull())).get();
    final deLaOrden = {for (final oe in ordenEquipos) oe.equipoId};

    // (equipo, plantilla, inspeccion_equipo) en el orden de la visita: con
    // visita empezada, sus `inspeccion_equipos`; sin ella, `orden_equipos`.
    final filas = <(String, String, String?)>[];
    if (inspeccion != null) {
      final ies =
          await (_db.select(_db.inspeccionEquipos)
                ..where((x) => x.inspeccionId.equals(inspeccion.id))
                ..orderBy([(x) => OrderingTerm.asc(x.createdAt)]))
              .get();
      for (final ie in ies) {
        filas.add((ie.equipoId, ie.plantillaId, ie.id));
      }
    } else {
      for (final oe in ordenEquipos) {
        filas.add((oe.equipoId, oe.plantillaId, null));
      }
    }

    final plantillaIds = {for (final f in filas) f.$2};
    final plantillas = {
      for (final p in await (_db.select(
        _db.plantillas,
      )..where((p) => p.id.isIn(plantillaIds))).get())
        p.id: p,
    };
    final items = await (_db.select(
      _db.itemsPlantilla,
    )..where((i) => i.plantillaId.isIn(plantillaIds))).get();
    final itemsPorPlantilla = <String, List<ItemPlantilla>>{};
    for (final i in items) {
      (itemsPorPlantilla[i.plantillaId] ??= []).add(i);
    }

    final ieIds = [for (final f in filas) ?f.$3];
    final respuestas = ieIds.isEmpty
        ? const <Respuesta>[]
        : await (_db.select(
            _db.respuestas,
          )..where((r) => r.inspeccionEquipoId.isIn(ieIds))).get();
    final respondidasPorIe = <String, Set<String>>{};
    for (final r in respuestas) {
      if (r.estado != null || r.valorNum != null) {
        (respondidasPorIe[r.inspeccionEquipoId] ??= {}).add(r.itemPlantillaId);
      }
    }

    final estados = {
      for (final e in await (_db.select(
        _db.estadoEquipo,
      )..where((e) => e.id.isIn(porId.keys))).get())
        e.id: hechosDe(e),
    };

    final equipos = <EquipoEnVisita>[];
    for (final (equipoId, plantillaId, ieId) in filas) {
      final equipo = porId[equipoId];
      if (equipo == null) continue;
      final its = itemsPorPlantilla[plantillaId] ?? const [];
      final hechas = ieId == null
          ? const <String>{}
          : respondidasPorIe[ieId] ?? {};
      equipos.add(
        EquipoEnVisita(
          equipo: equipo,
          plantilla: plantillas[plantillaId],
          inspeccionEquipoId: ieId,
          respondidas: its.where((i) => hechas.contains(i.id)).length,
          totalItems: its.length,
          obligatoriosPendientes: its
              .where((i) => i.obligatorio && !hechas.contains(i.id))
              .length,
          hechos: estados[equipoId],
          anadidoEnCampo: !deLaOrden.contains(equipoId),
        ),
      );
    }

    final resoluciones = inspeccion == null
        ? const <ResolucionIncidencia>[]
        : await (_db.select(
            _db.resolucionesIncidencia,
          )..where((r) => r.inspeccionId.equals(inspeccion.id))).get();
    final resueltaPor = {for (final r in resoluciones) r.incidenciaId: r.id};
    final incidencias = <IncidenciaEnVisita>[
      for (final e in equipos)
        for (final i
            in e.hechos?.incidenciasAbiertas ?? const <IncidenciaAbierta>[])
          IncidenciaEnVisita(
            equipo: e.equipo,
            incidencia: i,
            resolucionId: resueltaPor[i.id],
          ),
    ];

    return VistaVisita(
      orden: orden,
      estado: _estadoDe(orden, inspecciones),
      cliente: cliente,
      instalacion: instalacion,
      inspeccion: inspeccion,
      equipos: equipos,
      equiposInstalacion: equiposInstalacion,
      incidencias: incidencias,
    );
  }

  /// T3 Ficha de un equipo; null si no existe.
  Stream<FichaEquipo?> watchFicha(String equipoId) => _observar([
    _db.equipos,
    _db.estadoEquipo,
    _db.instalaciones,
    _db.itemsPlantilla,
  ], () => cargarFicha(equipoId));

  Future<FichaEquipo?> cargarFicha(String equipoId) async {
    final equipo = await (_db.select(
      _db.equipos,
    )..where((e) => e.id.equals(equipoId))).getSingleOrNull();
    if (equipo == null) return null;
    final instalacion = await (_db.select(
      _db.instalaciones,
    )..where((i) => i.id.equals(equipo.instalacionId))).getSingleOrNull();
    if (instalacion == null) return null;
    final otros =
        await (_db.select(_db.equipos)..where(
              (e) =>
                  e.instalacionId.equals(instalacion.id) & e.deletedAt.isNull(),
            ))
            .get();
    final estado = await (_db.select(
      _db.estadoEquipo,
    )..where((e) => e.id.equals(equipoId))).getSingleOrNull();
    final hechos = estado == null ? null : hechosDe(estado);
    final claves = hechos?.ultimosValores.keys.toSet() ?? const <String>{};
    final textos = <String, String>{};
    if (claves.isNotEmpty) {
      for (final i in await (_db.select(
        _db.itemsPlantilla,
      )..where((i) => i.clave.isIn(claves))).get()) {
        textos.putIfAbsent(i.clave, () => i.texto);
      }
    }
    return FichaEquipo(
      equipo: equipo,
      instalacion: instalacion,
      equiposInstalacion: otros,
      hechos: hechos,
      textosItem: textos,
    );
  }

  // -------------------------------------------------------------------------
  // Escritura
  // -------------------------------------------------------------------------

  /// **Empezar visita** (F2.1): crea la inspección con la hora sellada y un
  /// `inspeccion_equipos` por cada equipo de la orden, con la plantilla (y
  /// su versión) que fijó la oficina.
  ///
  /// Si la orden ya tiene una visita en curso o firmada, la devuelve sin
  /// crear otra (doble toque, o volver a T2). El GPS del inicio llega el
  /// día 5: hasta entonces `gps_inicio` queda null.
  Future<Inspeccion> empezarVisita(String ordenId) => _db.transaction(() async {
    final orden =
        await (_db.select(_db.ordenesTrabajo)
              ..where((o) => o.id.equals(ordenId) & o.deletedAt.isNull()))
            .getSingleOrNull();
    if (orden == null) throw StateError('La orden $ordenId no existe');
    if (orden.empresaId != sesion.empresaId) {
      throw StateError('La orden $ordenId es de otra empresa');
    }
    if (orden.estado == EstadoOrden.cancelada.wire) {
      throw const InspeccionCerrada('La orden está cancelada');
    }
    final previas = await (_db.select(
      _db.inspecciones,
    )..where((i) => i.ordenId.equals(ordenId))).get();
    final previa = _inspeccionVisible(previas);
    if (previa != null) return previa;

    final now = _now;
    final inspeccion = Inspeccion(
      id: newId(),
      empresaId: orden.empresaId,
      ordenId: orden.id,
      tecnicoId: sesion.miembroId,
      version: 1,
      iniciadaAt: now,
      estado: EstadoInspeccion.enCurso.wire,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.inspecciones).insert(inspeccion);
    await _encolar('inspecciones', inspeccion.id, inspeccion);

    final oes =
        await (_db.select(_db.ordenEquipos)
              ..where((x) => x.ordenId.equals(ordenId) & x.deletedAt.isNull())
              ..orderBy([(x) => OrderingTerm.asc(x.createdAt)]))
            .get();
    for (final oe in oes) {
      await _crearInspeccionEquipo(inspeccion, oe.equipoId, oe.plantillaId);
    }
    return inspeccion;
  });

  /// **Añadir equipo** en campo (F2.2): da de alta el equipo en la
  /// instalación y lo mete en la visita con la plantilla que el técnico
  /// confirmó entre las sugeridas. Solo toca `equipos` e
  /// `inspeccion_equipos`; `orden_equipos` es de la oficina. Devuelve el id
  /// del equipo nuevo.
  Future<String> anadirEquipo({
    required String inspeccionId,
    required TipoEquipo tipo,
    required String plantillaId,
    double? potenciaFrioKw,
    double? potenciaCalorKw,
  }) => _db.transaction(() async {
    final inspeccion = await _inspeccionEditable(inspeccionId);
    final orden = await (_db.select(
      _db.ordenesTrabajo,
    )..where((o) => o.id.equals(inspeccion.ordenId))).getSingle();
    final plantilla = await (_db.select(
      _db.plantillas,
    )..where((p) => p.id.equals(plantillaId))).getSingleOrNull();
    if (plantilla == null) {
      throw ArgumentError.value(plantillaId, 'plantillaId', 'No está en local');
    }
    for (final kw in [potenciaFrioKw, potenciaCalorKw]) {
      if (kw != null && (!kw.isFinite || kw < 0)) {
        throw ArgumentError.value(kw, 'potencia', 'Debe ser un número ≥ 0');
      }
    }
    final now = _now;
    final equipo = Equipo(
      id: newId(),
      empresaId: inspeccion.empresaId,
      instalacionId: orden.instalacionId,
      tipo: tipo,
      potenciaFrioKw: potenciaFrioKw,
      potenciaCalorKw: potenciaCalorKw,
      origenDatos: 'manual',
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.equipos).insert(equipo);
    await _encolar('equipos', equipo.id, equipo);
    await _crearInspeccionEquipo(inspeccion, equipo.id, plantillaId);
    return equipo.id;
  });

  /// Guarda la ficha del equipo (T3). Con [confirmar], deja constancia de
  /// quién confirmó los datos y cuándo (`datos_confirmados_por/at`).
  ///
  /// [equipo] trae los valores editados; la identidad (`id`, `empresa_id`,
  /// `instalacion_id`, `created_at`) se conserva de la fila guardada.
  Future<void> guardarEquipo(
    Equipo equipo, {
    bool confirmar = true,
  }) => _db.transaction(() async {
    final actual = await (_db.select(
      _db.equipos,
    )..where((e) => e.id.equals(equipo.id))).getSingleOrNull();
    if (actual == null) throw StateError('El equipo ${equipo.id} no existe');
    if (actual.empresaId != sesion.empresaId) {
      throw StateError('El equipo ${equipo.id} es de otra empresa');
    }
    for (final v in [
      equipo.potenciaFrioKw,
      equipo.potenciaCalorKw,
      equipo.cargaKg,
    ]) {
      if (v != null && (!v.isFinite || v < 0)) {
        throw ArgumentError.value(v, 'equipo', 'Valor negativo o no válido');
      }
    }
    final now = _now;
    final fila = equipo.copyWith(
      empresaId: actual.empresaId,
      instalacionId: actual.instalacionId,
      createdAt: actual.createdAt,
      updatedAt: now,
      datosConfirmadosPor: confirmar
          ? Value(sesion.miembroId)
          : Value(actual.datosConfirmadosPor),
      datosConfirmadosAt: confirmar
          ? Value(now)
          : Value(actual.datosConfirmadosAt),
    );
    await _db.update(_db.equipos).replace(fila);
    await _encolar('equipos', fila.id, fila);
  });

  /// **Resuelta en esta visita** (F2.6): crea la fila de
  /// `resoluciones_incidencia` de esta inspección. La incidencia original no
  /// se toca (§7.10, regla 7). Si ya estaba marcada en esta visita, devuelve
  /// la resolución que había.
  Future<String> resolverIncidencia({
    required String inspeccionId,
    required String equipoId,
    required String incidenciaId,
    String? nota,
  }) => _db.transaction(() async {
    final inspeccion = await _inspeccionEditable(inspeccionId);
    final ie =
        await (_db.select(_db.inspeccionEquipos)..where(
              (x) =>
                  x.inspeccionId.equals(inspeccion.id) &
                  x.equipoId.equals(equipoId),
            ))
            .getSingleOrNull();
    if (ie == null) {
      throw StateError('El equipo $equipoId no está en esta visita');
    }
    final ya =
        await (_db.select(_db.resolucionesIncidencia)..where(
              (r) =>
                  r.inspeccionId.equals(inspeccion.id) &
                  r.incidenciaId.equals(incidenciaId),
            ))
            .getSingleOrNull();
    if (ya != null) return ya.id;
    final now = _now;
    final r = ResolucionIncidencia(
      id: newId(),
      empresaId: inspeccion.empresaId,
      incidenciaId: incidenciaId,
      inspeccionId: inspeccion.id,
      inspeccionEquipoId: ie.id,
      nota: nota,
      resueltaAt: now,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.resolucionesIncidencia).insert(r);
    await _encolar('resoluciones_incidencia', r.id, r);
    return r.id;
  });

  /// «Deshacer» de «Resuelta en esta visita» (§6.0: deshacer 5 s en vez de
  /// diálogos). `resoluciones_incidencia` es de solo inserción en el
  /// servidor, así que solo se puede deshacer mientras no ha salido del
  /// aparato: se borra la fila y su entrada de la cola. Devuelve false si ya
  /// subió (o se está subiendo) y no se puede.
  ///
  /// [A VERIFICAR el día 10] Con el `SyncEngine`, una entrada que se está
  /// subiendo aún tiene 0 intentos: si se retira justo entonces, el servidor
  /// se queda la resolución y el pull la vuelve a bajar (gana el servidor).
  Future<bool> deshacerResolucion(String resolucionId) =>
      _db.transaction(() async {
        final r = await (_db.select(
          _db.resolucionesIncidencia,
        )..where((x) => x.id.equals(resolucionId))).getSingleOrNull();
        if (r == null) return false;
        await _inspeccionEditable(r.inspeccionId);
        if (!await _outbox.retirarSiNoHaSalido(
          'resoluciones_incidencia',
          resolucionId,
        )) {
          return false;
        }
        await (_db.delete(
          _db.resolucionesIncidencia,
        )..where((x) => x.id.equals(resolucionId))).go();
        return true;
      });

  /// Recalcula en local `estado_equipo` de cada equipo de una inspección
  /// **firmada** (§7.2: «al firmar, la app la recalcula con la misma lógica
  /// para no esperar al servidor»). No se encola nunca: la del servidor la
  /// escribe su trigger y llega por el pull.
  ///
  /// Hay que llamarla una vez por firma y en el orden de las firmas (la
  /// llamará la transacción de firma del día 6; hoy, la siembra de la demo).
  Future<void> recalcularEstadoEquipo(String inspeccionId) =>
      _db.transaction(() async {
        final insp = await (_db.select(
          _db.inspecciones,
        )..where((i) => i.id.equals(inspeccionId))).getSingle();
        final firmadaAt = insp.firmadaAt;
        if (firmadaAt == null) {
          throw StateError('La inspección $inspeccionId no está firmada');
        }
        final orden = await (_db.select(
          _db.ordenesTrabajo,
        )..where((o) => o.id.equals(insp.ordenId))).getSingleOrNull();
        final esPreventivo =
            orden?.tipoIntervencion == TipoIntervencion.preventivo.wire;
        final ies = await (_db.select(
          _db.inspeccionEquipos,
        )..where((x) => x.inspeccionId.equals(inspeccionId))).get();
        final resueltasPorIe = <String, Set<String>>{};
        for (final r in await (_db.select(
          _db.resolucionesIncidencia,
        )..where((x) => x.inspeccionId.equals(inspeccionId))).get()) {
          (resueltasPorIe[r.inspeccionEquipoId] ??= {}).add(r.incidenciaId);
        }
        for (final ie in ies) {
          final respuestas = await (_db.select(
            _db.respuestas,
          )..where((r) => r.inspeccionEquipoId.equals(ie.id))).get();
          final itemIds = {for (final r in respuestas) r.itemPlantillaId};
          final claves = {
            for (final i in await (_db.select(
              _db.itemsPlantilla,
            )..where((i) => i.id.isIn(itemIds))).get())
              i.id: i.clave,
          };
          final incidencias =
              await (_db.select(_db.incidencias)
                    ..where((x) => x.inspeccionEquipoId.equals(ie.id))
                    ..orderBy([(x) => OrderingTerm.asc(x.createdAt)]))
                  .get();
          final controles =
              await (_db.select(_db.controlesFugas)
                    ..where((x) => x.inspeccionEquipoId.equals(ie.id))
                    ..orderBy([(x) => OrderingTerm.asc(x.createdAt)]))
                  .get();
          final firma = FirmaDeEquipo(
            inspeccionId: inspeccionId,
            firmadaAt: firmadaAt,
            esPreventivo: esPreventivo,
            valores: [
              for (final r in respuestas)
                if (r.valorNum != null && claves[r.itemPlantillaId] != null)
                  ValorMedido(
                    clave: claves[r.itemPlantillaId]!,
                    valor: r.valorNum!,
                    unidad: r.unidad,
                  ),
            ],
            incidenciasNuevas: [
              for (final i in incidencias)
                IncidenciaNueva(
                  id: i.id,
                  descripcion: i.descripcion,
                  gravedad: i.gravedad,
                ),
            ],
            incidenciasResueltas: resueltasPorIe[ie.id] ?? const {},
            resultadoFugas: controles.isEmpty ? null : controles.last.resultado,
          );
          final fila = await (_db.select(
            _db.estadoEquipo,
          )..where((e) => e.id.equals(ie.equipoId))).getSingleOrNull();
          final nuevo = aplicarFirma(
            fila == null ? HechosEquipo.vacio : hechosDe(fila),
            firma,
          );
          final now = _now;
          await _db
              .into(_db.estadoEquipo)
              .insertOnConflictUpdate(
                EstadoDeEquipo(
                  id: ie.equipoId,
                  empresaId: ie.empresaId,
                  ultimoPreventivoAt: nuevo.ultimoPreventivoAt,
                  ultimaInspeccionId: nuevo.ultimaInspeccionId,
                  ultimoControlFugasAt: nuevo.ultimoControlFugasAt,
                  ultimoResultadoFugas: nuevo.ultimoResultadoFugas,
                  ultimosValoresJson: nuevo.ultimosValoresJson,
                  incidenciasAbiertasJson: nuevo.incidenciasAbiertasJson,
                  createdAt: fila?.createdAt ?? now,
                  updatedAt: now,
                ).toCompanion(false),
              );
        }
      });

  // -------------------------------------------------------------------------
  // Checklist, incidencias y gas (día 4)
  // -------------------------------------------------------------------------

  /// T5: el checklist de un `inspeccion_equipos`; null si no existe.
  Stream<ChecklistEquipo?> watchChecklist(String inspeccionEquipoId) =>
      _observar([
        _db.inspeccionEquipos,
        _db.inspecciones,
        _db.respuestas,
        _db.incidencias,
        _db.movimientosGas,
        _db.controlesFugas,
        _db.equipos,
        _db.estadoEquipo,
        _db.itemsPlantilla,
        _db.fotos,
      ], () => cargarChecklist(inspeccionEquipoId));

  Future<ChecklistEquipo?> cargarChecklist(String inspeccionEquipoId) async {
    final ie = await (_db.select(
      _db.inspeccionEquipos,
    )..where((x) => x.id.equals(inspeccionEquipoId))).getSingleOrNull();
    if (ie == null) return null;
    final insp = await (_db.select(
      _db.inspecciones,
    )..where((x) => x.id.equals(ie.inspeccionId))).getSingle();
    final equipo = await (_db.select(
      _db.equipos,
    )..where((x) => x.id.equals(ie.equipoId))).getSingle();
    final plantilla = await (_db.select(
      _db.plantillas,
    )..where((x) => x.id.equals(ie.plantillaId))).getSingleOrNull();
    final items =
        await (_db.select(_db.itemsPlantilla)
              ..where((x) => x.plantillaId.equals(ie.plantillaId))
              ..orderBy([(x) => OrderingTerm.asc(x.orden)]))
            .get();
    final respuestas = {
      for (final r in await (_db.select(
        _db.respuestas,
      )..where((x) => x.inspeccionEquipoId.equals(ie.id))).get())
        r.itemPlantillaId: r,
    };
    final estado = await (_db.select(
      _db.estadoEquipo,
    )..where((x) => x.id.equals(ie.equipoId))).getSingleOrNull();
    return ChecklistEquipo(
      inspeccionEquipo: ie,
      inspeccion: insp,
      equipo: equipo,
      plantilla: plantilla,
      items: [
        for (final i in items)
          ItemConRespuesta(item: i, respuesta: respuestas[i.id]),
      ],
      hechos: estado == null ? null : hechosDe(estado),
      incidencias:
          await (_db.select(_db.incidencias)
                ..where((x) => x.inspeccionEquipoId.equals(ie.id))
                ..orderBy([(x) => OrderingTerm.asc(x.createdAt)]))
              .get(),
      movimientos:
          await (_db.select(_db.movimientosGas)
                ..where((x) => x.inspeccionEquipoId.equals(ie.id))
                ..orderBy([(x) => OrderingTerm.asc(x.createdAt)]))
              .get(),
      controles:
          await (_db.select(_db.controlesFugas)
                ..where((x) => x.inspeccionEquipoId.equals(ie.id))
                ..orderBy([(x) => OrderingTerm.asc(x.createdAt)]))
              .get(),
      fotos:
          await (_db.select(_db.fotos)
                ..where(
                  (x) =>
                      x.inspeccionEquipoId.equals(ie.id) & x.deletedAt.isNull(),
                )
                ..orderBy([(x) => OrderingTerm.asc(x.tomadaAt)]))
              .get(),
    );
  }

  /// Responde un ítem (T5/T6). Crea la respuesta la primera vez y la
  /// actualiza después; copia el texto y el código normativo del ítem
  /// (§7.4: el informe es autocontenido). Pasar null deja el campo vacío.
  /// Devuelve el estado anterior para «Deshacer».
  Future<RespuestaPrevia> responder({
    required String inspeccionEquipoId,
    required String itemId,
    required String? estado,
    required double? valor,
    required String? observacion,
  }) => _db.transaction(() async {
    const estados = {'ok', 'observacion', 'defecto', 'na'};
    if (estado != null && !estados.contains(estado)) {
      throw ArgumentError.value(estado, 'estado', 'Desconocido');
    }
    if (valor != null && !valor.isFinite) {
      throw ArgumentError.value(valor, 'valor', 'No es un número');
    }
    final ie = await (_db.select(
      _db.inspeccionEquipos,
    )..where((x) => x.id.equals(inspeccionEquipoId))).getSingle();
    final insp = await _inspeccionEditable(ie.inspeccionId);
    final item = await (_db.select(
      _db.itemsPlantilla,
    )..where((x) => x.id.equals(itemId))).getSingle();
    if (item.plantillaId != ie.plantillaId) {
      throw ArgumentError.value(itemId, 'itemId', 'No es de esta plantilla');
    }
    final previa =
        await (_db.select(_db.respuestas)..where(
              (x) =>
                  x.inspeccionEquipoId.equals(ie.id) &
                  x.itemPlantillaId.equals(itemId),
            ))
            .getSingleOrNull();
    final now = _now;
    final fila = Respuesta(
      id: previa?.id ?? newId(),
      empresaId: insp.empresaId,
      inspeccionEquipoId: ie.id,
      itemPlantillaId: item.id,
      textoItem: item.texto,
      codigoNormativo: item.codigoNormativo,
      estado: estado,
      valorNum: valor,
      unidad: valor == null ? null : item.unidad,
      observacion: observacion == null || observacion.trim().isEmpty
          ? null
          : observacion.trim(),
      origen: previa?.origen ?? 'manual',
      propuestaIaId: previa?.propuestaIaId,
      createdAt: previa?.createdAt ?? now,
      updatedAt: now,
    );
    // `toCompanion(false)`: un null tiene que vaciar la columna; con la fila
    // tal cual, Drift trata los null como «no tocar» y no se podría borrar.
    await _db
        .into(_db.respuestas)
        .insertOnConflictUpdate(fila.toCompanion(false));
    await _encolar('respuestas', fila.id, fila);
    return RespuestaPrevia(
      inspeccionEquipoId: ie.id,
      itemId: itemId,
      estado: previa?.estado,
      valor: previa?.valorNum,
      observacion: previa?.observacion,
    );
  });

  /// «Deshacer» de una respuesta: la deja como estaba (vacía si no existía).
  /// Es un UPDATE más, que el servidor admite antes de la firma.
  Future<void> deshacerRespuesta(RespuestaPrevia p) => responder(
    inspeccionEquipoId: p.inspeccionEquipoId,
    itemId: p.itemId,
    estado: p.estado,
    valor: p.valor,
    observacion: p.observacion,
  );

  /// T10: crea o edita una incidencia de esta visita. La gravedad la elige
  /// el técnico, sin valor por defecto (§9.1): sin ella no se guarda.
  /// `respuesta_id` solo se rellena al crearla (§8.2).
  Future<String> guardarIncidencia({
    String? id,
    required String inspeccionEquipoId,
    String? itemId,
    required String descripcion,
    required String gravedad,
    String? accionRecomendada,
    int? plazoDias,
    required bool paraEquipo,
  }) => _db.transaction(() async {
    if (descripcion.trim().isEmpty) {
      throw ArgumentError.value(descripcion, 'descripcion', 'Vacía');
    }
    if (!{'leve', 'grave', 'muy_grave'}.contains(gravedad)) {
      throw ArgumentError.value(gravedad, 'gravedad', 'Desconocida');
    }
    if (plazoDias != null && plazoDias <= 0) {
      throw ArgumentError.value(plazoDias, 'plazoDias', 'Debe ser > 0');
    }
    final ie = await (_db.select(
      _db.inspeccionEquipos,
    )..where((x) => x.id.equals(inspeccionEquipoId))).getSingle();
    final insp = await _inspeccionEditable(ie.inspeccionId);
    final previa = id == null
        ? null
        : await (_db.select(
            _db.incidencias,
          )..where((x) => x.id.equals(id))).getSingleOrNull();
    if (previa != null && previa.inspeccionEquipoId != ie.id) {
      throw StateError('La incidencia $id es de otro equipo');
    }
    var respuestaId = previa?.respuestaId;
    if (previa == null && itemId != null) {
      respuestaId =
          (await (_db.select(_db.respuestas)..where(
                    (x) =>
                        x.inspeccionEquipoId.equals(ie.id) &
                        x.itemPlantillaId.equals(itemId),
                  ))
                  .getSingleOrNull())
              ?.id;
    }
    final now = _now;
    final accion = accionRecomendada?.trim();
    final fila = Incidencia(
      id: previa?.id ?? id ?? newId(),
      empresaId: insp.empresaId,
      inspeccionEquipoId: ie.id,
      respuestaId: respuestaId,
      descripcion: descripcion.trim(),
      gravedad: gravedad,
      accionRecomendada: accion == null || accion.isEmpty ? null : accion,
      plazoDias: plazoDias,
      paraEquipo: paraEquipo,
      origen: previa?.origen ?? 'manual',
      propuestaIaId: previa?.propuestaIaId,
      decididaPor: sesion.miembroId,
      decididaAt: now,
      createdAt: previa?.createdAt ?? now,
      updatedAt: now,
    );
    // `toCompanion(false)`: un null tiene que vaciar la columna; con la fila
    // tal cual, Drift trata los null como «no tocar» y no se podría borrar.
    await _db
        .into(_db.incidencias)
        .insertOnConflictUpdate(fila.toCompanion(false));
    await _encolar('incidencias', fila.id, fila);
    return fila.id;
  });

  /// T11: guarda un movimiento de gas. [validacion] es la de
  /// `validarCargaGas` con estos mismos datos: si bloquea, no se guarda
  /// (doble barrera: la pantalla ya lo enseña a pantalla completa).
  Future<String> registrarMovimientoGas({
    required String inspeccionEquipoId,
    required MovimientoGasNuevo m,
    required ValidacionCarga validacion,
  }) => _db.transaction(() async {
    if (!m.kg.isFinite || m.kg <= 0) {
      throw ArgumentError.value(m.kg, 'kg', 'Debe ser > 0');
    }
    if (validacion is CargaBloqueada) throw CargaGasBloqueada(validacion);
    final ie = await (_db.select(
      _db.inspeccionEquipos,
    )..where((x) => x.id.equals(inspeccionEquipoId))).getSingle();
    final insp = await _inspeccionEditable(ie.inspeccionId);
    final now = _now;
    final esCarga = m.tipo == TipoMovimientoGas.carga;
    final fila = MovimientoGas(
      id: newId(),
      empresaId: insp.empresaId,
      inspeccionEquipoId: ie.id,
      tipo: m.tipo.wire,
      refrigerante: m.refrigerante,
      kg: m.kg,
      origenGas: esCarga ? m.origen?.wire : null,
      regeneradoLote: esCarga && m.origen == OrigenGas.regenerado
          ? m.datos.regeneradoLote
          : null,
      regeneradoEtiquetaFotoId: esCarga && m.origen == OrigenGas.regenerado
          ? m.datos.regeneradoEtiquetaFotoId
          : null,
      recicladoRecuperadoPor: esCarga && m.origen == OrigenGas.reciclado
          ? m.datos.recicladoRecuperadoPor?.wire
          : null,
      recicladoDeclaracion: esCarga && m.origen == OrigenGas.reciclado
          ? m.datos.recicladoDeclaracion
          : null,
      gestorNombre: m.gestorNombre,
      gestorDocumento: m.gestorDocumento,
      motivo: m.motivo,
      avisoPcg: validacion is CargaConAviso,
      reglaAplicada: validacion.regla.wire,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.movimientosGas).insert(fila);
    await _encolar('movimientos_gas', fila.id, fila);
    return fila.id;
  });

  /// T11: control de fugas. Si se reparó, guarda la ventana del nuevo
  /// control (art. 4.5) que calcula `fgas.dart` y llega ya hecha.
  Future<String> registrarControlFugas({
    required String inspeccionEquipoId,
    String? metodo,
    String? detectorModelo,
    required String resultado,
    String? localizacion,
    bool? reparada,
    VentanaNuevoControl? ventana,
  }) => _db.transaction(() async {
    if (resultado != 'sin_fuga' && resultado != 'fuga') {
      throw ArgumentError.value(resultado, 'resultado', 'Desconocido');
    }
    final ie = await (_db.select(
      _db.inspeccionEquipos,
    )..where((x) => x.id.equals(inspeccionEquipoId))).getSingle();
    final insp = await _inspeccionEditable(ie.inspeccionId);
    final now = _now;
    final reparadaAhora = resultado == 'fuga' && reparada == true;
    final fila = ControlFugas(
      id: newId(),
      empresaId: insp.empresaId,
      inspeccionEquipoId: ie.id,
      metodo: metodo,
      detectorModelo: detectorModelo,
      resultado: resultado,
      localizacion: resultado == 'fuga' ? localizacion : null,
      reparada: resultado == 'fuga' ? reparada : null,
      fechaReparacion: reparadaAhora ? now : null,
      recontrolDesde: reparadaAhora ? ventana?.desde.toUtc() : null,
      recontrolHasta: reparadaAhora ? ventana?.hasta.toUtc() : null,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.controlesFugas).insert(fila);
    await _encolar('controles_fugas', fila.id, fila);
    return fila.id;
  });

  // -------------------------------------------------------------------------
  // Fotos, firma y cierre (días 5-7)
  // -------------------------------------------------------------------------

  /// Bucket privado de Storage (§8.3).
  static const bucket = 'inspecta';

  String _rutaInspeccion(Inspeccion i) =>
      'empresas/${i.empresaId}/inspecciones/${i.id}';

  /// Guarda los bytes en `blobs` y encola su subida. La entrada de fichero va
  /// **antes** que la fila que la anuncia (§8.2): `entity` = `storage`,
  /// `rowId` = id del blob y el payload lleva `{bucket, ruta, blob_id,
  /// tabla, fila, mime}`, nunca los bytes.
  Future<String> _guardarBlob({
    required String origenId,
    required String tabla,
    required Uint8List bytes,
    required String mime,
    required String ruta,
    String variante = 'original',
  }) async {
    final id = newId();
    final sha = sha256De(bytes);
    await _db
        .into(_db.blobs)
        .insert(
          BlobLocal(
            id: id,
            origenId: origenId,
            variante: variante,
            bytes: bytes,
            mime: mime,
            sha256: sha,
            bucket: bucket,
            ruta: ruta,
          ),
        );
    await _outbox.enqueueUpsert(
      entity: 'storage',
      rowId: id,
      payload: {
        'bucket': bucket,
        'ruta': ruta,
        'blob_id': id,
        'tabla': tabla,
        'fila': origenId,
        'mime': mime,
      },
    );
    return sha;
  }

  /// T7 (versión mínima del día 5): guarda una foto ligada a un ítem por
  /// (`inspeccion_equipo_id`, `item_plantilla_id`), sin apuntar a la
  /// respuesta (§8.2). Pendiente del día 5 completo: miniatura, variante de
  /// 1.000 px, nitidez y brillo, y GPS.
  Future<String> guardarFoto({
    required String inspeccionEquipoId,
    String? itemId,
    String proposito = 'item',
    required Uint8List bytes,
    required String mime,
    int? ancho,
    int? alto,
  }) => _db.transaction(() async {
    final ie = await (_db.select(
      _db.inspeccionEquipos,
    )..where((x) => x.id.equals(inspeccionEquipoId))).getSingle();
    final insp = await _inspeccionEditable(ie.inspeccionId);
    final id = newId();
    final ext = mime == 'image/png' ? 'png' : 'jpg';
    final ruta = '${_rutaInspeccion(insp)}/fotos/$id.$ext';
    final sha = await _guardarBlob(
      origenId: id,
      tabla: 'fotos',
      bytes: bytes,
      mime: mime,
      ruta: ruta,
    );
    final now = _now;
    final f = Foto(
      id: id,
      empresaId: insp.empresaId,
      inspeccionId: insp.id,
      inspeccionEquipoId: ie.id,
      itemPlantillaId: itemId,
      proposito: proposito,
      ruta: ruta,
      sha256: sha,
      ancho: ancho,
      alto: alto,
      tomadaAt: now,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.fotos).insert(f);
    await _encolar('fotos', f.id, f);
    return id;
  });

  /// Borrar una foto antes de firmar: borrado lógico (`deleted_at`), que es
  /// un UPDATE que el servidor admite hasta la firma (§7.5).
  Future<void> borrarFoto(String fotoId) => _db.transaction(() async {
    final f = await (_db.select(
      _db.fotos,
    )..where((x) => x.id.equals(fotoId))).getSingle();
    await _inspeccionEditable(f.inspeccionId);
    final fila = f.copyWith(deletedAt: Value(_now), updatedAt: _now);
    await _db.update(_db.fotos).replace(fila);
    await _encolar('fotos', fila.id, fila);
  });

  /// Bytes originales de una foto, firma o informe; null si no están en el
  /// aparato (en la nube se pedirían con URL firmada, §8.2).
  Future<Uint8List?> bytesDe(String origenId) async =>
      (await (_db.select(_db.blobs)
                ..where(
                  (b) =>
                      b.origenId.equals(origenId) &
                      b.variante.equals('original'),
                )
                ..limit(1))
              .getSingleOrNull())
          ?.bytes;

  /// Lo que falta para poder firmar (F4.1): obligatorios sin responder,
  /// mediciones obligatorias sin valor y fotos obligatorias sin foto (salvo
  /// N.A.). Vacía = se puede firmar. Las propuestas de la IA sin decidir solo
  /// avisan y llegarán con la IA.
  Future<List<PendienteFirma>> pendientesDeFirma(String inspeccionId) async {
    final ies =
        await (_db.select(_db.inspeccionEquipos)
              ..where((x) => x.inspeccionId.equals(inspeccionId))
              ..orderBy([(x) => OrderingTerm.asc(x.createdAt)]))
            .get();
    final pendientes = <PendienteFirma>[];
    if (ies.isEmpty) {
      pendientes.add(
        const PendienteFirma(
          inspeccionEquipoId: null,
          equipo: '',
          indiceItem: null,
          texto: 'La visita no tiene ningún equipo.',
        ),
      );
    }
    for (final ie in ies) {
      final ch = (await cargarChecklist(ie.id))!;
      final nombre = [
        ch.equipo.tipo.texto,
        if (ch.equipo.ubicacion != null) ch.equipo.ubicacion!,
      ].join(' · ');
      for (final (i, ic) in ch.items.indexed) {
        final it = ic.item;
        final r = ic.respuesta;
        final na = r?.estado == 'na';
        String? falta;
        if (it.obligatorio && !ic.respondido) {
          falta = 'Sin responder';
        } else if (it.obligatorio &&
            it.tipoRespuesta == 'estado_valor' &&
            !na &&
            r?.valorNum == null) {
          falta = 'Falta el valor medido';
        } else if (it.obligatorio &&
            it.tipoRespuesta == 'estado_valor' &&
            r?.estado == null) {
          falta = 'Falta el estado';
        } else if (it.fotoObligatoria && !na && ch.fotosDe(it.id).isEmpty) {
          falta = 'Falta la foto';
        }
        if (falta != null) {
          pendientes.add(
            PendienteFirma(
              inspeccionEquipoId: ie.id,
              equipo: nombre,
              indiceItem: i,
              texto: '$falta: ${it.texto}',
            ),
          );
        }
      }
    }
    return pendientes;
  }

  /// **Firma** (F4.3), primera mitad, en una sola transacción: número
  /// correlativo de la serie del aparato (§7.9), copia congelada de la
  /// cabecera y de cada equipo con su cálculo F-gas, firmas del cliente y del
  /// técnico (solo PNG, §10), recuentos del cierre (§7.10.3) y `firmada_at`.
  /// Desde aquí el informe es de solo lectura. La segunda mitad
  /// ([completarCierre]) genera el PDF y encola el cierre al final.
  ///
  /// [datosEquipo] devuelve la copia de un equipo con su cálculo (la hace
  /// la capa que tiene la normativa). [serie] y [letra] son las del aparato:
  /// en la demo, `DEMO` y `A`.
  Future<Inspeccion> firmar({
    required String inspeccionId,
    required String resumen,
    required FirmaCapturada cliente,
    required FirmaCapturada tecnico,
    required Map<String, Object?> Function(Equipo equipo, HechosEquipo? hechos)
    datosEquipo,
    required String normativaVersion,
    required String serie,
    required String letra,
    String appVersion = '1.0.0',
  }) => _db.transaction(() async {
    final insp = await _inspeccionEditable(inspeccionId);
    final pendientes = await pendientesDeFirma(inspeccionId);
    if (pendientes.isNotEmpty) throw FirmaIncompleta(pendientes);
    if (cliente.nombre.trim().isEmpty ||
        cliente.png.isEmpty ||
        tecnico.png.isEmpty) {
      throw ArgumentError('Faltan el nombre o una de las firmas');
    }
    final now = _now;

    // Número: AAAA-SERIE-LETRA-NNNN, con el año local de la firma.
    final claveSerie = '${enHoraLocal(now).year}-$serie-$letra';
    final contador = await (_db.select(
      _db.contadoresInforme,
    )..where((c) => c.serie.equals(claveSerie))).getSingleOrNull();
    final n = (contador?.ultimo ?? 0) + 1;
    await _db
        .into(_db.contadoresInforme)
        .insertOnConflictUpdate(
          ContadoresInformeCompanion.insert(
            serie: claveSerie,
            ultimo: Value(n),
          ),
        );
    final numero = '$claveSerie-${n.toString().padLeft(4, '0')}';

    // Cabecera congelada.
    final orden = await (_db.select(
      _db.ordenesTrabajo,
    )..where((o) => o.id.equals(insp.ordenId))).getSingle();
    final inst = await (_db.select(
      _db.instalaciones,
    )..where((i) => i.id.equals(orden.instalacionId))).getSingle();
    final cli = await (_db.select(
      _db.clientes,
    )..where((c) => c.id.equals(inst.clienteId))).getSingleOrNull();
    final emp = await (_db.select(
      _db.empresas,
    )..where((e) => e.id.equals(insp.empresaId))).getSingleOrNull();
    final tec = await (_db.select(
      _db.miembros,
    )..where((m) => m.id.equals(insp.tecnicoId))).getSingleOrNull();
    Map<String, Object?>? sinSync(String t, DataClass? f) => f == null
        ? null
        : (aJsonPostgrest(t, f)..removeWhere(
            (k, _) =>
                k == 'created_at' || k == 'updated_at' || k == 'deleted_at',
          ));
    final cabecera = {
      'empresa': sinSync('empresas', emp),
      'tecnico': sinSync('miembros', tec),
      'cliente': sinSync('clientes', cli),
      'instalacion': sinSync('instalaciones', inst),
      'tipo_intervencion': orden.tipoIntervencion,
    };

    // Equipos: copia y cálculo al firmar.
    final ies = await (_db.select(
      _db.inspeccionEquipos,
    )..where((x) => x.inspeccionId.equals(inspeccionId))).get();
    for (final ie in ies) {
      final e = await (_db.select(
        _db.equipos,
      )..where((x) => x.id.equals(ie.equipoId))).getSingle();
      final est = await (_db.select(
        _db.estadoEquipo,
      )..where((x) => x.id.equals(ie.equipoId))).getSingleOrNull();
      final fila = ie.copyWith(
        datosEquipoJson: Value(
          jsonEncode(datosEquipo(e, est == null ? null : hechosDe(est))),
        ),
        updatedAt: now,
      );
      await _db.update(_db.inspeccionEquipos).replace(fila);
      await _encolar('inspeccion_equipos', fila.id, fila);
    }

    // Firmas: el PNG primero, la fila después.
    for (final (rol, f) in [('cliente', cliente), ('tecnico', tecnico)]) {
      final id = newId();
      final ruta = '${_rutaInspeccion(insp)}/firmas/$id.png';
      final sha = await _guardarBlob(
        origenId: id,
        tabla: 'firmas',
        bytes: f.png,
        mime: 'image/png',
        ruta: ruta,
      );
      final fila = Firma(
        id: id,
        empresaId: insp.empresaId,
        inspeccionId: insp.id,
        rol: rol,
        nombre: f.nombre.trim(),
        cargo: f.cargo?.trim().isEmpty ?? true ? null : f.cargo!.trim(),
        rutaPng: ruta,
        sha256: sha,
        firmadaAt: now,
        createdAt: now,
        updatedAt: now,
      );
      await _db.into(_db.firmas).insert(fila);
      await _encolar('firmas', fila.id, fila);
    }

    // Recuentos del cierre (§7.10.3): lo no borrado.
    final ieIds = [for (final ie in ies) ie.id];
    Future<int> contar<T extends Table, R>(
      TableInfo<T, R> t,
      Expression<bool> Function(T) filtro,
    ) async => (await (_db.select(t)..where(filtro)).get()).length;
    final fila = insp.copyWith(
      numero: Value(numero),
      version: 1,
      finalizadaAt: Value(now),
      firmadaAt: Value(now),
      estado: EstadoInspeccion.firmada.wire,
      resumenTexto: Value(resumen.trim()),
      resumenOrigen: const Value('determinista'),
      nEquipos: Value(ies.length),
      nRespuestas: Value(
        await contar(_db.respuestas, (r) => r.inspeccionEquipoId.isIn(ieIds)),
      ),
      nIncidencias: Value(
        await contar(_db.incidencias, (r) => r.inspeccionEquipoId.isIn(ieIds)),
      ),
      nFotos: Value(
        await contar(
          _db.fotos,
          (f) => f.inspeccionId.equals(insp.id) & f.deletedAt.isNull(),
        ),
      ),
      nEnlacesFotos: Value(
        await contar(
          _db.incidenciaFotos,
          (f) => f.inspeccionId.equals(insp.id),
        ),
      ),
      nNotas: Value(
        await contar(
          _db.notasVoz,
          (f) => f.inspeccionId.equals(insp.id) & f.deletedAt.isNull(),
        ),
      ),
      nControles: Value(
        await contar(
          _db.controlesFugas,
          (r) => r.inspeccionEquipoId.isIn(ieIds),
        ),
      ),
      nMovimientosGas: Value(
        await contar(
          _db.movimientosGas,
          (r) => r.inspeccionEquipoId.isIn(ieIds),
        ),
      ),
      nResoluciones: Value(
        await contar(
          _db.resolucionesIncidencia,
          (r) => r.inspeccionId.equals(insp.id),
        ),
      ),
      normativaVersion: Value(normativaVersion),
      appVersion: Value(appVersion),
      datosCabeceraJson: Value(jsonEncode(cabecera)),
      updatedAt: now,
    );
    // Sin encolar todavía: el cierre sube el último, con el PDF (§8.2).
    await _db.update(_db.inspecciones).replace(fila);
    return fila;
  });

  /// La fila de `miembros` de quien usa la app (para «Firmo como…»).
  Future<Miembro?> miembroActual() => (_db.select(
    _db.miembros,
  )..where((m) => m.id.equals(sesion.miembroId))).getSingleOrNull();

  /// T12: la visita, el checklist de cada equipo y lo que falta.
  Stream<RevisionVisita?> watchRevision(String ordenId) => _observar(
    [
      _db.inspecciones,
      _db.inspeccionEquipos,
      _db.respuestas,
      _db.incidencias,
      _db.movimientosGas,
      _db.controlesFugas,
      _db.fotos,
      _db.resolucionesIncidencia,
      _db.equipos,
    ],
    () async {
      final v = await cargarVisita(ordenId);
      final insp = v?.inspeccion;
      if (v == null || insp == null) return null;
      return RevisionVisita(
        visita: v,
        checklists: [
          for (final e in v.equipos)
            if (e.inspeccionEquipoId != null)
              (await cargarChecklist(e.inspeccionEquipoId!))!,
        ],
        pendientes: await pendientesDeFirma(insp.id),
      );
    },
  );

  /// Todo lo que sale en el PDF de una inspección.
  Future<DatosInforme> cargarDatosInforme(
    String inspeccionId, {
    required bool esDemo,
  }) async {
    final insp = await (_db.select(
      _db.inspecciones,
    )..where((i) => i.id.equals(inspeccionId))).getSingle();
    final orden = await (_db.select(
      _db.ordenesTrabajo,
    )..where((o) => o.id.equals(insp.ordenId))).getSingle();
    final ies =
        await (_db.select(_db.inspeccionEquipos)
              ..where((x) => x.inspeccionId.equals(inspeccionId))
              ..orderBy([(x) => OrderingTerm.asc(x.createdAt)]))
            .get();
    final bytes = <String, Uint8List>{};
    final equipos = <EquipoInforme>[];
    for (final ie in ies) {
      final ch = (await cargarChecklist(ie.id))!;
      for (final f in ch.fotos) {
        final b = await bytesDe(f.id);
        if (b != null) bytes[f.id] = b;
      }
      equipos.add(
        EquipoInforme(
          inspeccionEquipo: ie,
          equipo: ch.equipo,
          respuestas: [for (final i in ch.items) ?i.respuesta],
          incidencias: ch.incidencias,
          controles: ch.controles,
          movimientos: ch.movimientos,
          fotos: ch.fotos,
          resoluciones: await (_db.select(
            _db.resolucionesIncidencia,
          )..where((r) => r.inspeccionEquipoId.equals(ie.id))).get(),
        ),
      );
    }
    final firmas = await (_db.select(
      _db.firmas,
    )..where((f) => f.inspeccionId.equals(inspeccionId))).get();
    for (final f in firmas) {
      final b = await bytesDe(f.id);
      if (b != null) bytes[f.id] = b;
    }
    return DatosInforme(
      inspeccion: insp,
      tipoIntervencion: orden.tipoIntervencion,
      equipos: equipos,
      firmas: firmas,
      bytes: bytes,
      esDemo: esDemo,
    );
  }

  /// **Cierre**, segunda mitad: `contenido_sha256`, PDF (lo genera
  /// [generarPdf], en un isolate en el móvil), `pdf_sha256`, subida del PDF
  /// y, **al final de la cola**, la fila de cierre (`fusionarSoloCon`, §8.2).
  /// Después recalcula `estado_equipo` en local.
  ///
  /// Idempotente: si la app se cerró entre la firma y el PDF, T14 la vuelve
  /// a llamar; si el PDF ya existe, no hace nada. El PDF canónico es el
  /// primero que se generó (§7.10.6).
  Future<Inspeccion> completarCierre(
    String inspeccionId, {
    required bool esDemo,
    required Future<Uint8List> Function(DatosInforme datos, String contenidoSha)
    generarPdf,
  }) async {
    final insp = await (_db.select(
      _db.inspecciones,
    )..where((i) => i.id.equals(inspeccionId))).getSingle();
    if (insp.firmadaAt == null) {
      throw StateError('La inspección $inspeccionId no está firmada');
    }
    if (insp.pdfSha256 != null) return insp;
    final datos = await cargarDatosInforme(inspeccionId, esDemo: esDemo);
    final contenido = contenidoSha256(datos);
    final pdf = await generarPdf(datos, contenido);
    final cerrada = await _db.transaction(() async {
      final ruta = '${_rutaInspeccion(insp)}/pdf/informe_v${insp.version}.pdf';
      final sha = await _guardarBlob(
        origenId: insp.id,
        tabla: 'inspecciones',
        bytes: pdf,
        mime: 'application/pdf',
        ruta: ruta,
      );
      final fila = insp.copyWith(
        pdfRuta: Value(ruta),
        pdfSha256: Value(sha),
        contenidoSha256: Value(contenido),
        updatedAt: _now,
      );
      await _db.update(_db.inspecciones).replace(fila);
      await _outbox.enqueueUpsert(
        entity: 'inspecciones',
        rowId: fila.id,
        payload: aJsonPostgrest('inspecciones', fila),
        fusionarSoloCon: '"estado":"firmada"',
      );
      return fila;
    });
    await recalcularEstadoEquipo(inspeccionId);
    return cerrada;
  }

  /// T14: la inspección, si su cierre aún tiene cambios sin subir.
  Stream<(Inspeccion, bool sinSubir)?> watchInforme(String inspeccionId) =>
      _observar([_db.inspecciones, _db.outboxEntries], () async {
        final i = await (_db.select(
          _db.inspecciones,
        )..where((x) => x.id.equals(inspeccionId))).getSingleOrNull();
        if (i == null) return null;
        final pendientes = await _outbox.pendingRowIds('inspecciones');
        return (i, pendientes.contains(i.id));
      });

  /// Anota que se compartió el informe (`comparticiones`, fuera del
  /// contenido firmado: puede crecer después de la firma, §7.10.5).
  Future<void> anotarComparticion(String inspeccionId, String canal) async {
    final insp = await (_db.select(
      _db.inspecciones,
    )..where((i) => i.id.equals(inspeccionId))).getSingle();
    final now = _now;
    final c = Comparticion(
      id: newId(),
      empresaId: insp.empresaId,
      inspeccionId: insp.id,
      canal: canal,
      at: now,
      por: sesion.miembroId,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.comparticiones).insert(c);
    await _encolar('comparticiones', c.id, c);
  }

  // -------------------------------------------------------------------------
  // Internos
  // -------------------------------------------------------------------------

  Future<void> _crearInspeccionEquipo(
    Inspeccion inspeccion,
    String equipoId,
    String plantillaId,
  ) async {
    final now = _now;
    final ie = InspeccionEquipo(
      id: newId(),
      empresaId: inspeccion.empresaId,
      inspeccionId: inspeccion.id,
      equipoId: equipoId,
      plantillaId: plantillaId,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.inspeccionEquipos).insert(ie);
    await _encolar('inspeccion_equipos', ie.id, ie);
  }

  Future<Inspeccion> _inspeccionEditable(String id) async {
    final i = await (_db.select(
      _db.inspecciones,
    )..where((x) => x.id.equals(id))).getSingleOrNull();
    if (i == null) throw StateError('La inspección $id no existe');
    if (i.empresaId != sesion.empresaId) {
      throw StateError('La inspección $id es de otra empresa');
    }
    if (i.firmadaAt != null || i.estado == EstadoInspeccion.firmada.wire) {
      throw const InspeccionCerrada('El informe ya está firmado');
    }
    if (i.estado == EstadoInspeccion.descartada.wire) {
      throw const InspeccionCerrada('La visita se descartó');
    }
    return i;
  }

  Future<void> _encolar(String tabla, String id, DataClass fila) =>
      _outbox.enqueueUpsert(
        entity: tabla,
        rowId: id,
        payload: aJsonPostgrest(tabla, fila),
      );

  static EstadoOrden _estadoDe(OrdenTrabajo o, List<Inspeccion> insp) =>
      estadoOrdenLocal(
        estadoServidor: EstadoOrden.desde(o.estado),
        inspecciones: [for (final i in insp) EstadoInspeccion.desde(i.estado)],
      );

  /// La inspección que cuenta para la orden: la firmada o, si no, la activa
  /// más reciente. Las descartadas no cuentan.
  static Inspeccion? _inspeccionVisible(List<Inspeccion> insp) {
    Inspeccion? mejor;
    for (final i in insp) {
      if (i.estado == EstadoInspeccion.descartada.wire) continue;
      if (i.estado == EstadoInspeccion.firmada.wire) return i;
      if (mejor == null || i.iniciadaAt.isAfter(mejor.iniciadaAt)) mejor = i;
    }
    return mejor;
  }

  /// Emite [cargar] al escuchar y cada vez que cambia alguna de [tablas]. Si
  /// llegan cambios mientras carga, vuelve a cargar una sola vez al acabar.
  Stream<T> _observar<T>(
    List<ResultSetImplementation<dynamic, dynamic>> tablas,
    Future<T> Function() cargar,
  ) {
    late final StreamController<T> c;
    StreamSubscription<void>? sub;
    var cargando = false;
    var otraVez = false;
    Future<void> recargar() async {
      if (cargando) {
        otraVez = true;
        return;
      }
      cargando = true;
      do {
        otraVez = false;
        try {
          final v = await cargar();
          if (!c.isClosed) c.add(v);
        } on Object catch (e, s) {
          if (!c.isClosed) c.addError(e, s);
        }
      } while (otraVez && !c.isClosed);
      cargando = false;
    }

    c = StreamController<T>(
      onListen: () {
        sub = _db
            .tableUpdates(TableUpdateQuery.onAllTables(tablas))
            .listen((_) => recargar());
        recargar();
      },
      onCancel: () async {
        await sub?.cancel();
        await c.close();
      },
    );
    return c.stream;
  }
}
