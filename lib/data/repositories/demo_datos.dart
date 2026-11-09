import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../dominio/estados.dart';
import '../../dominio/normativa.dart';
import '../../dominio/plantillas.dart' as dom;
import '../../dominio/rite.dart';
import '../../dominio/tipos.dart';
import '../local/app_database.dart';
import '../local/siembra.dart';
import '../sync/outbox.dart';
import 'inspeccion_repository.dart';

// Datos de la demo pública (DISEÑO.md §11.1). Todo es inventado: la empresa,
// los clientes, las direcciones y las personas. Solo se siembra en modo local
// con `--dart-define=INSPECTA_DEMO=true` y nunca se encola: hace el papel de
// lo que en la nube ya estaría en el servidor.
//
// Potencias coherentes (§11.1): cada instalación declara una potencia igual
// o mayor que la suma de sus equipos, en frío y en calor, así ninguna da el
// aviso «régimen RITE a revisar». La comunidad y el hotel quedan en 70 kW o
// menos (preventivos con las plantillas 1 y 2); la oficina pasa de 70 kW por
// la enfriadora y solo tiene órdenes de control de fugas (plantilla 3).
// [A VERIFICAR con el técnico de la llamada: que carga y potencia de cada
// equipo sean verosímiles.]
//
// Fechas relativas a [DemoDatos.sembrar]`(ahora:)`: las órdenes son «de hoy»
// el día que se siembra. «Reiniciar demo» (día 13) vuelve a sembrar.

/// Namespace de los ids de la demo: `uuid v5(NAMESPACE_URL,
/// 'urn:inspecta:demo')`. Ids deterministas: sembrar dos veces da las mismas
/// filas.
final String namespaceDemo = const Uuid().v5(
  Namespace.url.value,
  'urn:inspecta:demo',
);

String _id(String nombre) => const Uuid().v5(namespaceDemo, nombre);

/// Un equipo de la demo.
class EquipoDemo {
  const EquipoDemo({
    required this.clave,
    required this.instalacion,
    required this.tipo,
    required this.marca,
    required this.modelo,
    required this.ubicacion,
    required this.frioKw,
    required this.calorKw,
    required this.refrigerante,
    required this.cargaKg,
    this.preventivoPrevio,
    this.controlFugasPrevio,
  });

  final String clave;
  final String instalacion;
  final TipoEquipo tipo;
  final String marca;
  final String modelo;
  final String ubicacion;
  final double frioKw;
  final double? calorKw;
  final String refrigerante;
  final double cargaKg;

  /// Días antes de la siembra del último preventivo anterior a Inspecta.
  final int? preventivoPrevio;
  final int? controlFugasPrevio;

  String get id => _id('equipo:$clave');
}

/// Una instalación de la demo, con su cliente.
class InstalacionDemo {
  const InstalacionDemo({
    required this.clave,
    required this.cliente,
    required this.cif,
    required this.contacto,
    required this.telefono,
    required this.nombre,
    required this.direccion,
    required this.frioKw,
    required this.calorKw,
  });

  final String clave;
  final String cliente;
  final String cif;
  final String contacto;
  final String telefono;
  final String nombre;
  final String direccion;
  final double frioKw;
  final double calorKw;

  String get id => _id('instalacion:$clave');
  String get clienteId => _id('cliente:$clave');
}

/// Una orden de la demo.
class OrdenDemo {
  const OrdenDemo({
    required this.clave,
    required this.instalacion,
    required this.tipo,
    required this.equipos,
    required this.diasAntes,
    this.tecnico = 'tecnico',
    this.notas,
  });

  final String clave;
  final String instalacion;
  final dom.TipoIntervencion tipo;
  final List<String> equipos;

  /// 0 = hoy. Las de días anteriores son las de los informes ya firmados.
  final int diasAntes;
  final String tecnico;
  final String? notas;

  String get id => _id('orden:$clave');
}

class DemoDatos {
  const DemoDatos._();

