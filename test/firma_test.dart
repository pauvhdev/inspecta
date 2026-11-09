import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/data/local/app_database.dart';
import 'package:inspecta/data/repositories/demo_datos.dart';
import 'package:inspecta/data/repositories/inspeccion_repository.dart';
import 'package:inspecta/data/sync/outbox.dart';
import 'package:inspecta/dominio/fgas.dart';
import 'package:inspecta/dominio/normativa.dart';
import 'package:inspecta/dominio/plantillas.dart' as dom;
import 'package:inspecta/informe/calculo_informe.dart';
import 'package:inspecta/informe/datos_informe.dart';
import 'package:inspecta/informe/pdf_informe.dart';

import 'ayuda.dart';

// Días 5-7: fotos, revisar y firmar, numeración, candado, cierre al final de
// la cola, contenido_sha256 y el PDF generado en el aparato.

final _foto = File('assets/demo/etiqueta_fgas.jpg').readAsBytesSync();
final _firma = File('test/fixtures/firma.png').readAsBytesSync();
final _regular = File('assets/fuentes/Roboto-Regular.ttf').readAsBytesSync();
final _negrita = File('assets/fuentes/Roboto-Bold.ttf').readAsBytesSync();

Future<Uint8List> pdfDePrueba(DatosInforme d, String sha) => construirPdf(
  d,
  contenidoSha: sha,
  fuenteRegular: _regular,
  fuenteNegrita: _negrita,
);

