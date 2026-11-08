import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/app/app.dart';
import 'package:inspecta/app/providers.dart';

void main() {
  testWidgets('la base que no abre no deja un «cargando» infinito', (
    tester,
  ) async {
    // Un stream que nunca emite: como un navegador sin SharedWorker.
    final nunca = StreamController<int>();
    addTearDown(nunca.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pendientesDeSubirProvider.overrideWith((ref) => nunca.stream),
        ],
        child: const InspectaApp(),
      ),
    );

    expect(find.text('Abriendo la base de datos local…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 11));

    expect(find.text('Abriendo la base de datos local…'), findsNothing);
    expect(find.textContaining('no termina de abrir'), findsOneWidget);
  });

  testWidgets('con la base abierta enseña los cambios sin subir', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pendientesDeSubirProvider.overrideWith((ref) => Stream.value(3)),
        ],
        child: const InspectaApp(),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('pendientes')), findsOneWidget);
    expect(find.text('Cambios sin subir: 3'), findsOneWidget);

    // El reloj vence sin cambiar nada: ya no se está cargando.
    await tester.pump(const Duration(seconds: 11));
    expect(find.textContaining('no termina de abrir'), findsNothing);
  });
}
