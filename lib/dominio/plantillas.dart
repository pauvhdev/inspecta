// Plantillas versionadas de checklist (DISEÑO.md §4.1.4, §7.4).
//
// Las plantillas base viven como JSON en `assets/plantillas/` (ver su
// README): una fila de `plantillas` y sus `items_plantilla`, con las mismas
// columnas que Drift y Postgres para sembrarlas tal cual. Este fichero tiene
// tres piezas separadas:
//   1. `parsearPlantilla`: parseo puro desde un String, con validación
//      estricta (no depende de Flutter; se prueba con dart:io).
//   2. `cargarPlantillasBase`: lee todos los JSON del bundle.
//   3. `sugerirPlantillas`: qué plantillas ofrecer a un equipo según tipo,
//      potencia, uso y potencia de la instalación (regla de O2 y F2.2).
//
// Ojo con los nombres: Drift genera también las clases de fila `Plantilla` e
// `ItemPlantilla` (`lib/data/local/tablas/plantillas.dart`, exportadas por
// `app_database.dart`). Un fichero que use las dos importa una con prefijo
// (`import '…/app_database.dart' as db;`). Estas son las del dominio: ya
// validadas, con enums y sin `created_at`/`updated_at`.

import 'dart:convert';

import 'package:flutter/services.dart'
    show AssetBundle, AssetManifest, rootBundle;
import 'package:uuid/uuid.dart';

import 'tipos.dart';

// ---------------------------------------------------------------------------
// Ids deterministas
// ---------------------------------------------------------------------------

/// Namespace UUID de las plantillas de Inspecta.
///
/// Es `uuid v5(NAMESPACE_URL, 'urn:inspecta:plantillas')` (lo comprueba
/// `test/plantillas_test.dart`). **No se cambia nunca:** de él salen los ids
/// de todas las plantillas e ítems ya sembrados y firmados en informes. Con
/// ids deterministas, sembrar la misma versión en cualquier aparato o en el
/// servidor da las mismas filas, y el upsert es idempotente.
const namespacePlantillas = 'a0520858-c7b4-57cb-a047-8092aa6d31e0';

const _uuid = Uuid();

/// Id de una versión de plantilla: v5 de `plantilla:<clave>:v<version>`.
String idPlantilla(String clave, int version) =>
    _uuid.v5(namespacePlantillas, 'plantilla:$clave:v$version');

/// Id de un ítem: v5 de `item:<clave_plantilla>:v<version>:<clave_item>`.
/// Cambia con la versión: un ítem de la v2 es otra fila (la v1 es inmutable).
String idItemPlantilla(String clavePlantilla, int version, String claveItem) =>
    _uuid.v5(namespacePlantillas, 'item:$clavePlantilla:v$version:$claveItem');

// ---------------------------------------------------------------------------
// Tipos cerrados
// ---------------------------------------------------------------------------

/// Cómo se responde un ítem (`items_plantilla.tipo_respuesta`, §7.4; T5/T6).
enum TipoRespuesta {
  /// Los 4 botones: OK / Observación / Defecto / N.A.
  estado('estado'),

  /// Los 4 botones y un valor con unidad (teclado T6).
  estadoValor('estado_valor'),

  /// Solo el valor con unidad.
  soloValor('solo_valor'),

  /// Sí / No.
  siNo('si_no');

  const TipoRespuesta(this.wire);
  final String wire;

  /// Lleva valor numérico, y por tanto unidad y rango plausible.
  bool get llevaValor => this == estadoValor || this == soloValor;

  static TipoRespuesta? _desde(String wire) {
    for (final t in values) {
      if (t.wire == wire) return t;
    }
    return null;
  }
}

/// Tipo de intervención de la orden (`ordenes_trabajo.tipo_intervencion`,
/// §7.5). Va aquí y no en `tipos.dart` porque de momento solo la usan las
/// plantillas; si otro módulo la necesita, se mueve allí.
enum TipoIntervencion {
  preventivo('preventivo'),
  correctivo('correctivo'),
  controlFugas('control_fugas'),
  recontrolFugas('recontrol_fugas'),
  puestaMarcha('puesta_marcha');

  const TipoIntervencion(this.wire);
  final String wire;

  static TipoIntervencion desde(String wire) => values.firstWhere(
    (t) => t.wire == wire,
    orElse: () =>
        throw ArgumentError.value(wire, 'tipo_intervencion', 'Desconocido'),
  );
}

/// Estado de una versión de plantilla (§7.4). Los JSON base solo admiten
/// `publicada`: un borrador no se siembra.
enum EstadoPlantilla {
  borrador('borrador'),
  publicada('publicada'),
  retirada('retirada');

  const EstadoPlantilla(this.wire);
  final String wire;
}

// ---------------------------------------------------------------------------
// Modelos inmutables
// ---------------------------------------------------------------------------

/// A qué equipos se aplica una plantilla (`plantillas.aplica_a`, jsonb).
///
/// Potencias del equipo como en la Tabla 3.1 del RITE: `potenciaMinKw`
/// exclusiva y `potenciaMaxKw` inclusiva («12 kW < Pn ≤ 70 kW»); null = sin
/// límite. `potenciaInstalacionMaxKw` es inclusiva: la fila «Instalaciones de
/// potencia superior a 70 kW» empieza por encima de 70.
class AplicaA {
  const AplicaA({
    required this.tipos,
    required this.usos,
    required this.potenciaMinKw,
    required this.potenciaMaxKw,
    required this.potenciaInstalacionMaxKw,
    required this.intervenciones,
  });

