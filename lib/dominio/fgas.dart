// Cálculos F-gas del Reglamento (UE) 2024/573 (DISEÑO.md §3.2, §7.2 y §7.5).
//
// Funciones puras y deterministas: no leen el reloj (la fecha entra como
// parámetro), no tocan la base y todas las cifras salen de [Normativa]
// (`assets/normativa/<version>.json`). Lo que no se puede afirmar devuelve un
// resultado explícito (sealed class), nunca un número inventado, un null
// ambiguo o un bool que no diga por qué.
//
// No se guardan como verdad en `equipos` (§7.2): T3, T11, T12 y el PDF los
// recalculan, y el informe firmado guarda la foto fija del cálculo.

import 'normativa.dart';
import 'tipos.dart';

// ---------------------------------------------------------------------------
// t CO2-eq (art. 3.3 y anexo VI)
// ---------------------------------------------------------------------------

/// Toneladas equivalentes de CO2: kg × PCG / 1000 (art. 3, punto 3).
///
/// Se redondea a 6 decimales (gramos de CO2-eq) para que los bordes de las
/// franjas (5, 50, 500 t) no dependan de errores de coma flotante.
double tCo2eq(Refrigerante refrigerante, double kg) {
  _comprobarKg(kg);
  return _redondear6(kg * refrigerante.pcg / 1000);
}

/// Kg de gases del anexo II, sección 1 (HFO) que lleva una carga.
double kgAnexoIISeccion1(Refrigerante refrigerante, double kg) {
  _comprobarKg(kg);
  return _redondear6(kg * refrigerante.porcentajeAnexoIISeccion1 / 100);
}

void _comprobarKg(double kg) {
  if (!kg.isFinite || kg < 0) {
    throw ArgumentError.value(kg, 'kg', 'La carga debe ser un número ≥ 0');
  }
}

double _redondear6(double v) => (v * 1e6).roundToDouble() / 1e6;

// ---------------------------------------------------------------------------
// Categoría F-gas deducida del tipo de equipo (§7.2, T3)
// ---------------------------------------------------------------------------

/// Categoría propuesta para `equipos.categoria_fgas`. El técnico la confirma
/// o la cambia en T3; [dudosa] pide que la mire con atención.
class CategoriaDeducida {
  const CategoriaDeducida({
    required this.categoria,
    required this.dudosa,
    required this.motivo,
  });
  final CategoriaFgas categoria;
  final bool dudosa;
  final String motivo;
}

/// Deduce la categoría a efectos de los arts. 13.3 y 13.4 a partir del tipo.
///
/// - Split, conductos, VRF, rooftop, bomba de calor y UTA son aire
///   acondicionado o bomba de calor (art. 3: «aire acondicionado», «bomba de
///   calor»).
/// - La enfriadora puede ser de confort o de proceso: el art. 3 la define como
///   el sistema que enfría un fluido «con fines de refrigeración, tratamiento,
///   conservación o confort». En una mantenedora RITE lo normal es confort, y
///   es además lo prudente: con aire acondicionado el art. 13.4 **bloquea**,
///   mientras que en refrigeración el MVP solo avisa (13.3). Se marca dudosa.
/// - «Otro» queda en otro: no se presume ninguna regla y se marca dudosa.
CategoriaDeducida deducirCategoriaFgas(TipoEquipo tipo) {
  switch (tipo) {
    case TipoEquipo.split:
    case TipoEquipo.conductos:
    case TipoEquipo.vrf:
    case TipoEquipo.rooftop:
    case TipoEquipo.bombaCalor:
    case TipoEquipo.uta:
      return const CategoriaDeducida(
        categoria: CategoriaFgas.aireAcondicionadoBombaCalor,
        dudosa: false,
        motivo: 'Equipo de climatización: aire acondicionado o bomba de calor',
      );
    case TipoEquipo.enfriadora:
      return const CategoriaDeducida(
        categoria: CategoriaFgas.aireAcondicionadoBombaCalor,
        dudosa: true,
        motivo:
            'Enfriadora: se propone aire acondicionado (confort). Si enfría '
            'un proceso o productos, cámbiela a refrigeración',
      );
    case TipoEquipo.otro:
      return const CategoriaDeducida(
        categoria: CategoriaFgas.otro,
        dudosa: true,
        motivo: 'Tipo «otro»: indique la categoría del aparato',
      );
  }
}

