// Estados derivados en local (DISEÑO.md §7.2, §7.5 y §8.2, «Conflictos»).
//
// En el servidor los escriben triggers `security definer`:
// `orden_estado_desde_inspeccion` (estado de la orden) y el de
// `estado_equipo` al recibir un cierre firmado. El técnico no escribe ninguno
// de los dos. Pero sin red la app tiene que enseñarlos ya: la orden «En curso»
// en cuanto empieza la visita y el último valor de un equipo en cuanto se
// firma. Estas funciones repiten esa lógica en local, solo para mostrarla:
// lo que baja del servidor siempre gana, y `estado_equipo` nunca se encola.
//
// Funciones puras, sin reloj ni base de datos, con pruebas en
// `test/estados_test.dart`. El día 9, los triggers de `schema.sql` deben
// hacer exactamente lo mismo [A VERIFICAR el día 9].

import 'dart:convert';

/// `ordenes_trabajo.estado` (§7.5).
enum EstadoOrden {
  pendiente('pendiente'),
  enCurso('en_curso'),
  firmada('firmada'),
  cancelada('cancelada');

  const EstadoOrden(this.wire);
  final String wire;

  static EstadoOrden desde(String wire) => values.firstWhere(
    (e) => e.wire == wire,
    orElse: () => throw ArgumentError.value(wire, 'estado', 'Desconocido'),
  );
}

/// `inspecciones.estado` (§7.5; `descartada`, ver `tablas/trabajo.dart`).
enum EstadoInspeccion {
  enCurso('en_curso'),
  lista('lista'),
  firmada('firmada'),
  descartada('descartada');

  const EstadoInspeccion(this.wire);
  final String wire;

  static EstadoInspeccion desde(String wire) => values.firstWhere(
    (e) => e.wire == wire,
    orElse: () => throw ArgumentError.value(wire, 'estado', 'Desconocido'),
  );
}

/// Estado de la orden que se enseña en el aparato.
///
/// [estadoServidor] es `ordenes_trabajo.estado` tal como está en Drift (lo
/// último que bajó, o lo sembrado). [inspecciones] son los estados de las
/// inspecciones locales de esa orden. Reglas, en este orden:
///
/// 1. `cancelada` la pone la oficina y gana a todo.
/// 2. Una inspección local firmada → `firmada` (aunque no haya subido).
/// 3. Una inspección local en curso o lista → `en_curso`.
/// 4. El servidor dice `firmada` → `firmada`: lo firmado no vuelve atrás,
///    aunque su inspección haya salido de la ventana de 60 días.
/// 5. Solo hay inspecciones descartadas → `pendiente` (el trigger devuelve la
///    orden a pendiente al descartar, §7.5).
/// 6. Si no, lo que diga el servidor.
EstadoOrden estadoOrdenLocal({
  required EstadoOrden estadoServidor,
  required Iterable<EstadoInspeccion> inspecciones,
}) {
  if (estadoServidor == EstadoOrden.cancelada) return EstadoOrden.cancelada;
  if (inspecciones.contains(EstadoInspeccion.firmada)) {
    return EstadoOrden.firmada;
  }
  if (inspecciones.any(
    (e) => e == EstadoInspeccion.enCurso || e == EstadoInspeccion.lista,
  )) {
    return EstadoOrden.enCurso;
  }
  if (estadoServidor == EstadoOrden.firmada) return EstadoOrden.firmada;
  if (inspecciones.isNotEmpty) return EstadoOrden.pendiente;
  return estadoServidor;
}

// ---------------------------------------------------------------------------
// estado_equipo
// ---------------------------------------------------------------------------

/// Un valor de `estado_equipo.ultimos_valores_json`, por `clave` de ítem.
class UltimoValor {
  const UltimoValor({required this.valor, this.unidad, required this.fecha});

  final double valor;
  final String? unidad;

  /// Instante de la firma del informe que lo midió (UTC).
  final DateTime fecha;

  Map<String, Object?> toJson() => {
    'valor': valor,
    'unidad': unidad,
    'fecha': fecha.toUtc().toIso8601String(),
  };

  static UltimoValor fromJson(Map<String, Object?> j) => UltimoValor(
    valor: (j['valor']! as num).toDouble(),
    unidad: j['unidad'] as String?,
    fecha: DateTime.parse(j['fecha']! as String).toUtc(),
  );
}

