import '../core/formato.dart' as fmt;
import '../data/local/app_database.dart';
import '../data/repositories/inspeccion_repository.dart';
import '../data/sync/mapper.dart';
import '../dominio/estados.dart';
import '../dominio/normativa.dart';
import '../dominio/plantillas.dart' show TipoIntervencion;
import '../features/equipo/calculos_ficha.dart';
import '../features/textos.dart';

// Lo que se congela al firmar y el resumen determinista (F4.1, §7.5).

/// `inspeccion_equipos.datos_equipo_json`: copia del equipo y el cálculo
/// F-gas y RITE **tal como quedan después de esta visita** (si es un
/// preventivo, el siguiente cuenta desde hoy; si hubo control de fugas,
/// también). Lo calcula el código con la normativa versionada; el PDF solo
/// lo copia.
Map<String, Object?> datosEquipoParaInforme(
  Normativa n, {
  required Equipo equipo,
  required Instalacion instalacion,
  required List<Equipo> equiposInstalacion,
  required HechosEquipo? hechos,
  required bool esPreventivo,
  required String? resultadoFugas,
  required DateTime firmadaAt,
}) {
  final tras = aplicarFirma(
    hechos ?? HechosEquipo.vacio,
    FirmaDeEquipo(
      inspeccionId: '',
      firmadaAt: firmadaAt,
      esPreventivo: esPreventivo,
      resultadoFugas: resultadoFugas,
    ),
  );
  final fgas = bloqueFgas(n, equipo, tras);
  return {
    'equipo': aJsonPostgrest('equipos', equipo)
      ..removeWhere(
        (k, _) => k == 'created_at' || k == 'updated_at' || k == 'deleted_at',
      ),
    'nombre': nombreEquipo(equipo),
    'fgas': {'titular': fgas.titular, 'detalle': fgas.detalle},
    'rite': textoRite(
      n,
      e: equipo,
      instalacion: instalacion,
      equiposInstalacion: equiposInstalacion,
      hechos: tras,
    ),
  };
}

String nombreEquipo(Equipo e) => [
  textoTipoEquipo(e.tipo),
  ?e.ubicacion,
  if (e.marca != null || e.modelo != null) [?e.marca, ?e.modelo].join(' '),
].join(' · ');

/// Resumen determinista de la visita (F4.1): plantilla Dart, sin red. El
/// técnico lo puede editar en T12.
String resumenDeterminista(VistaVisita v, List<ChecklistEquipo> equipos) {
  var respondidos = 0, total = 0, defectos = 0, observaciones = 0;
  final incidencias = <String, int>{};
  final gas = <String>[];
  var controles = 0, fugas = 0;
  for (final ch in equipos) {
    total += ch.items.length;
    respondidos += ch.respondidos;
    for (final i in ch.items) {
      if (i.respuesta?.estado == 'defecto') defectos++;
      if (i.respuesta?.estado == 'observacion') observaciones++;
    }
    for (final i in ch.incidencias) {
      final g = textoGravedad(i.gravedad).toLowerCase();
      incidencias[g] = (incidencias[g] ?? 0) + 1;
    }
    for (final m in ch.movimientos) {
      gas.add(
        '${m.tipo == 'carga' ? 'carga' : m.tipo} de ${fmt.numero(m.kg, decimales: 3)} kg de ${m.refrigerante}',
      );
    }
    controles += ch.controles.length;
    fugas += ch.controles.where((c) => c.resultado == 'fuga').length;
  }
  final resueltas = v.incidencias.where((i) => i.resolucionId != null).length;
  final nInc = incidencias.values.fold(0, (a, b) => a + b);
  return [
    '${textoIntervencion(v.tipo)} en ${v.instalacion.nombre}'
        '${v.cliente == null ? '' : ' (${v.cliente!.razonSocial})'}: '
        '${equipos.length} ${equipos.length == 1 ? 'equipo revisado' : 'equipos revisados'}, '
        '$respondidos de $total puntos respondidos.',
    '$defectos ${defectos == 1 ? 'defecto' : 'defectos'} y $observaciones '
        '${observaciones == 1 ? 'observación' : 'observaciones'}.',
    if (nInc > 0)
      'Incidencias registradas: $nInc '
          '(${[for (final e in incidencias.entries) '${e.key}: ${e.value}'].join(', ')}).',
    if (resueltas > 0)
      '$resueltas ${resueltas == 1 ? 'incidencia anterior resuelta' : 'incidencias anteriores resueltas'} en esta visita.',
    if (gas.isNotEmpty) 'Gas: ${gas.join('; ')}.',
    if (controles > 0)
      'Control de fugas: $controles ${controles == 1 ? 'control' : 'controles'}, '
          '${fugas == 0 ? 'sin fugas' : '$fugas con fuga'}.',
  ].join(' ');
}

bool esPreventivo(VistaVisita v) => v.tipo == TipoIntervencion.preventivo;
