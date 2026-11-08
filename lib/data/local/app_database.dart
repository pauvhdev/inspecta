import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../dominio/tipos.dart';
import 'app_database.steps.dart';
import 'conversores.dart';
import 'tablas/activos.dart';
import 'tablas/ia.dart';
import 'tablas/locales.dart';
import 'tablas/organizacion.dart';
import 'tablas/plantillas.dart';
import 'tablas/trabajo.dart';

export 'tablas/activos.dart';
export 'tablas/ia.dart';
export 'tablas/locales.dart';
export 'tablas/organizacion.dart';
export 'tablas/plantillas.dart';
export 'tablas/trabajo.dart';

part 'app_database.g.dart';

// Base de datos local de Inspecta.
//
// Drift es la fuente de verdad en el móvil: la app lee y escribe siempre aquí,
// con o sin cobertura, y el motor de sincronización sube y baja a Supabase
// cuando hay red (DISEÑO.md §8.2). Las tablas del dominio están en `tablas/`
// (una por apartado de §7) y las reglas comunes del esquema, en
// `tablas/comunes.dart`. Aquí queda la infraestructura de sincronización,
// que viene de Forja.

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

  /// Cierre aparcado por `cierre_incompleto` (`IC001`): espera a que suban los
  /// hijos de su inspección sin gastar intentos ni parar la cola (§8.2).
  BoolColumn get esperandoHijos =>
      boolean().withDefault(const Constant(false))();
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

@DriftDatabase(
  tables: [
    // §7.1 Organización
    Empresas,
    Miembros,
    Dispositivos,
    // §7.2 Clientes y activos
    Clientes,
    Instalaciones,
    Equipos,
    EstadoEquipo,
    // §7.4 Plantillas
    Plantillas,
    ItemsPlantilla,
    // §7.5 Trabajo
    OrdenesTrabajo,
    OrdenEquipos,
    OrdenesSugeridas,
    Inspecciones,
    InspeccionEquipos,
    Respuestas,
    Incidencias,
    IncidenciaFotos,
    ResolucionesIncidencia,
    ControlesFugas,
    MovimientosGas,
    Fotos,
    NotasVoz,
    Firmas,
    Comparticiones,
    // §7.6 IA
    PropuestasIa,
    DecisionesIa,
    // §7.7 Solo locales
    Blobs,
    TrabajosIa,
    ContadoresInforme,
    OutboxEntries,
    SyncCursors,
    AppSettings,
  ],
)
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

  /// Cada versión publicada queda guardada en `drift_schemas/` y la prueba de
  /// `test/drift/inspecta/migration_test.dart` migra desde todas ellas. Tras
  /// cambiar una tabla: subir la versión, `dart run build_runner build`,
  /// `dart run drift_dev make-migrations` y escribir el paso `fromXToY`.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: stepByStep(from1To2: _de1a2),
  );

  /// v1 (día 1) → v2 (día 2): el dominio de §7 y las tablas locales.
  ///
  /// Se usa el esquema congelado de la v2 ([Schema2]) y no las tablas de hoy:
  /// cuando llegue la v3, este paso tiene que seguir creando la v2.
  static Future<void> _de1a2(Migrator m, Schema2 schema) async {
    const deLaV1 = {'outbox_entries', 'sync_cursors', 'app_settings'};

    // Tablas nuevas y, después, sus índices (un índice necesita su tabla).
    for (final tabla in schema.entities.whereType<TableInfo>()) {
      if (!deLaV1.contains(tabla.actualTableName)) await m.createTable(tabla);
    }
    for (final indice in schema.entities.whereType<Index>()) {
      await m.createIndex(indice);
    }

    // La v1 guardaba las fechas en segundos Unix (INTEGER); desde la v2 van
    // como texto ISO-8601 (build.yaml). SQLite no cambia el tipo de una
    // columna: `alterTable` copia la tabla convirtiendo el valor, a UTC con
    // `Z`, que es como Drift guarda un DateTime UTC. La cola puede tener
    // cambios sin subir: perderlos sería perder partes.
    String isoDesdeUnix(String columna) =>
        "strftime('%Y-%m-%dT%H:%M:%fZ', $columna, 'unixepoch')";

    await m.alterTable(
      TableMigration(
        schema.outboxEntries,
        columnTransformer: {
          schema.outboxEntries.createdAt: CustomExpression<String>(
            isoDesdeUnix('created_at'),
          ),
        },
        // `esperando_hijos` nace en false para lo que ya estaba en la cola.
        newColumns: [schema.outboxEntries.esperandoHijos],
      ),
    );
    await m.alterTable(
      TableMigration(
        schema.syncCursors,
        columnTransformer: {
          schema.syncCursors.lastPulledAt: CustomExpression<String>(
            isoDesdeUnix('last_pulled_at'),
          ),
        },
      ),
    );
  }
}
