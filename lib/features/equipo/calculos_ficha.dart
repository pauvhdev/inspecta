// Textos calculados de T3 (bloque F-gas y próxima revisión RITE). Toda cifra
// sale de `fgas.dart` y `rite.dart` (regla 4 de docs/REGLAS.md); aquí solo se
// redacta. Funciones puras, con prueba en `test/ficha_equipo_test.dart`.

import '../../core/formato.dart' as fmt;
import '../../data/local/app_database.dart';
import '../../data/repositories/inspeccion_repository.dart';
import '../../dominio/estados.dart';
import '../../dominio/fgas.dart';
import '../../dominio/normativa.dart' show Normativa;
import '../../dominio/rite.dart';

/// Bloque F-gas de T3, p. ej. «12 kg R-410A → 25,06 t CO2-eq · control cada
/// 12 meses · próximo 03/05/2027».
class BloqueFgas {
  const BloqueFgas({required this.titular, this.detalle = const []});
  final String titular;
  final List<String> detalle;
}

BloqueFgas bloqueFgas(Normativa n, Equipo e, HechosEquipo? hechos) {
  final codigo = e.refrigerante;
  final kg = e.cargaKg;
  if (codigo == null || kg == null) {
    return const BloqueFgas(
      titular: 'Faltan el refrigerante y la carga para calcular el control de fugas.',
    );
  }
  final ref = n.refrigerante(codigo);
  if (ref == null) {
    return BloqueFgas(
      titular: '$codigo no está en el catálogo de esta versión: no se calcula.',
    );
  }
  final detalle = <String>[];
  if (e.deteccionFugas == null || e.hermeticoEtiquetado == null) {
    detalle.add('Sin dato de hermético o detección: se calcula como «no».');
  }
  final r = evaluarControlFugas(
    n,
    refrigerante: ref,
    cargaKg: kg,
    conDeteccion: e.deteccionFugas ?? false,
    hermeticoEtiquetado: e.hermeticoEtiquetado ?? false,
  );
  final cabeza = '${fmt.numero(kg)} kg ${ref.codigo}';
  switch (r) {
    case NoSujetoControlFugas(:final tCo2eq, :final explicacion, :final avisos):
      detalle.addAll(avisos);
      return BloqueFgas(
        titular:
            '$cabeza → ${fmt.numero(tCo2eq)} t CO2-eq · no sujeto a control de fugas',
        detalle: [explicacion, ...detalle],
      );
    case ControlFugasNoCalculado(:final tCo2eq, :final motivo):
      return BloqueFgas(
        titular: '$cabeza → ${fmt.numero(tCo2eq)} t CO2-eq · no calculado',
        detalle: [motivo, ...detalle],
      );
    case SujetoControlFugas(
      :final tCo2eq,
      :final periodicidadMeses,
      :final articulo,
      :final avisos,
    ):
      final p = proximoControlFugas(
        r,
        ultimoControlAt: hechos?.ultimoControlFugasAt,
        controlPrevioDeclarado: e.controlFugasPrevioDeclarado,
      );
      final proximo = switch (p) {
        ProximoControlEnFecha(:final dia) => 'próximo ${fmt.dia(dia)}',
        ProximoControlSinReferencia() => 'sin control conocido: hacerlo ya',
        ProximoControlNoAplica(:final motivo) => motivo,
      };
      return BloqueFgas(
        titular:
            '$cabeza → ${fmt.numero(tCo2eq)} t CO2-eq · control cada '
            '$periodicidadMeses meses · $proximo',
        detalle: [articulo, ...avisos, ...detalle],
      );
  }
}

/// Próxima revisión RITE de T3, con la potencia de la instalación contando
/// los valores que se están editando de [e].
String textoRite(
  Normativa n, {
  required Equipo e,
  required Instalacion instalacion,
  required List<Equipo> equiposInstalacion,
  HechosEquipo? hechos,
}) {
  final equipos = [
    for (final x in equiposInstalacion)
      if (x.id != e.id) x,
    e,
  ];
  final regimen = regimenRite(
    n,
    instalacion: potenciaDe(instalacion, equipos),
    tipo: e.tipo,
    equipo: PotenciaEquipo(
      frioKw: e.potenciaFrioKw,
      calorKw: e.potenciaCalorKw,
    ),
    uso: instalacion.usoEdificio,
    supervisionRemota: instalacion.supervisionRemota ?? false,
  );
  final p = proximaRevisionRite(
    regimen,
    ultimoPreventivoAt: hechos?.ultimoPreventivoAt,
    preventivoPrevioDeclarado: e.preventivoPrevioDeclarado,
  );
  return switch (p) {
    ProximaRevisionEnFecha(:final meses, :final dia) =>
      'Preventivo RITE cada $meses meses · próximo ${fmt.dia(dia)}',
    ProximaRevisionSinReferencia(:final meses) =>
      'Preventivo RITE cada $meses meses · sin preventivo conocido: toca en esta visita',
    ProximaRevisionPotenciaDesconocida(:final mensaje) => mensaje,
    ProximaRevisionFueraMvp(:final mensaje) => mensaje,
  };
}

/// Avisos de potencia de la instalación («La suma de los equipos… supera la
/// potencia declarada…»), con los valores editados de [e].
List<String> avisosPotencia(
  Instalacion instalacion,
  List<Equipo> equiposInstalacion,
  Equipo e,
) {
  final p = potenciaDe(instalacion, [
    for (final x in equiposInstalacion)
      if (x.id != e.id) x,
    e,
  ]);
  return p.sumaSuperaDeclarada ? p.avisos : const [];
}
