import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/data/repositories/demo_datos.dart';
import 'package:inspecta/data/repositories/inspeccion_repository.dart';
import 'package:inspecta/data/sync/outbox.dart';
import 'package:inspecta/dominio/normativa.dart';
import 'package:inspecta/dominio/plantillas.dart' as dom;
import 'package:inspecta/informe/calculo_informe.dart';

import 'ayuda.dart';
import 'ayuda_widgets.dart';
import 'firma_test.dart' show completarVisita, pdfDePrueba;

// T12 → T13 → T14 en la app. La firma de verdad (PNG del lienzo, firmar y
// PDF) la prueban `firma_test.dart` y el repositorio: exportar el lienzo a
// PNG necesita el motor real y en una prueba de widgets se interbloquea con
// Drift. Aquí se prueba lo que ve y toca el técnico.

/// Espera a un Future que usa Drift dentro del reloj falso de la prueba.
Future<T> esperar<T>(WidgetTester tester, Future<T> f) async {
  T? r;
  Object? error;
  var hecho = false;
  f.then(
    (v) {
      r = v;
      hecho = true;
    },
    onError: (Object e) {
      error = e;
      hecho = true;
    },
  );
  for (var i = 0; i < 2000 && !hecho; i++) {
    await tester.pump(const Duration(milliseconds: 5));
  }
  if (error != null) throw error!;
  expect(hecho, isTrue, reason: 'la operación no terminó');
  return r as T;
}

void main() {
  late Normativa normativa;
  late List<dom.Plantilla> plantillas;

  setUpAll(() {
    normativa = leerNormativa();
    plantillas = leerPlantillas();
  });

  testWidgets('T12 bloquea, T13 se firma con el dedo, T14 enseña el número', (
    tester,
  ) async {
    final db = await montarDemo(
      tester,
      normativa: normativa,
      plantillas: plantillas,
    );
    final repo = InspeccionRepository(
      db,
      Outbox(db),
      sesion: DemoDatos.sesion,
      ahora: () => ahoraFijo,
    );
    final hotel = DemoDatos.ordenes.firstWhere((o) => o.clave == 'hoy_hotel');
    await tester.tap(find.byKey(Key('orden_${hotel.id}')));
    await asentar(tester);
    await tester.tap(find.byKey(const Key('empezar_visita')));
    await asentar(tester);

    // T12 con todo por hacer: «Firmar» inactivo con el motivo.
    await tester.tap(find.byKey(const Key('revisar_firmar')));
    await asentar(tester);
    expect(find.textContaining('Falta para firmar'), findsOneWidget);
    expect(find.text('Completa lo que falta para firmar.'), findsOneWidget);
    comprobarObjetivos56(tester, 'T12 Revisar y firmar');

    // Se completa la visita (como si el técnico respondiera todo).
    await esperar(tester, completarVisita(repo, hotel.id));
    await asentar(tester);
    expect(find.text('Todo respondido'), findsOneWidget);
    expect(
      find.textContaining('3 equipos revisados'),
      findsOneWidget,
      reason: 'resumen determinista',
    );

    // T13: nombre del cliente y lienzo.
    await tester.tap(find.byKey(const Key('ir_a_firmar')));
    await asentar(tester);
    expect(
      find.text('Javier Soler'),
      findsOneWidget,
      reason: 'el contacto, sin el paréntesis',
    );
    await tester.enterText(
      find.byKey(const Key('firma_cargo')),
      'Jefe de mantenimiento',
    );
    await tester.tap(find.byKey(const Key('firma_continuar')));
    await asentar(tester);
    expect(find.textContaining('Jefe de mantenimiento'), findsOneWidget);
    final confirmar = find.byKey(const Key('firma_confirmar'));
    expect(
      tester.widget<ButtonStyleButton>(confirmar).enabled,
      isFalse,
      reason: 'sin trazo no se confirma',
    );
    final c = tester.getCenter(find.byKey(const Key('lienzo_firma')));
    final g = await tester.startGesture(c - const Offset(80, 0));
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(c + Offset(-80 + i * 20.0, i.isEven ? -30 : 30));
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(confirmar).enabled, isTrue);
    comprobarObjetivos56(tester, 'T13 Firma');

    // Se firma por el repositorio (lo que haría «Confirmar» dos veces).
    final png = File('test/fixtures/firma.png').readAsBytesSync();
    final v = (await esperar(tester, repo.cargarVisita(hotel.id)))!;
    final f = await esperar(
      tester,
      repo.firmar(
        inspeccionId: v.inspeccion!.id,
        resumen: 'Visita de prueba',
        cliente: FirmaCapturada(
          nombre: 'Javier Soler',
          cargo: 'Jefe de mantenimiento',
          png: png,
        ),
        tecnico: FirmaCapturada(nombre: 'Lucía Ferrer', png: png),
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
      ),
    );
    await esperar(
      tester,
      repo.completarCierre(f.id, esDemo: true, generarPdf: pdfDePrueba),
    );

    // De vuelta a T2: solo lectura y «Ver informe» → T14.
    for (var i = 0; i < 3; i++) {
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await asentar(tester);
    }
    expect(find.text('Firmada'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ver_informe')));
    await asentar(tester);
    expect(find.text('2026-DEMO-A-0002'), findsOneWidget);
    expect(find.text('Firmado · pendiente de subir'), findsOneWidget);
    comprobarObjetivos56(tester, 'T14 Informe');

    await desmontar(tester, db);
  });
}
