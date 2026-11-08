// Pruebas de tabla de fgas.dart (DISEÑO.md §12, día 2) con la normativa real
// de assets/normativa/. Los PCG son los del Reglamento (UE) 2024/573, anexo I
// (IPCC AR4: R-32 675, R-125 3.500, R-134a 1.430, R-143a 4.470), que coinciden
// con los de DISEÑO.md: los kg frontera del hito (R-410A 2,39 / 2,40 kg y
// R-32 7,41 kg) siguen siendo los correctos.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/dominio/fgas.dart';
import 'package:inspecta/dominio/normativa.dart';
import 'package:inspecta/dominio/tipos.dart';

late final Normativa n;

Refrigerante gas(String codigo) {
  final r = n.refrigerante(codigo);
  if (r == null) throw StateError('Falta $codigo en la normativa');
  return r;
}

/// Gas de prueba con PCG 1.000: kg = t CO2-eq, para probar los bordes exactos
/// de las franjas (5, 10, 50, 500 t) sin depender de un PCG real.
const pcg1000 = Refrigerante(
  codigo: 'PRUEBA-1000',
  nombre: 'Gas de prueba',
  anexo: AnexoFgas.i,
  seccion: 1,
  pcg: 1000,
  calculado: false,
  composicion: [],
  fuente: 'prueba',
  verificada: false,
);

ResultadoControlFugas evaluar(
  Refrigerante r,
  double kg, {
  bool deteccion = false,
  bool hermetico = false,
  bool residencial = false,
}) => evaluarControlFugas(
  n,
  refrigerante: r,
  cargaKg: kg,
  conDeteccion: deteccion,
  hermeticoEtiquetado: hermetico,
  excepcionResidencialMarcada: residencial,
);

/// Periodicidad en meses, o null si no está sujeto. Falla si no se calculó.
int? meses(ResultadoControlFugas r) => switch (r) {
  SujetoControlFugas(:final periodicidadMeses) => periodicidadMeses,
  NoSujetoControlFugas() => null,
  ControlFugasNoCalculado() => throw StateError('No calculado'),
};

