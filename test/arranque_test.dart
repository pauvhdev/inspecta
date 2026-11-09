import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/app/app.dart';
import 'package:inspecta/app/providers.dart';
import 'package:inspecta/data/repositories/inspeccion_repository.dart';

void main() {
  testWidgets('la base que no abre no deja un «cargando» infinito', (
    tester,
  ) async {
    // Un stream que nunca emite: como un navegador sin SharedWorker.
    final nunca = StreamController<int>();
    final nuncaOrdenes = StreamController<List<TarjetaOrden>>();
    addTearDown(nunca.close);
    addTearDown(nuncaOrdenes.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pendientesDeSubirProvider.overrideWith((ref) => nunca.stream),
          ordenesHoyProvider.overrideWith((ref) => nuncaOrdenes.stream),
        ],
        child: const InspectaApp(),
      ),
    );

    expect(find.text('Abriendo la base de datos local…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 11));

    expect(find.text('Abriendo la base de datos local…'), findsNothing);
    expect(find.textContaining('no termina de abrir'), findsOneWidget);
  });

  testWidgets(
    'con la base abierta, Hoy y la píldora con los cambios sin subir',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pendientesDeSubirProvider.overrideWith((ref) => Stream.value(3)),
            ordenesHoyProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: const InspectaApp(),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('pildora_sync')), findsOneWidget);
      expect(find.text('Modo local · 3 sin subir'), findsOneWidget);
      // Modo local sin demo: Hoy explica cómo ver la demo, no se queda vacío.
      expect(find.byKey(const Key('hoy_vacio')), findsOneWidget);

      // El reloj vence sin cambiar nada: ya no se está cargando.
      await tester.pump(const Duration(seconds: 11));
      expect(find.textContaining('no termina de abrir'), findsNothing);
    },
  );
}