  final List<TipoEquipo> tipos;
  final List<UsoEdificio> usos;
  final double? potenciaMinKw;
  final double? potenciaMaxKw;
  final double? potenciaInstalacionMaxKw;
  final List<TipoIntervencion> intervenciones;

  /// ¿La potencia del equipo cae en la franja? Sin potencia conocida no se
  /// puede decidir; quien llama lo trata aparte.
  bool admitePotenciaEquipo(double kw) =>
      (potenciaMinKw == null || kw > potenciaMinKw!) &&
      (potenciaMaxKw == null || kw <= potenciaMaxKw!);

  bool admitePotenciaInstalacion(double kw) =>
      potenciaInstalacionMaxKw == null || kw <= potenciaInstalacionMaxKw!;

  Map<String, Object?> toJson() => {
    'tipos': [for (final t in tipos) t.wire],
    'usos': [for (final u in usos) u.wire],
    'potencia_min_kw': potenciaMinKw,
    'potencia_max_kw': potenciaMaxKw,
    'potencia_instalacion_max_kw': potenciaInstalacionMaxKw,
    'intervenciones': [for (final i in intervenciones) i.wire],
  };
}

/// Fila de `items_plantilla` (§7.4).
class ItemPlantilla {
  const ItemPlantilla({
    required this.id,
    required this.empresaId,
    required this.plantillaId,
    required this.clave,
    required this.orden,
    required this.seccion,
    required this.codigoNormativo,
    required this.texto,
    required this.tipoRespuesta,
    required this.unidad,
    required this.rangoMin,
    required this.rangoMax,
    required this.obligatorio,
    required this.fotoObligatoria,
    required this.analizableIa,
  });

  final String id;
  final String? empresaId;
  final String plantillaId;

  /// Estable entre versiones y compartida entre plantillas cuando es la misma
  /// operación: es la clave de `estado_equipo.ultimos_valores_json`.
  final String clave;
  final int orden;
  final String seccion;

  /// Lo que T5 muestra en pequeño y la respuesta copia (§7.4): permite
  /// localizar la operación en la norma.
  final String codigoNormativo;
  final String texto;
  final TipoRespuesta tipoRespuesta;
  final String? unidad;

  /// Rango plausible para avisar en T6 y validar la voz (§9.3); no bloquea.
  final double? rangoMin;
  final double? rangoMax;
  final bool obligatorio;
  final bool fotoObligatoria;
  final bool analizableIa;

  /// ¿Hace falta foto para dar el ítem por respondido (F4.1, T12)?
  ///
  /// Un ítem marcado N.A. no la exige aunque tenga `foto_obligatoria`: no hay
  /// nada que fotografiar. Es el caso de `etiqueta_fgas` en un equipo con
  /// refrigerante no fluorado (R-290, R-744), que no lleva etiqueta F-gas
  /// (art. 12.1 del Rgto. 2024/573: solo los aparatos «que contengan gases
  /// fluorados»). [A VERIFICAR] que T5/T12 usen esta regla (DISEÑO.md no la
  /// escribe).
  bool exigeFoto({required bool marcadoNa}) => fotoObligatoria && !marcadoNa;

  /// ¿El valor cae fuera del rango plausible? (T6 avisa, no bloquea.)
  bool fueraDeRango(double valor) =>
      rangoMin != null &&
      rangoMax != null &&
      (valor < rangoMin! || valor > rangoMax!);

  Map<String, Object?> toJson() => {
    'id': id,
    'empresa_id': empresaId,
    'plantilla_id': plantillaId,
    'clave': clave,
    'orden': orden,
    'seccion': seccion,
    'codigo_normativo': codigoNormativo,
    'texto': texto,
    'tipo_respuesta': tipoRespuesta.wire,
    'unidad': unidad,
    'rango_min': rangoMin,
    'rango_max': rangoMax,
    'obligatorio': obligatorio,
    'foto_obligatoria': fotoObligatoria,
    'analizable_ia': analizableIa,
  };
}

/// Fila de `plantillas` (§7.4) con sus ítems ordenados por `orden`.
class Plantilla {
  Plantilla({
    required this.id,
    required this.empresaId,
    required this.clave,
    required this.version,
    required this.titulo,
    required this.baseNormativa,
    required this.aplicaA,
    required this.estado,
    required this.sustituyeA,
    required this.publicadaAt,
    required List<ItemPlantilla> items,
  }) : items = List.unmodifiable(items);

  final String id;
  final String? empresaId;
  final String clave;
  final int version;
  final String titulo;
  final String baseNormativa;
  final AplicaA aplicaA;
  final EstadoPlantilla estado;
  final String? sustituyeA;
  final DateTime publicadaAt;
  final List<ItemPlantilla> items;

  ItemPlantilla? item(String clave) {
    for (final i in items) {
      if (i.clave == clave) return i;
    }
    return null;
  }

  /// La fila de `plantillas` con los nombres de columna (para sembrar).
  Map<String, Object?> toJson() => {
    'id': id,
    'empresa_id': empresaId,
    'clave': clave,
    'version': version,
    'titulo': titulo,
    'base_normativa': baseNormativa,
    'aplica_a': aplicaA.toJson(),
    'estado': estado.wire,
    'sustituye_a': sustituyeA,
    'publicada_at': publicadaAt.toUtc().toIso8601String(),
  };

  @override
  String toString() => 'Plantilla($clave v$version)';
}

