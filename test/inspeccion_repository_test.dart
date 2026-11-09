import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/data/local/app_database.dart';
import 'package:inspecta/data/repositories/demo_datos.dart';
import 'package:inspecta/data/repositories/inspeccion_repository.dart';
import 'package:inspecta/data/sync/outbox.dart';
import 'package:inspecta/dominio/estados.dart';
import 'package:inspecta/dominio/fgas.dart';
import 'package:inspecta/dominio/normativa.dart';
import 'package:inspecta/dominio/plantillas.dart' as dom;
import 'package:inspecta/dominio/rite.dart';
import 'package:inspecta/dominio/tipos.dart';

import 'ayuda.dart';

void main() {
  late Normativa normativa;
  late List<dom.Plantilla> plantillas;
  late AppDatabase db;
  late Outbox outbox;
  late InspeccionRepository repo;

  setUpAll(() {
    normativa = leerNormativa();
    plantillas = leerPlantillas();
  });

  setUp(() async {
    db = baseEnMemoria();
    outbox = Outbox(db);
    await DemoDatos.sembrar(
      db,
      normativa: normativa,
      plantillas: plantillas,
      ahora: ahoraFijo,
    );
    repo = InspeccionRepository(
      db,
      outbox,
      sesion: DemoDatos.sesion,
      ahora: () => ahoraFijo,
    );
  });

  tearDown(() => db.close());

  Future<List<OutboxEntry>> cola() => (db.select(
    db.outboxEntries,
  )..orderBy([(t) => OrderingTerm.asc(t.seq)])).get();

  group('DemoDatos', () {
    test('la siembra no encola nada y es idempotente', () async {
      expect(await cola(), isEmpty);
      final otra = await DemoDatos.sembrarSiFalta(
        db,
        normativa: normativa,
        plantillas: plantillas,
        ahora: ahoraFijo,
      );
      expect(otra, isFalse);
      expect(await db.select(db.equipos).get(), hasLength(8));
      expect(await db.select(db.clientes).get(), hasLength(3));
    });

    test('potencias coherentes: lo declarado cubre la suma de los equipos', () {
      for (final i in DemoDatos.instalaciones) {
        final eqs = DemoDatos.equipos.where((e) => e.instalacion == i.clave);
        final p = potenciaInstalacion(
          declaradaFrioKw: i.frioKw,
          declaradaCalorKw: i.calorKw,
          equipos: [
            for (final e in eqs)
              PotenciaEquipo(frioKw: e.frioKw, calorKw: e.calorKw),
          ],
        );
        expect(p.sumaSuperaDeclarada, isFalse, reason: i.clave);
        expect(p.avisos, isEmpty, reason: i.clave);
        final umbral = normativa.rite.umbralRegimenMensualKw;
        if (i.clave == 'oficina') {
          expect(p.kw, greaterThan(umbral));
        } else {
          expect(p.kw, lessThanOrEqualTo(umbral), reason: i.clave);
        }
      }
    });

    test('los equipos cubren las franjas F-gas que dice §11.1', () {
      String franja(EquipoDemo e) {
        final r = evaluarControlFugas(
          normativa,
          refrigerante: normativa.refrigerante(e.refrigerante)!,
          cargaKg: e.cargaKg,
          conDeteccion: false,
          hermeticoEtiquetado: false,
        );
        return switch (r) {
          NoSujetoControlFugas() => 'no sujeto',
          SujetoControlFugas(:final periodicidadMeses) => '$periodicidadMeses',
          ControlFugasNoCalculado() => 'no calculado',
        };
      }

      final f = {for (final e in DemoDatos.equipos) e.clave: franja(e)};
      expect(f['comunidad_split'], 'no sujeto');
      expect(f['hotel_vrf'], '12');
      expect(f['hotel_rooftop'], '12');
      expect(f['oficina_enfriadora'], '6');
      expect(f['oficina_conductos'], '12', reason: 'R-32 7,5 kg > 7,41 kg');
    });

    test('plantilla por equipo con la regla de O2; la oficina, solo la 3', () async {
      final clave = {for (final p in plantillas) p.id: p.clave};
      final oes = await db.select(db.ordenEquipos).get();
      final porOrdenEquipo = {
        for (final oe in oes)
          '${oe.ordenId}:${oe.equipoId}': clave[oe.plantillaId],
      };
      String? de(String orden, String equipo) =>
          porOrdenEquipo['${DemoDatos.ordenes.firstWhere((o) => o.clave == orden).id}:'
              '${DemoDatos.equipo(equipo).id}'];
      expect(de('hoy_comunidad', 'comunidad_split'), 'split_hasta_12kw');
      expect(de('hoy_comunidad', 'comunidad_conductos'), 'split_hasta_12kw');
      expect(de('hoy_hotel', 'hotel_vrf'), 'equipo_12_70kw');
      expect(de('hoy_hotel', 'hotel_split'), 'split_hasta_12kw');
      expect(de('hoy_oficina', 'oficina_enfriadora'), 'control_fugas');
      expect(de('hoy_oficina', 'oficina_split'), 'control_fugas');
    });

    test('estado_equipo sale de los informes firmados', () async {
      final rooftop =
          await (db.select(db.estadoEquipo)..where(
                (e) => e.id.equals(DemoDatos.equipo('hotel_rooftop').id),
              ))
              .getSingle();
      final h = hechosDe(rooftop);
      expect(h.ultimoPreventivoAt, isNotNull);
      expect(h.ultimosValores['presion_alta']!.valor, 22.8);
      expect(h.incidenciasAbiertas.single.gravedad, 'leve');

      final enf = hechosDe(
        await (db.select(db.estadoEquipo)..where(
              (e) => e.id.equals(DemoDatos.equipo('oficina_enfriadora').id),
            ))
            .getSingle(),
      );
      expect(enf.ultimoResultadoFugas, 'sin_fuga');
      expect(enf.ultimoPreventivoAt, isNull);

      final numeros = [
        for (final i in await db.select(db.inspecciones).get()) i.numero,
      ];
      expect(numeros, everyElement(matches(RegExp(r'^\d{4}-DEMO-A-\d{4}$'))));
    });
  });

  group('InspeccionRepository', () {
    String orden(String clave) =>
        DemoDatos.ordenes.firstWhere((o) => o.clave == clave).id;

    test('Hoy: las 4 órdenes del técnico, todas pendientes', () async {
      final hoy = await repo.watchHoy().first;
      expect(hoy, hasLength(4));
      expect(hoy.every((t) => t.estado == EstadoOrden.pendiente), isTrue);
      expect(hoy.every((t) => t.esDeHoy), isTrue);
      final hotel = hoy.firstWhere((t) => t.orden.id == orden('hoy_hotel'));
      expect(hotel.nEquipos, 3);
      expect(hotel.cliente!.razonSocial, contains('Hotel'));
    });

    test(
      'empezar visita: hora sellada, orden en curso y cola en orden',
      () async {
        final i = await repo.empezarVisita(orden('hoy_hotel'));
        expect(i.iniciadaAt, ahoraFijo);
        expect(i.tecnicoId, DemoDatos.tecnicoId);

        final hoy = await repo.watchHoy().first;
        final t = hoy.firstWhere((t) => t.orden.id == orden('hoy_hotel'));
        expect(t.estado, EstadoOrden.enCurso);
        expect(
          hoy.first.orden.id,
          orden('hoy_hotel'),
          reason: 'en curso, primero',
        );

        // La orden no se toca en local: su estado lo deriva el servidor.
        final o = await (db.select(
          db.ordenesTrabajo,
        )..where((x) => x.id.equals(orden('hoy_hotel')))).getSingle();
        expect(o.estado, 'pendiente');

        final c = await cola();
        expect(
          [for (final e in c) e.entity],
          [
            'inspecciones',
            'inspeccion_equipos',
            'inspeccion_equipos',
            'inspeccion_equipos',
          ],
        );
        expect(c.where((e) => e.entity == 'ordenes_trabajo'), isEmpty);
        final payload = jsonDecode(c.first.payload) as Map<String, dynamic>;
        expect(payload['estado'], 'en_curso');
        expect(payload.containsKey('sincronizada_at'), isFalse);

        // Un segundo toque no crea otra visita.
        final otra = await repo.empezarVisita(orden('hoy_hotel'));
        expect(otra.id, i.id);
        expect(await cola(), hasLength(4));
      },
    );

    test(
      'T2: incidencia abierta, «Resuelta en esta visita» y deshacer',
      () async {
        final i = await repo.empezarVisita(orden('hoy_hotel'));
        var v = (await repo.cargarVisita(orden('hoy_hotel')))!;
        expect(v.editable, isTrue);
        expect(v.incidencias, hasLength(1));
        final inc = v.incidencias.single;
        expect(inc.resolucionId, isNull);

        final rid = await repo.resolverIncidencia(
          inspeccionId: i.id,
          equipoId: inc.equipo.id,
          incidenciaId: inc.incidencia.id,
        );
        v = (await repo.cargarVisita(orden('hoy_hotel')))!;
        expect(v.incidencias.single.resolucionId, rid);
        expect((await cola()).last.entity, 'resoluciones_incidencia');

        // Repetir no duplica.
        expect(
          await repo.resolverIncidencia(
            inspeccionId: i.id,
            equipoId: inc.equipo.id,
            incidenciaId: inc.incidencia.id,
          ),
          rid,
        );

        expect(await repo.deshacerResolucion(rid), isTrue);
        v = (await repo.cargarVisita(orden('hoy_hotel')))!;
        expect(v.incidencias.single.resolucionId, isNull);
        expect(
          (await cola()).where((e) => e.entity == 'resoluciones_incidencia'),
          isEmpty,
        );
      },
    );

    test('deshacer no se puede si la resolución ya se intentó subir', () async {
      final i = await repo.empezarVisita(orden('hoy_hotel'));
      final v = (await repo.cargarVisita(orden('hoy_hotel')))!;
      final rid = await repo.resolverIncidencia(
        inspeccionId: i.id,
        equipoId: v.incidencias.single.equipo.id,
        incidenciaId: v.incidencias.single.incidencia.id,
      );
      final e = (await cola()).last;
      await outbox.bumpAttempts(e.seq, 'timeout');
      expect(await repo.deshacerResolucion(rid), isFalse);
      expect(await db.select(db.resolucionesIncidencia).get(), hasLength(1));
    });

    test(
      'añadir equipo en campo: equipo antes que su inspeccion_equipos',
      () async {
        final i = await repo.empezarVisita(orden('hoy_comunidad'));
        final split = plantillas.firstWhere(
          (p) => p.clave == 'split_hasta_12kw',
        );
        final id = await repo.anadirEquipo(
          inspeccionId: i.id,
          tipo: TipoEquipo.split,
          plantillaId: split.id,
          potenciaFrioKw: 2.5,
          potenciaCalorKw: 3.2,
        );
        final c = await cola();
        final iEq = c.indexWhere((e) => e.entity == 'equipos' && e.rowId == id);
        final iIe = c.lastIndexWhere((e) => e.entity == 'inspeccion_equipos');
        expect(iEq, lessThan(iIe));
        expect(c[iIe].payload, contains(id));

        final v = (await repo.cargarVisita(orden('hoy_comunidad')))!;
        expect(v.equipos, hasLength(3));
        final nuevo = v.equipos.firstWhere((e) => e.equipo.id == id);
        expect(nuevo.anadidoEnCampo, isTrue);
        expect(nuevo.plantilla!.id, split.id);
        // No toca orden_equipos, que es de la oficina.
        expect(c.where((e) => e.entity == 'orden_equipos'), isEmpty);
      },
    );

    test('T2 muestra el último valor de referencia de otro equipo', () async {
      final f = (await repo.cargarFicha(DemoDatos.equipo('hotel_vrf').id))!;
      expect(f.hechos!.ultimosValores['temp_retorno']!.valor, 24.5);
      expect(f.textosItem['temp_retorno'], 'Temperatura del aire de retorno');
    });

    test('guardar la ficha encola el equipo y confirma los datos', () async {
      final f = (await repo.cargarFicha(
        DemoDatos.equipo('comunidad_split').id,
      ))!;
      await repo.guardarEquipo(f.equipo.copyWith(cargaKg: const Value(1.2)));
      final g = (await repo.cargarFicha(f.equipo.id))!.equipo;
      expect(g.cargaKg, 1.2);
      expect(g.datosConfirmadosPor, DemoDatos.tecnicoId);
      expect(g.datosConfirmadosAt, ahoraFijo);
      final c = await cola();
      expect(c.single.entity, 'equipos');
      expect(jsonDecode(c.single.payload)['carga_kg'], 1.2);
      expect(
        () => repo.guardarEquipo(f.equipo.copyWith(cargaKg: const Value(-1))),
        throwsArgumentError,
      );
    });

    test('un informe firmado no deja escribir (§7.10.1)', () async {
      final firmada = (await db.select(db.inspecciones).get()).first;
      expect(
        () => repo.anadirEquipo(
          inspeccionId: firmada.id,
          tipo: TipoEquipo.split,
          plantillaId: plantillas.first.id,
        ),
        throwsA(isA<InspeccionCerrada>()),
      );
      final v = (await repo.cargarVisita(firmada.ordenId))!;
      expect(v.editable, isFalse);
      expect(v.estado, EstadoOrden.firmada);
    });

    test('recalcular exige un informe firmado', () async {
      final i = await repo.empezarVisita(orden('hoy_hotel'));
      expect(() => repo.recalcularEstadoEquipo(i.id), throwsStateError);
    });

    test('Hoy se actualiza solo al empezar una visita', () async {
      final estados = <EstadoOrden>[];
      final sub = repo.watchHoy().listen(
        (l) => estados.add(
          l.firstWhere((t) => t.orden.id == orden('hoy_oficina')).estado,
        ),
      );
      await pumpEventQueue();
      await repo.empezarVisita(orden('hoy_oficina'));
      await pumpEventQueue();
      await sub.cancel();
      expect(estados.first, EstadoOrden.pendiente);
      expect(estados.last, EstadoOrden.enCurso);
    });
  });
}
