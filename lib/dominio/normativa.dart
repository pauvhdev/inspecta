// Normativa como datos versionados (DISEÑO.md §7.3): el modelo tipado e
// inmutable de `assets/normativa/<version>.json` y su carga.
//
// Las cifras (PCG, umbrales, periodicidades, fechas) viven en el JSON y no en
// el código: cambiar una cifra es publicar una versión nueva del fichero, con
// su prueba, y cada informe firmado guarda la versión con la que se calculó
// (`inspecciones.normativa_version`). Aquí solo se lee, se valida y se expone.
//
// `parsearNormativa` es pura (recibe el texto) para poder probarla sin Flutter;
// `cargarNormativa` es el único punto que toca `rootBundle`.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'tipos.dart';

/// Versión de la normativa que usa esta build de la app.
const String versionNormativaActual = '2026-11';

/// Ruta del asset de la versión actual.
const String rutaNormativaActual =
    'assets/normativa/$versionNormativaActual.json';

/// Error de carga: el JSON no cumple el contrato. Se lanza al cargar, alto y
/// claro, para que una cifra mal escrita no llegue nunca a un cálculo.
class NormativaInvalida implements Exception {
  NormativaInvalida(this.mensaje);
  final String mensaje;

  @override
  String toString() => 'NormativaInvalida: $mensaje';
}

// ---------------------------------------------------------------------------
// Fechas: suma de meses de calendario (compartida por fgas.dart y rite.dart)
// ---------------------------------------------------------------------------

/// Suma [meses] de calendario a [fecha] conservando la hora y la zona.
///
/// Si el día no existe en el mes de destino se toma el último día de ese mes
/// (31 de enero + 1 mes = 28 o 29 de febrero): es lo prudente para un plazo
/// «a más tardar», que no debe saltar al mes siguiente.
DateTime sumarMesesCalendario(DateTime fecha, int meses) {
  final totalMeses = fecha.year * 12 + (fecha.month - 1) + meses;
  final anio = totalMeses ~/ 12;
  final mes = totalMeses % 12 + 1;
  final ultimoDia = _diasDelMes(anio, mes);
  final dia = fecha.day > ultimoDia ? ultimoDia : fecha.day;
  return fecha.isUtc
      ? DateTime.utc(
          anio,
          mes,
          dia,
          fecha.hour,
          fecha.minute,
          fecha.second,
          fecha.millisecond,
          fecha.microsecond,
        )
      : DateTime(
          anio,
          mes,
          dia,
          fecha.hour,
          fecha.minute,
          fecha.second,
          fecha.millisecond,
          fecha.microsecond,
        );
}

int _diasDelMes(int anio, int mes) =>
    DateTime.utc(anio, mes + 1, 0).day; // día 0 del mes siguiente

// Instantes y días. El repo guarda los instantes en UTC
// (`lib/data/local/tablas/comunes.dart`, «Instantes en UTC»: el mapper deja en
// UTC todo lo que baja y los repositorios escriben `DateTime.now().toUtc()`),
// pero los plazos de la norma son días de calendario del técnico en España: una
// carga del 1/1/2026 a las 00:30 en Madrid es 2025-12-31T23:30Z y ya está en
// 2026 (art. 13.4). Por eso todo instante se pasa a hora local antes de mirar
// su día. Las columnas `date` (`SoloFecha`, `conversores.dart`) son otra cosa:
// medianoche UTC de un día, que se lee por componentes y nunca se convierte
// (en una zona al oeste de UTC, `toLocal` la movería al día anterior).

/// El instante [instante] en hora local (no hace nada si ya lo está).
DateTime enHoraLocal(DateTime instante) =>
    instante.isUtc ? instante.toLocal() : instante;

/// Compara el día de calendario **local** del instante [fecha] con [dia]. Las
/// fechas de entrada en vigor son días, no instantes: una carga del 1/1/2026 a
/// las 00:30 hora de Madrid ya está en 2026, venga en UTC o en hora local.
bool esIgualOPosterior(DateTime fecha, DiaCalendario dia) =>
    DiaCalendario.deInstante(fecha).clave >= dia.clave;

/// Vencimiento a [meses] de calendario de una referencia.
///
/// [referenciaEsInstante]: `true` para un instante (`estado_equipo.ultimo_*_at`,
/// en UTC en el repo), que se pasa a hora local antes de sumar; `false` para un
/// día (`SoloFecha`: `equipos.*_previo_declarado`), que se suma tal cual y se
/// lee por componentes. [dia] es el último día en plazo.
({DateTime fecha, DiaCalendario dia}) vencimientoDesde(
  DateTime referencia,
  int meses, {
  required bool referenciaEsInstante,
}) {
  final fecha = sumarMesesCalendario(
    referenciaEsInstante ? enHoraLocal(referencia) : referencia,
    meses,
  );
  return (fecha: fecha, dia: DiaCalendario.deComponentes(fecha));
}