  static final empresaId = _id('empresa');
  static final tecnicoId = _id('miembro:tecnico');
  static final otroTecnicoId = _id('miembro:otro');

  /// La sesión de la demo: el técnico que ve «Hoy».
  static final sesion = Sesion(empresaId: empresaId, miembroId: tecnicoId);

  /// Serie de numeración de la demo (§7.9): `AAAA-DEMO-A-NNNN`.
  static const serie = 'DEMO';
  static const letra = 'A';

  static const instalaciones = <InstalacionDemo>[
    InstalacionDemo(
      clave: 'comunidad',
      cliente: 'Comunidad de Propietarios Calle del Olmo 14 (ficticia)',
      cif: 'H00000001',
      contacto: 'Marta Ruiz (administradora)',
      telefono: '600 000 001',
      nombre: 'Zonas comunes',
      direccion: 'Calle del Olmo 14, Valencia',
      // Suma de los equipos: 13,5 kW de frío y 15 kW de calor.
      frioKw: 14,
      calorKw: 15,
    ),
    InstalacionDemo(
      clave: 'hotel',
      cliente: 'Hotel Brisa del Puerto (ficticio)',
      cif: 'B00000002',
      contacto: 'Javier Soler (mantenimiento)',
      telefono: '600 000 002',
      nombre: 'Climatización del hotel',
      direccion: 'Avenida del Puerto 210, Valencia',
      // Suma: 60,6 kW de frío y 67,2 kW de calor. Queda en 70 kW o menos.
      frioKw: 62,
      calorKw: 68,
    ),
    InstalacionDemo(
      clave: 'oficina',
      cliente: 'Oficinas Ejemplo, S. L. (ficticia)',
      cif: 'B00000003',
      contacto: 'Elena Navarro (servicios generales)',
      telefono: '600 000 003',
      nombre: 'Edificio de oficinas',
      direccion: 'Calle de la Industria 5, Paterna',
      // Suma: 207 kW de frío y 29,5 kW de calor. Más de 70 kW: preventivo
      // RITE mensual, fuera del MVP.
      frioKw: 210,
      calorKw: 30,
    ),
  ];