/// Una incidencia de `estado_equipo.incidencias_abiertas_json`.
class IncidenciaAbierta {
  const IncidenciaAbierta({
    required this.id,
    required this.descripcion,
    required this.gravedad,
    required this.fecha,
  });

  final String id;
  final String descripcion;

  /// `leve|grave|muy_grave`, o null si llegó sin elegir (no debería: la firma
  /// lo exige, día 6).
  final String? gravedad;

  /// Instante de la firma del informe que la registró (UTC).
  final DateTime fecha;

  Map<String, Object?> toJson() => {
    'id': id,
    'descripcion': descripcion,
    'gravedad': gravedad,
    'fecha': fecha.toUtc().toIso8601String(),
  };

  static IncidenciaAbierta fromJson(Map<String, Object?> j) =>
      IncidenciaAbierta(
        id: j['id']! as String,
        descripcion: j['descripcion']! as String,
        gravedad: j['gravedad'] as String?,
        fecha: DateTime.parse(j['fecha']! as String).toUtc(),
      );
}

/// Los hechos de `estado_equipo` (§7.2), sin las columnas de sincronización.
class HechosEquipo {
  const HechosEquipo({
    this.ultimoPreventivoAt,
    this.ultimaInspeccionId,
    this.ultimoControlFugasAt,
    this.ultimoResultadoFugas,
    this.ultimosValores = const {},
    this.incidenciasAbiertas = const [],
  });

  /// Un equipo sin ninguna visita firmada en Inspecta.
  static const vacio = HechosEquipo();

  final DateTime? ultimoPreventivoAt;
  final String? ultimaInspeccionId;
  final DateTime? ultimoControlFugasAt;

  /// `sin_fuga|fuga`.
  final String? ultimoResultadoFugas;
  final Map<String, UltimoValor> ultimosValores;
  final List<IncidenciaAbierta> incidenciasAbiertas;

  /// Lee las dos columnas jsonb tal como las guarda Drift (texto JSON).
  /// Una lista o un mapa mal formados fallan: inventar «sin incidencias»
  /// escondería un defecto abierto (mismo motivo que `Jsonb.fromJson`).
  static HechosEquipo desdeColumnas({
    DateTime? ultimoPreventivoAt,
    String? ultimaInspeccionId,
    DateTime? ultimoControlFugasAt,
    String? ultimoResultadoFugas,
    required String ultimosValoresJson,
    required String incidenciasAbiertasJson,
  }) {
    final valores = (jsonDecode(ultimosValoresJson) as Map)
        .cast<String, Object?>();
    final incidencias = jsonDecode(incidenciasAbiertasJson) as List;
    return HechosEquipo(
      ultimoPreventivoAt: ultimoPreventivoAt,
      ultimaInspeccionId: ultimaInspeccionId,
      ultimoControlFugasAt: ultimoControlFugasAt,
      ultimoResultadoFugas: ultimoResultadoFugas,
      ultimosValores: {
        for (final MapEntry(:key, :value) in valores.entries)
          key: UltimoValor.fromJson((value! as Map).cast<String, Object?>()),
      },
      incidenciasAbiertas: [
        for (final i in incidencias)
          IncidenciaAbierta.fromJson((i as Map).cast<String, Object?>()),
      ],
    );
  }

  /// `ultimos_valores_json`, con las claves ordenadas (texto estable).
  String get ultimosValoresJson {
    final claves = ultimosValores.keys.toList()..sort();
    return jsonEncode({for (final k in claves) k: ultimosValores[k]!.toJson()});
  }

  /// `incidencias_abiertas_json`, de la más antigua a la más reciente.
  String get incidenciasAbiertasJson =>
      jsonEncode([for (final i in incidenciasAbiertas) i.toJson()]);
}

/// Un valor medido en la visita que se acaba de firmar.
class ValorMedido {
  const ValorMedido({required this.clave, required this.valor, this.unidad});
  final String clave;
  final double valor;
  final String? unidad;
}

/// Una incidencia registrada en la visita que se acaba de firmar.
class IncidenciaNueva {
  const IncidenciaNueva({
    required this.id,
    required this.descripcion,
    required this.gravedad,
  });
  final String id;
  final String descripcion;
  final String? gravedad;
}

/// Lo que aporta a un equipo una inspección firmada (`inspeccion_equipos` y
/// sus hijos).
class FirmaDeEquipo {
  const FirmaDeEquipo({
    required this.inspeccionId,
    required this.firmadaAt,
    required this.esPreventivo,
    this.valores = const [],
    this.incidenciasNuevas = const [],
    this.incidenciasResueltas = const {},
    this.resultadoFugas,
  });

