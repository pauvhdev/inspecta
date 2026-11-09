import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show DataClass;

import '../data/local/app_database.dart';
import '../data/sync/mapper.dart';

// Todo lo que sale en el PDF de un informe firmado (DISEÑO.md §8.4) y su
// huella `contenido_sha256` (§7.10.6).
//
// Son las filas de Drift tal cual (clases de datos simples, se pueden mandar
// a un isolate) más los bytes de fotos y firmas. El PDF se construye solo con
// esto: así el mismo informe da el mismo contenido en Android y en la web.

class EquipoInforme {
  const EquipoInforme({
    required this.inspeccionEquipo,
    required this.equipo,
    required this.respuestas,
    required this.incidencias,
    required this.controles,
    required this.movimientos,
    required this.fotos,
    required this.resoluciones,
  });

  final InspeccionEquipo inspeccionEquipo;

  /// La fila actual del equipo: solo para el orden y el nombre en pantalla.
  /// El PDF usa la copia congelada de `datos_equipo_json`.
  final Equipo? equipo;
  final List<Respuesta> respuestas;
  final List<Incidencia> incidencias;
  final List<ControlFugas> controles;
  final List<MovimientoGas> movimientos;
  final List<Foto> fotos;
  final List<ResolucionIncidencia> resoluciones;

  /// `datos_equipo_json` decodificado (copia y cálculo F-gas al firmar).
  Map<String, Object?> get datos => inspeccionEquipo.datosEquipoJson == null
      ? const {}
      : (jsonDecode(inspeccionEquipo.datosEquipoJson!) as Map)
            .cast<String, Object?>();
}

class DatosInforme {
  const DatosInforme({
    required this.inspeccion,
    required this.tipoIntervencion,
    required this.equipos,
    required this.firmas,
    required this.bytes,
    required this.esDemo,
  });

  final Inspeccion inspeccion;
  final String tipoIntervencion;
  final List<EquipoInforme> equipos;
  final List<Firma> firmas;

  /// Bytes de las fotos y las firmas, por `id` de su fila.
  final Map<String, Uint8List> bytes;

  /// Marca de agua «DATOS DE EJEMPLO FICTICIOS» (§8.4, punto 11).
  final bool esDemo;

  /// `datos_cabecera_json` decodificado.
  Map<String, Object?> get cabecera => inspeccion.datosCabeceraJson == null
      ? const {}
      : (jsonDecode(inspeccion.datosCabeceraJson!) as Map)
            .cast<String, Object?>();
}

/// Columnas que no forman parte del contenido: las pone el servidor o
/// cambian sin cambiar lo firmado (§7.10.6).
const _fueraDelContenido = {'created_at', 'updated_at', 'sincronizada_at'};

/// Columnas de `inspecciones` que se calculan **a partir** del contenido.
const _evidencias = {'pdf_ruta', 'pdf_sha256', 'contenido_sha256'};

/// JSON canónico de todo lo que sale en el PDF (§7.10.6): orden fijo por
/// tabla y por `id`, claves ordenadas, formato de PostgREST (el mismo que
/// sube la cola) y sin campos de servidor. De las fotos y firmas entra su
/// `sha256`, no los bytes.
String contenidoCanonico(DatosInforme d) {
  Map<String, Object?> fila(String tabla, DataClass f) {
    final j = aJsonPostgrest(tabla, f)
      ..removeWhere((k, _) => _fueraDelContenido.contains(k));
    if (tabla == 'inspecciones') {
      j.removeWhere((k, _) => _evidencias.contains(k));
    }
    return j;
  }

  List<Map<String, Object?>> tabla(String nombre, Iterable<DataClass> filas) {
    final l = [for (final f in filas) fila(nombre, f)]
      ..sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
    return l;
  }

  final contenido = <String, Object?>{
    'inspecciones': [fila('inspecciones', d.inspeccion)],
    'inspeccion_equipos': tabla('inspeccion_equipos', [
      for (final e in d.equipos) e.inspeccionEquipo,
    ]),
    'respuestas': tabla('respuestas', [
      for (final e in d.equipos) ...e.respuestas,
    ]),
    'incidencias': tabla('incidencias', [
      for (final e in d.equipos) ...e.incidencias,
    ]),
    'resoluciones_incidencia': tabla('resoluciones_incidencia', [
      for (final e in d.equipos) ...e.resoluciones,
    ]),
    'controles_fugas': tabla('controles_fugas', [
      for (final e in d.equipos) ...e.controles,
    ]),
    'movimientos_gas': tabla('movimientos_gas', [
      for (final e in d.equipos) ...e.movimientos,
    ]),
    'fotos': tabla('fotos', [for (final e in d.equipos) ...e.fotos]),
    'firmas': tabla('firmas', d.firmas),
  };
  return jsonEncode(_ordenar(contenido));
}

Object? _ordenar(Object? v) => switch (v) {
  Map() => {
    for (final k in (v.keys.map((k) => '$k').toList()..sort()))
      k: _ordenar(v[k]),
  },
  List() => [for (final x in v) _ordenar(x)],
  _ => v,
};

/// `contenido_sha256`: SHA-256 en hexadecimal de [contenidoCanonico].
String contenidoSha256(DatosInforme d) =>
    sha256.convert(utf8.encode(contenidoCanonico(d))).toString();

String sha256De(List<int> bytes) => sha256.convert(bytes).toString();