  /// Los 8 equipos. Cifras F-gas con el PCG del AR4 (`fgas.dart`):
  /// split R-32 1,1 kg → 0,7425 t, no sujeto; conductos R-410A 3 kg →
  /// 6,26 t, 12 meses; VRF R-410A 12 kg → 25,05 t, 12 meses; rooftop
  /// R-407C 8 kg → 14,19 t, 12 meses; split R-410A 2,5 kg → 5,22 t,
  /// 12 meses; conductos R-32 7,5 kg → 5,0625 t, 12 meses; enfriadora
  /// R-134a 60 kg → 85,8 t, 6 meses. Ninguno llega a 500 t (3 meses): en una
  /// mantenedora de climatización no es verosímil.
  static const equipos = <EquipoDemo>[
    EquipoDemo(
      clave: 'comunidad_split',
      instalacion: 'comunidad',
      tipo: TipoEquipo.split,
      marca: 'Marca Ficticia',
      modelo: 'SPL-35',
      ubicacion: 'Portería',
      frioKw: 3.5,
      calorKw: 4,
      refrigerante: 'R-32',
      cargaKg: 1.1,
      preventivoPrevio: 600,
    ),
    EquipoDemo(
      clave: 'comunidad_conductos',
      instalacion: 'comunidad',
      tipo: TipoEquipo.conductos,
      marca: 'Marca Ficticia',
      modelo: 'CND-100',
      ubicacion: 'Local social, falso techo',
      frioKw: 10,
      calorKw: 11,
      refrigerante: 'R-410A',
      cargaKg: 3,
      preventivoPrevio: 600,
      controlFugasPrevio: 300,
    ),
    EquipoDemo(
      clave: 'hotel_vrf',
      instalacion: 'hotel',
      tipo: TipoEquipo.vrf,
      marca: 'Marca Ficticia',
      modelo: 'VRF-400',
      ubicacion: 'Cubierta, unidad exterior',
      frioKw: 40,
      calorKw: 45,
      refrigerante: 'R-410A',
      cargaKg: 12,
      controlFugasPrevio: 200,
    ),
    EquipoDemo(
      clave: 'hotel_rooftop',
      instalacion: 'hotel',
      tipo: TipoEquipo.rooftop,
      marca: 'Marca Ficticia',
      modelo: 'RT-180',
      ubicacion: 'Cubierta, sobre el comedor',
      frioKw: 18,
      calorKw: 19,
      refrigerante: 'R-407C',
      cargaKg: 8,
      controlFugasPrevio: 200,
    ),
    EquipoDemo(
      clave: 'hotel_split',
      instalacion: 'hotel',
      tipo: TipoEquipo.split,
      marca: 'Marca Ficticia',
      modelo: 'SPL-26',
      ubicacion: 'Recepción',
      frioKw: 2.6,
      calorKw: 3.2,
      refrigerante: 'R-32',
      cargaKg: 1.1,
    ),
    EquipoDemo(
      clave: 'oficina_enfriadora',
      instalacion: 'oficina',
      tipo: TipoEquipo.enfriadora,
      marca: 'Marca Ficticia',
      modelo: 'ENF-1800',
      ubicacion: 'Cubierta',
      frioKw: 180,
      calorKw: null,
      refrigerante: 'R-134a',
      cargaKg: 60,
    ),
    EquipoDemo(
      clave: 'oficina_split',
      instalacion: 'oficina',
      tipo: TipoEquipo.split,
      marca: 'Marca Ficticia',
      modelo: 'SPL-70',
      ubicacion: 'Sala de servidores',
      frioKw: 7,
      calorKw: 7.5,
      refrigerante: 'R-410A',
      cargaKg: 2.5,
    ),
    EquipoDemo(
      clave: 'oficina_conductos',
      instalacion: 'oficina',
      tipo: TipoEquipo.conductos,
      marca: 'Marca Ficticia',
      modelo: 'CND-200',
      ubicacion: 'Planta baja, recepción',
      frioKw: 20,
      calorKw: 22,
      refrigerante: 'R-32',
      cargaKg: 7.5,
    ),
  ];

  /// 5 órdenes de hoy (4 del técnico de la demo y 1 de otro técnico) y las 2
  /// de los informes ya firmados.
  static const ordenes = <OrdenDemo>[
    OrdenDemo(
      clave: 'hoy_comunidad',
      instalacion: 'comunidad',
      tipo: dom.TipoIntervencion.preventivo,
      equipos: ['comunidad_split', 'comunidad_conductos'],
      diasAntes: 0,
    ),
    OrdenDemo(
      clave: 'hoy_hotel',
      instalacion: 'hotel',
      tipo: dom.TipoIntervencion.preventivo,
      equipos: ['hotel_vrf', 'hotel_rooftop', 'hotel_split'],
      diasAntes: 0,
    ),
    OrdenDemo(
      clave: 'hoy_oficina',
      instalacion: 'oficina',
      tipo: dom.TipoIntervencion.controlFugas,
      equipos: ['oficina_enfriadora', 'oficina_split', 'oficina_conductos'],
      diasAntes: 0,
    ),
    OrdenDemo(
      clave: 'hoy_comunidad_aviso',
      instalacion: 'comunidad',
      tipo: dom.TipoIntervencion.correctivo,
      equipos: ['comunidad_split'],
      diasAntes: 0,
      notas: 'Aviso del cliente: el split de la portería gotea.',
    ),
    OrdenDemo(
      clave: 'hoy_hotel_otro',
      instalacion: 'hotel',
      tipo: dom.TipoIntervencion.controlFugas,
      equipos: ['hotel_vrf', 'hotel_rooftop'],
      diasAntes: 0,
      tecnico: 'otro',
    ),
    OrdenDemo(
      clave: 'firmada_hotel',
      instalacion: 'hotel',
      tipo: dom.TipoIntervencion.preventivo,
      equipos: ['hotel_vrf', 'hotel_rooftop', 'hotel_split'],
      diasAntes: 330,
    ),
    OrdenDemo(
      clave: 'firmada_oficina',
      instalacion: 'oficina',
      tipo: dom.TipoIntervencion.controlFugas,
      equipos: ['oficina_enfriadora', 'oficina_split', 'oficina_conductos'],
      diasAntes: 170,
    ),
  ];