// ---------------------------------------------------------------------------
// Parseo con validación estricta
// ---------------------------------------------------------------------------

/// Un JSON de plantilla que no cumple las reglas. El mensaje dice qué
/// fichero, qué ítem y qué falla, para arreglarlo sin depurar.
class PlantillaInvalida implements Exception {
  PlantillaInvalida(this.mensaje);
  final String mensaje;

  @override
  String toString() => 'PlantillaInvalida: $mensaje';
}

const _columnasPlantilla = {
  'id',
  'empresa_id',
  'clave',
  'version',
  'titulo',
  'base_normativa',
  'aplica_a',
  'estado',
  'sustituye_a',
  'publicada_at',
};

const _columnasItem = {
  'id',
  'empresa_id',
  'plantilla_id',
  'clave',
  'orden',
  'seccion',
  'codigo_normativo',
  'texto',
  'tipo_respuesta',
  'unidad',
  'rango_min',
  'rango_max',
  'obligatorio',
  'foto_obligatoria',
  'analizable_ia',
};

const _clavesAplicaA = {
  'tipos',
  'usos',
  'potencia_min_kw',
  'potencia_max_kw',
  'potencia_instalacion_max_kw',
  'intervenciones',
};

/// Clave del ítem de la etiqueta F-gas (art. 12 del Rgto. 2024/573), que
/// tiene reglas propias: nunca analizable por la IA (§9.3).
const claveEtiquetaFgas = 'etiqueta_fgas';

/// snake_case corto: empieza por letra, solo minúsculas, cifras y `_`.
final _reClave = RegExp(r'^[a-z][a-z0-9_]{1,40}$');

/// Texto de un ítem: corto, porque se lee de un vistazo con guantes (§6.0).
const _maxTextoItem = 80;

/// Parsea y valida una plantilla desde su JSON. [origen] (p. ej., el nombre
/// del fichero) solo sirve para los mensajes de error.
///
/// Rechaza (con [PlantillaInvalida]): columnas de más o de menos (el JSON se
/// siembra tal cual), estado distinto de `publicada`, `empresa_id` no nulo,
/// ids que no son los deterministas, `sustituye_a` incoherente con la
/// versión, claves de ítem repetidas o mal formadas, `orden` repetido o con
/// huecos, `tipo_respuesta` desconocido, unidad o rango donde no tocan (o
/// ausentes donde sí), `rango_min >= rango_max`, `solo_valor` obligatorio
/// (no tiene N.A.) y `analizable_ia` fuera de los ítems de estado o en la
/// etiqueta F-gas (§9.3).
Plantilla parsearPlantilla(String json, {String origen = 'plantilla'}) {
  final Object? raiz;
  try {
    raiz = jsonDecode(json);
  } on FormatException catch (e) {
    throw PlantillaInvalida('$origen: JSON mal formado (${e.message})');
  }
  final doc = _mapa(raiz, origen);
  _columnasExactas(doc, const {'plantilla', 'items_plantilla'}, origen);

  final p = _mapa(doc['plantilla'], '$origen › plantilla');
  final ctx = '$origen › plantilla';
  _columnasExactas(p, _columnasPlantilla, ctx);

  final clave = _texto(p, 'clave', ctx);
  if (!_reClave.hasMatch(clave)) {
    throw PlantillaInvalida('$ctx: clave «$clave» no es snake_case corto');
  }
  final version = _entero(p, 'version', ctx);
  if (version < 1) throw PlantillaInvalida('$ctx: version debe ser ≥ 1');
  final c = '$origen › $clave v$version';

  final id = _texto(p, 'id', c);
  final idEsperado = idPlantilla(clave, version);
  if (id != idEsperado) {
    throw PlantillaInvalida(
      '$c: id «$id» no es el determinista; debe ser «$idEsperado»',
    );
  }
  if (p['empresa_id'] != null) {
    throw PlantillaInvalida(
      '$c: empresa_id debe ser null (plantilla base de Inspecta)',
    );
  }
  final estadoWire = _texto(p, 'estado', c);
  if (estadoWire != EstadoPlantilla.publicada.wire) {
    throw PlantillaInvalida(
      '$c: estado «$estadoWire»; solo se siembran versiones publicadas',
    );
  }
  final sustituyeA = p['sustituye_a'];
  if (version == 1 && sustituyeA != null) {
    throw PlantillaInvalida('$c: la versión 1 no sustituye a ninguna');
  }
  if (version > 1 && sustituyeA != idPlantilla(clave, version - 1)) {
    throw PlantillaInvalida(
      '$c: sustituye_a debe ser el id de la v${version - 1} '
      '(«${idPlantilla(clave, version - 1)}»)',
    );
  }
  final publicadaTxt = _texto(p, 'publicada_at', c);
  final publicadaAt = DateTime.tryParse(publicadaTxt);
  if (publicadaAt == null || !publicadaAt.isUtc) {
    throw PlantillaInvalida(
      '$c: publicada_at «$publicadaTxt» debe ser ISO 8601 en UTC (con Z)',
    );
  }

  final aplicaA = _parsearAplicaA(p['aplica_a'], '$c › aplica_a');

  final crudos = doc['items_plantilla'];
  if (crudos is! List || crudos.isEmpty) {
    throw PlantillaInvalida('$c: items_plantilla debe ser una lista no vacía');
  }
  final items = <ItemPlantilla>[];
  final claves = <String, int>{};
  final ordenes = <int>{};
  for (var i = 0; i < crudos.length; i++) {
    final item = _parsearItem(
      crudos[i],
      clave,
      version,
      id,
      '$c › ítem ${i + 1}',
    );
    final previa = claves[item.clave];
    if (previa != null) {
      throw PlantillaInvalida(
        '$c: clave de ítem duplicada «${item.clave}» (órdenes $previa y ${item.orden})',
      );
    }
    claves[item.clave] = item.orden;
    if (!ordenes.add(item.orden)) {
      throw PlantillaInvalida('$c: orden ${item.orden} repetido');
    }
    items.add(item);
  }
  // Orden 1..n sin huecos: T5 cuenta «7/24» y el PDF numera con él.
  for (var n = 1; n <= items.length; n++) {
    if (!ordenes.contains(n)) {
      throw PlantillaInvalida(
        '$c: los órdenes deben ir de 1 a ${items.length} sin huecos; falta el $n',
      );
    }
  }
  items.sort((a, b) => a.orden.compareTo(b.orden));

  return Plantilla(
    id: id,
    empresaId: null,
    clave: clave,
    version: version,
    titulo: _texto(p, 'titulo', c),
    baseNormativa: _texto(p, 'base_normativa', c),
    aplicaA: aplicaA,
    estado: EstadoPlantilla.publicada,
    sustituyeA: sustituyeA as String?,
    publicadaAt: publicadaAt,
    items: items,
  );
}