// ---------------------------------------------------------------------------
// Control de fugas (arts. 5 y 6)
// ---------------------------------------------------------------------------

/// Criterio del art. 5 que decide la periodicidad.
enum CriterioControlFugas {
  /// Gases del anexo I y sus mezclas: t CO2-eq.
  tCo2eq,

  /// Fracción HFO (anexo II, sección 1) de una mezcla, en kg.
  /// [A VERIFICAR] ver `mezclas_con_anexo_ii` en la normativa.
  kgAnexoII,
}

enum MotivoNoSujeto {
  /// Por debajo de 5 t CO2-eq (y de 1 kg de HFO, si es mezcla).
  bajoUmbral,

  /// Hermético etiquetado por debajo de 10 t (o 2 kg de HFO): art. 5.1,
  /// párrafo segundo.
  hermeticoEtiquetado,

  /// Hermético etiquetado de menos de 3 kg en edificio residencial, marcado
  /// por el técnico: art. 5.1, párrafo tercero.
  excepcionResidencialMarcada,
}

sealed class ResultadoControlFugas {
  const ResultadoControlFugas();
}

final class NoSujetoControlFugas extends ResultadoControlFugas {
  const NoSujetoControlFugas({
    required this.tCo2eq,
    required this.motivo,
    required this.explicacion,
    this.avisos = const [],
  });
  final double tCo2eq;
  final MotivoNoSujeto motivo;
  final String explicacion;
  final List<String> avisos;
}

final class SujetoControlFugas extends ResultadoControlFugas {
  const SujetoControlFugas({
    required this.tCo2eq,
    required this.kgAnexoII,
    required this.periodicidadMeses,
    required this.criterio,
    required this.conDeteccion,
    required this.deteccionObligatoria,
    required this.articulo,
    this.avisos = const [],
  });
  final double tCo2eq;

  /// Kg de HFO de la carga (0 si no es mezcla con anexo II).
  final double kgAnexoII;
  final int periodicidadMeses;
  final CriterioControlFugas criterio;
  final bool conDeteccion;

  /// Art. 6.1: 500 t CO2-eq o más (o 100 kg de HFO).
  final bool deteccionObligatoria;
  final String articulo;
  final List<String> avisos;

  /// Detección obligatoria que el equipo no tiene: incumplimiento del art. 6.
  bool get faltaDeteccionObligatoria => deteccionObligatoria && !conDeteccion;
}

/// Gas puro del anexo II (HFO): el MVP no calcula su periodicidad y lo dice
/// (DISEÑO.md §3.2 y §4.3). Nunca devuelve un número de meses.
final class ControlFugasNoCalculado extends ResultadoControlFugas {
  const ControlFugasNoCalculado({required this.tCo2eq, required this.motivo});

  /// La t CO2-eq sí se informa (va en la etiqueta del art. 12).
  final double tCo2eq;
  final String motivo;
}