  /// Valores medidos en el preventivo firmado del hotel, por equipo y clave.
  static const valoresHotel = <String, Map<String, double>>{
    'hotel_vrf': {
      'temp_retorno': 24.5,
      'temp_impulsion': 13.0,
      'salto_termico': 11.5,
      'temp_exterior': 31.0,
      'presion_alta': 26.4,
      'presion_baja': 8.1,
      'intensidad_absorbida': 21.3,
    },
    'hotel_rooftop': {
      'temp_retorno': 25.0,
      'temp_impulsion': 14.5,
      'salto_termico': 10.5,
      'temp_exterior': 31.0,
      'presion_alta': 22.8,
      'presion_baja': 5.2,
      'intensidad_absorbida': 14.8,
    },
    'hotel_split': {
      'temp_retorno': 23.0,
      'temp_impulsion': 12.0,
      'salto_termico': 11.0,
      'intensidad_absorbida': 4.1,
    },
  };

  /// Valores del control de fugas firmado de la oficina.
  static const valoresOficina = <String, Map<String, double>>{
    'oficina_enfriadora': {'presion_alta': 11.2, 'presion_baja': 3.4},
    'oficina_split': {'presion_alta': 25.1, 'presion_baja': 8.4},
    'oficina_conductos': {'presion_alta': 24.0, 'presion_baja': 9.0},
  };

  /// Incidencia que quedó abierta en el preventivo del hotel: T2 la enseña
  /// con «Resuelta en esta visita».
  static const incidenciaHotel = (
    equipo: 'hotel_rooftop',
    descripcion:
        'Aislamiento de la línea frigorífica deteriorado en la cubierta '
        '(unos 2 m expuestos al sol)',
    gravedad: 'leve',
    accion: 'Sustituir el aislamiento y protegerlo de la radiación UV',
    plazoDias: 60,
  );

  static InstalacionDemo instalacion(String clave) =>
      instalaciones.firstWhere((i) => i.clave == clave);
  static EquipoDemo equipo(String clave) =>
      equipos.firstWhere((e) => e.clave == clave);

  /// Siembra la demo si la base no la tiene ya. Devuelve true si sembró.
  static Future<bool> sembrarSiFalta(
    AppDatabase db, {
    required Normativa normativa,
    required List<dom.Plantilla> plantillas,
    required DateTime ahora,
  }) async {
    final ya = await (db.select(
      db.empresas,
    )..where((e) => e.id.equals(empresaId))).getSingleOrNull();
    if (ya != null) return false;
    await sembrar(
      db,
      normativa: normativa,
      plantillas: plantillas,
      ahora: ahora,
    );
    return true;
  }

  /// La plantilla que la oficina habría fijado para un equipo de una orden:
  /// la recomendada por la misma regla que O2 (`sugerirPlantillas`).
  static dom.Plantilla? plantillaPara(
    EquipoDemo e,
    dom.TipoIntervencion tipo, {
    required Normativa normativa,
    required List<dom.Plantilla> plantillas,
  }) {
    final inst = instalacion(e.instalacion);
    final pot = potenciaInstalacion(
      declaradaFrioKw: inst.frioKw,
      declaradaCalorKw: inst.calorKw,
      equipos: [
        for (final x in equipos)
          if (x.instalacion == e.instalacion)
            PotenciaEquipo(frioKw: x.frioKw, calorKw: x.calorKw),
      ],
    );
    return dom
        .sugerirPlantillas(
          umbralRegimenMensualKw: normativa.rite.umbralRegimenMensualKw,
          tipo: e.tipo,
          potenciaEquipoKw: math.max(e.frioKw, e.calorKw ?? 0),
          potenciaInstalacionKw: pot.kw,
          uso: UsoEdificio.otros,
          intervencion: tipo,
          plantillas: plantillas,
        )
        .recomendada;
  }