AplicaA _parsearAplicaA(Object? crudo, String c) {
  final a = _mapa(crudo, c);
  _columnasExactas(a, _clavesAplicaA, c);

  List<T> lista<T>(String campo, T? Function(String) desde) {
    final l = a[campo];
    if (l is! List || l.isEmpty) {
      throw PlantillaInvalida('$c: $campo debe ser una lista no vacía');
    }
    final r = <T>[];
    for (final e in l) {
      final v = e is String ? desde(e) : null;
      if (v == null) throw PlantillaInvalida('$c: $campo «$e» desconocido');
      if (r.contains(v)) throw PlantillaInvalida('$c: $campo «$e» repetido');
      r.add(v);
    }
    return r;
  }

  T? sinExcepcion<T>(T Function() f) {
    try {
      return f();
    } on ArgumentError {
      return null;
    }
  }

  final min = _numeroOpcional(a, 'potencia_min_kw', c);
  final max = _numeroOpcional(a, 'potencia_max_kw', c);
  final inst = _numeroOpcional(a, 'potencia_instalacion_max_kw', c);
  for (final (nombre, v) in [
    ('potencia_min_kw', min),
    ('potencia_max_kw', max),
    ('potencia_instalacion_max_kw', inst),
  ]) {
    if (v != null && v < 0) throw PlantillaInvalida('$c: $nombre negativa');
  }
  if (min != null && max != null && min >= max) {
    throw PlantillaInvalida(
      '$c: potencia_min_kw ($min) debe ser menor que potencia_max_kw ($max)',
    );
  }
  return AplicaA(
    tipos: List.unmodifiable(
      lista('tipos', (w) => sinExcepcion(() => TipoEquipo.desde(w))),
    ),
    usos: List.unmodifiable(
      lista('usos', (w) => sinExcepcion(() => UsoEdificio.desde(w))),
    ),
    potenciaMinKw: min,
    potenciaMaxKw: max,
    potenciaInstalacionMaxKw: inst,
    intervenciones: List.unmodifiable(
      lista(
        'intervenciones',
        (w) => sinExcepcion(() => TipoIntervencion.desde(w)),
      ),
    ),
  );
}