void main() {
  setUpAll(() {
    n = parsearNormativa(
      File('assets/normativa/2026-11.json').readAsStringSync(),
    );
  });

  group('t CO2-eq = kg × PCG / 1000 (art. 3.3, anexos I y VI)', () {
    final casos = <(String, double, double)>[
      ('R-32', 1.1, 0.7425),
      ('R-32', 7.41, 5.00175),
      ('R-410A', 2.39, 4.989125),
      ('R-410A', 2.40, 5.01),
      ('R-410A', 12, 25.05),
      ('R-407C', 8, 14.1908),
      ('R-134a', 60, 85.8),
      ('R-134a', 3.50, 5.005),
      ('R-404A', 10, 39.216),
      ('R-1234yf', 5, 0.002505),
      ('R-454B', 33, 15.352617),
    ];
    for (final (codigo, kg, t) in casos) {
      test('$codigo $kg kg → $t t', () {
        expect(tCo2eq(gas(codigo), kg), closeTo(t, 1e-6));
      });
    }

    test('carga negativa o no finita: error', () {
      expect(() => tCo2eq(gas('R-32'), -1), throwsArgumentError);
      expect(() => tCo2eq(gas('R-32'), double.nan), throwsArgumentError);
    });
  });

  group('Hito día 2: casos frontera del art. 5', () {
    // (gas, kg, detección, meses esperados o null = no sujeto)
    final casos = <(String, double, bool, int?)>[
      ('R-410A', 2.39, false, null), // 4,99 t
      ('R-410A', 2.39, true, null),
      ('R-410A', 2.40, false, 12), // 5,01 t
      ('R-410A', 2.40, true, 24),
      ('R-32', 7.40, false, null), // 4,995 t
      ('R-32', 7.41, false, 12), // 5,002 t
      ('R-32', 7.41, true, 24),
      ('R-134a', 3.49, false, null), // 4,99 t
      ('R-134a', 3.50, false, 12), // 5,005 t
    ];
    for (final (codigo, kg, det, esperado) in casos) {
      test('$codigo $kg kg, detección $det → ${esperado ?? 'no sujeto'}', () {
        expect(meses(evaluar(gas(codigo), kg, deteccion: det)), esperado);
      });
    }

    test('hermético etiquetado < 10 t: no sujeto; ≥ 10 t: sujeto', () {
      // R-410A: 4,79 kg = 9,999 t; 4,80 kg = 10,02 t.
      final bajo = evaluar(gas('R-410A'), 4.79, hermetico: true);
      expect(bajo, isA<NoSujetoControlFugas>());
      expect(
        (bajo as NoSujetoControlFugas).motivo,
        MotivoNoSujeto.hermeticoEtiquetado,
      );
      expect(meses(evaluar(gas('R-410A'), 4.80, hermetico: true)), 12);
      // Sin la etiqueta de hermético, 9,999 t sí está sujeto.
      expect(meses(evaluar(gas('R-410A'), 4.79)), 12);
    });
  });

  group('Franjas del art. 5.6 y sus bordes (PCG 1.000: kg = t)', () {
    final casos = <(double, bool, bool, int?)>[
      // (t, detección, hermético, meses)
      (4.999, false, false, null),
      (5, false, false, 12),
      (5, true, false, 24),
      (5, false, true, null), // hermético < 10 t
      (9.999, false, true, null),
      (10, false, true, 12), // hermético en 10 t exactas: sujeto
      (49.999, false, false, 12),
      (49.999, true, false, 24),
      (50, false, false, 6),
      (50, true, false, 12),
      (499.999, false, false, 6),
      (499.999, true, false, 12),
      (500, false, false, 3),
      (500, true, false, 6),
      (5000, true, false, 6),
    ];
    for (final (t, det, herm, esperado) in casos) {
      test('$t t, detección $det, hermético $herm → ${esperado ?? 'no'}', () {
        expect(
          meses(evaluar(pcg1000, t, deteccion: det, hermetico: herm)),
          esperado,
        );
      });
    }

    test('detección obligatoria desde 500 t (art. 6.1)', () {
      final a = evaluar(pcg1000, 499.999) as SujetoControlFugas;
      expect(a.deteccionObligatoria, isFalse);
      final b = evaluar(pcg1000, 500) as SujetoControlFugas;
      expect(b.deteccionObligatoria, isTrue);
      expect(b.faltaDeteccionObligatoria, isTrue);
      expect(b.avisos.any((s) => s.contains('art. 6.1')), isTrue);
      final c = evaluar(pcg1000, 500, deteccion: true) as SujetoControlFugas;
      expect(c.faltaDeteccionObligatoria, isFalse);
    });
  });

  group('Gases del anexo II y mezclas con HFO', () {
    for (final codigo in ['R-1234yf', 'R-1234ze']) {
      test('$codigo puro → no calculado en el MVP, nunca un número', () {
        for (final kg in [0.5, 5.0, 50.0, 500.0]) {
          final r = evaluar(gas(codigo), kg);
          expect(r, isA<ControlFugasNoCalculado>());
          expect((r as ControlFugasNoCalculado).motivo, contains('MVP'));
        }
      });
    }

    test('R-454B 33 kg: 15,35 t (12 meses) pero 10,26 kg de HFO → 6 meses '
        '[A VERIFICAR: criterio en kg sobre la fracción HFO]', () {
      final r = evaluar(gas('R-454B'), 33) as SujetoControlFugas;
      expect(r.tCo2eq, closeTo(15.352617, 1e-6));
      expect(r.kgAnexoII, closeTo(10.263, 1e-6));
      expect(r.periodicidadMeses, 6);
      expect(r.criterio, CriterioControlFugas.kgAnexoII);
    });

    test('R-454B 10 kg: 4,65 t pero 3,11 kg de HFO ≥ 1 kg → sujeto 12 meses '
        '[A VERIFICAR]', () {
      final r = evaluar(gas('R-454B'), 10) as SujetoControlFugas;
      expect(r.tCo2eq, lessThan(5));
      expect(r.periodicidadMeses, 12);
      expect(r.criterio, CriterioControlFugas.kgAnexoII);
    });

    test('R-410A no lleva HFO: manda la t CO2-eq', () {
      final r = evaluar(gas('R-410A'), 12) as SujetoControlFugas;
      expect(r.criterio, CriterioControlFugas.tCo2eq);
      expect(r.kgAnexoII, 0);
    });
  });

  group('Excepción residencial del art. 5.1 (la marca el técnico)', () {
    test('no se automatiza: sin marca, un hermético de 2 kg y 10,4 t está '
        'sujeto', () {
      expect(meses(evaluar(gas('R-404A'), 2.66, hermetico: true)), 12);
    });

    test('marcada, hermético y < 3 kg → no sujeto', () {
      final r = evaluar(
        gas('R-404A'),
        2.66,
        hermetico: true,
        residencial: true,
      );
      expect(
        (r as NoSujetoControlFugas).motivo,
        MotivoNoSujeto.excepcionResidencialMarcada,
      );
    });

    test('marcada pero 3 kg o no hermético → no aplica y avisa', () {
      final a = evaluar(gas('R-404A'), 3, hermetico: true, residencial: true);
      expect(meses(a), 12);
      expect((a as SujetoControlFugas).avisos.first, contains('no aplica'));
      final b = evaluar(gas('R-404A'), 2.66, residencial: true);
      expect(meses(b), 12);
    });
  });

  group('Siembra de la demo (§11.1) con los PCG verificados', () {
    final casos = <(String, String, double, double, int?)>[
      ('split', 'R-32', 1.1, 0.7425, null),
      ('rooftop', 'R-407C', 8, 14.1908, 12),
      ('VRV', 'R-410A', 12, 25.05, 12),
      ('enfriadora', 'R-134a', 60, 85.8, 6),
    ];
    for (final (equipo, codigo, kg, t, esperado) in casos) {
      test('$equipo $codigo $kg kg → $t t → ${esperado ?? 'no sujeto'}', () {
        final r = evaluar(gas(codigo), kg);
        expect(meses(r), esperado);
        final tr = switch (r) {
          SujetoControlFugas(:final tCo2eq) => tCo2eq,
          NoSujetoControlFugas(:final tCo2eq) => tCo2eq,
          ControlFugasNoCalculado(:final tCo2eq) => tCo2eq,
        };
        expect(tr, closeTo(t, 1e-6));
      });
    }
  });

  group('categoria_fgas deducida de tipo', () {
    final casos = <(TipoEquipo, CategoriaFgas, bool)>[
      (TipoEquipo.split, CategoriaFgas.aireAcondicionadoBombaCalor, false),
      (TipoEquipo.conductos, CategoriaFgas.aireAcondicionadoBombaCalor, false),
      (TipoEquipo.vrf, CategoriaFgas.aireAcondicionadoBombaCalor, false),
      (TipoEquipo.rooftop, CategoriaFgas.aireAcondicionadoBombaCalor, false),
      (TipoEquipo.bombaCalor, CategoriaFgas.aireAcondicionadoBombaCalor, false),
      (TipoEquipo.uta, CategoriaFgas.aireAcondicionadoBombaCalor, false),
      // Enfriadora: confort por defecto (lo prudente: el 13.4 bloquea) y
      // marcada dudosa para que el técnico la confirme.
      (TipoEquipo.enfriadora, CategoriaFgas.aireAcondicionadoBombaCalor, true),
      (TipoEquipo.otro, CategoriaFgas.otro, true),
    ];
    for (final (tipo, cat, dudosa) in casos) {
      test('${tipo.wire} → ${cat.wire}${dudosa ? ' (dudosa)' : ''}', () {
        final d = deducirCategoriaFgas(tipo);
        expect(d.categoria, cat);
        expect(d.dudosa, dudosa);
        expect(d.motivo, isNotEmpty);
      });
    }
  });

  group('Próximo control de fugas (meses de calendario)', () {
    // Se evalúan dentro de cada prueba: la normativa se carga en setUpAll.
    ResultadoControlFugas sujeto12() => evaluar(gas('R-410A'), 12);
    ResultadoControlFugas sujeto6() => evaluar(gas('R-134a'), 60);

    test('desde el último control en Inspecta', () {
      final p = proximoControlFugas(
        sujeto12(),
        ultimoControlAt: DateTime(2026, 3, 15, 10),
        controlPrevioDeclarado: DateTime(2025, 1, 1),
      ) as ProximoControlEnFecha;
      expect(p.fecha, DateTime(2027, 3, 15, 10));
      expect(p.origen, OrigenReferencia.ultimoEnInspecta);
      expect(p.meses, 12);
    });

    test('sin control en Inspecta: desde el previo declarado', () {
      final p = proximoControlFugas(
        sujeto6(),
        controlPrevioDeclarado: DateTime(2026, 8, 31),
      ) as ProximoControlEnFecha;
      expect(p.fecha, DateTime(2027, 2, 28)); // 31 de agosto + 6 meses
      expect(p.origen, OrigenReferencia.previoDeclarado);
    });

    test('31 de enero + 12 meses y + 1 mes en fin de mes', () {
      final p = proximoControlFugas(
        sujeto12(),
        ultimoControlAt: DateTime(2026, 1, 31),
      ) as ProximoControlEnFecha;
      expect(p.fecha, DateTime(2027, 1, 31));
      expect(
        sumarMesesCalendario(DateTime(2026, 1, 31), 1),
        DateTime(2026, 2, 28),
      );
      expect(
        sumarMesesCalendario(DateTime(2028, 1, 31), 1),
        DateTime(2028, 2, 29),
      );
    });

    test('vencido solo cuando pasa el día', () {
      final p = proximoControlFugas(
        sujeto12(),
        ultimoControlAt: DateTime(2025, 11, 8, 9),
      ) as ProximoControlEnFecha;
      expect(p.vencido(DateTime(2026, 11, 8, 23, 59)), isFalse);
      expect(p.vencido(DateTime(2026, 11, 9)), isTrue);
    });

    test('sujeto sin ninguna referencia → sin referencia (hacerlo ya)', () {
      expect(
        proximoControlFugas(sujeto12()),
        isA<ProximoControlSinReferencia>(),
      );
    });

    test('no sujeto o no calculado → no aplica', () {
      expect(
        proximoControlFugas(
          evaluar(gas('R-32'), 1.1),
          ultimoControlAt: DateTime(2026),
        ),
        isA<ProximoControlNoAplica>(),
      );
      expect(
        proximoControlFugas(
          evaluar(gas('R-1234yf'), 5),
          ultimoControlAt: DateTime(2026),
        ),
        isA<ProximoControlNoAplica>(),
      );
    });
  });

  group('Revisión del detector (art. 6.3: 12 meses)', () {
    test('con detector y última revisión', () {
      final r = revisionDetector(
        n,
        conDeteccion: true,
        deteccionObligatoria: true,
        ultimaRevision: DateTime(2026, 2, 28),
      ) as RevisionDetectorEnFecha;
      expect(r.fecha, DateTime(2027, 2, 28));
      expect(r.obligatoria, isTrue);
    });

    test('sin detector → no aplica; sin revisión → sin referencia', () {
      expect(
        revisionDetector(n, conDeteccion: false, deteccionObligatoria: true),
        isA<RevisionDetectorNoAplica>(),
      );
      expect(
        revisionDetector(n, conDeteccion: true, deteccionObligatoria: false),
        isA<RevisionDetectorSinReferencia>(),
      );
    });
  });

  group('Nuevo control tras reparar (art. 4.5): +24 h a +1 mes', () {
    test('ventana desde +24 h hasta +1 mes', () {
      final v = ventanaNuevoControl(n, DateTime(2026, 3, 10, 10, 30));
      expect(v.desde, DateTime(2026, 3, 11, 10, 30));
      expect(v.hasta, DateTime(2026, 4, 10, 10, 30));
    });

    test('reparada el 31 de enero → hasta el 28 de febrero', () {
      final v = ventanaNuevoControl(n, DateTime(2026, 1, 31, 18));
      expect(v.desde, DateTime(2026, 2, 1, 18));
      expect(v.hasta, DateTime(2026, 2, 28, 18));
    });

    test('obligatorio si está sujeto; a revisar si es HFO; no exigido si no '
        'está sujeto', () {
      final at = DateTime(2026, 5, 1);
      expect(
        nuevoControlTrasReparacion(
          n,
          sujecion: evaluar(gas('R-410A'), 12),
          reparadaAt: at,
        ),
        isA<NuevoControlObligatorio>(),
      );
      expect(
        nuevoControlTrasReparacion(
          n,
          sujecion: evaluar(gas('R-1234yf'), 12),
          reparadaAt: at,
        ),
        isA<NuevoControlARevisar>(),
      );
      expect(
        nuevoControlTrasReparacion(
          n,
          sujecion: evaluar(gas('R-32'), 1.1),
          reparadaAt: at,
        ),
        isA<NuevoControlNoExigido>(),
      );
    });
  });

  group('Validación de una carga (arts. 13.3, 13.4 y 13.5)', () {
    ValidacionCarga validar(
      String codigo, {
      CategoriaFgas cat = CategoriaFgas.aireAcondicionadoBombaCalor,
      OrigenGas origen = OrigenGas.virgen,
      DateTime? fecha,
      DatosOrigenGas datos = const DatosOrigenGas(),
      TipoMovimientoGas tipo = TipoMovimientoGas.carga,
    }) => validarCargaGas(
      n,
      tipo: tipo,
      refrigerante: gas(codigo),
      categoria: cat,
      origen: origen,
      fecha: fecha ?? DateTime(2026, 11, 8, 12),
      datos: datos,
    );

    test('R-404A virgen en aire acondicionado → bloqueado (art. 13.4)', () {
      final v = validar('R-404A');
      expect(v, isA<CargaBloqueada>());
      final b = v as CargaBloqueada;
      expect(b.articulo, contains('13.4'));
      expect(b.motivo, contains('virgen'));
      expect(b.faltan, isEmpty); // el virgen no se justifica con datos
      expect(b.regla, ReglaAplicada.art134);
    });

    test(
      'R-404A regenerado: bloqueado hasta tener lote y foto (art. 12.7)',
      () {
        final sinNada = validar('R-404A', origen: OrigenGas.regenerado);
        expect((sinNada as CargaBloqueada).faltan, [
          DatoOrigen.regeneradoLote,
          DatoOrigen.regeneradoEtiquetaFotoId,
        ]);

        final sinFoto = validar(
          'R-404A',
          origen: OrigenGas.regenerado,
          datos: const DatosOrigenGas(regeneradoLote: 'L-2026-001'),
        );
        expect((sinFoto as CargaBloqueada).faltan, [
          DatoOrigen.regeneradoEtiquetaFotoId,
        ]);

        final sinLote = validar(
          'R-404A',
          origen: OrigenGas.regenerado,
          datos: const DatosOrigenGas(
            regeneradoLote: '  ',
            regeneradoEtiquetaFotoId: 'foto-1',
          ),
        );
        expect((sinLote as CargaBloqueada).faltan, [DatoOrigen.regeneradoLote]);

        final ok = validar(
          'R-404A',
          origen: OrigenGas.regenerado,
          datos: const DatosOrigenGas(
            regeneradoLote: 'L-2026-001',
            regeneradoEtiquetaFotoId: 'foto-1',
          ),
        );
        expect(ok, isA<CargaPermitida>());
        expect(ok.regla, ReglaAplicada.art134);
      },
    );

    test('R-404A reciclado: pide quién lo recuperó y la declaración', () {
      final sinDatos = validar('R-404A', origen: OrigenGas.reciclado);
      expect((sinDatos as CargaBloqueada).faltan, [
        DatoOrigen.recicladoRecuperadoPor,
        DatoOrigen.recicladoDeclaracion,
      ]);

      final sinDeclaracion = validar(
        'R-404A',
        origen: OrigenGas.reciclado,
        datos: const DatosOrigenGas(
          recicladoRecuperadoPor: RecuperadoPor.propiaEmpresa,
        ),
      );
      expect(sinDeclaracion, isA<CargaBloqueada>());

      final ok = validar(
        'R-404A',
        origen: OrigenGas.reciclado,
        datos: const DatosOrigenGas(
          recicladoRecuperadoPor: RecuperadoPor.paraEstaEmpresa,
          recicladoDeclaracion: true,
        ),
      );
      expect(ok, isA<CargaPermitida>());
      expect(ok.regla, ReglaAplicada.art134);
    });

    test('los datos de un origen no desbloquean otro', () {
      final v = validar(
        'R-404A',
        origen: OrigenGas.reciclado,
        datos: const DatosOrigenGas(
          regeneradoLote: 'L-1',
          regeneradoEtiquetaFotoId: 'foto-1',
        ),
      );
      expect(v, isA<CargaBloqueada>());
    });

    test('13.4 antes del 1/1/2026 no bloquea; el 1/1/2026 a las 00:30 sí', () {
      expect(
        validar('R-404A', fecha: DateTime(2025, 12, 31, 23, 59)),
        isA<CargaPermitida>(),
      );
      expect(
        validar('R-404A', fecha: DateTime(2026, 1, 1, 0, 30)),
        isA<CargaBloqueada>(),
      );
    });

    test('desde el 1/1/2032 tampoco regenerado ni reciclado', () {
      final v = validar(
        'R-404A',
        origen: OrigenGas.regenerado,
        fecha: DateTime(2032, 1, 1),
        datos: const DatosOrigenGas(
          regeneradoLote: 'L-1',
          regeneradoEtiquetaFotoId: 'foto-1',
        ),
      );
      expect(v, isA<CargaBloqueada>());
      expect((v as CargaBloqueada).faltan, isEmpty);
    });

    test('PCG < 2.500 no bloquea (R-410A, R-407C, R-32 vírgenes)', () {
      for (final c in ['R-410A', 'R-407C', 'R-32', 'R-134a', 'R-448A']) {
        expect(validar(c), isA<CargaPermitida>(), reason: c);
      }
    });

    test('R-422D (PCG 2.729) y R-507A (3.985) vírgenes sí se bloquean', () {
      expect(validar('R-422D'), isA<CargaBloqueada>());
      expect(validar('R-507A'), isA<CargaBloqueada>());
    });

    test('refrigeración → aviso del 13.3 sin bloqueo', () {
      final v = validar('R-404A', cat: CategoriaFgas.refrigeracion);
      expect(v, isA<CargaConAviso>());
      expect((v as CargaConAviso).articulo, contains('13.3'));
      expect(v.regla, ReglaAplicada.art133Aviso);
    });

    test('refrigeración desde 2032 con PCG ≥ 750 → aviso del 13.5', () {
      final v = validar(
        'R-134a',
        cat: CategoriaFgas.refrigeracion,
        fecha: DateTime(2032, 3, 1),
      );
      expect((v as CargaConAviso).articulo, contains('13.5'));
      expect(v.regla, ReglaAplicada.ninguna);
    });

    test('categoría «otro» con PCG alto → aviso para que se elija', () {
      expect(validar('R-404A', cat: CategoriaFgas.otro), isA<CargaConAviso>());
    });

    test('recuperar o desmantelar nunca se bloquea', () {
      for (final t in [
        TipoMovimientoGas.recuperacion,
        TipoMovimientoGas.desmantelamiento,
      ]) {
        expect(validar('R-404A', tipo: t), isA<CargaPermitida>());
      }
    });

    test('gas del anexo II → permitido', () {
      expect(validar('R-1234yf'), isA<CargaPermitida>());
    });
  });

  group('Hermético etiquetado con mezcla HFC/HFO (art. 5.1, párrafo '
      'segundo: basta «una de las condiciones»)', () {
    // R-454B: 68,9 % R-32 y 31,1 % R-1234yf; PCG 465,23.
    for (final kg in [10.0, 12.0, 20.0]) {
      test('R-454B $kg kg hermético: < 10 t (letra a) → no sujeto aunque '
          'lleve ≥ 2 kg de HFO', () {
        final r = evaluar(gas('R-454B'), kg, hermetico: true);
        expect(r, isA<NoSujetoControlFugas>());
        final ns = r as NoSujetoControlFugas;
        expect(ns.motivo, MotivoNoSujeto.hermeticoEtiquetado);
        expect(ns.tCo2eq, lessThan(10));
        expect(ns.explicacion, contains('letra a'));
        expect(kgAnexoIISeccion1(gas('R-454B'), kg), greaterThanOrEqualTo(2));
        // Sin la etiqueta de hermético, en cambio, sí está sujeto.
        expect(evaluar(gas('R-454B'), kg), isA<SujetoControlFugas>());
      });
    }

    test(
      'R-454B 22 kg hermético: 10,24 t ≥ 10 t y 6,84 kg de HFO → sujeto',
      () {
        final r =
            evaluar(gas('R-454B'), 22, hermetico: true) as SujetoControlFugas;
        expect(r.tCo2eq, greaterThanOrEqualTo(10));
        expect(r.periodicidadMeses, 12);
      },
    );

    test('R-448A 7,3 kg hermético: 10,12 t pero 1,97 kg de HFO (solo la '
        'letra b) → sigue sujeto por t CO2-eq [A VERIFICAR]', () {
      final r =
          evaluar(gas('R-448A'), 7.3, hermetico: true) as SujetoControlFugas;
      expect(r.tCo2eq, closeTo(10.117772, 1e-6));
      expect(r.kgAnexoII, closeTo(1.971, 1e-6));
      expect(r.criterio, CriterioControlFugas.tCo2eq);
      expect(r.periodicidadMeses, 12);
    });

    test('R-454B 4 kg hermético: < 5 t y < 2 kg de HFO → no sujeto', () {
      final r = evaluar(gas('R-454B'), 4, hermetico: true);
      expect(r, isA<NoSujetoControlFugas>());
    });
  });

  // El repo guarda los instantes en UTC (lib/data/local/tablas/comunes.dart).
  // Las pruebas construyen el instante en hora local y lo pasan a UTC, así no
  // dependen de la zona del equipo; en una zona UTC+1/+2 (España) sí ejercen
  // el cambio de día.
  group('Instantes en UTC (convención del repo)', () {
    ValidacionCarga validarEn(
      DateTime fecha, {
      OrigenGas origen = OrigenGas.virgen,
      DatosOrigenGas datos = const DatosOrigenGas(),
    }) => validarCargaGas(
      n,
      tipo: TipoMovimientoGas.carga,
      refrigerante: gas('R-404A'),
      categoria: CategoriaFgas.aireAcondicionadoBombaCalor,
      origen: origen,
      fecha: fecha,
      datos: datos,
    );

    test('13.4: el 1/1/2026 a las 00:30 locales en UTC ya bloquea; el '
        '31/12/2025 a las 23:59 locales en UTC no', () {
      expect(
        validarEn(DateTime(2026, 1, 1, 0, 30).toUtc()),
        isA<CargaBloqueada>(),
      );
      expect(
        validarEn(DateTime(2025, 12, 31, 23, 59).toUtc()),
        isA<CargaPermitida>(),
      );
    });

    test('desde el 1/1/2032 a las 00:30 locales en UTC, regenerado con lote '
        'y foto también bloqueado', () {
      final v = validarEn(
        DateTime(2032, 1, 1, 0, 30).toUtc(),
        origen: OrigenGas.regenerado,
        datos: const DatosOrigenGas(
          regeneradoLote: 'L-1',
          regeneradoEtiquetaFotoId: 'foto-1',
        ),
      );
      expect(v, isA<CargaBloqueada>());
      expect(
        validarEn(
          DateTime(2031, 12, 31, 23, 59).toUtc(),
          origen: OrigenGas.regenerado,
          datos: const DatosOrigenGas(
            regeneradoLote: 'L-1',
            regeneradoEtiquetaFotoId: 'foto-1',
          ),
        ),
        isA<CargaPermitida>(),
      );
    });

    test('control del 9/11/2025 a las 00:30 locales guardado en UTC: vence '
        'el 9/11/2026, no un día antes', () {
      final p = proximoControlFugas(
        evaluar(gas('R-410A'), 12),
        ultimoControlAt: DateTime(2025, 11, 9, 0, 30).toUtc(),
      ) as ProximoControlEnFecha;
      expect(p.dia, const DiaCalendario(2026, 11, 9));
      expect(p.fecha, DateTime(2026, 11, 9, 0, 30));
      expect(p.vencido(DateTime(2026, 11, 9, 10)), isFalse);
      expect(p.vencido(DateTime(2026, 11, 9, 23, 59).toUtc()), isFalse);
      expect(p.vencido(DateTime(2026, 11, 10, 0, 30).toUtc()), isTrue);
    });

    test('previo declarado como SoloFecha (medianoche UTC): se lee por '
        'componentes, sin cambiar de día', () {
      final p = proximoControlFugas(
        evaluar(gas('R-134a'), 60),
        controlPrevioDeclarado: DateTime.utc(2026, 8, 31),
      ) as ProximoControlEnFecha;
      expect(p.dia, const DiaCalendario(2027, 2, 28));
      expect(p.fecha, DateTime.utc(2027, 2, 28));
      expect(p.vencido(DateTime(2027, 2, 28, 23, 59)), isFalse);
      expect(p.vencido(DateTime(2027, 3, 1, 0, 30).toUtc()), isTrue);
    });

    test('art. 4.5: reparada el 31/1 a las 00:30 locales en UTC → hasta el '
        '28/2 local', () {
      final v = ventanaNuevoControl(n, DateTime(2026, 1, 31, 0, 30).toUtc());
      expect(v.hasta, DateTime(2026, 2, 28, 0, 30));
      expect(v.desde, DateTime(2026, 2, 1, 0, 30));
    });
  });
}