/// Decide si el aparato está sujeto a control de fugas y cada cuántos meses.
///
/// [conDeteccion]: tiene sistema de detección de fugas instalado
/// (`equipos.deteccion_fugas`). [hermeticoEtiquetado]: sellado
/// herméticamente y etiquetado como tal (`equipos.hermetico_etiquetado`).
/// [excepcionResidencialMarcada]: el técnico marca la excepción del art. 5.1,
/// párrafo tercero (no se automatiza: DISEÑO.md §3.3).
ResultadoControlFugas evaluarControlFugas(
  Normativa normativa, {
  required Refrigerante refrigerante,
  required double cargaKg,
  required bool conDeteccion,
  required bool hermeticoEtiquetado,
  bool excepcionResidencialMarcada = false,
}) {
  final r5 = normativa.fgas.art5;
  final r6 = normativa.fgas.art6;
  final t = tCo2eq(refrigerante, cargaKg);

  if (refrigerante.esAnexoIIPuro && !r5.anexoIIPurosCalculados) {
    return ControlFugasNoCalculado(
      tCo2eq: t,
      motivo:
          '${refrigerante.codigo} es un gas del anexo II (HFO): su control '
          'de fugas va en kg (art. 5.1 y 5.6) y no se calcula en el MVP. '
          'Compruébelo a mano.',
    );
  }

  final avisos = <String>[];

  // Art. 5.1, párrafo tercero: hermético etiquetado de menos de 3 kg en un
  // edificio residencial. Solo si el técnico la marca, y solo si cuadra.
  if (excepcionResidencialMarcada) {
    if (hermeticoEtiquetado && cargaKg < r5.umbralExcepcionResidencialKg) {
      return NoSujetoControlFugas(
        tCo2eq: t,
        motivo: MotivoNoSujeto.excepcionResidencialMarcada,
        explicacion:
            'Hermético etiquetado de menos de '
            '${_kg(r5.umbralExcepcionResidencialKg)} en edificio residencial, '
            'marcado por el técnico (art. 5.1, párrafo tercero)',
      );
    }
    avisos.add(
      'La excepción residencial marcada no aplica: exige hermético etiquetado '
      'y menos de ${_kg(r5.umbralExcepcionResidencialKg)} (art. 5.1)',
    );
  }

  // Art. 5.1, párrafo segundo: el hermético etiquetado queda exento si
  // cumple «una de las condiciones siguientes»: a) menos de 10 t CO2-eq de
  // gases del anexo I, o b) menos de 2 kg del anexo II, sección 1. Basta con
  // a): un hermético de R-454B de 20 kg (9,3 t, 6,2 kg de HFO) está exento
  // aunque su fracción HFO pase de 2 kg. Se mide a) con la t CO2-eq de la
  // carga completa, que incluye la pequeña aportación del HFO: nunca exime de
  // más.
  final kgII = kgAnexoIISeccion1(refrigerante, cargaKg);
  final criterioKgMezcla =
      refrigerante.esMezclaConAnexoII && r5.mezclasCriterioKgFraccion;
  final exentoHermeticoA = hermeticoEtiquetado && t < r5.umbralHermeticoT;
  // [A VERIFICAR] La condición b) sola (≥ 10 t pero < 2 kg de HFO, p. ej.
  // un hermético de R-448A de 7,3 kg: 10,1 t y 1,97 kg de HFO) eximiría
  // según la letra del párrafo, pero la b) está pensada para los gases del
  // anexo II y la mezcla es un HFC del anexo I (art. 3.4). Lo prudente: con
  // b) sola solo se exime el criterio en kg, y la t CO2-eq sigue mandando.
  final exentoHermeticoB =
      hermeticoEtiquetado &&
      criterioKgMezcla &&
      kgII < r5.umbralHermeticoKgAnexoII;

  // Criterio del anexo I: t CO2-eq de la carga completa (la mezcla HFC/HFO es
  // un HFC: art. 3.4).
  final candidatos = <({CriterioControlFugas criterio, int meses})>[];
  var exentoPorHermetico = false;

  if (t >= r5.umbralSujecionT) {
    if (exentoHermeticoA) {
      exentoPorHermetico = true;
    } else {
      candidatos.add((
        criterio: CriterioControlFugas.tCo2eq,
        meses: _meses(r5.franjasT, t, conDeteccion),
      ));
    }
  }

  // Criterio del anexo II sobre la fracción HFO de una mezcla.
  // [A VERIFICAR] Lo más prudente con la duda de `mezclas_con_anexo_ii`: se
  // calcula también y manda el plazo más corto.
  if (criterioKgMezcla) {
    if (kgII >= r5.umbralSujecionKgAnexoII) {
      if (exentoHermeticoA || exentoHermeticoB) {
        exentoPorHermetico = true;
      } else {
        candidatos.add((
          criterio: CriterioControlFugas.kgAnexoII,
          meses: _meses(r5.franjasKgAnexoII, kgII, conDeteccion),
        ));
      }
    }
  }

  if (candidatos.isEmpty) {
    return exentoPorHermetico
        ? NoSujetoControlFugas(
            tCo2eq: t,
            motivo: MotivoNoSujeto.hermeticoEtiquetado,
            explicacion: exentoHermeticoA
                ? 'Hermético etiquetado por debajo de '
                      '${_num(r5.umbralHermeticoT)} t CO2-eq (art. 5.1, '
                      'párrafo segundo, letra a)'
                : 'Hermético etiquetado por debajo de '
                      '${_kg(r5.umbralHermeticoKgAnexoII)} de HFO (art. 5.1, '
                      'párrafo segundo, letra b)',
            avisos: List.unmodifiable(avisos),
          )
        : NoSujetoControlFugas(
            tCo2eq: t,
            motivo: MotivoNoSujeto.bajoUmbral,
            explicacion:
                'Menos de ${_num(r5.umbralSujecionT)} t CO2-eq (art. 5.1)',
            avisos: List.unmodifiable(avisos),
          );
  }

  candidatos.sort((a, b) => a.meses.compareTo(b.meses));
  final elegido = candidatos.first;
  if (elegido.criterio == CriterioControlFugas.kgAnexoII) {
    avisos.add(
      'Plazo fijado por los ${_kg(kgII)} de HFO de la mezcla (anexo II, '
      'art. 5.6), más exigente que por t CO2-eq. [A VERIFICAR]',
    );
  }

  final obligatoria =
      t >= r6.umbralDeteccionT ||
      (criterioKgMezcla && kgII >= r6.umbralDeteccionKgAnexoII);
  if (obligatoria && !conDeteccion) {
    avisos.add(
      'Detección de fugas obligatoria desde ${_num(r6.umbralDeteccionT)} t '
      'CO2-eq y el equipo no la tiene (art. 6.1)',
    );
  }

  return SujetoControlFugas(
    tCo2eq: t,
    kgAnexoII: kgII,
    periodicidadMeses: elegido.meses,
    criterio: elegido.criterio,
    conDeteccion: conDeteccion,
    deteccionObligatoria: obligatoria,
    articulo: 'Reglamento (UE) 2024/573, art. 5.6',
    avisos: List.unmodifiable(avisos),
  );
}