ItemPlantilla _parsearItem(
  Object? crudo,
  String clavePlantilla,
  int version,
  String plantillaId,
  String ctx,
) {
  final m = _mapa(crudo, ctx);
  _columnasExactas(m, _columnasItem, ctx);
  final clave = _texto(m, 'clave', ctx);
  if (!_reClave.hasMatch(clave)) {
    throw PlantillaInvalida('$ctx: clave «$clave» no es snake_case corto');
  }
  final c = '$ctx («$clave»)';

  final id = _texto(m, 'id', c);
  final esperado = idItemPlantilla(clavePlantilla, version, clave);
  if (id != esperado) {
    throw PlantillaInvalida(
      '$c: id «$id» no es el determinista; debe ser «$esperado»',
    );
  }
  if (m['empresa_id'] != null) {
    throw PlantillaInvalida('$c: empresa_id debe ser null (plantilla base)');
  }
  if (m['plantilla_id'] != plantillaId) {
    throw PlantillaInvalida(
      '$c: plantilla_id «${m['plantilla_id']}» no es el de su plantilla',
    );
  }
  final orden = _entero(m, 'orden', c);
  if (orden < 1) throw PlantillaInvalida('$c: orden debe ser ≥ 1');

  final texto = _texto(m, 'texto', c);
  if (texto.length > _maxTextoItem) {
    throw PlantillaInvalida(
      '$c: texto de ${texto.length} caracteres; máximo $_maxTextoItem '
      '(se lee con guantes, §6.0)',
    );
  }

  final tipoWire = _texto(m, 'tipo_respuesta', c);
  final tipo = TipoRespuesta._desde(tipoWire);
  if (tipo == null) {
    throw PlantillaInvalida(
      '$c: tipo_respuesta desconocido «$tipoWire»; válidos: '
      '${TipoRespuesta.values.map((t) => t.wire).join(', ')}',
    );
  }

  final unidad = m['unidad'];
  final rangoMin = _numeroOpcional(m, 'rango_min', c);
  final rangoMax = _numeroOpcional(m, 'rango_max', c);
  if (tipo.llevaValor) {
    if (unidad is! String || unidad.trim().isEmpty) {
      throw PlantillaInvalida('$c: un ítem ${tipo.wire} necesita unidad');
    }
    if (rangoMin == null || rangoMax == null) {
      throw PlantillaInvalida(
        '$c: un ítem ${tipo.wire} necesita rango_min y rango_max',
      );
    }
    if (rangoMin >= rangoMax) {
      throw PlantillaInvalida(
        '$c: rango invertido o vacío: rango_min ($rangoMin) debe ser menor '
        'que rango_max ($rangoMax)',
      );
    }
  } else if (unidad != null || rangoMin != null || rangoMax != null) {
    throw PlantillaInvalida(
      '$c: un ítem ${tipo.wire} no lleva unidad ni rango',
    );
  }

  final obligatorio = _bool(m, 'obligatorio', c);
  // `solo_valor` no tiene N.A. y un obligatorio sin responder bloquea la
  // firma (F4.1, T12): si el equipo no arranca, el técnico tendría que
  // inventarse un valor que acaba en un PDF firmado. Una medición
  // obligatoria va como `estado_valor`, que sí tiene N.A.
  if (obligatorio && tipo == TipoRespuesta.soloValor) {
    throw PlantillaInvalida(
      '$c: un ítem solo_valor no puede ser obligatorio (no tiene N.A.); '
      'usa estado_valor o hazlo opcional',
    );
  }

  final analizableIa = _bool(m, 'analizable_ia', c);
  // §9.3: `analizar-foto` solo busca defectos visuales (enum cerrado), así
  // que solo tiene sentido en ítems de estado; y `falta_etiqueta` no está en
  // su enum a propósito («con una sola foto no se puede afirmar»): la
  // etiqueta la decide siempre el técnico. Se valida aquí y no solo en las
  // pruebas para que una v2 nueva, que entra sin tocar código, no se lo
  // salte.
  if (analizableIa && tipo != TipoRespuesta.estado) {
    throw PlantillaInvalida(
      '$c: analizable_ia solo en ítems de tipo estado (inspección visual, '
      '§9.3), no en ${tipo.wire}',
    );
  }
  if (analizableIa && clave == claveEtiquetaFgas) {
    throw PlantillaInvalida(
      '$c: la etiqueta F-gas no es analizable por la IA (§9.3: '
      'falta_etiqueta no está en el enum de analizar-foto)',
    );
  }

  return ItemPlantilla(
    id: id,
    empresaId: null,
    plantillaId: plantillaId,
    clave: clave,
    orden: orden,
    seccion: _texto(m, 'seccion', c),
    codigoNormativo: _texto(m, 'codigo_normativo', c),
    texto: texto,
    tipoRespuesta: tipo,
    unidad: unidad as String?,
    rangoMin: rangoMin,
    rangoMax: rangoMax,
    obligatorio: obligatorio,
    fotoObligatoria: _bool(m, 'foto_obligatoria', c),
    analizableIa: analizableIa,
  );
}

Map<String, Object?> _mapa(Object? v, String c) {
  if (v is! Map<String, Object?>) {
    throw PlantillaInvalida('$c: se esperaba un objeto JSON');
  }
  return v;
}

void _columnasExactas(Map<String, Object?> m, Set<String> esperadas, String c) {
  final sobran = m.keys.toSet().difference(esperadas);
  final faltan = esperadas.difference(m.keys.toSet());
  if (sobran.isNotEmpty || faltan.isNotEmpty) {
    throw PlantillaInvalida(
      '$c: columnas no válidas'
      '${faltan.isEmpty ? '' : '; faltan ${faltan.join(', ')}'}'
      '${sobran.isEmpty ? '' : '; sobran ${sobran.join(', ')}'}',
    );
  }
}

String _texto(Map<String, Object?> m, String campo, String c) {
  final v = m[campo];
  if (v is! String || v.trim().isEmpty) {
    throw PlantillaInvalida('$c: $campo debe ser un texto no vacío');
  }
  return v;
}

int _entero(Map<String, Object?> m, String campo, String c) {
  final v = m[campo];
  if (v is! int) throw PlantillaInvalida('$c: $campo debe ser un entero');
  return v;
}

bool _bool(Map<String, Object?> m, String campo, String c) {
  final v = m[campo];
  if (v is! bool) throw PlantillaInvalida('$c: $campo debe ser true o false');
  return v;
}

double? _numeroOpcional(Map<String, Object?> m, String campo, String c) {
  final v = m[campo];
  if (v == null) return null;
  if (v is! num || !v.isFinite) {
    throw PlantillaInvalida('$c: $campo debe ser un número o null');
  }
  return v.toDouble();
}

// ---------------------------------------------------------------------------
// Carga desde el bundle
// ---------------------------------------------------------------------------

/// Carpeta de las plantillas base (declarada en `pubspec.yaml`).
const carpetaPlantillas = 'assets/plantillas/';