  /// Escribe toda la demo en [db] (sin encolar nada) y deriva
  /// `estado_equipo` de los dos informes firmados, en orden de firma, con la
  /// misma función que usará la firma del día 6.
  static Future<void> sembrar(
    AppDatabase db, {
    required Normativa normativa,
    required List<dom.Plantilla> plantillas,
    required DateTime ahora,
  }) async {
    await sembrarPlantillasBase(db, plantillas);
    final now = ahora.toUtc();
    final d = DiaCalendario.deInstante(ahora);
    DateTime dia(int antes) =>
        DateTime.utc(d.anio, d.mes, d.dia).subtract(Duration(days: antes));
    // Las 10:00 en UTC del día indicado (las 11 o las 12 en España).
    DateTime instante(int antes, {int hora = 9}) =>
        dia(antes).add(Duration(hours: hora));

    final plantillaPorId = {for (final p in plantillas) p.id: p};
    final inspeccionesFirmadas = <String>[];

    await db.transaction(() async {
      await db
          .into(db.empresas)
          .insertOnConflictUpdate(
            Empresa(
              id: empresaId,
              empresaId: empresaId,
              razonSocial: 'Climatización Ejemplo, S. L. (ficticia)',
              cif: 'B00000000',
              nHabilitacionRite: 'DEMO-RITE-0000',
              ccaa: 'Comunitat Valenciana',
              nCertificadoFgasEmpresa: 'DEMO-FGAS-0000',
              esDemo: true,
              createdAt: now,
              updatedAt: now,
            ),
          );
      for (final (clave, nombre, serieM) in [
        ('tecnico', 'Lucía Ferrer (técnica ficticia)', serie),
        ('otro', 'Andrés Gil (técnico ficticio)', 'DEMO2'),
      ]) {
        await db
            .into(db.miembros)
            .insertOnConflictUpdate(
              Miembro(
                id: _id('miembro:$clave'),
                empresaId: empresaId,
                rol: 'tecnico',
                nombre: nombre,
                carneRite: 'DEMO-${clave.toUpperCase()}',
                serieInformes: serieM,
                activo: true,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      for (final i in instalaciones) {
        await db
            .into(db.clientes)
            .insertOnConflictUpdate(
              Cliente(
                id: i.clienteId,
                empresaId: empresaId,
                razonSocial: i.cliente,
                cif: i.cif,
                contactoNombre: i.contacto,
                contactoTelefono: i.telefono,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.instalaciones)
            .insertOnConflictUpdate(
              Instalacion(
                id: i.id,
                empresaId: empresaId,
                clienteId: i.clienteId,
                nombre: i.nombre,
                direccion: i.direccion,
                // [A VERIFICAR] Las zonas comunes de una comunidad se toman
                // como «restantes usos», no como vivienda (Tabla 3.1).
                usoEdificio: UsoEdificio.otros,
                potenciaFrioKw: i.frioKw,
                potenciaCalorKw: i.calorKw,
                contratoMantenimiento: true,
                manualDisponible: i.clave != 'comunidad',
                supervisionRemota: false,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      for (final e in equipos) {
        await db
            .into(db.equipos)
            .insertOnConflictUpdate(
              Equipo(
                id: e.id,
                empresaId: empresaId,
                instalacionId: instalacion(e.instalacion).id,
                tipo: e.tipo,
                categoriaFgas: CategoriaFgas.aireAcondicionadoBombaCalor,
                marca: e.marca,
                modelo: e.modelo,
                nSerie: 'DEMO-${e.clave.toUpperCase()}',
                ubicacion: e.ubicacion,
                potenciaFrioKw: e.frioKw,
                potenciaCalorKw: e.calorKw,
                refrigerante: e.refrigerante,
                cargaKg: e.cargaKg,
                hermeticoEtiquetado: false,
                deteccionFugas: false,
                etiquetaOk: true,
                preventivoPrevioDeclarado: e.preventivoPrevio == null
                    ? null
                    : dia(e.preventivoPrevio!),
                controlFugasPrevioDeclarado: e.controlFugasPrevio == null
                    ? null
                    : dia(e.controlFugasPrevio!),
                origenDatos: 'manual',
                datosConfirmadosPor: tecnicoId,
                datosConfirmadosAt: now,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }

      final contadores = <String, int>{};
      for (final o in ordenes) {
        final firmada = o.diasAntes > 0;
        await db
            .into(db.ordenesTrabajo)
            .insertOnConflictUpdate(
              OrdenTrabajo(
                id: o.id,
                empresaId: empresaId,
                instalacionId: instalacion(o.instalacion).id,
                tecnicoId: _id('miembro:${o.tecnico}'),
                fechaPrevista: dia(o.diasAntes),
                tipoIntervencion: o.tipo.wire,
                estado: firmada
                    ? EstadoOrden.firmada.wire
                    : EstadoOrden.pendiente.wire,
                notasOficina: o.notas,
                createdAt: now,
                updatedAt: now,
              ),
            );
        final ies = <(EquipoDemo, String, dom.Plantilla)>[];
        for (final clave in o.equipos) {
          final e = equipo(clave);
          final p = plantillaPara(
            e,
            o.tipo,
            normativa: normativa,
            plantillas: plantillas,
          );
          if (p == null) {
            throw StateError('Sin plantilla para ${e.clave} en ${o.clave}');
          }
          await db
              .into(db.ordenEquipos)
              .insertOnConflictUpdate(
                OrdenEquipo(
                  id: _id('orden_equipo:${o.clave}:$clave'),
                  empresaId: empresaId,
                  ordenId: o.id,
                  equipoId: e.id,
                  plantillaId: p.id,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          ies.add((e, _id('inspeccion_equipo:${o.clave}:$clave'), p));
        }
        if (!firmada) continue;

        // Informe firmado de ejemplo. Sin PDF ni firmas hasta los días 6 y 7.
        final inspeccionId = _id('inspeccion:${o.clave}');
        final firmadaAt = instante(o.diasAntes, hora: 11);
        final anio = enHoraLocal(firmadaAt).year;
        final clave = '$anio-$serie-$letra';
        final n = (contadores[clave] ?? 0) + 1;
        contadores[clave] = n;
        final valores = o.clave == 'firmada_hotel'
            ? valoresHotel
            : valoresOficina;
        var nRespuestas = 0, nIncidencias = 0, nControles = 0;
        for (final (e, ieId, p) in ies) {
          await db
              .into(db.inspeccionEquipos)
              .insertOnConflictUpdate(
                InspeccionEquipo(
                  id: ieId,
                  empresaId: empresaId,
                  inspeccionId: inspeccionId,
                  equipoId: e.id,
                  plantillaId: p.id,
                  createdAt: firmadaAt,
                  updatedAt: firmadaAt,
                ),
              );
          final medidos = valores[e.clave] ?? const <String, double>{};
          for (final item in plantillaPorId[p.id]!.items) {
            final v = medidos[item.clave];
            if (item.tipoRespuesta.llevaValor &&
                v == null &&
                !item.obligatorio) {
              continue;
            }
            await db
                .into(db.respuestas)
                .insertOnConflictUpdate(
                  Respuesta(
                    id: _id('respuesta:$ieId:${item.clave}'),
                    empresaId: empresaId,
                    inspeccionEquipoId: ieId,
                    itemPlantillaId: item.id,
                    textoItem: item.texto,
                    codigoNormativo: item.codigoNormativo,
                    estado: item.tipoRespuesta == dom.TipoRespuesta.soloValor
                        ? null
                        : (e.clave == incidenciaHotel.equipo &&
                                  item.clave == 'aislamiento_tuberias' &&
                                  o.clave == 'firmada_hotel'
                              ? 'defecto'
                              : 'ok'),
                    valorNum: v,
                    unidad: v == null ? null : item.unidad,
                    origen: 'manual',
                    createdAt: firmadaAt,
                    updatedAt: firmadaAt,
                  ),
                );
            nRespuestas++;
          }
          if (o.clave == 'firmada_hotel' && e.clave == incidenciaHotel.equipo) {
            await db
                .into(db.incidencias)
                .insertOnConflictUpdate(
                  Incidencia(
                    id: _id('incidencia:${o.clave}:${e.clave}'),
                    empresaId: empresaId,
                    inspeccionEquipoId: ieId,
                    respuestaId: _id('respuesta:$ieId:aislamiento_tuberias'),
                    descripcion: incidenciaHotel.descripcion,
                    gravedad: incidenciaHotel.gravedad,
                    accionRecomendada: incidenciaHotel.accion,
                    plazoDias: incidenciaHotel.plazoDias,
                    paraEquipo: false,
                    origen: 'manual',
                    decididaPor: tecnicoId,
                    decididaAt: firmadaAt,
                    createdAt: firmadaAt,
                    updatedAt: firmadaAt,
                  ),
                );
            nIncidencias++;
          }
          if (o.tipo == dom.TipoIntervencion.controlFugas) {
            await db
                .into(db.controlesFugas)
                .insertOnConflictUpdate(
                  ControlFugas(
                    id: _id('control:${o.clave}:${e.clave}'),
                    empresaId: empresaId,
                    inspeccionEquipoId: ieId,
                    metodo: 'Detector electrónico (método indirecto)',
                    detectorModelo: 'Detector ficticio DF-1',
                    resultado: 'sin_fuga',
                    createdAt: firmadaAt,
                    updatedAt: firmadaAt,
                  ),
                );
            nControles++;
          }
        }
        await db
            .into(db.inspecciones)
            .insertOnConflictUpdate(
              Inspeccion(
                id: inspeccionId,
                empresaId: empresaId,
                ordenId: o.id,
                tecnicoId: tecnicoId,
                numero: '$clave-${n.toString().padLeft(4, '0')}',
                version: 1,
                iniciadaAt: instante(o.diasAntes),
                finalizadaAt: firmadaAt,
                firmadaAt: firmadaAt,
                sincronizadaAt: firmadaAt.add(const Duration(hours: 1)),
                estado: EstadoInspeccion.firmada.wire,
                resumenOrigen: 'determinista',
                nEquipos: ies.length,
                nRespuestas: nRespuestas,
                nIncidencias: nIncidencias,
                nFotos: 0,
                nEnlacesFotos: 0,
                nNotas: 0,
                nControles: nControles,
                nMovimientosGas: 0,
                nResoluciones: 0,
                normativaVersion: normativa.version,
                createdAt: firmadaAt,
                updatedAt: firmadaAt,
              ),
            );
        inspeccionesFirmadas.add(inspeccionId);
      }
      for (final MapEntry(:key, :value) in contadores.entries) {
        await db
            .into(db.contadoresInforme)
            .insertOnConflictUpdate(
              ContadoresInformeCompanion.insert(
                serie: key,
                ultimo: Value(value),
              ),
            );
      }
    });

    // `estado_equipo` derivado de los informes firmados, como en la firma.
    final repo = InspeccionRepository(
      db,
      Outbox(db),
      sesion: sesion,
      ahora: () => ahora,
    );
    for (final id in inspeccionesFirmadas) {
      await repo.recalcularEstadoEquipo(id);
    }
  }
}