int _meses(List<FranjaControlFugas> franjas, double valor, bool conDeteccion) {
  final f = franjas.firstWhere(
    (f) => f.contiene(valor),
    // Las franjas se validan contiguas y abiertas al cargar: no hay hueco.
    orElse: () => throw StateError('Sin franja para $valor'),
  );
  return conDeteccion ? f.mesesConDeteccion : f.meses;
}

// ---------------------------------------------------------------------------
// Próximo control de fugas
// ---------------------------------------------------------------------------

enum OrigenReferencia {
  /// `estado_equipo.ultimo_control_fugas_at` (o `ultimo_preventivo_at`).
  ultimoEnInspecta,

  /// `equipos.control_fugas_previo_declarado` (o `preventivo_previo_declarado`).
  previoDeclarado,
}

sealed class ProximoControlFugas {
  const ProximoControlFugas();
}

final class ProximoControlEnFecha extends ProximoControlFugas {
  const ProximoControlEnFecha({
    required this.fecha,
    required this.dia,
    required this.referencia,
    required this.origen,
    required this.meses,
  });

  /// Referencia + [meses]: en hora local si la referencia era un instante, o
  /// medianoche del día si era una fecha declarada (ver [vencimientoDesde]).
  final DateTime fecha;

  /// Último día en plazo, el que se muestra en T3 y en el PDF.
  final DiaCalendario dia;
  final DateTime referencia;
  final OrigenReferencia origen;
  final int meses;

  /// Vencido si el instante [hoy], en su día local, ya pasó [dia] (el mismo
  /// día aún está en plazo). [hoy] puede venir en UTC o en hora local.
  bool vencido(DateTime hoy) => DiaCalendario.deInstante(hoy).clave > dia.clave;
}

/// Sujeto pero sin ningún control conocido: hay que hacerlo ya.
final class ProximoControlSinReferencia extends ProximoControlFugas {
  const ProximoControlSinReferencia({required this.meses});
  final int meses;
}

/// No sujeto o no calculado: no hay vencimiento que mostrar.
final class ProximoControlNoAplica extends ProximoControlFugas {
  const ProximoControlNoAplica({required this.motivo});
  final String motivo;
}

