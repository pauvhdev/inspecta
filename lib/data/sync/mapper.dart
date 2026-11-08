/// Mapper genérico entre las filas de Drift y el JSON de PostgREST.
///
/// DISEÑO.md §8.2, «Mappers Drift↔Postgres»: en vez de escribir a mano un
/// mapper por tabla (Forja tiene 388 líneas para 11), las clases de datos que
/// genera Drift ya traen `toJson`/`fromJson`, y con
/// `use_sql_column_name_as_json_key` (build.yaml) sus claves son los nombres
/// de columna SQL, que son los de Postgres (§7, «Convenciones»). Aquí solo
/// queda lo que no sabe Drift:
///
/// - **Tipos de PostgREST** ([SerializadorPostgrest]): instantes en ISO-8601
///   UTC hacia el servidor y con offset desde él, `numeric` que llega como
///   cadena, `bigint` que puede llegar como cadena.
/// - **jsonb, `date` y enums** los resuelven los conversores de columna
///   (`lib/data/local/conversores.dart`), que viven junto a cada columna.
/// - **Excepciones explícitas** ([columnasSoloServidor], [tablasSoloBajada]).
///
/// La prueba de ida y vuelta de todas las tablas está en
/// `test/mapper_test.dart`.
library;

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import 'codecs.dart';

/// Lee y escribe los tipos tal como los habla PostgREST.
///
/// Drift llama a [toJson]/[fromJson] columna a columna con el tipo de la
/// columna (el SQL o, si tiene conversor, el JSON del conversor).
class SerializadorPostgrest extends ValueSerializer {
  const SerializadorPostgrest();

  @override
  T fromJson<T>(dynamic json) {
    // Un nulo en una columna no nula falla aquí, con un `TypeError`: es mejor
    // que inventar un valor (ver `tablas/comunes.dart`, «Nulos»).
    if (json == null) return null as T;

    // Truco de Drift (`_DefaultValueSerializer`) para preguntar por `T` sin
    // perder la nulabilidad: `<double>[]` es `List<double?>`, `<Object?>[]`
    // no lo es.
    final tipo = <T>[];

    if (tipo is List<DateTime?>) {
      if (json is DateTime) return json.toUtc() as T;
      // `timestamptz` llega con offset (`2026-11-08T09:30:00.123456+00:00`).
      // Se guarda en UTC: si cada fila llevara la hora local del móvil,
      // `ORDER BY` sobre el texto las ordenaría mal (`tablas/comunes.dart`) y
      // `DateTime.==` diría que dos instantes iguales son distintos.
      return DateTime.parse(json.toString()).toUtc() as T;
    }
    // `numeric` llega como cadena para no perder precisión, o como número.
    if (tipo is List<double?>) return _o<T>(asDouble(json), json);
    // `bigint` puede llegar como cadena. Un número con decimales en una
    // columna entera es un error, no se trunca (`asInt` haría `toInt`).
    if (tipo is List<int?>) {
      if (json is double && json != json.truncateToDouble()) {
        throw FormatException('Valor con decimales para $T', json);
      }
      return _o<T>(asInt(json), json);
    }
    if (tipo is List<bool?>) return _bool(json) as T;
    if (tipo is List<String?> && json is! String) {
      // Un `jsonb` en una columna de texto sin conversor (no debería haber
      // ninguna) se guarda como JSON, no como el `toString` de un mapa.
      return (json is Map || json is List ? asJsonText(json, '') : '$json')
          as T;
    }
    return json as T;
  }

  /// Solo lo que puede mandar Postgres por un `boolean`. `asBool` de
  /// codecs.dart da `false` para cualquier otra cosa (`'quizas'`), y un
  /// `para_equipo` o una `reciclado_declaracion` inventados son peores que una
  /// fila que no baja.
  static bool _bool(Object json) => switch (json) {
    bool b => b,
    0 || '0' || 'f' || 'false' => false,
    1 || '1' || 't' || 'true' => true,
    _ => throw FormatException('Valor inesperado de PostgREST para bool', json),
  };

  /// Si la conversión falla, el error tiene que nombrar el valor recibido, no
  /// convertirse en un nulo silencioso.
  static T _o<T>(Object? convertido, Object json) {
    if (convertido == null) {
      throw FormatException('Valor inesperado de PostgREST para $T', json);
    }
    return convertido as T;
  }