/// Lee y valida todas las plantillas base del bundle (`*.json` de
/// [carpetaPlantillas]; el README se ignora). Lista las del manifiesto para
/// que una `v2` nueva entre sin tocar código. Una plantilla inválida es un
/// fallo de compilación del producto, no del técnico: se lanza
/// [PlantillaInvalida] en vez de saltarla en silencio. Además comprueba que
/// no hay dos ficheros con la misma `clave` y `version`, y las reglas de las
/// claves compartidas ([comprobarClavesCompartidas]).
Future<List<Plantilla>> cargarPlantillasBase([AssetBundle? bundle]) async {
  final b = bundle ?? rootBundle;
  final manifiesto = await AssetManifest.loadFromAssetBundle(b);
  final rutas =
      manifiesto
          .listAssets()
          .where((r) => r.startsWith(carpetaPlantillas) && r.endsWith('.json'))
          .toList()
        ..sort();
  final plantillas = <Plantilla>[];
  final vistas = <String, String>{};
  for (final ruta in rutas) {
    final p = parsearPlantilla(await b.loadString(ruta), origen: ruta);
    final k = '${p.clave}:v${p.version}';
    final otra = vistas[k];
    if (otra != null) {
      throw PlantillaInvalida(
        '$ruta: ${p.clave} v${p.version} ya está en $otra',
      );
    }
    vistas[k] = ruta;
    plantillas.add(p);
  }
  comprobarClavesCompartidas(plantillas);
  return plantillas;
}