/// Próximo control: último control registrado en Inspecta o, si no hay, el
/// previo declarado al dar de alta el equipo, más la periodicidad en meses de
/// calendario.
///
/// [ultimoControlAt] es un instante (`estado_equipo.ultimo_control_fugas_at`,
/// en UTC en el repo): se cuenta desde su día local. [controlPrevioDeclarado]
/// es un día (`equipos.control_fugas_previo_declarado`, `SoloFecha`).
ProximoControlFugas proximoControlFugas(
  ResultadoControlFugas resultado, {
  DateTime? ultimoControlAt,
  DateTime? controlPrevioDeclarado,
}) {
  switch (resultado) {
    case NoSujetoControlFugas(:final explicacion):
      return ProximoControlNoAplica(motivo: 'No sujeto: $explicacion');
    case ControlFugasNoCalculado(:final motivo):
      return ProximoControlNoAplica(motivo: motivo);
    case SujetoControlFugas(:final periodicidadMeses):
      final (ref, origen) = _referencia(
        ultimoControlAt,
        controlPrevioDeclarado,
      );
      if (ref == null) {
        return ProximoControlSinReferencia(meses: periodicidadMeses);
      }
      final v = vencimientoDesde(
        ref,
        periodicidadMeses,
        referenciaEsInstante: origen == OrigenReferencia.ultimoEnInspecta,
      );
      return ProximoControlEnFecha(
        fecha: v.fecha,
        dia: v.dia,
        referencia: ref,
        origen: origen!,
        meses: periodicidadMeses,
      );
  }
}

(DateTime?, OrigenReferencia?) _referencia(DateTime? ultimo, DateTime? previo) {
  if (ultimo != null) return (ultimo, OrigenReferencia.ultimoEnInspecta);
  if (previo != null) return (previo, OrigenReferencia.previoDeclarado);
  return (null, null);
}

// ---------------------------------------------------------------------------
// Revisión del sistema de detección (art. 6.3)
// ---------------------------------------------------------------------------

sealed class RevisionDetector {
  const RevisionDetector();
}

final class RevisionDetectorEnFecha extends RevisionDetector {
  const RevisionDetectorEnFecha({
    required this.fecha,
    required this.obligatoria,
  });
  final DateTime fecha;

  /// Obligatoria por el art. 6.3 (detector exigido por el 6.1). Si no lo es,
  /// la fecha es la misma pauta, recomendada: la ampliación del plazo del
  /// art. 5.6 se apoya en que el detector funcione.
  final bool obligatoria;
}

final class RevisionDetectorSinReferencia extends RevisionDetector {
  const RevisionDetectorSinReferencia({required this.obligatoria});
  final bool obligatoria;
}

final class RevisionDetectorNoAplica extends RevisionDetector {
  const RevisionDetectorNoAplica();
}

/// [ultimaRevision] es un día (`equipos.deteccion_ultima_revision`,
/// `SoloFecha`): se suma tal cual, sin cambiar de zona.
RevisionDetector revisionDetector(
  Normativa normativa, {
  required bool conDeteccion,
  required bool deteccionObligatoria,
  DateTime? ultimaRevision,
}) {
  if (!conDeteccion) return const RevisionDetectorNoAplica();
  if (ultimaRevision == null) {
    return RevisionDetectorSinReferencia(obligatoria: deteccionObligatoria);
  }
  return RevisionDetectorEnFecha(
    fecha: sumarMesesCalendario(
      ultimaRevision,
      normativa.fgas.art6.mesesRevisionDetector,
    ),
    obligatoria: deteccionObligatoria,
  );
}

// ---------------------------------------------------------------------------
// Nuevo control tras reparar una fuga (art. 4.5)
// ---------------------------------------------------------------------------

/// Ventana del nuevo control: desde 24 h de funcionamiento tras la reparación
/// hasta un mes después (art. 4.5, párrafo segundo). `desde` es lo antes
/// posible: 24 h de reloj suponen que el equipo funcionó todo ese tiempo.
/// Las dos van en hora local: el mes se cuenta desde el día local de la
/// reparación (en UTC, una reparación del 31/1 a las 00:30 en Madrid sería del
/// 30/1 y el plazo acabaría un día tarde).
class VentanaNuevoControl {
  const VentanaNuevoControl({required this.desde, required this.hasta});
  final DateTime desde;
  final DateTime hasta;
}

