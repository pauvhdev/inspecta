// Periodicidad del mantenimiento preventivo RITE (RD 1027/2007, art. 26.6 e
// IT 3.3, Tabla 3.1; DISEÑO.md §3.2 y §7.2).
//
// Funciones puras: la fecha entra como parámetro y las cifras salen de
// [Normativa]. El régimen se decide primero con la **potencia de la
// instalación** y solo si es de 70 kW o menos se baja a la fila del equipo:
// diez splits de 10 kW en un hotel son una instalación de 100 kW (mensual), no
// diez equipos «cada 2 años». Lo que no se puede afirmar (potencia
// desconocida) devuelve un resultado explícito, nunca la fila más laxa.

import 'dart:math' as math;

import 'fgas.dart' show OrigenReferencia;
import 'normativa.dart';
import 'tipos.dart';

export 'fgas.dart' show OrigenReferencia;

/// Potencias nominales de un equipo (`equipos.potencia_frio_kw` y
/// `potencia_calor_kw`); null si no se conoce.
class PotenciaEquipo {
  const PotenciaEquipo({this.frioKw, this.calorKw});
  final double? frioKw;
  final double? calorKw;

  /// La mayor de frío y calor, o null si no hay ninguna.
  double? get mayorKw => _mayor(frioKw, calorKw);
}

/// Potencia de la instalación que decide el régimen RITE.
class PotenciaInstalacion {
  const PotenciaInstalacion({
    required this.kw,
    required this.frioKw,
    required this.calorKw,
    required this.sumaFrioEquiposKw,
    required this.sumaCalorEquiposKw,
    required this.declaradaFrioKw,
    required this.declaradaCalorKw,
    required this.sumaSuperaDeclarada,
    required this.numeroEquipos,
    required this.equiposSinPotencia,
    required this.avisos,
  });

  /// La mayor de [frioKw] y [calorKw]: con la que se mide el umbral de 70 kW.
  final double kw;

  /// max(declarada de frío, suma de frío de los equipos).
  final double frioKw;

  /// max(declarada de calor, suma de calor de los equipos).
  final double calorKw;
  final double sumaFrioEquiposKw;
  final double sumaCalorEquiposKw;
  final double? declaradaFrioKw;
  final double? declaradaCalorKw;

  /// Los equipos llevan la potencia por encima de lo declarado: la suma de
  /// frío o de calor supera lo declarado en esa magnitud, o una magnitud sin
  /// declarar supera la declarada de la otra (y decide [kw]). Aviso «régimen
  /// RITE a revisar» (T3, DISEÑO.md §4.1.3).
  final bool sumaSuperaDeclarada;

  final int numeroEquipos;

  /// Equipos sin ninguna potencia: no suman nada a [kw].
  final int equiposSinPotencia;
  final List<String> avisos;

  /// Hay alguna potencia declarada en `instalaciones`.
  bool get tieneDeclarada =>
      declaradaFrioKw != null || declaradaCalorKw != null;

  /// [kw] se puede tomar como la potencia de la instalación: hay potencia
  /// declarada, o hay equipos y todos tienen la suya. Si no, [kw] es solo una
  /// cota inferior (los equipos sin potencia cuentan 0) y no basta para decir
  /// que la instalación es de 70 kW o menos.
  bool get conocida =>
      tieneDeclarada || (numeroEquipos > 0 && equiposSinPotencia == 0);
}

