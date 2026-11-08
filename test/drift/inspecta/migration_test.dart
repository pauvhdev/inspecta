// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:inspecta/data/local/app_database.dart';
import 'package:inspecta/data/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

// Pruebas de migración (DISEÑO.md §12, día 2). Los esquemas congelados están
// en `drift_schemas/inspecta/` (v1 = commit 724d3ec, día 1) y las clases de
// `generated/` las genera `dart run drift_dev make-migrations`.

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  // Desde cada versión guardada hasta cada una posterior, sin datos: el
  // esquema resultante tiene que ser idéntico al de una base nueva
  // (`validateDatabaseSchema`).
  group('migraciones sin datos', () {
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('desde $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('a $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // La 1→2 cambia el tipo de las fechas (segundos Unix → texto ISO-8601,
  // build.yaml): la cola puede tener cambios sin subir y perderlos sería
  // perder partes.
  final creada = DateTime.utc(2026, 11, 7, 18, 45, 12);
  final ultimoPull = DateTime.utc(2026, 11, 7, 18, 40);
  int unix(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

  test('1→2 conserva la cola, los cursores y los ajustes', () async {
    final antiguaCola = [
      v1.OutboxEntriesData(
        seq: 1,
        entity: 'inspecciones',
        op: 'upsert',
        rowId: 'insp1',
        payload: '{"id":"insp1","estado":"en_curso"}',
        createdAt: unix(creada),
        attempts: 2,
        lastError: 'timeout',
        isBlocked: 0,
      ),
      v1.OutboxEntriesData(
        seq: 2,
        entity: 'fotos',
        op: 'upsert',
        rowId: 'f1',
        payload: '{"id":"f1","inspeccion_id":"insp1"}',
        createdAt: unix(creada) + 1,
        attempts: 0,
        isBlocked: 1,
      ),
    ];
    final nuevaCola = [
      v2.OutboxEntriesData(
        seq: 1,
        entity: 'inspecciones',
        op: 'upsert',
        rowId: 'insp1',
        payload: '{"id":"insp1","estado":"en_curso"}',
        createdAt: '2026-11-07T18:45:12.000Z',
        attempts: 2,
        lastError: 'timeout',
        isBlocked: 0,
        esperandoHijos: 0,
      ),
      v2.OutboxEntriesData(
        seq: 2,
        entity: 'fotos',
        op: 'upsert',
        rowId: 'f1',
        payload: '{"id":"f1","inspeccion_id":"insp1"}',
        createdAt: '2026-11-07T18:45:13.000Z',
        attempts: 0,
        isBlocked: 1,
        esperandoHijos: 0,
      ),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.outboxEntries, antiguaCola);
        batch.insertAll(oldDb.syncCursors, [
          v1.SyncCursorsData(entity: 'equipos', lastPulledAt: unix(ultimoPull)),
          const v1.SyncCursorsData(entity: 'fotos'),
        ]);
        batch.insertAll(oldDb.appSettings, [
          const v1.AppSettingsData(key: 'tema', value: 'sotano'),
        ]);
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.outboxEntries).get(), nuevaCola);
        expect(await newDb.select(newDb.syncCursors).get(), [
          const v2.SyncCursorsData(
            entity: 'equipos',
            lastPulledAt: '2026-11-07T18:40:00.000Z',
          ),
          const v2.SyncCursorsData(entity: 'fotos'),
        ]);
        expect(await newDb.select(newDb.appSettings).get(), [
          const v2.AppSettingsData(key: 'tema', value: 'sotano'),
        ]);
        // Las tablas nuevas nacen vacías.
        expect(await newDb.select(newDb.inspecciones).get(), isEmpty);
      },
    );
  });

  test(
    'tras migrar, la app lee las fechas y la cola sigue funcionando',
    () async {
      final schema = await verifier.schemaAt(1);
      schema.rawDatabase.execute(
        'INSERT INTO outbox_entries '
        '(entity, op, row_id, payload, created_at, attempts, is_blocked) '
        "VALUES ('inspecciones', 'upsert', 'insp1', '{}', ?, 0, 0)",
        [unix(creada)],
      );
      schema.rawDatabase.execute(
        'INSERT INTO sync_cursors (entity, last_pulled_at) VALUES (?, ?)',
        ['equipos', unix(ultimoPull)],
      );

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);

      final entrada = await db.select(db.outboxEntries).getSingle();
      expect(entrada.createdAt, creada);
      expect(entrada.esperandoHijos, isFalse);
      final cursor = await db.select(db.syncCursors).getSingle();
      expect(cursor.lastPulledAt, ultimoPull);

      // La entrada migrada se puede coalescer y sacar de la cola como siempre.
      final outbox = Outbox(db);
      await outbox.enqueueUpsert(
        entity: 'inspecciones',
        rowId: 'insp1',
        payload: {'id': 'insp1', 'estado': 'lista'},
      );
      expect(await db.select(db.outboxEntries).get(), hasLength(1));

      // Y las tablas del dominio ya están.
      await db
          .into(db.empresas)
          .insert(
            EmpresasCompanion.insert(
              id: 'e1',
              empresaId: 'e1',
              razonSocial: 'Climas Norte SL',
            ),
          );
      expect(await db.select(db.empresas).get(), hasLength(1));
    },
  );
}
