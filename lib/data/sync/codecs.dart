/// Conversiones entre los tipos de PostgREST y los de Dart.
///
/// PostgREST no es consistente con los numéricos: un `numeric` puede llegar
/// como número JSON o como cadena según el contexto. Estos helpers absorben
/// esa variabilidad en un solo sitio en vez de repartir `is String` por todo
/// el código de mapeo.
library;

import 'dart:convert';

double? asDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

bool asBool(Object? v, {bool fallback = false}) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == 't' || v == '1';
  return fallback;
}

String? asString(Object? v) => v?.toString();

/// `jsonb` o `text[]` → el JSON en texto que guarda la columna local. Llega
/// ya decodificado (lista o mapa); si no llega, [vacio].
String asJsonText(Object? v, String vacio) {
  if (v == null) return vacio;
  if (v is String) return v;
  return jsonEncode(v);
}

/// `timestamptz` → DateTime local. Postgres lo manda en UTC con offset.
DateTime? asTimestamp(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return DateTime.tryParse(s)?.toLocal();
}

DateTime asTimestampOr(Object? v, DateTime fallback) =>
    asTimestamp(v) ?? fallback;

/// `date` (sin hora) → DateTime a medianoche local.
DateTime? asDate(Object? v) {
  if (v == null) return null;
  final parsed = DateTime.tryParse(v.toString());
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// DateTime → `timestamptz`. Siempre en UTC: dejar que cada móvil mande su
/// hora local sería la receta perfecta para un histórico desordenado.
String? toTimestamp(DateTime? v) => v?.toUtc().toIso8601String();

/// DateTime → `date`. Aquí NO se convierte a UTC a propósito: "la revisión del
/// martes" es el martes del cliente. Pasarlo a UTC movería de día las visitas
/// de madrugada y los vencimientos.
String? toDate(DateTime? v) {
  if (v == null) return null;
  final m = v.month.toString().padLeft(2, '0');
  final d = v.day.toString().padLeft(2, '0');
  return '${v.year}-$m-$d';
}

/// Quita las claves nulas que el servidor calcula solo (`created_at`,
/// columnas generadas...). Mandar null en ellas las sobrescribiría.
Map<String, dynamic> pruneNulls(Map<String, dynamic> row) {
  return {
    for (final e in row.entries)
      if (e.value != null) e.key: e.value,
  };
}

/// Hoy, sin hora. Se usa como `performed_on` por defecto.
DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}