/// Un día de calendario sin hora ni zona (fechas de entrada en vigor).
class DiaCalendario {
  const DiaCalendario(this.anio, this.mes, this.dia);

  /// Día local de un instante (ver [enHoraLocal]).
  factory DiaCalendario.deInstante(DateTime instante) =>
      DiaCalendario.deComponentes(enHoraLocal(instante));

  /// Día tal como lo dicen los componentes de [fecha], sin cambiar de zona:
  /// para columnas `SoloFecha` (medianoche UTC) o fechas ya en hora local.
  factory DiaCalendario.deComponentes(DateTime fecha) =>
      DiaCalendario(fecha.year, fecha.month, fecha.day);
  final int anio;
  final int mes;
  final int dia;

  int get clave => anio * 10000 + mes * 100 + dia;

  @override
  String toString() =>
      '${anio.toString().padLeft(4, '0')}-${mes.toString().padLeft(2, '0')}-${dia.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is DiaCalendario && other.clave == clave;

  @override
  int get hashCode => clave;
}

// ---------------------------------------------------------------------------
// Refrigerantes (anexos I, II y VI del Reglamento (UE) 2024/573)
// ---------------------------------------------------------------------------

/// Anexo del Reglamento (UE) 2024/573 en que figura el gas. Una mezcla que
/// contiene algún HFC del anexo I es un HFC (art. 3.4 y nota 1 del anexo I).
enum AnexoFgas {
  i('I'),
  ii('II');

  const AnexoFgas(this.wire);
  final String wire;

  static AnexoFgas desde(String wire, String ruta) => values.firstWhere(
    (a) => a.wire == wire,
    orElse: () => throw NormativaInvalida('$ruta: anexo «$wire» desconocido'),
  );
}

/// Componente de una mezcla, con su contribución en masa (anexo VI).
class ComponenteMezcla {
  const ComponenteMezcla({required this.codigo, required this.porcentajeMasa});
  final String codigo;
  final double porcentajeMasa;
}

class Refrigerante {
  const Refrigerante({
    required this.codigo,
    required this.nombre,
    required this.anexo,
    required this.seccion,
    required this.pcg,
    required this.calculado,
    required this.composicion,
    required this.fuente,
    required this.verificada,
    this.porcentajeAnexoIISeccion1 = 0,
  });

  final String codigo;
  final String nombre;
  final AnexoFgas anexo;
  final int seccion;

  /// PCG a 100 años según el anexo I o II, o calculado con el anexo VI.
  final double pcg;

  /// `true` si el PCG sale del método del anexo VI (mezclas).
  final bool calculado;
  final List<ComponenteMezcla> composicion;
  final String fuente;
  final bool verificada;

  /// Porcentaje en masa de gases del anexo II, sección 1 (HFO) que contiene.
  /// 100 en un HFO puro; en una mezcla, la suma de sus componentes HFO. Se
  /// deriva al cargar, no se escribe en el JSON.
  final double porcentajeAnexoIISeccion1;

  bool get esMezcla => composicion.isNotEmpty;

  /// Gas puro del anexo II: fuera del cálculo del MVP (DISEÑO.md §3.2 y
  /// §4.3). Al cargar solo se admite la sección 1; si llegara otra sección
  /// (un [Refrigerante] construido a mano), también queda «no calculado», que
  /// es lo prudente.
  bool get esAnexoIIPuro => anexo == AnexoFgas.ii && !esMezcla;

  /// Mezcla del anexo I que lleva parte de HFO del anexo II, sección 1.
  bool get esMezclaConAnexoII => esMezcla && porcentajeAnexoIISeccion1 > 0;
}

// ---------------------------------------------------------------------------
// Reglas F-gas
// ---------------------------------------------------------------------------

/// Franja del art. 5.6: `desde` incluido, `hasta` excluido (null = sin tope).
class FranjaControlFugas {
  const FranjaControlFugas({
    required this.desde,
    required this.hasta,
    required this.meses,
    required this.mesesConDeteccion,
  });
  final double desde;
  final double? hasta;
  final int meses;
  final int mesesConDeteccion;

  bool contiene(double valor) =>
      valor >= desde && (hasta == null || valor < hasta!);
}

class ReglasArt5 {
  const ReglasArt5({
    required this.umbralSujecionT,
    required this.umbralHermeticoT,
    required this.franjasT,
    required this.umbralSujecionKgAnexoII,
    required this.umbralHermeticoKgAnexoII,
    required this.franjasKgAnexoII,
    required this.anexoIIPurosCalculados,
    required this.mezclasCriterioKgFraccion,
    required this.mezclasCriterioKgVerificada,
    required this.umbralExcepcionResidencialKg,
    required this.fuente,
  });