VentanaNuevoControl ventanaNuevoControl(
  Normativa normativa,
  DateTime reparadaAt,
) {
  final r = normativa.fgas.art45;
  final local = enHoraLocal(reparadaAt);
  return VentanaNuevoControl(
    desde: local.add(Duration(hours: r.desdeHoras)),
    hasta: sumarMesesCalendario(local, r.hastaMeses),
  );
}

sealed class NuevoControl {
  const NuevoControl();
}

final class NuevoControlObligatorio extends NuevoControl {
  const NuevoControlObligatorio(this.ventana);
  final VentanaNuevoControl ventana;
}

/// HFO puro: el art. 4.5 aplicaría si el aparato está sujeto, pero el MVP no
/// calcula la sujeción. Se da la ventana para que el técnico decida.
final class NuevoControlARevisar extends NuevoControl {
  const NuevoControlARevisar(this.ventana, this.motivo);
  final VentanaNuevoControl ventana;
  final String motivo;
}

/// El art. 4.5 solo obliga si el aparato está sujeto a control de fugas.
final class NuevoControlNoExigido extends NuevoControl {
  const NuevoControlNoExigido(this.motivo);
  final String motivo;
}

NuevoControl nuevoControlTrasReparacion(
  Normativa normativa, {
  required ResultadoControlFugas sujecion,
  required DateTime reparadaAt,
}) {
  final ventana = ventanaNuevoControl(normativa, reparadaAt);
  return switch (sujecion) {
    SujetoControlFugas() => NuevoControlObligatorio(ventana),
    ControlFugasNoCalculado(:final motivo) => NuevoControlARevisar(
      ventana,
      motivo,
    ),
    NoSujetoControlFugas() => const NuevoControlNoExigido(
      'El aparato no está sujeto a control de fugas (art. 4.5 remite al 5.1)',
    ),
  };
}

// ---------------------------------------------------------------------------
// Validación de una carga de gas (arts. 13.3, 13.4 y 13.5)
// ---------------------------------------------------------------------------

/// `movimientos_gas.tipo`.
enum TipoMovimientoGas {
  carga('carga'),
  recuperacion('recuperacion'),
  desmantelamiento('desmantelamiento');

  const TipoMovimientoGas(this.wire);
  final String wire;
}

/// `movimientos_gas.reciclado_recuperado_por`.
enum RecuperadoPor {
  propiaEmpresa('propia_empresa'),
  paraEstaEmpresa('para_esta_empresa');

  const RecuperadoPor(this.wire);
  final String wire;
}

/// `movimientos_gas.regla_aplicada`.
enum ReglaAplicada {
  art134('13.4'),
  art133Aviso('13.3_aviso'),
  ninguna('ninguna');

  const ReglaAplicada(this.wire);
  final String wire;
}

/// Dato de origen que falta para desbloquear (nombre de la columna de
/// `movimientos_gas`, igual que en `art13_4.origenes.*.datos`).
enum DatoOrigen {
  regeneradoLote('regenerado_lote'),
  regeneradoEtiquetaFotoId('regenerado_etiqueta_foto_id'),
  recicladoRecuperadoPor('reciclado_recuperado_por'),
  recicladoDeclaracion('reciclado_declaracion');

  const DatoOrigen(this.wire);
  final String wire;
}

/// Datos que acompañan al gas según su origen (§7.5).
class DatosOrigenGas {
  const DatosOrigenGas({
    this.regeneradoLote,
    this.regeneradoEtiquetaFotoId,
    this.recicladoRecuperadoPor,
    this.recicladoDeclaracion = false,
  });

  /// Lote de la etiqueta del art. 12.7.
  final String? regeneradoLote;

  /// Foto de la etiqueta del art. 12.7 (referencia blanda a `fotos`).
  final String? regeneradoEtiquetaFotoId;
  final RecuperadoPor? recicladoRecuperadoPor;

  /// Declaración de que se recuperó de un aparato de aire acondicionado o
  /// bomba de calor como parte de su mantenimiento, por la propia empresa o
  /// para ella (art. 13.4, letra b).
  final bool recicladoDeclaracion;

  bool _tiene(DatoOrigen d) => switch (d) {
    DatoOrigen.regeneradoLote => _relleno(regeneradoLote),
    DatoOrigen.regeneradoEtiquetaFotoId => _relleno(regeneradoEtiquetaFotoId),
    DatoOrigen.recicladoRecuperadoPor => recicladoRecuperadoPor != null,
    DatoOrigen.recicladoDeclaracion => recicladoDeclaracion,
  };

