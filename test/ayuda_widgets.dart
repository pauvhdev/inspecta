import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/app/app.dart';
import 'package:inspecta/app/providers.dart';
import 'package:inspecta/data/local/app_database.dart';
import 'package:inspecta/design/tokens.dart';
import 'package:inspecta/dominio/normativa.dart';
import 'package:inspecta/dominio/plantillas.dart' as dom;

import 'ayuda.dart';

// Utilidades de las pruebas de widgets de la app del técnico.

/// Monta la app en modo demo sobre una base en memoria, a 360 × 1600 dp.
Future<AppDatabase> montarDemo(
  WidgetTester tester, {
  required Normativa normativa,
  required List<dom.Plantilla> plantillas,
}) async {
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

/// Deja pasar las escrituras en Drift, los streams y las animaciones (la
/// transición de página de Android dura más de medio segundo).
Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Desplaza la lista de la pantalla de delante hasta [f].
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

/// Comprueba que todo objetivo táctil visible de la pantalla de delante mide
/// 56 dp o más en alto y en ancho (DISEÑO.md §6.0, `tactil_56dp_test`).
/// Devuelve cuántos ha medido, para que la prueba falle si no ve ninguno.
int comprobarObjetivos56(WidgetTester tester, String pantalla) {
  final pequenos = <String>[];
  var medidos = 0;
  final pantallaRect = tester.getRect(find.byType(MaterialApp));
  for (final tipo in [ButtonStyleButton, IconButton, InkWell, Checkbox]) {
    for (final e
        in find
            .byWidgetPredicate(
              (w) => tipo == ButtonStyleButton
                  ? w is ButtonStyleButton
                  : w.runtimeType == tipo,
            )
            .evaluate()) {
      final box = e.renderObject;
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final r = box.localToGlobal(Offset.zero) & box.size;
      if (!r.overlaps(pantallaRect)) continue;
      // Los InkWell internos de un botón ya cuentan como el botón.
      if (tipo == InkWell &&
          e.findAncestorWidgetOfExactType<ButtonStyleButton>() != null) {
        continue;
      }
      medidos++;
      if (r.height < Touch.min - 0.01 || r.width < Touch.min - 0.01) {
        pequenos.add('${e.widget.runtimeType} ${e.widget.key ?? ''} ${r.size}');
      }
    }
  }
  expect(pequenos, isEmpty, reason: '$pantalla: objetivos de menos de 56 dp');
  expect(medidos, greaterThan(0), reason: '$pantalla: no se midió nada');
  return medidos;
}