  final String inspeccionId;
  final DateTime firmadaAt;

  /// La orden es `preventivo`. Un correctivo o un control de fugas no
  /// reinician el plazo del preventivo RITE [A VERIFICAR con el técnico de
  /// la llamada: si un correctivo que repasa todo el checklist cuenta].
  final bool esPreventivo;
  final List<ValorMedido> valores;
  final List<IncidenciaNueva> incidenciasNuevas;

  /// `resoluciones_incidencia.incidencia_id` de esta inspección.
  final Set<String> incidenciasResueltas;

  /// Resultado del último `controles_fugas` de este equipo en la visita
  /// (`sin_fuga|fuga`); null si no se hizo control. La fecha es la de la
  /// firma: `controles_fugas` no lleva fecha propia (§7.5).
  final String? resultadoFugas;
}

/// Aplica a [actual] una inspección recién firmada, como el trigger del
/// servidor al recibir el cierre (§7.2).
///
/// No se recalcula desde cero con las inspecciones locales a propósito: en la
/// nube solo están las de los últimos 60 días (§8.2), y la historia larga
/// (un preventivo de hace dos años, una incidencia abierta de 2024) solo vive
/// en la fila que bajó. Por eso se parte de ella y se le suma la visita:
///
/// - `ultimo_preventivo_at`: la firma, si es preventivo y es más reciente.
/// - `ultima_inspeccion_id`: esta, si es la más reciente que se conoce (las
///   firmas se aplican en orden; una más antigua no la desplaza).
/// - Control de fugas: fecha y resultado, si hubo control y es más reciente.
/// - Últimos valores: por clave, gana el más reciente.
/// - Incidencias abiertas: las de antes, menos las resueltas en esta visita,
///   más las nuevas (que no se resuelven en la misma visita en que nacen).
HechosEquipo aplicarFirma(HechosEquipo actual, FirmaDeEquipo firma) {
  final f = firma.firmadaAt.toUtc();
  bool masReciente(DateTime? previo) => previo == null || !f.isBefore(previo);

  final valores = {...actual.ultimosValores};
  for (final v in firma.valores) {
    final previo = valores[v.clave];
    if (previo == null || masReciente(previo.fecha)) {
      valores[v.clave] = UltimoValor(
        valor: v.valor,
        unidad: v.unidad,
        fecha: f,
      );
    }
  }

  final abiertas = [
    for (final i in actual.incidenciasAbiertas)
      if (!firma.incidenciasResueltas.contains(i.id)) i,
  ];
  final yaEstan = {for (final i in abiertas) i.id};
  for (final n in firma.incidenciasNuevas) {
    if (yaEstan.contains(n.id)) continue;
    abiertas.add(
      IncidenciaAbierta(
        id: n.id,
        descripcion: n.descripcion,
        gravedad: n.gravedad,
        fecha: f,
      ),
    );
  }

  final fugasNuevo =
      firma.resultadoFugas != null && masReciente(actual.ultimoControlFugasAt);

  // La última inspección conocida: la más reciente entre la que ya estaba
  // (con fecha desconocida, se toma por anterior) y esta.
  final fechasConocidas = [
    actual.ultimoPreventivoAt,
    actual.ultimoControlFugasAt,
    for (final v in actual.ultimosValores.values) v.fecha,
    for (final i in actual.incidenciasAbiertas) i.fecha,
  ].whereType<DateTime>();
  final ultimaConocida = fechasConocidas.isEmpty
      ? null
      : fechasConocidas.reduce((a, b) => a.isAfter(b) ? a : b);

  return HechosEquipo(
    ultimoPreventivoAt:
        firma.esPreventivo && masReciente(actual.ultimoPreventivoAt)
        ? f
        : actual.ultimoPreventivoAt,
    ultimaInspeccionId: masReciente(ultimaConocida)
        ? firma.inspeccionId
        : actual.ultimaInspeccionId,
    ultimoControlFugasAt: fugasNuevo ? f : actual.ultimoControlFugasAt,
    ultimoResultadoFugas: fugasNuevo
        ? firma.resultadoFugas
        : actual.ultimoResultadoFugas,
    ultimosValores: valores,
    incidenciasAbiertas: abiertas,
  );
}
