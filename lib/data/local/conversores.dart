import 'dart:convert';

import 'package:drift/drift.dart';

import '../../dominio/tipos.dart';
import '../sync/codecs.dart';

// Conversores de columna de Drift.
//
// Todos implementan `JsonTypeConverter2`: así el `toJson`/`fromJson` que genera
// Drift ya habla el formato de PostgREST columna a columna, y el mapper
// genérico (`lib/data/sync/mapper.dart`) no necesita una lista de excepciones
// por tabla (DISEÑO.md §8.2, «Mappers Drift↔Postgres»). Lo que distingue un
// `jsonb`, un `date` o un enum vive en la definición de la tabla, junto a la
// columna, que es donde se mira cuando se cambia.

/// Columna `jsonb` de Postgres guardada como texto JSON en SQLite.
///
/// En Dart la fila guarda el texto tal cual (lo decodifica quien lo usa). Hacia
/// PostgREST sale **decodificado** (mapa, lista o escalar): si se mandara la
/// cadena, Postgres guardaría un `jsonb` de tipo string con el JSON escapado
/// dentro. Desde PostgREST llega ya decodificado y se vuelve a codificar.
///
/// Siempre `jsonEncode`, también si llega un `String`: un `jsonb` cuyo valor
/// es la cadena `"R-32"` (p. ej. `decisiones_ia.valor_final_json`, «lo que el
/// técnico dejó», §7.6) llega como el `String` de Dart `R-32`. Guardarlo tal
/// cual dejaría en la columna un texto que no es JSON y la fila ya no se
/// podría volver a subir (`jsonDecode` fallaría en [toJson]).
class Jsonb extends TypeConverter<String, String>
    with JsonTypeConverter2<String, String, Object?> {
  const Jsonb();

  @override
  String fromSql(String fromDb) => fromDb;

  @override
  String toSql(String value) => value;

  @override
  Object? toJson(String value) => jsonDecode(value);

  /// Drift solo llama aquí con null en columnas **no nulas** (en las nulas
  /// envuelve el conversor con `asNullable`, que deja null en null). Ahí un
  /// null es una clave ausente (un `select` de unas pocas columnas) o un
  /// servidor que no cumple el esquema: inventar `{}` pisaría el valor local
  /// con `insertOnConflictUpdate` o haría pasar unas `incidencias_abiertas_json`
  /// desconocidas por «ninguna abierta». Falla como cualquier otra columna no
  /// nula (`mapper.dart` lo convierte en un error con la tabla y la fila).
  @override
  String fromJson(Object? json) {
    if (json == null) {
      throw const FormatException('jsonb nulo o ausente en columna no nula');
    }
    return jsonEncode(json);
  }
}

/// Columna `date` de Postgres (sin hora): vencimientos, fechas declaradas,
/// la fecha prevista de una orden.
///
/// Se guarda como medianoche **UTC** del día y viaja como `AAAA-MM-DD`. Si se
/// tratara como un instante, `toIso8601String` en UTC movería al día anterior
/// todo lo que se guardó a medianoche local en España (UTC+1/+2), y una
/// revisión del martes vencería el lunes (mismo motivo que `toDate` en
/// `codecs.dart`). Medianoche UTC y no local para que, con las fechas
/// guardadas como texto, todas las filas lleven el mismo sufijo `Z` y se
/// ordenen bien también con `ORDER BY` (que compara el texto).
class SoloFecha extends TypeConverter<DateTime, DateTime>
    with JsonTypeConverter2<DateTime, DateTime, Object?> {
  const SoloFecha();

  static DateTime _dia(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  @override
  DateTime fromSql(DateTime fromDb) => _dia(fromDb);

  @override
  DateTime toSql(DateTime value) => _dia(value);

  @override
  Object? toJson(DateTime value) => toDate(value);

  @override
  DateTime fromJson(Object? json) {
    if (json is DateTime) return _dia(json);
    // `AAAA-MM-DD` se lee por componentes: `DateTime.parse` lo daría en hora
    // local y `_dia` lo dejaría igual, pero así no depende de la zona del móvil.
    final s = json.toString();
    final soloDia = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (soloDia != null) {
      return DateTime.utc(
        int.parse(soloDia.group(1)!),
        int.parse(soloDia.group(2)!),
        int.parse(soloDia.group(3)!),
      );
    }
    return _dia(DateTime.parse(s));
  }
}

/// `equipos.tipo` con su código wire (DISEÑO.md §7.2).
class ConversorTipoEquipo extends TypeConverter<TipoEquipo, String>
    with JsonTypeConverter2<TipoEquipo, String, String> {
  const ConversorTipoEquipo();

  @override
  TipoEquipo fromSql(String fromDb) => TipoEquipo.desde(fromDb);

  @override
  String toSql(TipoEquipo value) => value.wire;

  @override
  TipoEquipo fromJson(String json) => TipoEquipo.desde(json);

  @override
  String toJson(TipoEquipo value) => value.wire;
}

/// `equipos.categoria_fgas` con su código wire (DISEÑO.md §7.2).
class ConversorCategoriaFgas extends TypeConverter<CategoriaFgas, String>
    with JsonTypeConverter2<CategoriaFgas, String, String> {
  const ConversorCategoriaFgas();

  @override
  CategoriaFgas fromSql(String fromDb) => CategoriaFgas.desde(fromDb);

  @override
  String toSql(CategoriaFgas value) => value.wire;

  @override
  CategoriaFgas fromJson(String json) => CategoriaFgas.desde(json);

  @override
  String toJson(CategoriaFgas value) => value.wire;
}

/// `instalaciones.uso_edificio` con su código wire (DISEÑO.md §7.2).
class ConversorUsoEdificio extends TypeConverter<UsoEdificio, String>
    with JsonTypeConverter2<UsoEdificio, String, String> {
  const ConversorUsoEdificio();

  @override
  UsoEdificio fromSql(String fromDb) => UsoEdificio.desde(fromDb);

  @override
  String toSql(UsoEdificio value) => value.wire;

  @override
  UsoEdificio fromJson(String json) => UsoEdificio.desde(json);

  @override
  String toJson(UsoEdificio value) => value.wire;
}