/// Potencia térmica nominal total instalada (art. 26.6): por separado en frío
/// y en calor, la mayor entre lo declarado en `instalaciones` y la suma de los
/// equipos; y de las dos, la mayor.
///
/// [A VERIFICAR] (DISEÑO.md §3.3): si el umbral se mide con frío, calor o la
/// mayor. El MVP toma la mayor, que es lo prudente (nunca rebaja el régimen).
PotenciaInstalacion potenciaInstalacion({
  double? declaradaFrioKw,
  double? declaradaCalorKw,
  required Iterable<PotenciaEquipo> equipos,
}) {
  _comprobarPotencia(declaradaFrioKw, 'declaradaFrioKw');
  _comprobarPotencia(declaradaCalorKw, 'declaradaCalorKw');
  var sumaFrio = 0.0;
  var sumaCalor = 0.0;
  var sinPotencia = 0;
  var numero = 0;
  for (final e in equipos) {
    numero++;
    _comprobarPotencia(e.frioKw, 'frioKw');
    _comprobarPotencia(e.calorKw, 'calorKw');
    sumaFrio += e.frioKw ?? 0;
    sumaCalor += e.calorKw ?? 0;
    if (e.mayorKw == null) sinPotencia++;
  }
  sumaFrio = _redondear3(sumaFrio);
  sumaCalor = _redondear3(sumaCalor);

  final frio = math.max(declaradaFrioKw ?? 0, sumaFrio);
  final calor = math.max(declaradaCalorKw ?? 0, sumaCalor);

  // Aviso «régimen RITE a revisar» (DISEÑO.md §4.1.3 y T3) por magnitud, con
  // la suma y lo declarado de esa misma magnitud: comparar la mayor suma con
  // la mayor declarada daría textos como «70 kW supera 80 kW».
  final avisos = <String>[];
  var supera = false;
  final mayorDeclarada = _mayor(declaradaFrioKw, declaradaCalorKw);
  for (final (nombre, otro, suma, declarada) in [
    ('frío', 'calor', sumaFrio, declaradaFrioKw),
    ('calor', 'frío', sumaCalor, declaradaCalorKw),
  ]) {
    if (declarada != null && suma > declarada) {
      supera = true;
      avisos.add(
        'La suma de los equipos en $nombre (${_kw(suma)}) supera la potencia '
        'declarada de la instalación en $nombre (${_kw(declarada)}): régimen '
        'RITE a revisar. Se calcula con la mayor',
      );
    } else if (declarada == null &&
        mayorDeclarada != null &&
        suma > mayorDeclarada) {
      // Solo se declaró la otra magnitud y esta, sin declarar, es la que
      // lleva la potencia de la instalación por encima de lo declarado.
      supera = true;
      avisos.add(
        'La suma de los equipos en $nombre (${_kw(suma)}) supera la potencia '
        'declarada de la instalación (${_kw(mayorDeclarada)} en $otro; en '
        '$nombre no hay): régimen RITE a revisar. Se calcula con la mayor',
      );
    }
  }
  if (declaradaFrioKw == null && declaradaCalorKw == null) {
    avisos.add(
      'La instalación no tiene potencia declarada: se usa la suma de los '
      'equipos',
    );
  }
  if (sinPotencia > 0) {
    avisos.add(
      '$sinPotencia equipo(s) sin potencia: la suma puede quedarse corta',
    );
  }

  return PotenciaInstalacion(
    kw: math.max(frio, calor),
    frioKw: frio,
    calorKw: calor,
    sumaFrioEquiposKw: sumaFrio,
    sumaCalorEquiposKw: sumaCalor,
    declaradaFrioKw: declaradaFrioKw,
    declaradaCalorKw: declaradaCalorKw,
    sumaSuperaDeclarada: supera,
    numeroEquipos: numero,
    equiposSinPotencia: sinPotencia,
    avisos: List.unmodifiable(avisos),
  );
}

// ---------------------------------------------------------------------------
// Régimen y periodicidad
// ---------------------------------------------------------------------------

sealed class RegimenRite {
  const RegimenRite();
}

/// Instalación de más de 70 kW: preventivo mensual (Tabla 3.1, fila
/// «Instalaciones de potencia superior a 70 kW»; operaciones de la Tabla 3.3).
/// La plantilla está fuera del MVP: no hay fecha de preventivo que calcular.
final class RegimenMensualFueraMvp extends RegimenRite {
  const RegimenMensualFueraMvp({
    required this.potenciaInstalacionKw,
    required this.meses,
    required this.mensaje,
    required this.avisos,
  });
  final double potenciaInstalacionKw;
  final int meses;
  final String mensaje;
  final List<String> avisos;
}

/// No se puede afirmar que la instalación sea de 70 kW o menos, o no hay con
/// qué elegir la fila del equipo: sin fecha de preventivo. Suponer una
/// potencia daría la fila más laxa de la Tabla 3.1 (4 años en vivienda) con
/// apariencia de cálculo seguro, cuando la instalación podría ser de más de
/// 70 kW (mensual). T3 pide la potencia que falta.
final class RegimenPotenciaDesconocida extends RegimenRite {
  const RegimenPotenciaDesconocida({
    required this.potenciaMinimaKw,
    required this.mensaje,
    required this.avisos,
  });

  /// Lo que suman los equipos con potencia: cota inferior de la instalación.
  final double potenciaMinimaKw;
  final String mensaje;
  final List<String> avisos;
}

/// Instalación de 70 kW o menos: fila de la Tabla 3.1 por tipo, potencia del
/// equipo y uso del edificio.
final class RegimenTabla31 extends RegimenRite {
  const RegimenTabla31({
    required this.fila,
    required this.uso,
    required this.meses,
    required this.pnEquipoKw,
    required this.pnEstimada,
    required this.mesesMaxConSupervisionRemota,
    required this.potenciaInstalacionKw,
    required this.avisos,
  });
  final FilaTabla31 fila;
  final UsoEdificio uso;

  /// Periodicidad mínima de la Tabla 3.1 («al menos», IT 3.3.1).
  final int meses;