  final double umbralSujecionT;
  final double umbralHermeticoT;
  final List<FranjaControlFugas> franjasT;
  final double umbralSujecionKgAnexoII;
  final double umbralHermeticoKgAnexoII;
  final List<FranjaControlFugas> franjasKgAnexoII;

  /// `false` en el MVP: los HFO puros no se calculan.
  final bool anexoIIPurosCalculados;

  /// Aplicar también el criterio en kg a la fracción HFO de una mezcla.
  final bool mezclasCriterioKgFraccion;
  final bool mezclasCriterioKgVerificada;
  final double umbralExcepcionResidencialKg;
  final String fuente;
}

class ReglasArt6 {
  const ReglasArt6({
    required this.umbralDeteccionT,
    required this.umbralDeteccionKgAnexoII,
    required this.mesesRevisionDetector,
    required this.fuente,
  });
  final double umbralDeteccionT;
  final double umbralDeteccionKgAnexoII;
  final int mesesRevisionDetector;
  final String fuente;
}

class ReglasArt45 {
  const ReglasArt45({
    required this.desdeHoras,
    required this.hastaMeses,
    required this.fuente,
  });
  final int desdeHoras;
  final int hastaMeses;
  final String fuente;
}

/// Origen del gas cargado (`movimientos_gas.origen_gas`).
enum OrigenGas {
  virgen('virgen'),
  reciclado('reciclado'),
  regenerado('regenerado');

  const OrigenGas(this.wire);
  final String wire;

  static OrigenGas desde(String wire) => values.firstWhere(
    (o) => o.wire == wire,
    orElse: () => throw ArgumentError.value(wire, 'origen_gas', 'Desconocido'),
  );
}

class ReglaOrigen {
  const ReglaOrigen({required this.permitido, required this.datos});

  /// Si el origen puede usarse dentro de la excepción (hasta `excepcionesHasta`).
  final bool permitido;

  /// Campos de `movimientos_gas` obligatorios para ese origen.
  final List<String> datos;
}

class ReglasArt134 {
  const ReglasArt134({
    required this.desde,
    required this.umbralPcg,
    required this.categorias,
    required this.soloAnexoI,
    required this.excepcionesHasta,
    required this.origenes,
    required this.fuente,
  });
  final DiaCalendario desde;
  final double umbralPcg;
  final Set<CategoriaFgas> categorias;
  final bool soloAnexoI;

  /// Primer día en que ya no valen regenerado ni reciclado.
  final DiaCalendario excepcionesHasta;
  final Map<OrigenGas, ReglaOrigen> origenes;
  final String fuente;
}

/// Regla que solo avisa (arts. 13.3 y 13.5 en el MVP).
class ReglaAviso {
  const ReglaAviso({
    required this.desde,
    required this.umbralPcg,
    required this.categorias,
    required this.verificada,
    required this.fuente,
    required this.nota,
  });
  final DiaCalendario desde;
  final double umbralPcg;
  final Set<CategoriaFgas> categorias;
  final bool verificada;
  final String fuente;
  final String nota;
}

class ReglasFgas {
  const ReglasFgas({
    required this.art5,
    required this.art6,
    required this.art45,
    required this.art134,
    required this.art133,
    required this.art135,
  });
  final ReglasArt5 art5;
  final ReglasArt6 art6;
  final ReglasArt45 art45;
  final ReglasArt134 art134;
  final ReglaAviso art133;
  final ReglaAviso art135;
}

// ---------------------------------------------------------------------------
// Reglas RITE
// ---------------------------------------------------------------------------

/// Fila de la Tabla 3.1 de la IT 3.3. Borde inferior excluido
/// (`pnMayorQueKw`, «12 kW < Pn») y superior incluido (`pnHastaKw`, «Pn ≤ 70»),
/// tal como los escribe el BOE.
class FilaTabla31 {
  const FilaTabla31({
    required this.clave,
    required this.familia,
    required this.pnMayorQueKw,
    required this.pnHastaKw,
    required this.mesesVivienda,
    required this.mesesOtros,
    required this.textoBoe,
    required this.verificada,
  });
  final String clave;
  final String familia;
  final double? pnMayorQueKw;
  final double? pnHastaKw;
  final int mesesVivienda;
  final int mesesOtros;
  final String textoBoe;
  final bool verificada;

  bool contiene(double pnKw) =>
      (pnMayorQueKw == null || pnKw > pnMayorQueKw!) &&
      (pnHastaKw == null || pnKw <= pnHastaKw!);