  @override
  dynamic toJson<T>(T value) {
    // Siempre en UTC (`toTimestamp` de codecs.dart): Postgres lo guarda como
    // instante y así no depende de la zona del móvil.
    if (value is DateTime) return toTimestamp(value);
    return value;
  }
}

/// El serializador que usan [aJsonPostgrest] y [desdeJsonPostgrest].
const serializadorPostgrest = SerializadorPostgrest();

/// Columnas que nunca se suben porque las pone el servidor.
///
/// `inspecciones.sincronizada_at` la escribe el servidor (§7.5) y es lo único
/// que `inspecciones_lock` deja cambiar tras la firma (§7.10.2). La cola sube
/// la fila entera (`upsert(payload)`): si viajara, el móvil, que no la conoce,
/// la devolvería a null cada vez que reenvía la inspección.
///
/// `ordenes_trabajo.estado` sí viaja: la protege el trigger
/// `orden_estado_protegido`, y la oficina la necesita para cancelar (§7.5).
const columnasSoloServidor = <String, Set<String>>{
  'inspecciones': {'sincronizada_at'},
};

/// Tablas que el móvil solo baja: no tienen política de escritura para
/// `authenticated` y subirlas siempre acabaría bloqueado en la cola.
///
/// - `dispositivos`: la crea la RPC `registrar_dispositivo()` (§7.1).
/// - `estado_equipo`: solo la escribe un trigger (§7.2); la app la recalcula
///   en local al firmar, pero no la encola.
/// - `propuestas_ia`: la escribe la Edge Function con `service_role` (§7.6).
/// - `ordenes_sugeridas`: vacía en el MVP y «sin escritura para
///   `authenticated`» (§7.5, §8.5), tampoco para la oficina. Sale de aquí
///   cuando llegue §4.2 A, que le da a la oficina el cambio de `estado`.
///
/// [A VERIFICAR] `empresas` sí se puede subir (la edita el admin en el panel);
/// §8.5 no le da política de escritura y tendrá que decidirla.
const tablasSoloBajada = {
  'dispositivos',
  'estado_equipo',
  'propuestas_ia',
  'ordenes_sugeridas',
};

/// Tablas de §7.7 que solo existen en el dispositivo.
const tablasLocales = {
  'blobs',
  'trabajos_ia',
  'contadores_informe',
  'outbox_entries',
  'sync_cursors',
  'app_settings',
};

/// Cómo construir la clase de datos de cada tabla sincronizada desde JSON.
///
/// Es lo único que hay que tocar al añadir una tabla: Drift no expone un
/// `fromJson` genérico en `TableInfo`. `test/mapper_test.dart` comprueba que
/// están todas las tablas de la base salvo [tablasLocales].
final Map<String, DataClass Function(Map<String, dynamic>, ValueSerializer)>
constructoresDesdeJson = {
  // §7.1
  'empresas': (j, s) => Empresa.fromJson(j, serializer: s),
  'miembros': (j, s) => Miembro.fromJson(j, serializer: s),
  'dispositivos': (j, s) => Dispositivo.fromJson(j, serializer: s),
  // §7.2
  'clientes': (j, s) => Cliente.fromJson(j, serializer: s),
  'instalaciones': (j, s) => Instalacion.fromJson(j, serializer: s),
  'equipos': (j, s) => Equipo.fromJson(j, serializer: s),
  'estado_equipo': (j, s) => EstadoDeEquipo.fromJson(j, serializer: s),
  // §7.4
  'plantillas': (j, s) => Plantilla.fromJson(j, serializer: s),
  'items_plantilla': (j, s) => ItemPlantilla.fromJson(j, serializer: s),
  // §7.5
  'ordenes_trabajo': (j, s) => OrdenTrabajo.fromJson(j, serializer: s),
  'orden_equipos': (j, s) => OrdenEquipo.fromJson(j, serializer: s),
  'ordenes_sugeridas': (j, s) => OrdenSugerida.fromJson(j, serializer: s),
  'inspecciones': (j, s) => Inspeccion.fromJson(j, serializer: s),
  'inspeccion_equipos': (j, s) => InspeccionEquipo.fromJson(j, serializer: s),
  'respuestas': (j, s) => Respuesta.fromJson(j, serializer: s),
  'incidencias': (j, s) => Incidencia.fromJson(j, serializer: s),
  'incidencia_fotos': (j, s) => IncidenciaFoto.fromJson(j, serializer: s),
  'resoluciones_incidencia': (j, s) =>
      ResolucionIncidencia.fromJson(j, serializer: s),
  'controles_fugas': (j, s) => ControlFugas.fromJson(j, serializer: s),
  'movimientos_gas': (j, s) => MovimientoGas.fromJson(j, serializer: s),
  'fotos': (j, s) => Foto.fromJson(j, serializer: s),
  'notas_voz': (j, s) => NotaVoz.fromJson(j, serializer: s),
  'firmas': (j, s) => Firma.fromJson(j, serializer: s),
  'comparticiones': (j, s) => Comparticion.fromJson(j, serializer: s),
  // §7.6
  'propuestas_ia': (j, s) => PropuestaIa.fromJson(j, serializer: s),
  'decisiones_ia': (j, s) => DecisionIa.fromJson(j, serializer: s),
};

