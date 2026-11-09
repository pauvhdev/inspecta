import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/data/repositories/demo_datos.dart';
import 'package:inspecta/dominio/normativa.dart';
import 'package:inspecta/dominio/plantillas.dart' as dom;

import 'ayuda.dart';
import 'ayuda_widgets.dart';

// Objetivos táctiles de 56 dp o más (DISEÑO.md §6.0) en T1-T6, T10 y T11, y
// el flujo del día 4 con guantes: responder, deshacer, incidencia y bloqueo
// del art. 13.4 a pantalla completa. A 360 dp de ancho (móvil pequeño).

void main() {
  late Normativa normativa;
  late List<dom.Plantilla> plantillas;

  setUpAll(() {
    normativa = leerNormativa();
    plantillas = leerPlantillas();
  });

  testWidgets('T1-T6, T10 y T11: todo mide 56 dp o más', (tester) async {
    final db = await montarDemo(
      tester,
      normativa: normativa,
      plantillas: plantillas,
    );
    comprobarObjetivos56(tester, 'T1 Hoy');

    final hotel = DemoDatos.ordenes.firstWhere((o) => o.clave == 'hoy_hotel');
    await tester.tap(find.byKey(Key('orden_${hotel.id}')));
    await asentar(tester);
    comprobarObjetivos56(tester, 'T2 Visita sin empezar');

    // T3 Ficha (antes de empezar, abre la ficha).
    final vrf = DemoDatos.equipo('hotel_vrf').id;
    await tester.tap(find.byKey(Key('equipo_$vrf')));
    await asentar(tester);
    comprobarObjetivos56(tester, 'T3 Ficha');
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await asentar(tester);

    await tester.tap(find.byKey(const Key('empezar_visita')));
    await asentar(tester);
    comprobarObjetivos56(tester, 'T2 Visita en curso');

    // Añadir equipo (parte de T2).
    await tester.tap(find.byKey(const Key('anadir_equipo')));
    await asentar(tester);
    comprobarObjetivos56(tester, 'Añadir equipo');
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await asentar(tester);

    // T5 Checklist del VRF.
    await tester.tap(find.byKey(Key('equipo_$vrf')));
    await asentar(tester);
    expect(find.text('VRF · 1/24'), findsOneWidget);
    comprobarObjetivos56(tester, 'T5 Checklist');

    // Con guantes: OK → avanza solo y ofrece deshacer.
    await tester.tap(find.byKey(const Key('estado_ok')));
    await asentar(tester);
    expect(find.text('VRF · 2/24'), findsOneWidget);
    expect(find.textContaining('1 de 24 respondidos'), findsOneWidget);
    expect(find.byKey(const Key('deshacer')), findsOneWidget);
    comprobarObjetivos56(tester, 'T5 con «Deshacer»');
    await tester.tap(find.byKey(const Key('deshacer')));
    await asentar(tester);
    expect(find.textContaining('0 de 24 respondidos'), findsOneWidget);

    // Hasta la temperatura de retorno (ítem 17): referencia y T6.
    for (var i = 0; i < 15; i++) {
      await tester.tap(find.byKey(const Key('item_siguiente')));
      await tester.pump();
    }
    await asentar(tester);
    expect(find.text('Temperatura del aire de retorno'), findsOneWidget);
    expect(find.textContaining('Última vez: 24,5 °C'), findsOneWidget);
    await tester.tap(find.byKey(const Key('medir')));
    await asentar(tester);
    comprobarObjetivos56(tester, 'T6 Valor numérico');
    for (final t in ['4', '5']) {
      await tester.tap(find.byKey(Key('tecla_$t')));
      await tester.pump();
    }
    expect(
      find.byKey(const Key('pad_fuera_rango')),
      findsOneWidget,
      reason: '45 °C de retorno está fuera de 5-40: avisa, no bloquea',
    );
    await tester.tap(find.byKey(const Key('pad_aceptar')));
    await asentar(tester);
    expect(find.textContaining('45 °C'), findsWidgets);
    // Falta elegir el estado: no avanza.
    expect(find.text('VRF · 17/24'), findsOneWidget);
    await tester.tap(find.byKey(const Key('estado_defecto')));
    await asentar(tester);
    expect(
      find.text('VRF · 17/24'),
      findsOneWidget,
      reason: 'defecto no avanza',
    );

    // T10 Incidencia desde el defecto: la gravedad no viene elegida.
    await tester.tap(find.byKey(const Key('registrar_incidencia')));
    await asentar(tester);
    comprobarObjetivos56(tester, 'T10 Incidencia');
    expect(find.text('Elige la gravedad.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('gravedad_grave')));
    await asentar(tester);
    await tester.tap(find.byKey(const Key('guardar_incidencia')));
    await asentar(tester);
    expect(find.textContaining('Incidencias (1)'), findsOneWidget);
    expect(
      (await db.select(db.incidencias).get()).where(
        (i) => i.gravedad == 'grave',
      ),
      hasLength(1),
    );

    // T11 Gas: R-404A virgen en aire acondicionado → bloqueo a pantalla completa.
    await verA(tester, find.byKey(const Key('abrir_gas')));
    await tester.tap(find.byKey(const Key('abrir_gas')));
    await asentar(tester);
    comprobarObjetivos56(tester, 'T11 Gas');
    await tester.tap(find.byKey(const Key('nuevo_movimiento')));
    await asentar(tester);
    await verA(tester, find.text('R-404A'));
    await tester.tap(find.text('R-404A'));
    await asentar(tester);
    await verA(tester, find.byKey(const Key('gas_kg')));
    await tester.tap(find.byKey(const Key('gas_kg')));
    await asentar(tester);
    await tester.tap(find.byKey(const Key('tecla_2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pad_aceptar')));
    await asentar(tester);
    await verA(tester, find.text('Virgen'));
    await tester.tap(find.text('Virgen'));
    await asentar(tester);
    comprobarObjetivos56(tester, 'T11 Movimiento de gas');
    await tester.tap(find.byKey(const Key('guardar_movimiento')));
    await asentar(tester);
    expect(find.byKey(const Key('bloqueo_13_4')), findsOneWidget);
    expect(find.text('Reglamento (UE) 2024/573, art. 13.4'), findsOneWidget);
    comprobarObjetivos56(tester, 'T11 Bloqueo 13.4');
    expect(await db.select(db.movimientosGas).get(), isEmpty);
    await tester.tap(find.text('Volver y corregir'));
    await asentar(tester);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await asentar(tester);

    // Control de fugas con fuga reparada → ventana del nuevo control.
    await tester.tap(find.byKey(const Key('nuevo_control')));
    await asentar(tester);
    await tester.tap(find.text('Fuga'));
    await asentar(tester);
    await verA(tester, find.text('Sí'));
    await tester.tap(find.text('Sí'));
    await asentar(tester);
    await verA(tester, find.byKey(const Key('aviso_nuevo_control')));
    expect(
      find.textContaining('Nuevo control obligatorio (art. 4.5)'),
      findsOneWidget,
    );
    comprobarObjetivos56(tester, 'T11 Control de fugas');
    await tester.tap(find.byKey(const Key('guardar_control')));
    await asentar(tester);
    expect(
      (await db.select(db.controlesFugas).get()).where(
        (c) => c.reparada == true,
      ),
      hasLength(1),
    );

    await desmontar(tester, db);
  });
}