  int meses(UsoEdificio uso) =>
      uso == UsoEdificio.vivienda ? mesesVivienda : mesesOtros;
}

class ReglasRite {
  const ReglasRite({
    required this.umbralRegimenMensualKw,
    required this.umbralVerificada,
    required this.mesesRegimenMensual,
    required this.textoRegimenMensual,
    required this.supervisionPotenciaMaxKw,
    required this.supervisionMesesMax,
    required this.tabla31,
    required this.familiaPorTipo,
    required this.familiaPorTipoVerificada,
    required this.fuente,
  });

  /// Régimen mensual si la potencia de la instalación es **mayor** que esto.
  final double umbralRegimenMensualKw;
  final bool umbralVerificada;
  final int mesesRegimenMensual;
  final String textoRegimenMensual;
  final double supervisionPotenciaMaxKw;
  final int supervisionMesesMax;
  final List<FilaTabla31> tabla31;
  final Map<TipoEquipo, String> familiaPorTipo;
  final bool familiaPorTipoVerificada;
  final String fuente;

  /// Fila de la Tabla 3.1 para una familia y una potencia, o null si ninguna
  /// la cubre.
  FilaTabla31? fila(String familia, double pnKw) {
    for (final f in tabla31) {
      if (f.familia == familia && f.contiene(pnKw)) return f;
    }
    return null;
  }
}

class TipoCertificado {
  const TipoCertificado({
    required this.codigo,
    required this.descripcion,
    required this.fuente,
    required this.verificada,
  });
  final String codigo;
  final String descripcion;
  final String fuente;
  final bool verificada;
}

/// La normativa completa de una versión.
class Normativa {
  Normativa({
    required this.version,
    required List<Refrigerante> refrigerantes,
    required this.fgas,
    required this.rite,
    required List<TipoCertificado> tiposCertificado,
  }) : refrigerantes = List.unmodifiable(refrigerantes),
       tiposCertificado = List.unmodifiable(tiposCertificado),
       _porCodigo = {
         for (final r in refrigerantes) _normalizarCodigo(r.codigo): r,
       };

  final String version;
  final List<Refrigerante> refrigerantes;
  final ReglasFgas fgas;
  final ReglasRite rite;
  final List<TipoCertificado> tiposCertificado;
  final Map<String, Refrigerante> _porCodigo;

  /// Busca un refrigerante por código («R-410A», «r410a» y «R 410A» valen).
  /// Null si no está en el catálogo: la app lo dice y no inventa un PCG.
  Refrigerante? refrigerante(String codigo) =>
      _porCodigo[_normalizarCodigo(codigo)];
}

String _normalizarCodigo(String c) =>
    c.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');

// ---------------------------------------------------------------------------
// Carga y validación
// ---------------------------------------------------------------------------

/// Carga la versión actual desde los assets de la app.
Future<Normativa> cargarNormativa({String ruta = rutaNormativaActual}) async {
  final texto = await rootBundle.loadString(ruta);
  return parsearNormativa(texto);
}

/// Parsea y valida el JSON de normativa. Función pura: falla con
/// [NormativaInvalida] si falta un campo, sobra una incoherencia o una mezcla
/// no cuadra con su composición.
Normativa parsearNormativa(String texto) {
  final Object? raiz;
  try {
    raiz = jsonDecode(texto);
  } on FormatException catch (e) {
    throw NormativaInvalida('JSON mal formado: ${e.message}');
  }
  final j = _Lector(_comoMapa(raiz, r'$'), r'$');

  final version = j.texto('version');
  if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(version)) {
    throw NormativaInvalida(
      r'$.version: «'
      '$version» no es AAAA-MM',
    );
  }

  final refrigerantes = _parsearRefrigerantes(j);
  final fgas = _parsearFgas(j.mapa('fgas'));
  final rite = _parsearRite(j.mapa('rite'));
  final certificados = j
      .lista('tipos_certificado')
      .map(
        (l) => TipoCertificado(
          codigo: l.texto('codigo'),
          descripcion: l.texto('descripcion'),
          fuente: l.texto('fuente'),
          verificada: l.booleano('verificada'),
        ),
      )
      .toList();
  if (certificados.isEmpty) {
    throw NormativaInvalida(r'$.tipos_certificado: vacío');
  }

  return Normativa(
    version: version,
    refrigerantes: refrigerantes,
    fgas: fgas,
    rite: rite,
    tiposCertificado: certificados,
  );
}