  /// Pn con la que se eligió la fila.
  final double pnEquipoKw;

  /// `true` si el equipo no tenía potencia y se usó la de la instalación con
  /// potencia declarada (cota superior: nunca elige una fila más laxa).
  final bool pnEstimada;

  /// Con supervisión remota en continuo, la periodicidad «se puede
  /// incrementar hasta 2 años» (IT 3.3). Dato marcado, no se aplica solo:
  /// null si no hay supervisión o no amplía nada.
  final int? mesesMaxConSupervisionRemota;
  final double potenciaInstalacionKw;
  final List<String> avisos;
}

/// Régimen RITE de un equipo dentro de su instalación.
///
/// [instalacion] debe incluir a [equipo] con sus valores actuales (en T3, los
/// que se están editando). Si el equipo tiene más potencia que la instalación
/// (no se incluyó), se mide con la mayor de las dos: un equipo de 80 kW ya
/// hace la instalación de más de 70 kW.
///
/// [supervisionRemota] es `instalaciones.supervision_remota`.
RegimenRite regimenRite(
  Normativa normativa, {
  required PotenciaInstalacion instalacion,
  required TipoEquipo tipo,
  required PotenciaEquipo equipo,
  required UsoEdificio uso,
  bool supervisionRemota = false,
}) {
  final r = normativa.rite;
  final avisos = [...instalacion.avisos];
  final pnEquipo = equipo.mayorKw;

  // Potencia con la que se mide el umbral: la de la instalación, o la del
  // equipo si es mayor (no estaba incluido en la suma).
  var kw = instalacion.kw;
  if (pnEquipo != null && pnEquipo > kw) {
    kw = pnEquipo;
    avisos.add(
      'El equipo (${_kw(pnEquipo)}) supera la potencia calculada de la '
      'instalación (${_kw(instalacion.kw)}): se mide con la del equipo',
    );
  }

  // Art. 26.6.b y fila «más de 70 kW» de la Tabla 3.1: el borde es estricto
  // («mayor que 70 kW»); 70 kW exactos siguen en la tabla por equipo. Si la
  // potencia conocida ya pasa de 70 kW, la real (que no es menor) también.
  if (kw > r.umbralRegimenMensualKw) {
    return RegimenMensualFueraMvp(
      potenciaInstalacionKw: kw,
      meses: r.mesesRegimenMensual,
      mensaje: r.textoRegimenMensual,
      avisos: List.unmodifiable(avisos),
    );
  }

  // Sin potencia declarada y con equipos sin potencia (o sin equipos), [kw]
  // es solo una cota inferior: no se puede afirmar «70 kW o menos».
  if (!instalacion.conocida) {
    return RegimenPotenciaDesconocida(
      potenciaMinimaKw: kw,
      mensaje:
          'No se conoce la potencia de la instalación (hay equipos sin '
          'potencia y no hay potencia declarada): indíquela para calcular el '
          'preventivo RITE. Podría ser de más de 70 kW (mensual)',
      avisos: List.unmodifiable(avisos),
    );
  }

  // [A VERIFICAR] (DISEÑO.md §3.3): la Pn de cada fila se lee por equipo. Si
  // el equipo no tiene potencia, se usa la de la instalación con potencia
  // declarada, que acota la del equipo: la fila elegida nunca es más laxa que
  // la real. Sin declarada no hay cota (la suma de los otros equipos no acota
  // a este) y no se elige fila.
  if (pnEquipo == null && !instalacion.tieneDeclarada) {
    return RegimenPotenciaDesconocida(
      potenciaMinimaKw: kw,
      mensaje:
          'Equipo sin potencia y sin potencia declarada en la instalación: '
          'indique una de las dos para elegir la fila de la Tabla 3.1',
      avisos: List.unmodifiable(avisos),
    );
  }
  final pn = pnEquipo ?? kw;
  if (pnEquipo == null) {
    avisos.add(
      'Equipo sin potencia: se usa la de la instalación (${_kw(pn)}) para '
      'elegir la fila de la Tabla 3.1',
    );
  }
  final familia = r.familiaPorTipo[tipo]!;
  final fila = r.fila(familia, pn);
  if (fila == null) {
    // No debería pasar: pn ≤ kw ≤ 70 y la normativa se valida al cargar para
    // que cada familia cubra de 0 a 70 kW.
    throw StateError('Tabla 3.1 sin fila para $familia y ${_kw(pn)}');
  }
  final meses = fila.meses(uso);

  int? ampliacion;
  if (supervisionRemota &&
      kw <= r.supervisionPotenciaMaxKw &&
      meses < r.supervisionMesesMax) {
    ampliacion = r.supervisionMesesMax;
    avisos.add(
      'Supervisión remota en continuo: la periodicidad se puede ampliar hasta '
      '${r.supervisionMesesMax ~/ 12} años si están garantizadas la seguridad '
      'y la eficiencia energética (IT 3.3)',
    );
  }

  return RegimenTabla31(
    fila: fila,
    uso: uso,
    meses: meses,
    pnEquipoKw: pn,
    pnEstimada: pnEquipo == null,
    mesesMaxConSupervisionRemota: ampliacion,
    potenciaInstalacionKw: kw,
    avisos: List.unmodifiable(avisos),
  );
}

