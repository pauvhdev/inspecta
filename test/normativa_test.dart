// Carga el JSON real de assets/normativa/ con dart:io, lo valida y comprueba
// las cifras contra las fuentes primarias (DISEÑO.md §7.3):
// - Reglamento (UE) 2024/573, anexo I, sección 1 (PCG del IPCC AR4, nota 2):
//   HFC-32 675, HFC-125 3.500, HFC-134a 1.430, HFC-143a 4.470.
// - Anexo II, sección 1 (IPCC AR6): HFC-1234yf 0,501; HFC-1234ze 1,37.
// - Anexo VI: PCG de una mezcla = media ponderada por fracción en masa.
// - RD 1027/2007, IT 3.3, Tabla 3.1.
// Y que un JSON roto falla al cargar, alto y claro.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/dominio/normativa.dart';
import 'package:inspecta/dominio/tipos.dart';

const ruta = 'assets/normativa/$versionNormativaActual.json';

void main() {
  late String texto;
  late Normativa n;

  setUpAll(() {
    texto = File(ruta).readAsStringSync();
    n = parsearNormativa(texto);
  });

  /// Copia del JSON real con un cambio aplicado, para probar la validación.
  String mutado(void Function(Map<String, dynamic> j) cambio) {
    final j = jsonDecode(texto) as Map<String, dynamic>;
    cambio(j);
    return jsonEncode(j);
  }

  Matcher invalida(String fragmento) => throwsA(
    isA<NormativaInvalida>().having(
      (e) => e.mensaje,
      'mensaje',
      contains(fragmento),
    ),
  );

  group('El JSON real', () {
    test('carga y su versión coincide con el nombre del fichero', () {
      expect(n.version, versionNormativaActual);
      expect(ruta, endsWith('${n.version}.json'));
    });

    test('está el catálogo mínimo de refrigerantes', () {
      for (final c in [
        'R-410A',
        'R-407C',
        'R-404A',
        'R-407A',
        'R-507A',
        'R-422D',
        'R-448A',
        'R-449A',
        'R-452A',
        'R-454B',
        'R-513A',
        'R-134a',
        'R-32',
        'R-125',
        'R-143a',
        'R-1234yf',
        'R-1234ze',
      ]) {
        expect(n.refrigerante(c), isNotNull, reason: c);
      }
    });

    test('búsqueda tolerante al formato del código', () {
      expect(n.refrigerante('r410a')?.codigo, 'R-410A');
      expect(n.refrigerante('R 134A')?.codigo, 'R-134a');
      expect(n.refrigerante('R-22'), isNull); // no se inventa un PCG
    });

    // PCG del anexo I (AR4) y II (AR6) del 2024/573, y de las mezclas por el
    // método del anexo VI con la composición en masa de la Secretaría del
    // Ozono del PNUMA.
    final pcg = <String, double>{
      'R-32': 675,
      'R-125': 3500,
      'R-134a': 1430,
      'R-143a': 4470,
      'R-1234yf': 0.501,
      'R-1234ze': 1.37,
      'R-410A': 2087.5,
      'R-407C': 1773.85,
      'R-404A': 3921.6,
      'R-407A': 2107,
      'R-507A': 3985,
      'R-422D': 2728.95,
      'R-448A': 1385.9961,
      'R-449A': 1396.161753,
      'R-452A': 2139.4003,
      'R-454B': 465.230811,
      'R-513A': 629.48056,
    };
    for (final MapEntry(key: c, value: v) in pcg.entries) {
      test('PCG $c = $v', () {
        expect(n.refrigerante(c)!.pcg, closeTo(v, 1e-6));
      });
    }

    test('anexos: HFO puros en el II; las mezclas con HFC, en el I', () {
      expect(n.refrigerante('R-1234yf')!.esAnexoIIPuro, isTrue);
      expect(n.refrigerante('R-1234ze')!.esAnexoIIPuro, isTrue);
      for (final c in ['R-454B', 'R-448A', 'R-449A', 'R-452A', 'R-513A']) {
        final r = n.refrigerante(c)!;
        expect(r.anexo, AnexoFgas.i, reason: c);
        expect(r.esMezclaConAnexoII, isTrue, reason: c);
      }
      expect(
        n.refrigerante('R-454B')!.porcentajeAnexoIISeccion1,
        closeTo(31.1, 1e-9),
      );
      expect(n.refrigerante('R-410A')!.esMezclaConAnexoII, isFalse);
    });

    test('las mezclas son calculadas y guardan composición y fuente', () {
      for (final r in n.refrigerantes.where((r) => r.esMezcla)) {
        expect(r.calculado, isTrue, reason: r.codigo);
        final suma = r.composicion.fold<double>(
          0,
          (s, c) => s + c.porcentajeMasa,
        );
        expect(suma, closeTo(100, 1e-9), reason: r.codigo);
        expect(r.fuente, contains('anexo VI'), reason: r.codigo);
      }
    });

    test('art. 5: umbrales y franjas', () {
      final a = n.fgas.art5;
      expect(a.umbralSujecionT, 5);
      expect(a.umbralHermeticoT, 10);
      expect(
        [
          for (final f in a.franjasT)
            (f.desde, f.hasta, f.meses, f.mesesConDeteccion),
        ],
        [(5.0, 50.0, 12, 24), (50.0, 500.0, 6, 12), (500.0, null, 3, 6)],
      );
      expect(a.anexoIIPurosCalculados, isFalse);
      expect(a.mezclasCriterioKgVerificada, isFalse);
      expect(a.umbralExcepcionResidencialKg, 3);
    });

    test('arts. 6, 4.5 y 13', () {
      expect(n.fgas.art6.umbralDeteccionT, 500);
      expect(n.fgas.art6.mesesRevisionDetector, 12);
      expect(n.fgas.art45.desdeHoras, 24);
      expect(n.fgas.art45.hastaMeses, 1);
      final a134 = n.fgas.art134;
      expect(a134.desde, const DiaCalendario(2026, 1, 1));
      expect(a134.excepcionesHasta, const DiaCalendario(2032, 1, 1));
      expect(a134.umbralPcg, 2500);
      expect(a134.categorias, {CategoriaFgas.aireAcondicionadoBombaCalor});
      expect(a134.origenes[OrigenGas.virgen]!.permitido, isFalse);
      expect(a134.origenes[OrigenGas.regenerado]!.datos, [
        'regenerado_lote',
        'regenerado_etiqueta_foto_id',
      ]);
      expect(a134.origenes[OrigenGas.reciclado]!.datos, [
        'reciclado_recuperado_por',
        'reciclado_declaracion',
      ]);
      // DISEÑO.md §3.2: el 13.3 queda sin verificar y solo avisa.
      expect(n.fgas.art133.verificada, isFalse);
      expect(n.fgas.art133.categorias, {CategoriaFgas.refrigeracion});
    });

    test('RITE: umbral de 70 kW sin verificar y Tabla 3.1 de aire '
        'acondicionado', () {
      final r = n.rite;
      expect(r.umbralRegimenMensualKw, 70);
      expect(r.umbralVerificada, isFalse);
      expect(r.mesesRegimenMensual, 1);
      expect(r.supervisionMesesMax, 24);
      final aa = r.tabla31.where((f) => f.familia == 'aire_acondicionado');
      expect(
        [
          for (final f in aa)
            (f.pnMayorQueKw, f.pnHastaKw, f.mesesVivienda, f.mesesOtros),
        ],
        [(null, 12.0, 48, 24), (12.0, 70.0, 24, 12)],
      );
      for (final t in TipoEquipo.values) {
        expect(r.familiaPorTipo[t], isNotNull, reason: t.wire);
      }
    });

    test('tipos de certificado como datos', () {
      final codigos = n.tiposCertificado.map((c) => c.codigo).toSet();
      expect(codigos, containsAll(['A1', 'A2', 'E', 'I.1', 'I.2']));
    });

    test('es inmutable', () {
      expect(() => n.refrigerantes.clear(), throwsUnsupportedError);
      expect(() => n.fgas.art5.franjasT.clear(), throwsUnsupportedError);
    });
  });

  group('Sumar meses de calendario', () {
    final casos = <(DateTime, int, DateTime)>[
      (DateTime(2026, 1, 31), 1, DateTime(2026, 2, 28)),
      (DateTime(2028, 1, 31), 1, DateTime(2028, 2, 29)),
      (DateTime(2026, 3, 31), 1, DateTime(2026, 4, 30)),
      (DateTime(2026, 8, 31), 6, DateTime(2027, 2, 28)),
      (DateTime(2026, 11, 15, 10, 30), 3, DateTime(2027, 2, 15, 10, 30)),
      (DateTime(2026, 12, 1), 48, DateTime(2030, 12, 1)),
    ];
    for (final (desde, meses, hasta) in casos) {
      test('$desde + $meses → $hasta', () {
        expect(sumarMesesCalendario(desde, meses), hasta);
      });
    }

    test('conserva UTC', () {
      final r = sumarMesesCalendario(DateTime.utc(2026, 1, 31, 23), 1);
      expect(r.isUtc, isTrue);
      expect(r, DateTime.utc(2026, 2, 28, 23));
    });
  });

  // Instantes en UTC (lib/data/local/tablas/comunes.dart) frente a días
  // SoloFecha (medianoche UTC, conversores.dart). Los instantes se construyen
  // en hora local y se pasan a UTC: la prueba no depende de la zona.
  group('Instantes y días de calendario', () {
    test('esIgualOPosterior mira el día local del instante, venga en UTC o '
        'no', () {
      const dia = DiaCalendario(2026, 1, 1);
      final local = DateTime(2026, 1, 1, 0, 30);
      expect(esIgualOPosterior(local, dia), isTrue);
      expect(esIgualOPosterior(local.toUtc(), dia), isTrue);
      final antes = DateTime(2025, 12, 31, 23, 59);
      expect(esIgualOPosterior(antes, dia), isFalse);
      expect(esIgualOPosterior(antes.toUtc(), dia), isFalse);
    });

    test('DiaCalendario.deInstante convierte; deComponentes no', () {
      final instante = DateTime(2025, 11, 9, 0, 30).toUtc();
      expect(
        DiaCalendario.deInstante(instante),
        const DiaCalendario(2025, 11, 9),
      );
      expect(
        DiaCalendario.deComponentes(DateTime.utc(2026, 8, 31)),
        const DiaCalendario(2026, 8, 31),
      );
    });

    test('vencimientoDesde: instante a hora local; día tal cual', () {
      final a = vencimientoDesde(
        DateTime(2026, 1, 31, 0, 30).toUtc(),
        1,
        referenciaEsInstante: true,
      );
      expect(a.fecha, DateTime(2026, 2, 28, 0, 30));
      expect(a.dia, const DiaCalendario(2026, 2, 28));
      final b = vencimientoDesde(
        DateTime.utc(2026, 8, 31),
        6,
        referenciaEsInstante: false,
      );
      expect(b.fecha, DateTime.utc(2027, 2, 28));
      expect(b.dia, const DiaCalendario(2027, 2, 28));
    });
  });

  group('Validación al cargar (falla alto y claro)', () {
    test('JSON mal formado', () {
      expect(() => parsearNormativa('{'), invalida('JSON mal formado'));
    });

    test('falta un campo: dice la ruta', () {
      final t = mutado(
        (j) => (j['fgas']['art5']['anexo_i'] as Map).remove('franjas_t'),
      );
      expect(
        () => parsearNormativa(t),
        invalida(r'$.fgas.art5.anexo_i.franjas_t: falta'),
      );
    });

    test('versión con formato erróneo', () {
      expect(
        () => parsearNormativa(mutado((j) => j['version'] = 'nov-2026')),
        invalida('AAAA-MM'),
      );
    });

    test('PCG de una mezcla que no cuadra con su composición', () {
      final t = mutado((j) {
        final r = (j['refrigerantes'] as List).firstWhere(
          (r) => r['codigo'] == 'R-410A',
        );
        r['pcg'] = 2088;
      });
      expect(() => parsearNormativa(t), invalida('no cuadra con el anexo VI'));
    });

    test('composición que no suma 100 %', () {
      final t = mutado((j) {
        final r = (j['refrigerantes'] as List).firstWhere(
          (r) => r['codigo'] == 'R-410A',
        );
        (r['composicion'] as List)[0]['porcentaje_masa'] = 49;
      });
      expect(() => parsearNormativa(t), invalida('no 100 %'));
    });

    test('componente sin PCG', () {
      final t = mutado((j) {
        final r = (j['refrigerantes'] as List).firstWhere(
          (r) => r['codigo'] == 'R-410A',
        );
        (r['composicion'] as List)[0]['componente'] = 'R-999';
      });
      expect(() => parsearNormativa(t), invalida('sin PCG'));
    });

    test('código repetido', () {
      final t = mutado((j) {
        final l = j['refrigerantes'] as List;
        l.add(Map<String, dynamic>.from(l.first as Map));
      });
      expect(() => parsearNormativa(t), invalida('repetido'));
    });

    test('franjas no contiguas', () {
      final t = mutado(
        (j) => j['fgas']['art5']['anexo_i']['franjas_t'][1]['desde'] = 60,
      );
      expect(() => parsearNormativa(t), invalida('no contiguas'));
    });

    test('con detección no puede acortar el plazo', () {
      final t = mutado(
        (j) =>
            j['fgas']['art5']['anexo_i']['franjas_t'][0]['meses_con_deteccion'] =
                6,
      );
      expect(() => parsearNormativa(t), invalida('con detección'));
    });

    test('gas virgen permitido en el 13.4', () {
      final t = mutado(
        (j) => j['fgas']['art13_4']['origenes']['virgen']['permitido'] = true,
      );
      expect(() => parsearNormativa(t), invalida('virgen'));
    });

    test('origen permitido sin los datos que pide', () {
      final t = mutado(
        (j) => j['fgas']['art13_4']['origenes']['regenerado']['datos'] = [],
      );
      expect(() => parsearNormativa(t), invalida('faltan los datos'));
    });

    test('fecha que no existe', () {
      final t = mutado((j) => j['fgas']['art13_4']['desde'] = '2026-02-30');
      expect(() => parsearNormativa(t), invalida('no existe'));
    });

    test('excepción residencial automatizada', () {
      final t = mutado(
        (j) =>
            j['fgas']['art5']['excepcion_hermetico_residencial']['automatizada'] =
                true,
      );
      expect(() => parsearNormativa(t), invalida('no se automatiza'));
    });

    test('plantilla de más de 70 kW dentro del MVP', () {
      final t = mutado(
        (j) => j['rite']['regimen_mas_de_70_kw']['plantilla_en_mvp'] = true,
      );
      expect(() => parsearNormativa(t), invalida('fuera del MVP'));
    });

    test('hueco en la Tabla 3.1 de una familia usada', () {
      final t = mutado((j) {
        (j['rite']['tabla_3_1'] as List).removeWhere(
          (f) => f['clave'] == 'aire_acondicionado_12_a_70',
        );
      });
      expect(() => parsearNormativa(t), invalida('aire_acondicionado'));
    });

    test('tipo de equipo sin familia', () {
      final t = mutado(
        (j) =>
            (j['rite']['familia_por_tipo_equipo'] as Map).remove('enfriadora'),
      );
      expect(() => parsearNormativa(t), invalida('enfriadora'));
    });

    test('gas del anexo II de una sección distinta de la 1 (el art. 5.1 solo '
        'regula la sección 1)', () {
      final t = mutado((j) {
        final r = (j['refrigerantes'] as List).firstWhere(
          (r) => r['codigo'] == 'R-1234ze',
        );
        r['seccion'] = 2;
      });
      expect(() => parsearNormativa(t), invalida('sección 1'));
    });

    test('la fracción HFO de una mezcla sale solo del anexo II, sección 1', () {
      expect(n.refrigerante('R-454B')!.porcentajeAnexoIISeccion1, 31.1);
      expect(n.refrigerante('R-448A')!.porcentajeAnexoIISeccion1, 27);
      expect(n.refrigerante('R-410A')!.porcentajeAnexoIISeccion1, 0);
      expect(n.refrigerante('R-1234yf')!.porcentajeAnexoIISeccion1, 100);
    });

    test('categoría F-gas desconocida', () {
      final t = mutado(
        (j) => j['fgas']['art13_4']['categorias'] = ['frigorifico'],
      );
      expect(() => parsearNormativa(t), invalida('categorias'));
    });
  });
}
