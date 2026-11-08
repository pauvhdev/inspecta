import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// Base de datos local de Inspecta.
//
// Drift es la fuente de verdad en el móvil: la app lee y escribe siempre aquí,
// con o sin cobertura, y el motor de sincronización sube y baja a Supabase
// cuando hay red (DISEÑO.md §8.2). Las tablas del dominio (empresas, equipos,
// órdenes, inspecciones…) llegan el día 2; de momento solo está la
// infraestructura de sincronización, que viene de Forja.

/// Cola de salida: cada cambio local que falta subir.
class OutboxEntries extends Table {
  IntColumn get seq => integer().autoIncrement()();

  /// Nombre de la tabla en Postgres, p. ej. 'inspecciones'.
  TextColumn get entity => text()();

  /// 'upsert' o 'delete'.
  TextColumn get op => text()();

  TextColumn get rowId => text()();

  /// Fila completa serializada en JSON, tal cual la espera PostgREST.
  TextColumn get payload => text()();

  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  /// Un error 4xx no se arregla reintentando (RLS, validación, sesión
  /// cerrada). Se marca y se saca de la cola para que no la atasque.
  BoolColumn get isBlocked => boolean().withDefault(const Constant(false))();
}

/// Hasta dónde llegó el último pull de cada tabla.
@DataClassName('SyncCursor')
class SyncCursors extends Table {
  TextColumn get entity => text()();
  DateTimeColumn get lastPulledAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {entity};
}

/// Preferencias de este aparato (tema, modo guantes, rúbrica, serie de
/// numeración…). No se sincronizan: son del móvil, no de la cuenta.
@DataClassName('LocalSetting')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [OutboxEntries, SyncCursors, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'inspecta', web: _web));

  /// En el navegador sqlite corre compilado a WebAssembly dentro de un worker.
  /// Los dos ficheros van en `web/` y se sirven junto a la app; sin ellos
  /// drift no arranca.
  static final _web = DriftWebOptions(
    sqlite3Wasm: Uri.parse('sqlite3.wasm'),
    driftWorker: Uri.parse('drift_worker.js'),
  );

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (m) async => m.createAll());
}
