import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/data/local/app_database.dart';
import 'package:inspecta/data/repositories/demo_datos.dart';
import 'package:inspecta/data/repositories/inspeccion_repository.dart';
import 'package:inspecta/data/sync/outbox.dart';
import 'package:inspecta/dominio/fgas.dart';
import 'package:inspecta/dominio/normativa.dart';
import 'package:inspecta/dominio/plantillas.dart' as dom;
import 'package:inspecta/dominio/tipos.dart';

import 'ayuda.dart';

// Día 4 en el repositorio: respuestas con deshacer, incidencias sin gravedad
// por defecto, bloqueo del art. 13.4 y nuevo control del art. 4.5.

void main() {
  late Normativa normativa;
  late List<dom.Plantilla> plantillas;
  late AppDatabase db;
  late InspeccionRepository repo;

  setUpAll(() {
    normativa = leerNormativa();
    plantillas = leerPlantillas();
  });

  setUp(() async {
    db = baseEnMemoria();
    await DemoDatos.sembrar(
      db,
      normativa: normativa,
      plantillas: plantillas,
      ahora: ahoraFijo,
    );
    repo = InspeccionRepository(
      db,
      Outbox(db),
      sesion: DemoDatos.sesion,
      ahora: () => ahoraFijo,
    );
  });

  tearDown(() => db.close());

  String orden(String clave) =>
      DemoDatos.ordenes.firstWhere((o) => o.clave == clave).id;

  Future<ChecklistEquipo> checklistDe(String ordenClave, String equipo) async {
    await repo.empezarVisita(orden(ordenClave));
    final v = (await repo.cargarVisita(orden(ordenClave)))!;
    final e = v.equipos.firstWhere(
      (x) => x.equipo.id == DemoDatos.equipo(equipo).id,
    );
    return (await repo.cargarChecklist(e.inspeccionEquipoId!))!;
  }

  test(
    'el checklist trae los ítems en orden y la referencia anterior',
    () async {
      final ch = await checklistDe('hoy_hotel', 'hotel_vrf');
      expect(ch.items, hasLength(24));
      expect(ch.items.first.item.orden, 1);
      expect(ch.respondidos, 0);
      expect(ch.primeroPendiente, 0);
      expect(ch.hechos!.ultimosValores['temp_retorno']!.valor, 24.5);
    },
  );

  test(
    'responder crea una fila con la copia del ítem y la actualiza',
    () async {
      final ch = await checklistDe('hoy_hotel', 'hotel_vrf');
      final item = ch.items
          .firstWhere((i) => i.item.clave == 'temp_retorno')
          .item;
      await repo.responder(
        inspeccionEquipoId: ch.inspeccionEquipo.id,
        itemId: item.id,
        estado: null,
        valor: 23.8,
        observacion: null,
      );
      await repo.responder(
        inspeccionEquipoId: ch.inspeccionEquipo.id,
        itemId: item.id,
        estado: 'ok',
        valor: 23.8,
        observacion: '  ',
      );
      final rs =
          await (db.select(db.respuestas)..where(
                (r) => r.inspeccionEquipoId.equals(ch.inspeccionEquipo.id),
              ))
              .get();
      expect(rs, hasLength(1));
      expect(rs.single.textoItem, item.texto);
      expect(rs.single.codigoNormativo, item.codigoNormativo);
      expect(rs.single.unidad, '°C');
      expect(rs.single.observacion, isNull);
      final cola = await (db.select(
        db.outboxEntries,
      )..where((e) => e.entity.equals('respuestas'))).get();
      expect(
        cola,
        hasLength(1),
        reason: 'la coalescencia junta los dos cambios',
      );
      expect(jsonDecode(cola.single.payload)['estado'], 'ok');

      final otra = (await repo.cargarChecklist(ch.inspeccionEquipo.id))!;
      expect(otra.respondidos, 1);
    },
  );

  test('deshacer vuelve la respuesta a como estaba', () async {
    final ch = await checklistDe('hoy_hotel', 'hotel_vrf');
    final item = ch.items.first.item;
    final previa = await repo.responder(
      inspeccionEquipoId: ch.inspeccionEquipo.id,
      itemId: item.id,
      estado: 'defecto',
      valor: null,
      observacion: null,
    );
    expect(previa.estado, isNull);
    await repo.deshacerRespuesta(previa);
    final otra = (await repo.cargarChecklist(ch.inspeccionEquipo.id))!;
    expect(otra.items.first.respondido, isFalse);
    expect(otra.primeroPendiente, 0);
  });

  test('un ítem de otra plantilla o un estado inventado se rechazan', () async {
    final ch = await checklistDe('hoy_hotel', 'hotel_vrf');
    final ajeno = plantillas
        .firstWhere((p) => p.clave == 'control_fugas')
        .items
        .first;
    expect(
      () => repo.responder(
        inspeccionEquipoId: ch.inspeccionEquipo.id,
        itemId: ajeno.id,
        estado: 'ok',
        valor: null,
        observacion: null,
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.responder(
        inspeccionEquipoId: ch.inspeccionEquipo.id,
        itemId: ch.items.first.item.id,
        estado: 'regular',
        valor: null,
        observacion: null,
      ),
      throwsArgumentError,
    );
  });

  test(
    'incidencia: sin gravedad no se guarda; con ítem enlaza la respuesta',
    () async {
      final ch = await checklistDe('hoy_hotel', 'hotel_rooftop');
      final item = ch.items
          .firstWhere((i) => i.item.clave == 'filtro_limpieza')
          .item;
      await repo.responder(
        inspeccionEquipoId: ch.inspeccionEquipo.id,
        itemId: item.id,
        estado: 'defecto',
        valor: null,
        observacion: null,
      );
      expect(
        () => repo.guardarIncidencia(
          inspeccionEquipoId: ch.inspeccionEquipo.id,
          descripcion: 'Filtro roto',
          gravedad: '',
          paraEquipo: false,
        ),
        throwsArgumentError,
      );
      final id = await repo.guardarIncidencia(
        inspeccionEquipoId: ch.inspeccionEquipo.id,
        itemId: item.id,
        descripcion: 'Filtro roto',
        gravedad: 'grave',
        plazoDias: 90,
        paraEquipo: false,
      );
      final inc = await (db.select(
        db.incidencias,
      )..where((i) => i.id.equals(id))).getSingle();
      expect(inc.respuestaId, isNotNull);
      expect(inc.decididaPor, DemoDatos.tecnicoId);
      // Editarla no cambia el enlace (§8.2) ni crea otra.
      await repo.guardarIncidencia(
        id: id,
        inspeccionEquipoId: ch.inspeccionEquipo.id,
        descripcion: 'Filtro roto y sucio',
        gravedad: 'leve',
        paraEquipo: true,
      );
      final todas = await db.select(db.incidencias).get();
      expect(
        todas.where((i) => i.id == id).single.respuestaId,
        inc.respuestaId,
      );
      expect(todas.where((i) => i.id == id).single.paraEquipo, isTrue);
    },
  );

  group('gas', () {
    ValidacionCarga validar(
      MovimientoGasNuevo m, {
      CategoriaFgas c = CategoriaFgas.aireAcondicionadoBombaCalor,
    }) => validarCargaGas(
      normativa,
      tipo: m.tipo,
      refrigerante: normativa.refrigerante(m.refrigerante)!,
      categoria: c,
      origen: m.origen ?? OrigenGas.virgen,
      fecha: ahoraFijo,
      datos: m.datos,
    );

    test(
      'R-404A virgen en aire acondicionado: bloqueado y no se guarda',
      () async {
        final ch = await checklistDe('hoy_hotel', 'hotel_split');
        const m = MovimientoGasNuevo(
          tipo: TipoMovimientoGas.carga,
          refrigerante: 'R-404A',
          kg: 0.5,
          origen: OrigenGas.virgen,
        );
        final v = validar(m);
        expect(v, isA<CargaBloqueada>());
        expect(
          () => repo.registrarMovimientoGas(
            inspeccionEquipoId: ch.inspeccionEquipo.id,
            m: m,
            validacion: v,
          ),
          throwsA(isA<CargaGasBloqueada>()),
        );
        expect(await db.select(db.movimientosGas).get(), isEmpty);
      },
    );

    test('R-32 virgen se guarda con la regla aplicada', () async {
      final ch = await checklistDe('hoy_hotel', 'hotel_split');
      const m = MovimientoGasNuevo(
        tipo: TipoMovimientoGas.carga,
        refrigerante: 'R-32',
        kg: 0.3,
        origen: OrigenGas.virgen,
        motivo: 'mantenimiento',
      );
      await repo.registrarMovimientoGas(
        inspeccionEquipoId: ch.inspeccionEquipo.id,
        m: m,
        validacion: validar(m),
      );
      final g = (await db.select(db.movimientosGas).get()).single;
      expect(g.reglaAplicada, 'ninguna');
      expect(g.avisoPcg, isFalse);
      expect(g.origenGas, 'virgen');
    });

    test('en refrigeración, el 13.3 avisa y deja guardar', () async {
      final ch = await checklistDe('hoy_hotel', 'hotel_split');
      const m = MovimientoGasNuevo(
        tipo: TipoMovimientoGas.carga,
        refrigerante: 'R-404A',
        kg: 1,
        origen: OrigenGas.virgen,
      );
      final v = validar(m, c: CategoriaFgas.refrigeracion);
      expect(v, isA<CargaConAviso>());
      await repo.registrarMovimientoGas(
        inspeccionEquipoId: ch.inspeccionEquipo.id,
        m: m,
        validacion: v,
      );
      final g = (await db.select(db.movimientosGas).get()).single;
      expect(g.reglaAplicada, '13.3_aviso');
      expect(g.avisoPcg, isTrue);
    });

    test('una recuperación no lleva origen', () async {
      final ch = await checklistDe('hoy_hotel', 'hotel_split');
      const m = MovimientoGasNuevo(
        tipo: TipoMovimientoGas.recuperacion,
        refrigerante: 'R-404A',
        kg: 2,
        origen: OrigenGas.virgen,
      );
      await repo.registrarMovimientoGas(
        inspeccionEquipoId: ch.inspeccionEquipo.id,
        m: m,
        validacion: validar(m),
      );
      expect(
        (await db.select(db.movimientosGas).get()).single.origenGas,
        isNull,
      );
    });

    test('fuga reparada: guarda la ventana del nuevo control', () async {
      final ch = await checklistDe('hoy_oficina', 'oficina_enfriadora');
      final ventana = ventanaNuevoControl(normativa, ahoraFijo);
      await repo.registrarControlFugas(
        inspeccionEquipoId: ch.inspeccionEquipo.id,
        resultado: 'fuga',
        localizacion: 'Válvula de servicio de alta',
        reparada: true,
        ventana: ventana,
      );
      final c = (await db.select(db.controlesFugas).get()).firstWhere(
        (x) => x.inspeccionEquipoId == ch.inspeccionEquipo.id,
      );
      expect(c.fechaReparacion, ahoraFijo);
      expect(c.recontrolDesde, ahoraFijo.add(const Duration(hours: 24)));
      expect(c.recontrolHasta!.isAfter(c.recontrolDesde!), isTrue);
    });

    test('sin fuga no guarda localización ni reparación', () async {
      final ch = await checklistDe('hoy_oficina', 'oficina_split');
      await repo.registrarControlFugas(
        inspeccionEquipoId: ch.inspeccionEquipo.id,
        resultado: 'sin_fuga',
        localizacion: 'ninguna',
        reparada: true,
      );
      final c = (await db.select(db.controlesFugas).get()).firstWhere(
        (x) => x.inspeccionEquipoId == ch.inspeccionEquipo.id,
      );
      expect(c.localizacion, isNull);
      expect(c.reparada, isNull);
      expect(c.recontrolDesde, isNull);
    });
  });

  test('en un informe firmado no se responde ni se registra gas', () async {
    final ie = (await db.select(db.inspeccionEquipos).get()).first;
    final itemId = (await db.select(db.itemsPlantilla).get())
        .firstWhere((i) => i.plantillaId == ie.plantillaId)
        .id;
    expect(
      () => repo.responder(
        inspeccionEquipoId: ie.id,
        itemId: itemId,
        estado: 'ok',
        valor: null,
        observacion: null,
      ),
      throwsA(isA<InspeccionCerrada>()),
    );
    expect(
      () => repo.registrarControlFugas(
        inspeccionEquipoId: ie.id,
        resultado: 'sin_fuga',
      ),
      throwsA(isA<InspeccionCerrada>()),
    );
  });
}
