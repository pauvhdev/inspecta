import 'package:drift/drift.dart';

// Columnas que llevan todas las tablas sincronizadas (DISEÑO.md §7,
// «Convenciones»; regla 6 de docs/REGLAS.md).
//
// Reglas del esquema local, válidas para todos los ficheros de `tablas/`:
//
// - **Mismos nombres que en Postgres.** El getter va en camelCase y Drift lo
//   pasa a snake_case (`nEquipos` → `n_equipos`); con
//   `use_sql_column_name_as_json_key` (build.yaml) ese nombre SQL es también
//   la clave JSON que viaja a PostgREST. `test/database_test.dart` compara
//   cada tabla con la lista de columnas de §7.
//
// - **Sin claves foráneas en Drift.** §8.2 solo exige que una fila encolada no
//   apunte a filas que nacen después (eso lo garantiza el orden de la cola y
//   el servidor, que sí las declara). En local, una FK haría más daño que
//   bien: el pull baja tabla a tabla y por páginas de 500, la ventana de 60
//   días deja hijos cuyo padre no se baja (una resolución de una incidencia
//   antigua, §7.5), y reconcile poda padres que salen de la ventana. Con
//   `PRAGMA foreign_keys` activo cualquiera de esos casos rompería el pull a
//   medias; sin él, declararlas no comprueba nada y solo engaña. Forja tampoco
//   las declara (`entity_mappers.dart`). Por lo mismo, **sin `unique` locales**
//   (p. ej. `miembros(empresa_id, serie_informes)`): un cambio de serie entre
//   dos técnicos puede bajar en el orden que haga chocar las dos filas. Esas
//   restricciones viven en `schema.sql` (día 9).
//
// - **Nulos.** No nulas solo la identidad, las referencias que definen la
//   fila y lo que sin valor deja la fila sin sentido; el resto, nulo. Si
//   Drift exige un valor que el servidor no exige, el pull de esa fila falla.
//   `schema.sql` (día 9) debe copiar esta nulabilidad [A VERIFICAR el día 9].
//
// - **Instantes en UTC.** Las fechas se guardan como texto ISO-8601
//   (`store_date_time_values_as_text`, build.yaml). Drift compara con
//   `julianday`, pero `ORDER BY` compara el texto: mezclar filas en UTC (`Z`)
//   con filas en hora local (`+01:00`) las ordenaría mal. El mapper ya deja en
//   UTC todo lo que baja; los repositorios deben escribir
//   `DateTime.now().toUtc()`.

/// `id` (UUID v4 generado en el cliente, `lib/core/ids.dart`), `created_at` y
/// `updated_at`.
///
/// `updated_at` lo reescribe el trigger `touch_updated_at` en el servidor y el
/// pull trae el bueno; el valor por defecto de aquí solo sirve para que la
/// fila recién creada en local tenga uno.
mixin FilaSincronizada on Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// `deleted_at`: borrado lógico, en las tablas que la oficina puede borrar
/// (DISEÑO.md §7, «Convenciones») y en `fotos` y `notas_voz`, que el técnico
/// borra antes de firmar (§6.0; ver `trabajo.dart`). El borrado tiene que
/// bajar por el pull incremental, que solo ve filas cambiadas: una fila
/// borrada de verdad no se entera nadie hasta el reconcile.
mixin BorradoLogico on Table {
  DateTimeColumn get deletedAt => dateTime().nullable()();
}