/// Fila de Drift → JSON para el `upsert` de PostgREST (el payload de la cola).
///
/// [tabla] es el nombre en Postgres (`entity` de la cola). Las claves son los
/// nombres de columna SQL; quita [columnasSoloServidor] y rechaza las
/// [tablasSoloBajada], que no se suben nunca. No poda los nulos: la cola sube
/// la fila entera y un null es la forma de vaciar un campo.
Map<String, dynamic> aJsonPostgrest(String tabla, DataClass fila) {
  if (tablasSoloBajada.contains(tabla)) {
    throw ArgumentError.value(tabla, 'tabla', 'Solo baja: no se sube');
  }
  if (!constructoresDesdeJson.containsKey(tabla)) {
    throw ArgumentError.value(tabla, 'tabla', 'No es una tabla sincronizada');
  }
  final json = fila.toJson(serializer: serializadorPostgrest);
  for (final columna in columnasSoloServidor[tabla] ?? const <String>{}) {
    json.remove(columna);
  }
  return json;
}

/// JSON de PostgREST (una fila de un `select`) → clase de datos de Drift,
/// lista para `insertOnConflictUpdate`.
///
/// [D] es la clase de datos de [tabla], p. ej.
/// `desdeJsonPostgrest<Foto>('fotos', json)`. Las claves que Drift no conoce
/// se ignoran. Cualquier valor que no se puede leer (una columna no nula que
/// falta o llega null, un número o un bool ilegibles, un enum que esta versión
/// de la app no conoce) falla con una [FormatException] que nombra la tabla y
/// el `id` de la fila: cada conversor lanza lo suyo (`TypeError` en un null,
/// `FormatException` en el serializador y en `Jsonb`, `ArgumentError` en los
/// `desde` de `tipos.dart`), y quien sincroniza solo tiene que capturar una.
D desdeJsonPostgrest<D extends DataClass>(
  String tabla,
  Map<String, dynamic> json,
) {
  final constructor = constructoresDesdeJson[tabla];
  if (constructor == null) {
    throw ArgumentError.value(tabla, 'tabla', 'No es una tabla sincronizada');
  }
  try {
    return constructor(json, serializadorPostgrest) as D;
  } on Object catch (e) {
    if (e is! TypeError && e is! FormatException && e is! ArgumentError) {
      rethrow;
    }
    throw FormatException('Fila de $tabla no válida (${json['id']}): $e');
  }
}

/// Lo mismo para una página entera del pull. Una fila ilegible hace fallar
/// la página con el error de esa fila (tabla e `id`): saltársela en silencio
/// dejaría a reconcile creer que no existe en el servidor.
List<D> desdeJsonPostgrestLista<D extends DataClass>(
  String tabla,
  List<dynamic> filas,
) => [
  for (final f in filas)
    desdeJsonPostgrest<D>(tabla, (f as Map).cast<String, dynamic>()),
];

/// Una tabla de [AppDatabase] por su nombre SQL (el `entity` de la cola).
TableInfo<Table, DataClass>? tablaPorNombre(AppDatabase db, String nombre) {
  for (final t in db.allTables) {
    if (t.actualTableName == nombre) return t as TableInfo<Table, DataClass>;
  }
  return null;
}