/// Responde todo lo obligatorio de una visita: OK, un valor en rango donde
/// hace falta y la foto de los ítems que la piden.
Future<void> completarVisita(InspeccionRepository repo, String ordenId) async {
  final v = (await repo.cargarVisita(ordenId))!;
  for (final e in v.equipos) {
    final ch = (await repo.cargarChecklist(e.inspeccionEquipoId!))!;
    for (final ic in ch.items) {
      final it = ic.item;
      final valor =
          it.tipoRespuesta == 'estado_valor' || it.tipoRespuesta == 'solo_valor'
          ? ((it.rangoMin ?? 0) + (it.rangoMax ?? 10)) / 2
          : null;
      await repo.responder(
        inspeccionEquipoId: ch.inspeccionEquipo.id,
        itemId: it.id,
        estado: it.tipoRespuesta == 'solo_valor' ? null : 'ok',
        valor: valor,
        observacion: null,
      );
      if (it.fotoObligatoria) {
        await repo.guardarFoto(
          inspeccionEquipoId: ch.inspeccionEquipo.id,
          itemId: it.id,
          bytes: _foto,
          mime: 'image/jpeg',
        );
      }
    }
  }
}

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

  Future<Inspeccion> firmarHotel({bool completar = true}) async {
    final i = await repo.empezarVisita(orden('hoy_hotel'));
    if (completar) await completarVisita(repo, orden('hoy_hotel'));
    final v = (await repo.cargarVisita(orden('hoy_hotel')))!;
    final chs = [
      for (final e in v.equipos)
        (await repo.cargarChecklist(e.inspeccionEquipoId!))!,
    ];
    return repo.firmar(
      inspeccionId: i.id,
      resumen: resumenDeterminista(v, chs),
      cliente: FirmaCapturada(
        nombre: 'Javier Soler',
        cargo: 'Mantenimiento',
        png: _firma,
      ),
      tecnico: FirmaCapturada(nombre: 'Lucía Ferrer', png: _firma),
      normativaVersion: normativa.version,
      serie: DemoDatos.serie,
      letra: DemoDatos.letra,
      datosEquipo: (e, h) => datosEquipoParaInforme(
        normativa,
        equipo: e,
        instalacion: v.instalacion,
        equiposInstalacion: v.equiposInstalacion,
        hechos: h,
        esPreventivo: true,
        resultadoFugas: null,
        firmadaAt: ahoraFijo,
      ),
    );
  }

  test('la foto va a blobs y su subida se encola antes que la fila', () async {
    final i = await repo.empezarVisita(orden('hoy_hotel'));
    final ie = (await db.select(db.inspeccionEquipos).get()).firstWhere(
      (x) => x.inspeccionId == i.id,
    );
    final id = await repo.guardarFoto(
      inspeccionEquipoId: ie.id,
      bytes: _foto,
      mime: 'image/jpeg',
    );
    final cola = await (db.select(
      db.outboxEntries,
    )..orderBy([(t) => OrderingTerm.asc(t.seq)])).get();
    final iStorage = cola.indexWhere((e) => e.entity == 'storage');
    final iFila = cola.indexWhere((e) => e.entity == 'fotos' && e.rowId == id);
    expect(iStorage, lessThan(iFila));
    expect(
      cola[iStorage].payload.length,
      lessThan(400),
      reason: 'sin bytes en la cola',
    );
    expect(
      jsonDecode(cola[iStorage].payload)['ruta'],
      contains('/inspecciones/${i.id}/fotos/'),
    );
    expect(await repo.bytesDe(id), _foto);
    final f = (await db.select(db.fotos).get()).single;
    expect(f.sha256, sha256De(_foto));

    await repo.borrarFoto(id);
    final ch = (await repo.cargarChecklist(ie.id))!;
    expect(ch.fotos, isEmpty, reason: 'borrado lógico');
  });

  test('con pendientes no se firma (doble barrera)', () async {
    await repo.empezarVisita(orden('hoy_hotel'));
    final i = (await db.select(db.inspecciones).get()).firstWhere(
      (x) => x.firmadaAt == null,
    );
    final p = await repo.pendientesDeFirma(i.id);
    expect(p, isNotEmpty);
    // 3 equipos: 18 + 22 + 22 obligatorios sin responder (los opcionales no cuentan).
    expect(
      p.where((x) => x.texto.startsWith('Sin responder')),
      hasLength(p.length),
    );
    expect(p.first.indiceItem, 0);
    expect(
      () => firmarHotel(completar: false),
      throwsA(isA<FirmaIncompleta>()),
    );
  });

  test('N.A. no exige la foto obligatoria', () async {
    await repo.empezarVisita(orden('hoy_hotel'));
    await completarVisita(repo, orden('hoy_hotel'));
    final v = (await repo.cargarVisita(orden('hoy_hotel')))!;
    final ch = (await repo.cargarChecklist(
      v.equipos.first.inspeccionEquipoId!,
    ))!;
    final etiqueta = ch.items.firstWhere((i) => i.item.fotoObligatoria);
    for (final f in ch.fotosDe(etiqueta.item.id)) {
      await repo.borrarFoto(f.id);
    }
    expect(await repo.pendientesDeFirma(v.inspeccion!.id), hasLength(1));
    await repo.responder(
      inspeccionEquipoId: ch.inspeccionEquipo.id,
      itemId: etiqueta.item.id,
      estado: 'na',
      valor: null,
      observacion: null,
    );
    expect(await repo.pendientesDeFirma(v.inspeccion!.id), isEmpty);
  });

  test('firmar: número de la serie del aparato, cabecera y candado', () async {
    final f = await firmarHotel();
    expect(
      f.numero,
      '2026-DEMO-A-0002',
      reason: 'la demo ya tiene la 0001 de 2026',
    );
    expect(f.estado, 'firmada');
    expect(f.firmadaAt, ahoraFijo);
    expect(f.nEquipos, 3);
    expect(f.nFotos, 3);
    expect(f.nRespuestas, 66);
    final cab = jsonDecode(f.datosCabeceraJson!) as Map;
    expect((cab['cliente'] as Map)['razon_social'], contains('Hotel'));
    expect((cab['tecnico'] as Map)['nombre'], contains('Lucía'));
    final ie = (await db.select(db.inspeccionEquipos).get()).firstWhere(
      (x) => x.inspeccionId == f.id,
    );
    expect(jsonDecode(ie.datosEquipoJson!)['fgas'], isNotNull);
    expect(await db.select(db.firmas).get(), hasLength(2));

    // Solo lectura desde aquí.
    expect(
      () => repo.responder(
        inspeccionEquipoId: ie.id,
        itemId: plantillas
            .expand((p) => p.items)
            .firstWhere((x) => x.plantillaId == ie.plantillaId)
            .id,
        estado: 'defecto',
        valor: null,
        observacion: null,
      ),
      throwsA(isA<InspeccionCerrada>()),
    );
    expect(() => firmarHotel(), throwsA(isA<InspeccionCerrada>()));
  });

  test(
    'cierre: PDF, hashes, cierre al final de la cola y estado_equipo',
    () async {
      final f = await firmarHotel();
      // Antes del PDF, el cierre no está en la cola.
      final antes = await db.select(db.outboxEntries).get();
      expect(
        antes.where(
          (e) =>
              e.entity == 'inspecciones' &&
              e.payload.contains('"estado":"firmada"'),
        ),
        isEmpty,
      );

      final c = await repo.completarCierre(
        f.id,
        esDemo: true,
        generarPdf: pdfDePrueba,
      );
      final pdf = (await repo.bytesDe(f.id))!;
      expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
      expect(c.pdfSha256, sha256De(pdf));
      expect(c.contenidoSha256, hasLength(64));
      expect(c.pdfRuta, endsWith('/pdf/informe_v1.pdf'));

      final cola = await (db.select(
        db.outboxEntries,
      )..orderBy([(t) => OrderingTerm.asc(t.seq)])).get();
      expect(cola.last.entity, 'inspecciones');
      expect(cola.last.payload, contains('"estado":"firmada"'));
      expect(jsonDecode(cola.last.payload)['pdf_sha256'], c.pdfSha256);
      // La entrada en curso de la inspección sigue delante: no se fusionó.
      expect(cola.first.entity, 'inspecciones');
      expect(cola.first.payload, contains('"estado":"en_curso"'));

      // estado_equipo recalculado en local: el preventivo cuenta desde hoy.
      final vrf =
          await (db.select(db.estadoEquipo)
                ..where((e) => e.id.equals(DemoDatos.equipo('hotel_vrf').id)))
              .getSingle();
      expect(vrf.ultimoPreventivoAt, ahoraFijo);
      expect(vrf.ultimaInspeccionId, f.id);

      // Idempotente: no regenera el PDF canónico.
      final otra = await repo.completarCierre(
        f.id,
        esDemo: true,
        generarPdf: (_, _) => throw StateError('no'),
      );
      expect(otra.pdfSha256, c.pdfSha256);

      // Hoy: firmada y pendiente de subir.
      final hoy = await repo.watchHoy().first;
      final t = hoy.firstWhere((x) => x.orden.id == orden('hoy_hotel'));
      expect(t.sinSubir, isTrue);
    },
  );

  group('contenido_sha256', () {
    test(
      'mismo contenido en otro orden → mismo hash; un cambio → otro',
      () async {
        final f = await firmarHotel();
        final d = await repo.cargarDatosInforme(f.id, esDemo: true);
        final hash = contenidoSha256(d);
        final invertido = DatosInforme(
          inspeccion: d.inspeccion,
          tipoIntervencion: d.tipoIntervencion,
          equipos: [
            for (final e in d.equipos.reversed)
              EquipoInforme(
                inspeccionEquipo: e.inspeccionEquipo,
                equipo: e.equipo,
                respuestas: e.respuestas.reversed.toList(),
                incidencias: e.incidencias,
                controles: e.controles,
                movimientos: e.movimientos,
                fotos: e.fotos.reversed.toList(),
                resoluciones: e.resoluciones,
              ),
          ],
          firmas: d.firmas.reversed.toList(),
          bytes: const {},
          esDemo: false,
        );
        expect(
          contenidoSha256(invertido),
          hash,
          reason: 'ni el orden ni los bytes cuentan',
        );

        final r = d.equipos.first.respuestas.first;
        final cambiado = DatosInforme(
          inspeccion: d.inspeccion,
          tipoIntervencion: d.tipoIntervencion,
          equipos: [
            EquipoInforme(
              inspeccionEquipo: d.equipos.first.inspeccionEquipo,
              equipo: d.equipos.first.equipo,
              respuestas: [
                r.copyWith(estado: const Value('defecto')),
                ...d.equipos.first.respuestas.skip(1),
              ],
              incidencias: const [],
              controles: const [],
              movimientos: const [],
              fotos: d.equipos.first.fotos,
              resoluciones: const [],
            ),
            ...d.equipos.skip(1),
          ],
          firmas: d.firmas,
          bytes: d.bytes,
          esDemo: true,
        );
        expect(contenidoSha256(cambiado), isNot(hash));
      },
    );
  });

  test(
    'el PDF lleva un movimiento de gas y un control con nuevo control',
    () async {
      await repo.empezarVisita(orden('hoy_oficina'));
      await completarVisita(repo, orden('hoy_oficina'));
      final v = (await repo.cargarVisita(orden('hoy_oficina')))!;
      final ie = v.equipos.first.inspeccionEquipoId!;
      await repo.registrarControlFugas(
        inspeccionEquipoId: ie,
        resultado: 'fuga',
        localizacion: 'Válvula de servicio',
        reparada: true,
        ventana: ventanaNuevoControl(normativa, ahoraFijo),
      );
      const m = MovimientoGasNuevo(
        tipo: TipoMovimientoGas.carga,
        refrigerante: 'R-134a',
        kg: 1.5,
        origen: OrigenGas.virgen,
        motivo: 'fuga',
      );
      await repo.registrarMovimientoGas(
        inspeccionEquipoId: ie,
        m: m,
        validacion: const CargaPermitida(regla: ReglaAplicada.ninguna),
      );
      final f = await repo.firmar(
        inspeccionId: v.inspeccion!.id,
        resumen: 'Control',
        cliente: FirmaCapturada(nombre: 'Elena Navarro', png: _firma),
        tecnico: FirmaCapturada(nombre: 'Lucía Ferrer', png: _firma),
        normativaVersion: normativa.version,
        serie: DemoDatos.serie,
        letra: DemoDatos.letra,
        datosEquipo: (e, h) => datosEquipoParaInforme(
          normativa,
          equipo: e,
          instalacion: v.instalacion,
          equiposInstalacion: v.equiposInstalacion,
          hechos: h,
          esPreventivo: false,
          resultadoFugas: 'fuga',
          firmadaAt: ahoraFijo,
        ),
      );
      expect(f.nControles, 1);
      expect(f.nMovimientosGas, 1);
      final c = await repo.completarCierre(
        f.id,
        esDemo: true,
        generarPdf: pdfDePrueba,
      );
      expect(c.pdfSha256, isNotNull);
      final enf =
          await (db.select(db.estadoEquipo)..where(
                (e) => e.id.equals(DemoDatos.equipo('oficina_enfriadora').id),
              ))
              .getSingle();
      expect(enf.ultimoResultadoFugas, 'fuga');
      expect(enf.ultimoControlFugasAt, ahoraFijo);

      // Muestra para el README: `GENERAR_MUESTRAS=1 fvm flutter test test/firma_test.dart`.
      if (Platform.environment['GENERAR_MUESTRAS'] == '1') {
        Directory('docs/muestras').createSync(recursive: true);
        File('docs/muestras/informe_control_fugas.pdf')
            .writeAsBytesSync((await repo.bytesDe(f.id))!);
      }
    },
  );

  test('muestra del preventivo del hotel', () async {
    final f = await firmarHotel();
    await repo.completarCierre(f.id, esDemo: true, generarPdf: pdfDePrueba);
    if (Platform.environment['GENERAR_MUESTRAS'] == '1') {
      Directory('docs/muestras').createSync(recursive: true);
      File('docs/muestras/informe_preventivo.pdf')
          .writeAsBytesSync((await repo.bytesDe(f.id))!);
    }
  });
}