  static bool _relleno(String? s) => s != null && s.trim().isNotEmpty;
}

sealed class ValidacionCarga {
  const ValidacionCarga();
  ReglaAplicada get regla;
}

final class CargaPermitida extends ValidacionCarga {
  const CargaPermitida({required this.regla, this.nota});
  @override
  final ReglaAplicada regla;
  final String? nota;
}

/// Bloqueo a pantalla completa en T11: no se guarda la carga.
final class CargaBloqueada extends ValidacionCarga {
  const CargaBloqueada({
    required this.articulo,
    required this.motivo,
    this.faltan = const [],
  });
  final String articulo;
  final String motivo;

  /// Datos del origen que faltan; vacío si el origen no se puede justificar.
  final List<DatoOrigen> faltan;

  @override
  ReglaAplicada get regla => ReglaAplicada.art134;
}

/// Aviso sin bloqueo (13.3 en refrigeración, 13.5 desde 2032, o categoría
/// «otro» con gas de PCG alto).
final class CargaConAviso extends ValidacionCarga {
  const CargaConAviso({required this.articulo, required this.motivo});
  final String articulo;
  final String motivo;

  /// `movimientos_gas.regla_aplicada` solo admite `13.3_aviso`; los avisos
  /// del 13.5 y de categoría «otro» se guardan como `ninguna`. [A VERIFICAR]
  /// si conviene ampliar ese enum.
  @override
  ReglaAplicada get regla =>
      articulo == _art133 ? ReglaAplicada.art133Aviso : ReglaAplicada.ninguna;
}

const _art133 = 'Reglamento (UE) 2024/573, art. 13.3';
const _art134 = 'Reglamento (UE) 2024/573, art. 13.4';
const _art135 = 'Reglamento (UE) 2024/573, art. 13.5';

