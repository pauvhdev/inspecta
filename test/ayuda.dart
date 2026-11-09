import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:inspecta/data/local/app_database.dart';
import 'package:inspecta/dominio/normativa.dart';
import 'package:inspecta/dominio/plantillas.dart' as dom;

// Utilidades compartidas por las pruebas del día 3.

Normativa leerNormativa() =>
    parsearNormativa(File('assets/normativa/2026-11.json').readAsStringSync());

List<dom.Plantilla> leerPlantillas() => [
  for (final f in Directory(
    'assets/plantillas',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.json')))
    dom.parsearPlantilla(f.readAsStringSync(), origen: f.path),
];

AppDatabase baseEnMemoria() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// Un martes a las 10:00 en UTC (11:00 en Madrid).
final ahoraFijo = DateTime.utc(2026, 11, 10, 9);