List<Refrigerante> _parsearRefrigerantes(_Lector j) {
  // PCG de los componentes posibles: gases puros del catálogo y sustancias no
  // fluoradas del anexo VI (p. ej., isobutano en el R-422D).
  final pcgComponente = <String, double>{};
  final anexoComponente = <String, AnexoFgas?>{};
  // Gases del anexo II, sección 1: los únicos a los que el art. 5.1 aplica el
  // criterio en kg. Se deriva de `anexo` y `seccion`, no solo del anexo.
  final hfoSeccion1 = <String, bool>{};
  for (final c in j.lista('componentes_anexo_vi')) {
    final codigo = c.texto('codigo');
    pcgComponente[_normalizarCodigo(codigo)] = c.numeroNoNegativo('pcg');
    anexoComponente[_normalizarCodigo(codigo)] = null;
  }

  final crudos = j.lista('refrigerantes');
  if (crudos.isEmpty) throw NormativaInvalida(r'$.refrigerantes: vacío');

  // Primera pasada: gases puros.
  for (final r in crudos) {
    if (r.lista('composicion').isEmpty) {
      final codigo = _normalizarCodigo(r.texto('codigo'));
      if (pcgComponente.containsKey(codigo)) {
        throw NormativaInvalida(
          '${r.ruta}: código ${r.texto('codigo')} repetido',
        );
      }
      pcgComponente[codigo] = r.numeroNoNegativo('pcg');
      anexoComponente[codigo] = AnexoFgas.desde(r.texto('anexo'), r.ruta);
      hfoSeccion1[codigo] = _esHfoSeccion1(r);
    }
  }

  final resultado = <Refrigerante>[];
  final vistos = <String>{};
  for (final r in crudos) {
    final codigo = r.texto('codigo');
    if (!vistos.add(_normalizarCodigo(codigo))) {
      throw NormativaInvalida('${r.ruta}: código $codigo repetido');
    }
    final anexo = AnexoFgas.desde(r.texto('anexo'), r.ruta);
    final seccion = r.enteroPositivo('seccion');
    // El art. 5.1 solo pone umbrales en kg para el anexo II, sección 1. Un gas
    // de otra sección del anexo II (éteres, alcoholes fluorados) no tiene regla
    // en el MVP: se rechaza al cargar en vez de tratarlo en silencio como HFO.
    if (anexo == AnexoFgas.ii && seccion != 1) {
      throw NormativaInvalida(
        '${r.ruta}.seccion: solo se admite el anexo II, sección 1 (art. 5.1); '
        'la sección $seccion no tiene regla en el MVP',
      );
    }
    final pcg = r.numeroNoNegativo('pcg');
    final calculado = r.booleano('calculado');
    final composicion = <ComponenteMezcla>[];
    var porcentajeII = _esHfoSeccion1(r) ? 100.0 : 0.0;

    final compCrudos = r.lista('composicion');
    if (calculado != compCrudos.isNotEmpty) {
      throw NormativaInvalida(
        '${r.ruta}: «calculado» debe ser true si y solo si hay composición',
      );
    }
    if (compCrudos.isNotEmpty) {
      porcentajeII = 0;
      var suma = 0.0;
      var pcgCalculado = 0.0;
      var tieneAnexoI = false;
      for (final c in compCrudos) {
        final comp = _normalizarCodigo(c.texto('componente'));
        final pct = c.numeroNoNegativo('porcentaje_masa');
        final pcgC = pcgComponente[comp];
        if (pcgC == null) {
          throw NormativaInvalida(
            '${c.ruta}: componente ${c.texto('componente')} sin PCG en el catálogo',
          );
        }
        suma += pct;
        pcgCalculado += pct * pcgC / 100;
        if (hfoSeccion1[comp] ?? false) porcentajeII += pct;
        if (anexoComponente[comp] == AnexoFgas.i) tieneAnexoI = true;
        composicion.add(
          ComponenteMezcla(codigo: c.texto('componente'), porcentajeMasa: pct),
        );
      }
      if ((suma - 100).abs() > 0.001) {
        throw NormativaInvalida(
          '${r.ruta}: la composición suma $suma %, no 100 %',
        );
      }
      // El PCG guardado debe ser el del método del anexo VI: así un PCG
      // tecleado a mano que no cuadre con la composición no pasa.
      if ((pcgCalculado - pcg).abs() > 0.01) {
        throw NormativaInvalida(
          '${r.ruta}: PCG $pcg no cuadra con el anexo VI '
          '(${pcgCalculado.toStringAsFixed(4)})',
        );
      }
      if (tieneAnexoI && anexo != AnexoFgas.i) {
        throw NormativaInvalida(
          '${r.ruta}: una mezcla con HFC del anexo I es del anexo I (art. 3.4)',
        );
      }
    }

    resultado.add(
      Refrigerante(
        codigo: codigo,
        nombre: r.texto('nombre'),
        anexo: anexo,
        seccion: seccion,
        pcg: pcg,
        calculado: calculado,
        composicion: List.unmodifiable(composicion),
        fuente: r.texto('fuente'),
        verificada: r.booleano('verificada'),
        porcentajeAnexoIISeccion1: porcentajeII,
      ),
    );
  }
  return List.unmodifiable(resultado);
}