// ---------------------------------------------------------------------------
// Próxima revisión
// ---------------------------------------------------------------------------

sealed class ProximaRevisionRite {
  const ProximaRevisionRite();
}

final class ProximaRevisionEnFecha extends ProximaRevisionRite {
  const ProximaRevisionEnFecha({
    required this.fecha,
    required this.dia,
    required this.referencia,
    required this.origen,
    required this.meses,
    required this.ampliadaPorSupervisionRemota,
  });

  /// Referencia + [meses] (ver [vencimientoDesde]).
  final DateTime fecha;

  /// Último día en plazo.
  final DiaCalendario dia;
  final DateTime referencia;
  final OrigenReferencia origen;
  final int meses;
  final bool ampliadaPorSupervisionRemota;

  /// Vencida si el instante [hoy], en su día local, ya pasó [dia] (el mismo
  /// día aún está en plazo). [hoy] puede venir en UTC o en hora local.
  bool vencida(DateTime hoy) => DiaCalendario.deInstante(hoy).clave > dia.clave;
}

/// Sin preventivo conocido: toca hacerlo en esta visita.
final class ProximaRevisionSinReferencia extends ProximaRevisionRite {
  const ProximaRevisionSinReferencia({required this.meses});
  final int meses;
}

/// Potencia desconocida: sin fecha hasta que se indique (T3).
final class ProximaRevisionPotenciaDesconocida extends ProximaRevisionRite {
  const ProximaRevisionPotenciaDesconocida({required this.mensaje});
  final String mensaje;
}

/// Régimen mensual de más de 70 kW: fuera del MVP, sin fecha (T2, O1).
final class ProximaRevisionFueraMvp extends ProximaRevisionRite {
  const ProximaRevisionFueraMvp({required this.mensaje});
  final String mensaje;
}

/// Próxima revisión desde `estado_equipo.ultimo_preventivo_at` (instante, en
/// UTC en el repo: cuenta su día local) o, si no hay, desde
/// `equipos.preventivo_previo_declarado` (día, `SoloFecha`).
///
/// [aplicarSupervisionRemota]: la oficina decide usar la ampliación de la
/// IT 3.3; por defecto se usa la periodicidad de la tabla, la más prudente.
ProximaRevisionRite proximaRevisionRite(
  RegimenRite regimen, {
  DateTime? ultimoPreventivoAt,
  DateTime? preventivoPrevioDeclarado,
  bool aplicarSupervisionRemota = false,
}) {
  switch (regimen) {
    case RegimenMensualFueraMvp(:final mensaje):
      return ProximaRevisionFueraMvp(mensaje: mensaje);
    case RegimenPotenciaDesconocida(:final mensaje):
      return ProximaRevisionPotenciaDesconocida(mensaje: mensaje);
    case RegimenTabla31(:final meses, :final mesesMaxConSupervisionRemota):
      final ampliada =
          aplicarSupervisionRemota && mesesMaxConSupervisionRemota != null;
      final m = ampliada ? mesesMaxConSupervisionRemota : meses;
      final ref = ultimoPreventivoAt ?? preventivoPrevioDeclarado;
      if (ref == null) return ProximaRevisionSinReferencia(meses: m);
      final v = vencimientoDesde(
        ref,
        m,
        referenciaEsInstante: ultimoPreventivoAt != null,
      );
      return ProximaRevisionEnFecha(
        fecha: v.fecha,
        dia: v.dia,
        referencia: ref,
        origen: ultimoPreventivoAt != null
            ? OrigenReferencia.ultimoEnInspecta
            : OrigenReferencia.previoDeclarado,
        meses: m,
        ampliadaPorSupervisionRemota: ampliada,
      );
  }
}

// ---------------------------------------------------------------------------

void _comprobarPotencia(double? kw, String nombre) {
  if (kw != null && (!kw.isFinite || kw < 0)) {
    throw ArgumentError.value(kw, nombre, 'La potencia debe ser un número ≥ 0');
  }
}

double? _mayor(double? a, double? b) {
  if (a == null) return b;
  if (b == null) return a;
  return math.max(a, b);
}

double _redondear3(double v) => (v * 1000).roundToDouble() / 1000;

String _kw(double v) {
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  return '${s.replaceAll('.', ',')} kW';
}