/// Valida una carga de gas antes de guardarla (F2.7, T11).
///
/// Solo las cargas (`tipo = carga`) pueden bloquearse: recuperar o desmantelar
/// nunca. La [fecha] es el instante de la carga, en UTC (como lo guarda el
/// repo) o en hora local: cuenta su día de calendario local
/// ([esIgualOPosterior]).
ValidacionCarga validarCargaGas(
  Normativa normativa, {
  required TipoMovimientoGas tipo,
  required Refrigerante refrigerante,
  required CategoriaFgas categoria,
  required OrigenGas origen,
  required DateTime fecha,
  DatosOrigenGas datos = const DatosOrigenGas(),
}) {
  if (tipo != TipoMovimientoGas.carga) {
    return const CargaPermitida(regla: ReglaAplicada.ninguna);
  }
  final r134 = normativa.fgas.art134;
  final r133 = normativa.fgas.art133;
  final r135 = normativa.fgas.art135;
  final pcg = refrigerante.pcg;
  final pcgTexto = _num(pcg.roundToDouble());

  // Las prohibiciones del art. 13.3 a 13.5 son para gases del anexo I.
  if (r134.soloAnexoI && refrigerante.anexo != AnexoFgas.i) {
    return const CargaPermitida(regla: ReglaAplicada.ninguna);
  }

  switch (categoria) {
    case CategoriaFgas.aireAcondicionadoBombaCalor:
      if (!r134.categorias.contains(categoria) ||
          pcg < r134.umbralPcg ||
          !esIgualOPosterior(fecha, r134.desde)) {
        return const CargaPermitida(regla: ReglaAplicada.ninguna);
      }
      final base =
          '${refrigerante.codigo} tiene PCG $pcgTexto (≥ ${_num(r134.umbralPcg)}): '
          'desde el ${_dia(r134.desde)} no se puede usar en el mantenimiento de '
          'aire acondicionado ni bombas de calor';
      if (esIgualOPosterior(fecha, r134.excepcionesHasta)) {
        return CargaBloqueada(
          articulo: _art134,
          motivo:
              '$base, y desde el ${_dia(r134.excepcionesHasta)} tampoco '
              'regenerado ni reciclado',
        );
      }
      final regla = r134.origenes[origen]!;
      if (!regla.permitido) {
        return CargaBloqueada(
          articulo: _art134,
          motivo:
              '$base si es gas ${origen.wire}. Hasta el '
              '${_dia(r134.excepcionesHasta)} solo se admite regenerado (con '
              'la etiqueta del art. 12.7) o reciclado (recuperado por la propia '
              'empresa o para ella)',
        );
      }
      final faltan = [for (final d in regla.datos) _datoOrigen(d)]
          .where((d) => !datos._tiene(d))
          .toList(growable: false);
      if (faltan.isNotEmpty) {
        return CargaBloqueada(
          articulo: _art134,
          motivo:
              '$base. Para usar gas ${origen.wire} faltan: '
              '${faltan.map(_textoDato).join(', ')}',
          faltan: faltan,
        );
      }
      return CargaPermitida(
        regla: ReglaAplicada.art134,
        nota:
            'Gas ${origen.wire} de PCG ≥ ${_num(r134.umbralPcg)} admitido hasta '
            'el ${_dia(r134.excepcionesHasta)} '
            '(art. 13.4, letra ${origen == OrigenGas.regenerado ? 'a' : 'b'})',
      );

    case CategoriaFgas.refrigeracion:
      // 13.5 (desde 2032, PCG ≥ 750) es más amplio que el 13.3: se avisa del
      // más exigente que aplique. En el MVP ninguno bloquea (§4.3).
      if (r135.categorias.contains(categoria) &&
          pcg >= r135.umbralPcg &&
          esIgualOPosterior(fecha, r135.desde)) {
        return CargaConAviso(
          articulo: _art135,
          motivo:
              'Refrigeración con ${refrigerante.codigo} (PCG $pcgTexto): desde '
              'el ${_dia(r135.desde)} el art. 13.5 prohíbe PCG ≥ '
              '${_num(r135.umbralPcg)} en aparatos fijos de refrigeración '
              '(salvo enfriadoras). Compruébelo',
        );
      }
      if (r133.categorias.contains(categoria) && pcg >= r133.umbralPcg) {
        return CargaConAviso(
          articulo: _art133,
          motivo:
              'Refrigeración con ${refrigerante.codigo} (PCG $pcgTexto ≥ '
              '${_num(r133.umbralPcg)}): compruebe el art. 13.3 (desde el '
              '${_dia(r133.desde)}, solo regenerado o reciclado hasta 2030). '
              'La app no bloquea en refrigeración',
        );
      }
      return const CargaPermitida(regla: ReglaAplicada.ninguna);

    case CategoriaFgas.otro:
      if (pcg >= r133.umbralPcg) {
        return CargaConAviso(
          articulo: 'Reglamento (UE) 2024/573, art. 13',
          motivo:
              '${refrigerante.codigo} tiene PCG $pcgTexto: indique si el '
              'aparato es de aire acondicionado, bomba de calor o refrigeración '
              'para aplicar el art. 13.4 o el 13.3',
        );
      }
      return const CargaPermitida(regla: ReglaAplicada.ninguna);
  }
}

DatoOrigen _datoOrigen(String wire) => DatoOrigen.values.firstWhere(
  (d) => d.wire == wire,
  orElse: () =>
      throw StateError('Dato de origen desconocido en la normativa: $wire'),
);

String _textoDato(DatoOrigen d) => switch (d) {
  DatoOrigen.regeneradoLote => 'el lote de la etiqueta (art. 12.7)',
  DatoOrigen.regeneradoEtiquetaFotoId => 'la foto de la etiqueta del art. 12.7',
  DatoOrigen.recicladoRecuperadoPor =>
    'quién lo recuperó (la propia empresa o para ella)',
  DatoOrigen.recicladoDeclaracion => 'la declaración de recuperación',
};

// ---------------------------------------------------------------------------
// Formato de cifras en los textos (coma decimal, como el resto de la app)
// ---------------------------------------------------------------------------

String _num(double v) {
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  return s.replaceAll('.', ',');
}

String _kg(double v) => '${_num(_redondear6(v))} kg';

String _dia(DiaCalendario d) =>
    '${d.dia.toString().padLeft(2, '0')}/${d.mes.toString().padLeft(2, '0')}/${d.anio}';