bool _esHfoSeccion1(_Lector r) =>
    AnexoFgas.desde(r.texto('anexo'), r.ruta) == AnexoFgas.ii &&
    r.entero('seccion') == 1;

ReglasFgas _parsearFgas(_Lector f) {
  final a5 = f.mapa('art5');
  final ai = a5.mapa('anexo_i');
  final aii = a5.mapa('anexo_ii_seccion_1');
  final mezclas = a5.mapa('mezclas_con_anexo_ii');
  final resid = a5.mapa('excepcion_hermetico_residencial');

  final umbralT = ai.numeroPositivo('umbral_sujecion_t');
  final umbralKg = aii.numeroPositivo('umbral_sujecion_kg');
  final art5 = ReglasArt5(
    umbralSujecionT: umbralT,
    umbralHermeticoT: ai.numeroPositivo('umbral_hermetico_t'),
    franjasT: _parsearFranjas(ai, 'franjas_t', umbralT),
    umbralSujecionKgAnexoII: umbralKg,
    umbralHermeticoKgAnexoII: aii.numeroPositivo('umbral_hermetico_kg'),
    franjasKgAnexoII: _parsearFranjas(aii, 'franjas_kg', umbralKg),
    anexoIIPurosCalculados: aii.booleano('puros_calculados_en_mvp'),
    mezclasCriterioKgFraccion: mezclas.booleano(
      'aplicar_criterio_kg_a_la_fraccion',
    ),
    mezclasCriterioKgVerificada: mezclas.booleano('verificada'),
    umbralExcepcionResidencialKg: resid.numeroPositivo('umbral_kg'),
    fuente: a5.texto('fuente'),
  );
  if (resid.booleano('automatizada')) {
    // DISEÑO.md §3.3: la excepción residencial la marca el técnico.
    throw NormativaInvalida(
      r'$.fgas.art5.excepcion_hermetico_residencial: no se automatiza en el MVP',
    );
  }

  final a6 = f.mapa('art6');
  final art6 = ReglasArt6(
    umbralDeteccionT: a6.numeroPositivo('umbral_deteccion_t'),
    umbralDeteccionKgAnexoII: a6.numeroPositivo('umbral_deteccion_kg_anexo_ii'),
    mesesRevisionDetector: a6.enteroPositivo('meses_revision_detector'),
    fuente: a6.texto('fuente'),
  );

  final a45 = f.mapa('art4_5');
  final art45 = ReglasArt45(
    desdeHoras: a45.enteroPositivo('desde_horas_funcionamiento'),
    hastaMeses: a45.enteroPositivo('hasta_meses'),
    fuente: a45.texto('fuente'),
  );

  final a134 = f.mapa('art13_4');
  final origenesJ = a134.mapa('origenes');
  final origenes = <OrigenGas, ReglaOrigen>{};
  for (final o in OrigenGas.values) {
    final oj = origenesJ.mapa(o.wire);
    origenes[o] = ReglaOrigen(
      permitido: oj.booleano('permitido'),
      datos: List.unmodifiable(oj.listaTextos('datos')),
    );
  }
  if (origenes[OrigenGas.virgen]!.permitido) {
    throw NormativaInvalida(
      r'$.fgas.art13_4.origenes.virgen: no puede estar permitido',
    );
  }
  for (final o in [OrigenGas.regenerado, OrigenGas.reciclado]) {
    if (origenes[o]!.permitido && origenes[o]!.datos.isEmpty) {
      throw NormativaInvalida(
        '\$.fgas.art13_4.origenes.${o.wire}: faltan los datos que pide el origen',
      );
    }
  }
  final art134 = ReglasArt134(
    desde: a134.fecha('desde'),
    umbralPcg: a134.numeroPositivo('umbral_pcg'),
    categorias: a134.categorias('categorias'),
    soloAnexoI: a134.booleano('solo_anexo_i'),
    excepcionesHasta: a134.fecha('excepciones_hasta'),
    origenes: Map.unmodifiable(origenes),
    fuente: a134.texto('fuente'),
  );
  if (art134.excepcionesHasta.clave <= art134.desde.clave) {
    throw NormativaInvalida(
      r'$.fgas.art13_4: excepciones_hasta antes de desde',
    );
  }

  ReglaAviso aviso(String clave) {
    final a = f.mapa(clave);
    if (a.texto('modo') != 'aviso') {
      throw NormativaInvalida('\$.fgas.$clave.modo: en el MVP solo «aviso»');
    }
    return ReglaAviso(
      desde: a.fecha('desde'),
      umbralPcg: a.numeroPositivo('umbral_pcg'),
      categorias: a.categorias('categorias'),
      verificada: a.booleano('verificada'),
      fuente: a.texto('fuente'),
      nota: a.texto('nota'),
    );
  }

  return ReglasFgas(
    art5: art5,
    art6: art6,
    art45: art45,
    art134: art134,
    art133: aviso('art13_3'),
    art135: aviso('art13_5'),
  );
}