/// Reglas de las claves de ítem compartidas entre plantillas (§7.2, §7.4).
/// Lanza [PlantillaInvalida] con las dos plantillas en conflicto.
///
/// - **`unidad`, en todas las versiones:** `estado_equipo.ultimos_valores_json`
///   guarda el último valor por `clave` y T5/T6 lo enseñan como referencia en
///   la visita siguiente, aunque sea con otra plantilla u otra versión. Si la
///   unidad cambia, la comparación engaña (p. ej., bar absolutos frente a
///   manométricos). Cambiar de unidad = clave nueva.
/// - **`tipo_respuesta` y `codigo_normativo`, entre las versiones vigentes**
///   (la más alta de cada clave de plantilla): la misma operación se responde
///   y se cita igual en todas las plantillas que se ofrecen hoy. Una versión
///   antigua puede diferir: justo para corregir eso se publica la nueva.
void comprobarClavesCompartidas(List<Plantilla> plantillas) {
  final unidades = <String, (Plantilla, ItemPlantilla)>{};
  for (final p in plantillas) {
    for (final i in p.items) {
      final otra = unidades[i.clave];
      if (otra == null) {
        unidades[i.clave] = (p, i);
      } else if (otra.$2.unidad != i.unidad) {
        throw PlantillaInvalida(
          '${p.clave} v${p.version}: el ítem «${i.clave}» tiene unidad '
          '«${i.unidad}» y en ${otra.$1.clave} v${otra.$1.version} '
          '«${otra.$2.unidad}»; la unidad de una clave no cambia nunca '
          '(ultimos_valores_json, §7.2)',
        );
      }
    }
  }
  final vigentes = <String, (Plantilla, ItemPlantilla)>{};
  for (final p in _ultimaVersionPorClave(plantillas)) {
    for (final i in p.items) {
      final otra = vigentes[i.clave];
      if (otra == null) {
        vigentes[i.clave] = (p, i);
        continue;
      }
      final (po, io) = otra;
      String? campo;
      if (io.tipoRespuesta != i.tipoRespuesta) {
        campo = 'tipo_respuesta';
      } else if (io.codigoNormativo != i.codigoNormativo) {
        campo = 'codigo_normativo';
      }
      if (campo != null) {
        throw PlantillaInvalida(
          '${p.clave} v${p.version}: el ítem «${i.clave}» tiene otro '
          '$campo que en ${po.clave} v${po.version}; una clave compartida '
          'se responde y se cita igual en todas las plantillas vigentes',
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Sugerencia de plantillas (O2 y F2.2)
// ---------------------------------------------------------------------------

/// Por qué la sugerencia no es la obvia. La interfaz lo enseña siempre con
/// texto (§6.0): nunca se oculta que algo queda fuera.
enum AvisoPlantillas {
  /// Instalación de más de 70 kW: el preventivo RITE es mensual (Tabla 3.1 y
  /// 3.3) y su plantilla está fuera del MVP (§4.3). Solo se ofrece el control
  /// de fugas; nunca la 1 o la 2.
  preventivoRiteFueraMvp(
    'Preventivo RITE mensual (instalación de más de 70 kW): fuera de esta '
    'versión. Solo se ofrece el control de fugas.',
  ),

  /// Sin potencia del equipo no se sabe su fila de la Tabla 3.1: se sugiere
  /// con la de la instalación, que es una cota superior (la misma lectura que
  /// `rite.dart`), y el técnico la comprueba en la placa.
  potenciaEquipoDesconocida(
    'Falta la potencia del equipo: se ha sugerido con la de la instalación. '
    'Compruébala en la placa.',
  ),

  /// La instalación está en el régimen por equipo de la Tabla 3.1, pero
  /// ninguna plantilla preventiva publicada del tipo cubre su potencia o la
  /// del equipo (`aplica_a`). Solo pasa si la normativa versionada sube el
  /// umbral de 70 kW sin que haya plantillas nuevas.
  potenciaSinPlantilla(
    'Ninguna plantilla preventiva de esta versión cubre esta potencia.',
  ),

  /// Tipo sin plantilla preventiva en el MVP (enfriadora, bomba de calor
  /// aire-agua, UTA, otro): necesitan ítems hidráulicos de la Tabla 3.2 a).
  /// [A VERIFICAR] con el técnico de la llamada (decisión 14.10).
  tipoSinPlantillaPreventiva(
    'Este tipo de equipo no tiene plantilla preventiva en esta versión.',
  ),

  /// Nuevo control tras reparar (art. 4.5): la plantilla 4 es §4.2 A; se usa
  /// la de control de fugas y la eficacia no queda registrada en el checklist.
  recontrolConPlantillaControlFugas(
    'Nuevo control tras reparar: se usa la plantilla de control de fugas '
    '(la específica no está en esta versión).',
  ),

  /// Intervención sin plantilla en el MVP (puesta en marcha).
  intervencionSinPlantilla(
    'Esta intervención no tiene plantilla en esta versión.',
  );

  const AvisoPlantillas(this.texto);
  final String texto;
}

/// Resultado de [sugerirPlantillas]: lista ordenada (la primera es la
/// recomendada) y los avisos que la explican. Puede venir vacía, pero
/// entonces siempre trae un aviso.
class SugerenciaPlantillas {
  SugerenciaPlantillas(List<Plantilla> plantillas, List<AvisoPlantillas> avisos)
    : plantillas = List.unmodifiable(plantillas),
      avisos = List.unmodifiable(avisos);

  final List<Plantilla> plantillas;
  final List<AvisoPlantillas> avisos;

  Plantilla? get recomendada => plantillas.isEmpty ? null : plantillas.first;
}

/// Qué plantillas ofrecer a un equipo (regla de O2 y F2.2, §5).
///
/// - [umbralRegimenMensualKw]: `normativa.rite.umbralRegimenMensualKw`, el
///   límite de la Tabla 3.1 entre el régimen por equipo y «Instalaciones de
///   potencia superior a 70 kW» (mensual). Viene de la normativa versionada
///   (§7.3, regla 4 de docs/REGLAS.md) y no de una constante, para que T3
///   (`rite.dart`) y O2/F2.2 decidan siempre con la misma cifra.
/// - [potenciaEquipoKw]: la mayor de frío y calor del equipo (la misma
///   lectura prudente que `rite.dart`, §3.2); null si aún no se conoce.
/// - [potenciaInstalacionKw]: la de la instalación tal como la calcula
///   `rite.dart` (mayor de frío y calor, y mayor entre lo declarado y la suma
///   de equipos). Se recibe como parámetro para no depender de `rite.dart`.
///   Si el propio equipo supera lo recibido, se toma la del equipo: una
///   instalación no puede tener menos potencia que uno de sus equipos.
/// - [plantillas]: las publicadas disponibles (p. ej., de
///   [cargarPlantillasBase]). Si hay varias versiones de una clave, se usa
///   la más alta.
///
/// Reglas:
/// 1. Control de fugas o nuevo control → solo plantillas de esa intervención
///    (la 3), a cualquier potencia.
/// 2. Preventivo o correctivo en instalación de más del umbral (70 kW) →
///    solo la 3 y el aviso [AvisoPlantillas.preventivoRiteFueraMvp]; nunca
///    la 1 o la 2.
/// 3. Preventivo o correctivo en instalación ≤ umbral → la de la franja del
///    equipo según la Tabla 3.1 (≤ 12 kW → 1; 12 < P ≤ 70 → 2), entre las
///    que admiten la potencia de la instalación (`aplica_a`).
/// 4. Sin potencia del equipo → las plantillas en las que el equipo puede
///    caber sabiendo que no supera la potencia de la instalación (cota
///    superior), y primero la de la franja de esa cota, que es la fila que
///    usa `rite.dart` para la periodicidad.
SugerenciaPlantillas sugerirPlantillas({
  required double umbralRegimenMensualKw,
  required TipoEquipo tipo,
  required double? potenciaEquipoKw,
  required double potenciaInstalacionKw,
  required UsoEdificio uso,
  required TipoIntervencion intervencion,
  required List<Plantilla> plantillas,
}) {
  if (!umbralRegimenMensualKw.isFinite || umbralRegimenMensualKw <= 0) {
    throw ArgumentError.value(
      umbralRegimenMensualKw,
      'umbralRegimenMensualKw',
      'Debe ser un número > 0',
    );
  }
  if (!potenciaInstalacionKw.isFinite || potenciaInstalacionKw < 0) {
    throw ArgumentError.value(
      potenciaInstalacionKw,
      'potenciaInstalacionKw',
      'Debe ser un número ≥ 0',
    );
  }
  if (potenciaEquipoKw != null &&
      (!potenciaEquipoKw.isFinite || potenciaEquipoKw < 0)) {
    throw ArgumentError.value(
      potenciaEquipoKw,
      'potenciaEquipoKw',
      'Debe ser un número ≥ 0 o null',
    );
  }
  final instalacionKw =
      potenciaEquipoKw != null && potenciaEquipoKw > potenciaInstalacionKw
      ? potenciaEquipoKw
      : potenciaInstalacionKw;

  final vigentes = _ultimaVersionPorClave(plantillas);
  bool basicas(Plantilla p) =>
      p.aplicaA.tipos.contains(tipo) && p.aplicaA.usos.contains(uso);
  List<Plantilla> deIntervencion(TipoIntervencion i) => [
    for (final p in vigentes)
      if (p.aplicaA.intervenciones.contains(i) && basicas(p)) p,
  ];

  switch (intervencion) {
    case TipoIntervencion.controlFugas:
      return SugerenciaPlantillas(
        _ordenarPorAmplitud(deIntervencion(intervencion)),
        const [],
      );
    case TipoIntervencion.recontrolFugas:
      // [A VERIFICAR] La plantilla 4 (art. 4.5) es §4.2 A. Hasta entonces, el
      // nuevo control usa la de control de fugas, que también lo admite.
      final directas = [
        for (final p in deIntervencion(intervencion))
          if (!p.aplicaA.intervenciones.contains(TipoIntervencion.controlFugas))
            p,
      ];
      if (directas.isNotEmpty) {
        return SugerenciaPlantillas(_ordenarPorAmplitud(directas), const []);
      }
      return SugerenciaPlantillas(
        _ordenarPorAmplitud(deIntervencion(intervencion)),
        const [AvisoPlantillas.recontrolConPlantillaControlFugas],
      );
    case TipoIntervencion.puestaMarcha:
      final l = deIntervencion(intervencion);
      return SugerenciaPlantillas(
        l,
        l.isEmpty ? const [AvisoPlantillas.intervencionSinPlantilla] : const [],
      );
    case TipoIntervencion.preventivo:
    case TipoIntervencion.correctivo:
      // [A VERIFICAR] Correctivo: el MVP no tiene plantilla propia y ofrece
      // la preventiva de su franja (el técnico marca N.A. lo que no toque).
      break;
  }

  // Regla 2: más del umbral → régimen mensual (Tabla 3.1), fuera del MVP.
  // Borde estricto como en `rite.dart` («superior a 70 kW»).
  if (instalacionKw > umbralRegimenMensualKw) {
    return SugerenciaPlantillas(
      _ordenarPorAmplitud(deIntervencion(TipoIntervencion.controlFugas)),
      const [AvisoPlantillas.preventivoRiteFueraMvp],
    );
  }

  final delTipo = deIntervencion(intervencion);
  if (delTipo.isEmpty) {
    return SugerenciaPlantillas(const [], const [
      AvisoPlantillas.tipoSinPlantillaPreventiva,
    ]);
  }
  final candidatas = [
    for (final p in delTipo)
      if (p.aplicaA.admitePotenciaInstalacion(instalacionKw)) p,
  ];
  if (candidatas.isEmpty) {
    return SugerenciaPlantillas(const [], const [
      AvisoPlantillas.potenciaSinPlantilla,
    ]);
  }
  if (potenciaEquipoKw == null) {
    if (instalacionKw <= 0) {
      // [A VERIFICAR] Sin ninguna potencia (ni del equipo ni de la
      // instalación) no hay cota: van todas, la más completa primero (más
      // ítems = lo más prudente). `rite.dart` usaría 0 kW (fila ≤ 12 kW).
      final todas = [...candidatas]
        ..sort((a, b) {
          final c = b.items.length.compareTo(a.items.length);
          return c != 0 ? c : a.clave.compareTo(b.clave);
        });
      return SugerenciaPlantillas(todas, const [
        AvisoPlantillas.potenciaEquipoDesconocida,
      ]);
    }
    // El equipo no supera la potencia de la instalación (se tomó la mayor de
    // las dos), así que caben las franjas que empiezan por debajo de ella:
    // con 3,5 kW solo la 1; con 30 kW, la 1 y la 2. Primero la franja que
    // contiene la cota, la misma fila que `rite.dart` usa para la
    // periodicidad cuando el equipo no tiene potencia.
    final posibles = [
      for (final p in candidatas)
        if (p.aplicaA.potenciaMinKw == null ||
            instalacionKw > p.aplicaA.potenciaMinKw!)
          p,
    ];
    if (posibles.isEmpty) {
      return SugerenciaPlantillas(const [], const [
        AvisoPlantillas.potenciaSinPlantilla,
      ]);
    }
    final deLaCota = _ordenarPorAmplitud([
      for (final p in posibles)
        if (p.aplicaA.admitePotenciaEquipo(instalacionKw)) p,
    ]);
    final resto = _ordenarPorAmplitud([
      for (final p in posibles)
        if (!deLaCota.contains(p)) p,
    ]);
    return SugerenciaPlantillas(
      [...deLaCota, ...resto],
      const [AvisoPlantillas.potenciaEquipoDesconocida],
    );
  }
  final enFranja = [
    for (final p in candidatas)
      if (p.aplicaA.admitePotenciaEquipo(potenciaEquipoKw)) p,
  ];
  if (enFranja.isEmpty) {
    return SugerenciaPlantillas(const [], const [
      AvisoPlantillas.potenciaSinPlantilla,
    ]);
  }
  return SugerenciaPlantillas(_ordenarPorAmplitud(enFranja), const []);
}

/// Una sola versión por clave (la más alta) y por empresa. Una orden ya
/// creada sigue apuntando a su versión; esto solo decide qué se ofrece.
List<Plantilla> _ultimaVersionPorClave(List<Plantilla> plantillas) {
  final porClave = <String, Plantilla>{};
  for (final p in plantillas) {
    if (p.estado != EstadoPlantilla.publicada) continue;
    final k = '${p.empresaId ?? ''}/${p.clave}';
    final actual = porClave[k];
    if (actual == null || p.version > actual.version) porClave[k] = p;
  }
  return porClave.values.toList();
}

/// Orden estable: primero la franja más estrecha (la más específica), luego
/// por clave para que el resultado no dependa del orden de carga.
List<Plantilla> _ordenarPorAmplitud(List<Plantilla> l) {
  double amplitud(Plantilla p) =>
      (p.aplicaA.potenciaMaxKw ?? double.infinity) -
      (p.aplicaA.potenciaMinKw ?? 0);
  return [...l]..sort((a, b) {
    final c = amplitud(a).compareTo(amplitud(b));
    return c != 0 ? c : a.clave.compareTo(b.clave);
  });
}
