import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/app/app.dart';
import 'package:inspecta/app/providers.dart';
import 'package:inspecta/data/local/app_database.dart';
import 'package:inspecta/data/repositories/demo_datos.dart';
import 'package:inspecta/design/tokens.dart';
import 'package:inspecta/dominio/normativa.dart';
import 'package:inspecta/dominio/plantillas.dart' as dom;

import 'ayuda.dart';

// Recorrido del hito del día 3 (DISEÑO.md §12) sin red: abrir una orden demo,
// empezar la visita, dar de alta un equipo con su plantilla sugerida y ver el
// último valor de referencia de otro equipo, el bloque F-gas y el RITE.

void main() {
  late Normativa normativa;
  late List<dom.Plantilla> plantillas;

  setUpAll(() {
    normativa = leerNormativa();
    plantillas = leerPlantillas();
  });

  Future<AppDatabase> montar(WidgetTester tester) async {
    final db = baseEnMemoria();
    await tester.binding.setSurfaceSize(const Size(360, 1600));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          esDemoProvider.overrideWithValue(true),
          relojProvider.overrideWithValue(() => ahoraFijo),
          normativaProvider.overrideWith((ref) async => normativa),
          plantillasBaseProvider.overrideWith((ref) async => plantillas),
        ],
        child: const InspectaApp(),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return db;
  }

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Desplaza la lista de la pantalla de delante hasta [f] (ListView crea
  /// los hijos según se ven).
  Future<void> verA(WidgetTester tester, Finder f, {double paso = 200}) async {
    await tester.scrollUntilVisible(
      f,
      paso,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
  }

  Future<void> desmontar(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
    await db.close();
    await tester.binding.setSurfaceSize(null);
  }

  testWidgets('T1 → T2 → empezar visita → añadir equipo → T3', (tester) async {
    final db = await montar(tester);

    // T1: las 4 órdenes del técnico de la demo.
    expect(find.textContaining('Hotel Brisa'), findsWidgets);
    expect(find.text('Pendiente'), findsNWidgets(4));
    final hotel = DemoDatos.ordenes.firstWhere((o) => o.clave == 'hoy_hotel');
    final tarjeta = find.byKey(Key('orden_${hotel.id}'));
    expect(tester.getSize(tarjeta).height, greaterThanOrEqualTo(Touch.captura));

    // T2 del hotel: incidencia abierta y «Empezar visita».
    await tester.tap(tarjeta);
    await asentar(tester);
    expect(
      find.textContaining('Aislamiento de la línea frigorífica'),
      findsOneWidget,
    );
    final empezar = find.byKey(const Key('empezar_visita'));
    expect(tester.getSize(empezar).height, greaterThanOrEqualTo(Touch.primary));
    await tester.tap(empezar);
    await asentar(tester);
    expect(find.text('En curso'), findsOneWidget);
    // La hora sellada, en hora local del aparato.
    expect(
      find.textContaining(RegExp(r'^Visita empezada a las \d\d:\d\d$')),
      findsOneWidget,
    );
    expect(find.textContaining('Faltan'), findsOneWidget);

    // Resuelta en esta visita.
    final resolver = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('resolver_'),
    );
    await verA(tester, resolver);
    await tester.tap(resolver);
    await asentar(tester);
    expect(await db.select(db.resolucionesIncidencia).get(), hasLength(1));
    expect(find.text('Deshacer'), findsOneWidget);

    // Añadir equipo: tipo Split, 3,5 kW de frío → se sugiere la plantilla 1.
    await tester.ensureVisible(find.byKey(const Key('anadir_equipo')));
    await tester.tap(find.byKey(const Key('anadir_equipo')));
    await asentar(tester);
    await tester.tap(find.text('Split'));
    await asentar(tester);
    await tester.tap(find.byKey(const Key('potencia_frio')));
    await asentar(tester);
    await tester.tap(find.byKey(const Key('tecla_3')));
    await tester.tap(find.byKey(const Key('tecla_,')));
    await tester.tap(find.byKey(const Key('tecla_5')));
    await tester.pump();
    expect(find.text('3,5 kW'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pad_aceptar')));
    await asentar(tester);
    expect(
      find.textContaining('Split o autónomo hasta 12 kW (sugerida)'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirmar_equipo')));
    await asentar(tester);

    // T3 del equipo nuevo: sin refrigerante todavía, categoría deducida.
    expect(find.text('Ficha del equipo'), findsOneWidget);
    expect(
      find.textContaining('Faltan el refrigerante y la carga'),
      findsOneWidget,
    );
    await verA(tester, find.text('R-32'));
    await tester.tap(find.text('R-32'));
    await asentar(tester);
    await verA(tester, find.byKey(const Key('ficha_carga')));
    await tester.tap(find.byKey(const Key('ficha_carga')));
    await asentar(tester);
    for (final t in ['8', ',', '0']) {
      await tester.tap(find.byKey(Key('tecla_$t')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('pad_aceptar')));
    await asentar(tester);
    // 8 kg de R-32 → 5,4 t: sujeto, cada 12 meses, sin control conocido.
    await verA(tester, find.byKey(const Key('bloque_fgas')), paso: -300);
    expect(
      find.textContaining('8 kg R-32 → 5,4 t CO2-eq · control cada 12 meses'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('guardar_ficha')));
    await asentar(tester);
    final nuevo = (await db.select(db.equipos).get()).firstWhere(
      (e) => e.refrigerante == 'R-32' && e.cargaKg == 8,
    );
    expect(nuevo.categoriaFgas?.wire, 'aire_acondicionado_bomba_calor');
    expect(nuevo.datosConfirmadosPor, DemoDatos.tecnicoId);

    await desmontar(tester, db);
  });

  testWidgets('T3 de un equipo con historia: último valor, F-gas y RITE', (
    tester,
  ) async {
    final db = await montar(tester);
    final hotel = DemoDatos.ordenes.firstWhere((o) => o.clave == 'hoy_hotel');
    await tester.tap(find.byKey(Key('orden_${hotel.id}')));
    await asentar(tester);
    await tester.tap(
      find.byKey(Key('equipo_${DemoDatos.equipo('hotel_vrf').id}')),
    );
    await asentar(tester);

    expect(
      find.textContaining(
        '12 kg R-410A → 25,05 t CO2-eq · control cada 12 meses · próximo',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Preventivo RITE cada 12 meses · próximo'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ultima_visita')), findsOneWidget);
    expect(
      find.textContaining('Temperatura del aire de retorno: 24,5 °C'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('aviso_potencia')), findsNothing);

    // Subir la potencia por encima de lo declarado → aviso «a revisar».
    await verA(tester, find.byKey(const Key('ficha_frio')), paso: 200);
    await tester.tap(find.byKey(const Key('ficha_frio')));
    await asentar(tester);
    await tester.tap(find.text('⌫'));
    await tester.tap(find.text('⌫'));
    for (final t in ['6', '0']) {
      await tester.tap(find.byKey(Key('tecla_$t')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('pad_aceptar')));
    await asentar(tester);
    await verA(tester, find.byKey(const Key('aviso_potencia')), paso: -200);
    expect(find.byKey(const Key('aviso_potencia')), findsOneWidget);

    await desmontar(tester, db);
  });

  testWidgets('la oficina de más de 70 kW lo dice en T2', (tester) async {
    final db = await montar(tester);
    final o = DemoDatos.ordenes.firstWhere((o) => o.clave == 'hoy_oficina');
    await tester.tap(find.byKey(Key('orden_${o.id}')));
    await asentar(tester);
    expect(find.byKey(const Key('aviso_70kw')), findsOneWidget);
    await desmontar(tester, db);
  });
}