/// Franjas contiguas que empiezan en el umbral de sujeción y acaban abiertas.
List<FranjaControlFugas> _parsearFranjas(
  _Lector padre,
  String clave,
  double umbral,
) {
  final franjas = <FranjaControlFugas>[];
  for (final l in padre.lista(clave)) {
    final f = FranjaControlFugas(
      desde: l.numeroPositivo('desde'),
      hasta: l.numeroOpcional('hasta'),
      meses: l.enteroPositivo('meses'),
      mesesConDeteccion: l.enteroPositivo('meses_con_deteccion'),
    );
    if (f.hasta != null && f.hasta! <= f.desde) {
      throw NormativaInvalida('${l.ruta}: hasta ≤ desde');
    }
    if (f.mesesConDeteccion < f.meses) {
      // La detección amplía el plazo, nunca lo acorta (art. 5.6).
      throw NormativaInvalida('${l.ruta}: con detección no puede ser menor');
    }
    franjas.add(f);
  }
  final ruta = '${padre.ruta}.$clave';
  if (franjas.isEmpty) throw NormativaInvalida('$ruta: vacío');
  if (franjas.first.desde != umbral) {
    throw NormativaInvalida(
      '$ruta: la primera franja no empieza en el umbral $umbral',
    );
  }
  for (var k = 1; k < franjas.length; k++) {
    if (franjas[k - 1].hasta != franjas[k].desde) {
      throw NormativaInvalida('$ruta: franjas no contiguas en la posición $k');
    }
  }
  if (franjas.last.hasta != null) {
    throw NormativaInvalida('$ruta: la última franja debe ser abierta');
  }
  return List.unmodifiable(franjas);
}

ReglasRite _parsearRite(_Lector r) {
  final mensual = r.mapa('regimen_mas_de_70_kw');
  if (mensual.booleano('plantilla_en_mvp')) {
    throw NormativaInvalida(
      r'$.rite.regimen_mas_de_70_kw: la plantilla de más de 70 kW está fuera del MVP',
    );
  }
  final sup = r.mapa('supervision_remota');
  if (sup.booleano('aplicacion_automatica')) {
    throw NormativaInvalida(
      r'$.rite.supervision_remota: la ampliación no se aplica sola en el MVP',
    );
  }

  final filas = <FilaTabla31>[];
  final claves = <String>{};
  for (final l in r.lista('tabla_3_1')) {
    final f = FilaTabla31(
      clave: l.texto('clave'),
      familia: l.texto('familia'),
      pnMayorQueKw: l.numeroOpcional('pn_mayor_que_kw'),
      pnHastaKw: l.numeroOpcional('pn_hasta_kw'),
      mesesVivienda: l.enteroPositivo('meses_vivienda'),
      mesesOtros: l.enteroPositivo('meses_otros'),
      textoBoe: l.texto('texto_boe'),
      verificada: l.booleano('verificada'),
    );
    if (!claves.add(f.clave)) {
      throw NormativaInvalida('${l.ruta}: clave ${f.clave} repetida');
    }
    filas.add(f);
  }

  final familias = r.mapa('familia_por_tipo_equipo');
  final porTipo = <TipoEquipo, String>{};
  for (final t in TipoEquipo.values) {
    final fam = familias.texto(t.wire);
    if (!filas.any((f) => f.familia == fam)) {
      throw NormativaInvalida(
        '\$.rite.familia_por_tipo_equipo.${t.wire}: familia «$fam» sin filas',
      );
    }
    porTipo[t] = fam;
  }

  final umbral = r.numeroPositivo('umbral_regimen_mensual_kw');
  // Cada familia usada por un tipo debe cubrir sin huecos de 0 al umbral, para
  // que un equipo de una instalación ≤ 70 kW siempre encuentre su fila.
  for (final fam in porTipo.values.toSet()) {
    for (final pn in [0.0, 0.001, umbral]) {
      if (!filas.any((f) => f.familia == fam && f.contiene(pn))) {
        throw NormativaInvalida(
          '\$.rite.tabla_3_1: la familia $fam no cubre $pn kW',
        );
      }
    }
    for (final f in filas.where(
      (f) => f.familia == fam && f.pnHastaKw != null,
    )) {
      if (f.pnHastaKw! < umbral &&
          !filas.any(
            (g) => g.familia == fam && g.pnMayorQueKw == f.pnHastaKw,
          )) {
        throw NormativaInvalida(
          '\$.rite.tabla_3_1: hueco en $fam tras ${f.pnHastaKw} kW',
        );
      }
    }
  }

  return ReglasRite(
    umbralRegimenMensualKw: umbral,
    umbralVerificada: r.booleano('umbral_verificada'),
    mesesRegimenMensual: mensual.enteroPositivo('meses'),
    textoRegimenMensual: mensual.texto('texto'),
    supervisionPotenciaMaxKw: sup.numeroPositivo('potencia_max_kw'),
    supervisionMesesMax: sup.enteroPositivo('meses_max'),
    tabla31: List.unmodifiable(filas),
    familiaPorTipo: Map.unmodifiable(porTipo),
    familiaPorTipoVerificada: r.booleano('familia_por_tipo_equipo_verificada'),
    fuente: r.texto('fuente'),
  );
}

