import 'package:drift/drift.dart';

import '../../dominio/plantillas.dart' as dom;
import 'app_database.dart';

/// Copia en Drift las plantillas base del bundle (`assets/plantillas/`).
///
/// En la nube bajan por el pull (§8.2); en modo local no hay servidor y sin
/// estas filas las órdenes y las respuestas apuntarían a plantillas e ítems
/// que no existen en el aparato. Las publicadas son inmutables y sus ids son
/// deterministas (UUID v5, `plantillas.dart`): `insertOrIgnore` deja como
/// está lo que ya hubiera (la misma fila, o la que bajó del servidor).
/// No se encola: el servidor siembra las suyas (`tool/siembra_nube.sql`).
Future<void> sembrarPlantillasBase(
  AppDatabase db,
  List<dom.Plantilla> plantillas,
) async {
  await db.batch((b) {
    for (final p in plantillas) {
      final marcas = {
        'created_at': p.publicadaAt.toUtc().toIso8601String(),
        'updated_at': p.publicadaAt.toUtc().toIso8601String(),
      };
      b.insert(
        db.plantillas,
        Plantilla.fromJson({...p.toJson(), ...marcas}),
        mode: InsertMode.insertOrIgnore,
      );
      for (final i in p.items) {
        b.insert(
          db.itemsPlantilla,
          ItemPlantilla.fromJson({...i.toJson(), ...marcas}),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }
  });
}