Map<String, Object?> _comoMapa(Object? v, String ruta) {
  if (v is Map<String, Object?>) return v;
  throw NormativaInvalida('$ruta: se esperaba un objeto');
}

/// Lector con ruta para que cada error diga dónde está el fallo
/// («$.fgas.art5.anexo_i.franjas_t[1].meses: falta»).
class _Lector {
  _Lector(this._m, this.ruta);
  final Map<String, Object?> _m;
  final String ruta;

  Object? _campo(String clave) {
    if (!_m.containsKey(clave)) throw NormativaInvalida('$ruta.$clave: falta');
    return _m[clave];
  }

  _Lector mapa(String clave) =>
      _Lector(_comoMapa(_campo(clave), '$ruta.$clave'), '$ruta.$clave');

  List<_Lector> lista(String clave) {
    final v = _campo(clave);
    if (v is! List) {
      throw NormativaInvalida('$ruta.$clave: se esperaba una lista');
    }
    return [
      for (var k = 0; k < v.length; k++)
        _Lector(_comoMapa(v[k], '$ruta.$clave[$k]'), '$ruta.$clave[$k]'),
    ];
  }

  List<String> listaTextos(String clave) {
    final v = _campo(clave);
    if (v is! List || v.any((e) => e is! String || e.isEmpty)) {
      throw NormativaInvalida('$ruta.$clave: se esperaba una lista de textos');
    }
    return v.cast<String>();
  }

  String texto(String clave) {
    final v = _campo(clave);
    if (v is! String || v.trim().isEmpty) {
      throw NormativaInvalida('$ruta.$clave: se esperaba un texto no vacío');
    }
    return v;
  }

  bool booleano(String clave) {
    final v = _campo(clave);
    if (v is! bool) {
      throw NormativaInvalida('$ruta.$clave: se esperaba true o false');
    }
    return v;
  }

  double numeroNoNegativo(String clave) {
    final v = _campo(clave);
    if (v is! num || !v.isFinite || v < 0) {
      throw NormativaInvalida('$ruta.$clave: se esperaba un número ≥ 0');
    }
    return v.toDouble();
  }

  double numeroPositivo(String clave) {
    final v = numeroNoNegativo(clave);
    if (v == 0) {
      throw NormativaInvalida('$ruta.$clave: se esperaba un número > 0');
    }
    return v;
  }

  double? numeroOpcional(String clave) {
    if (_campo(clave) == null) return null;
    return numeroPositivo(clave);
  }

  int entero(String clave) {
    final v = _campo(clave);
    if (v is! int) {
      throw NormativaInvalida('$ruta.$clave: se esperaba un entero');
    }
    return v;
  }

  int enteroPositivo(String clave) {
    final v = entero(clave);
    if (v <= 0) {
      throw NormativaInvalida('$ruta.$clave: se esperaba un entero > 0');
    }
    return v;
  }

  DiaCalendario fecha(String clave) {
    final t = texto(clave);
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(t);
    if (m == null) {
      throw NormativaInvalida('$ruta.$clave: «$t» no es AAAA-MM-DD');
    }
    final d = DiaCalendario(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
    );
    final real = DateTime.utc(d.anio, d.mes, d.dia);
    if (real.month != d.mes || real.day != d.dia) {
      throw NormativaInvalida('$ruta.$clave: «$t» no existe');
    }
    return d;
  }

  Set<CategoriaFgas> categorias(String clave) {
    final textos = listaTextos(clave);
    if (textos.isEmpty) throw NormativaInvalida('$ruta.$clave: vacío');
    try {
      return Set.unmodifiable(textos.map(CategoriaFgas.desde));
    } on ArgumentError catch (e) {
      throw NormativaInvalida('$ruta.$clave: ${e.message} (${e.invalidValue})');
    }
  }
}
