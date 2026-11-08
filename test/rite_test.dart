// Pruebas de tabla de rite.dart (DISEÑO.md §12, día 2) con la normativa real.
// Tabla 3.1 de la IT 3.3 del RITE (RD 1027/2007, texto consolidado del BOE):
// aire acondicionado Pn ≤ 12 kW: 4 años / 2 años; 12 kW < Pn ≤ 70 kW: 2 años /
// anual; instalaciones de más de 70 kW: mensual (fuera del MVP).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/dominio/normativa.dart';
import 'package:inspecta/dominio/rite.dart';
import 'package:inspecta/dominio/tipos.dart';

late final Normativa n;

RegimenRite regimen({
  required PotenciaInstalacion instalacion,
  TipoEquipo tipo = TipoEquipo.split,
  PotenciaEquipo equipo = const PotenciaEquipo(frioKw: 3.5),
  UsoEdificio uso = UsoEdificio.otros,
  bool supervision = false,
}) => regimenRite(
  n,
  instalacion: instalacion,
  tipo: tipo,
  equipo: equipo,
  uso: uso,
  supervisionRemota: supervision,
);

/// Instalación cuya potencia es la de un único equipo.
PotenciaInstalacion soloEquipo(PotenciaEquipo e) =>
    potenciaInstalacion(equipos: [e]);

void main() {
  setUpAll(() {
    n = parsearNormativa(
      File('assets/normativa/2026-11.json').readAsStringSync(),
    );
  });

  group('Potencia de la instalación (art. 26.6, §7.2)', () {
    test('10 splits de 10 kW en un hotel → 100 kW → régimen de más de 70 kW '
        '(no «2 años»)', () {
      final splits = List.filled(
        10,
        const PotenciaEquipo(frioKw: 10, calorKw: 10),
      );
      final inst = potenciaInstalacion(equipos: splits);
      expect(inst.kw, 100);
      final r = regimen(
        instalacion: inst,
        equipo: const PotenciaEquipo(frioKw: 10, calorKw: 10),
      );
      expect(r, isA<RegimenMensualFueraMvp>());
      expect((r as RegimenMensualFueraMvp).meses, 1);
      expect(r.mensaje, contains('fuera del MVP'));
      final p = proximaRevisionRite(
        r,
        ultimoPreventivoAt: DateTime(2026, 6, 1),
      );
      expect(p, isA<ProximaRevisionFueraMvp>());
    });

    test('mismo hotel con 70 kW declarados: manda la suma y avisa «régimen '
        'RITE a revisar»', () {
      final inst = potenciaInstalacion(
        declaradaFrioKw: 70,
        declaradaCalorKw: 70,
        equipos: List.filled(10, const PotenciaEquipo(frioKw: 10, calorKw: 10)),
      );
      expect(inst.kw, 100);
      expect(inst.sumaSuperaDeclarada, isTrue);
      expect(inst.avisos.first, contains('régimen RITE a revisar'));
      expect(regimen(instalacion: inst), isA<RegimenMensualFueraMvp>());
    });

    test(
      '60 kW de frío y 75 kW de calor → 75 kW → más de 70 kW (la mayor)',
      () {
        final inst = potenciaInstalacion(
          declaradaFrioKw: 60,
          declaradaCalorKw: 75,
          equipos: const [PotenciaEquipo(frioKw: 60, calorKw: 75)],
        );
        expect(inst.frioKw, 60);
        expect(inst.calorKw, 75);
        expect(inst.kw, 75);
        expect(regimen(instalacion: inst), isA<RegimenMensualFueraMvp>());
      },
    );

    test('lo declarado manda si es mayor que la suma (sin aviso)', () {
      final inst = potenciaInstalacion(
        declaradaFrioKw: 65,
        equipos: const [PotenciaEquipo(frioKw: 20)],
      );
      expect(inst.kw, 65);
      expect(inst.sumaSuperaDeclarada, isFalse);
      expect(inst.avisos, isEmpty);
    });

    test('sin potencia declarada ni de algún equipo: avisa', () {
      final inst = potenciaInstalacion(
        equipos: const [PotenciaEquipo(frioKw: 5), PotenciaEquipo()],
      );
      expect(inst.kw, 5);
      expect(inst.avisos.length, 2);
    });

    test('70 kW exactos siguen en la Tabla 3.1 (el borde es «mayor que»); '
        '70,001 kW ya es mensual', () {
      final a = potenciaInstalacion(declaradaFrioKw: 70, equipos: const []);
      expect(
        regimen(instalacion: a, equipo: const PotenciaEquipo(frioKw: 70)),
        isA<RegimenTabla31>(),
      );
      final b = potenciaInstalacion(declaradaFrioKw: 70.001, equipos: const []);
      expect(regimen(instalacion: b), isA<RegimenMensualFueraMvp>());
    });

    test('potencia negativa: error', () {
      expect(
        () => potenciaInstalacion(equipos: const [PotenciaEquipo(frioKw: -1)]),
        throwsArgumentError,
      );
    });
  });

  group('Tabla 3.1, aire acondicionado (≤ 70 kW)', () {
    // (Pn del equipo, uso, meses)
    final casos = <(double, UsoEdificio, int)>[
      (3.5, UsoEdificio.vivienda, 48),
      (3.5, UsoEdificio.otros, 24),
      (12, UsoEdificio.vivienda, 48), // «Pn ≤ 12 kW»: 12 incluido
      (12, UsoEdificio.otros, 24),
      (12.001, UsoEdificio.vivienda, 24), // «12 kW < Pn ≤ 70 kW»
      (12.001, UsoEdificio.otros, 12),
      (70, UsoEdificio.vivienda, 24),
      (70, UsoEdificio.otros, 12),
    ];
    for (final (pn, uso, meses) in casos) {
      test('split de $pn kW, ${uso.wire} → $meses meses', () {
        final e = PotenciaEquipo(frioKw: pn);
        final r = regimen(instalacion: soloEquipo(e), equipo: e, uso: uso);
        expect((r as RegimenTabla31).meses, meses);
        expect(r.fila.familia, 'aire_acondicionado');
      });
    }

    test('la fila se elige con la mayor de frío y calor del equipo', () {
      const e = PotenciaEquipo(frioKw: 11, calorKw: 13);
      final r =
          regimen(instalacion: soloEquipo(e), equipo: e) as RegimenTabla31;
      expect(r.pnEquipoKw, 13);
      expect(r.meses, 12);
    });

    test('equipo sin potencia: usa la de la instalación (cota superior)', () {
      final inst = potenciaInstalacion(declaradaFrioKw: 20, equipos: const []);
      final r = regimen(
        instalacion: inst,
        equipo: const PotenciaEquipo(),
        uso: UsoEdificio.vivienda,
      ) as RegimenTabla31;
      expect(r.pnEstimada, isTrue);
      expect(r.pnEquipoKw, 20);
      expect(r.meses, 24);
    });

    test('todos los tipos del MVP encuentran fila', () {
      const e = PotenciaEquipo(frioKw: 7);
      for (final t in TipoEquipo.values) {
        expect(
          regimen(instalacion: soloEquipo(e), tipo: t, equipo: e),
          isA<RegimenTabla31>(),
          reason: t.wire,
        );
      }
    });
  });

  group('Supervisión remota en continuo (IT 3.3: hasta 2 años, ≤ 70 kW)', () {
    test('otros usos, 20 kW: anual, ampliable a 24 meses (dato marcado)', () {
      const e = PotenciaEquipo(frioKw: 20);
      final r = regimen(
        instalacion: soloEquipo(e),
        equipo: e,
        supervision: true,
      ) as RegimenTabla31;
      expect(r.meses, 12);
      expect(r.mesesMaxConSupervisionRemota, 24);

      final ref = DateTime(2026, 3, 31);
      final normal = proximaRevisionRite(
        r,
        ultimoPreventivoAt: ref,
      ) as ProximaRevisionEnFecha;
      expect(normal.fecha, DateTime(2027, 3, 31));
      expect(normal.ampliadaPorSupervisionRemota, isFalse);

      final ampliada = proximaRevisionRite(
        r,
        ultimoPreventivoAt: ref,
        aplicarSupervisionRemota: true,
      ) as ProximaRevisionEnFecha;
      expect(ampliada.fecha, DateTime(2028, 3, 31));
      expect(ampliada.ampliadaPorSupervisionRemota, isTrue);
    });

    test('si la tabla ya da 2 años o más, no amplía nada', () {
      const e = PotenciaEquipo(frioKw: 3.5);
      final r = regimen(
        instalacion: soloEquipo(e),
        equipo: e,
        uso: UsoEdificio.vivienda,
        supervision: true,
      ) as RegimenTabla31;
      expect(r.meses, 48);
      expect(r.mesesMaxConSupervisionRemota, isNull);
    });

    test('sin supervisión: null', () {
      const e = PotenciaEquipo(frioKw: 20);
      final r =
          regimen(instalacion: soloEquipo(e), equipo: e) as RegimenTabla31;
      expect(r.mesesMaxConSupervisionRemota, isNull);
    });
  });

  group('Próxima revisión RITE', () {
    RegimenTabla31 anual() {
      const e = PotenciaEquipo(frioKw: 20);
      return regimen(instalacion: soloEquipo(e), equipo: e) as RegimenTabla31;
    }

    test('desde ultimo_preventivo_at, aunque haya previo declarado', () {
      final p = proximaRevisionRite(
        anual(),
        ultimoPreventivoAt: DateTime(2026, 5, 20, 9),
        preventivoPrevioDeclarado: DateTime(2025, 1, 1),
      ) as ProximaRevisionEnFecha;
      expect(p.fecha, DateTime(2027, 5, 20, 9));
      expect(p.origen, OrigenReferencia.ultimoEnInspecta);
    });

    test('sin preventivo en Inspecta: desde el previo declarado', () {
      final p = proximaRevisionRite(
        anual(),
        preventivoPrevioDeclarado: DateTime(2024, 2, 29),
      ) as ProximaRevisionEnFecha;
      expect(p.fecha, DateTime(2025, 2, 28)); // 29/2 + 12 meses
      expect(p.origen, OrigenReferencia.previoDeclarado);
    });

    test('vencida al día siguiente de la fecha', () {
      final p = proximaRevisionRite(
        anual(),
        ultimoPreventivoAt: DateTime(2025, 11, 8),
      ) as ProximaRevisionEnFecha;
      expect(p.vencida(DateTime(2026, 11, 8, 20)), isFalse);
      expect(p.vencida(DateTime(2026, 11, 9)), isTrue);
    });

    test('sin ninguna referencia', () {
      final p = proximaRevisionRite(anual());
      expect(p, isA<ProximaRevisionSinReferencia>());
      expect((p as ProximaRevisionSinReferencia).meses, 12);
    });

    // El repo guarda los instantes en UTC; el previo declarado es SoloFecha.
    test('último preventivo del 9/11/2025 a las 00:30 locales en UTC: vence '
        'el 9/11/2026', () {
      final p = proximaRevisionRite(
        anual(),
        ultimoPreventivoAt: DateTime(2025, 11, 9, 0, 30).toUtc(),
      ) as ProximaRevisionEnFecha;
      expect(p.dia, const DiaCalendario(2026, 11, 9));
      expect(p.vencida(DateTime(2026, 11, 9, 10)), isFalse);
      expect(p.vencida(DateTime(2026, 11, 9, 10).toUtc()), isFalse);
      expect(p.vencida(DateTime(2026, 11, 10, 0, 30).toUtc()), isTrue);
    });

    test('previo declarado en medianoche UTC: 29/2/2024 + 12 meses = '
        '28/2/2025', () {
      final p = proximaRevisionRite(
        anual(),
        preventivoPrevioDeclarado: DateTime.utc(2024, 2, 29),
      ) as ProximaRevisionEnFecha;
      expect(p.dia, const DiaCalendario(2025, 2, 28));
      expect(p.fecha, DateTime.utc(2025, 2, 28));
    });
  });

  group(
    'Potencia desconocida: resultado explícito, nunca la fila más laxa',
    () {
      test('equipo sin potencia en una instalación sin potencia → desconocida, '
          'sin fecha', () {
        final inst = potenciaInstalacion(equipos: const [PotenciaEquipo()]);
        expect(inst.kw, 0);
        expect(inst.conocida, isFalse);
        final r = regimen(
          instalacion: inst,
          equipo: const PotenciaEquipo(),
          uso: UsoEdificio.vivienda,
        );
        expect(r, isA<RegimenPotenciaDesconocida>());
        final p = proximaRevisionRite(
          r,
          ultimoPreventivoAt: DateTime(2026, 1, 10),
        );
        expect(p, isA<ProximaRevisionPotenciaDesconocida>());
        expect(
          (p as ProximaRevisionPotenciaDesconocida).mensaje,
          contains('70 kW'),
        );
      });

      test('1 equipo de 5 kW y 9 enfriadoras sin potencia, sin declarada → '
          'desconocida (podría pasar de 70 kW)', () {
        final inst = potenciaInstalacion(
          equipos: [
            const PotenciaEquipo(frioKw: 5),
            ...List.filled(9, const PotenciaEquipo()),
          ],
        );
        expect(inst.kw, 5);
        final r = regimen(
          instalacion: inst,
          equipo: const PotenciaEquipo(frioKw: 5),
        );
        expect(r, isA<RegimenPotenciaDesconocida>());
        expect((r as RegimenPotenciaDesconocida).potenciaMinimaKw, 5);
      });

      test('sin equipos ni declarada → desconocida', () {
        final r = regimen(instalacion: potenciaInstalacion(equipos: const []));
        expect(r, isA<RegimenPotenciaDesconocida>());
      });

      test(
        'si lo conocido ya pasa de 70 kW, mensual aunque falten potencias',
        () {
          final inst = potenciaInstalacion(
            equipos: const [PotenciaEquipo(frioKw: 75), PotenciaEquipo()],
          );
          expect(regimen(instalacion: inst), isA<RegimenMensualFueraMvp>());
        },
      );

      test('equipo sin potencia, resto con potencia y sin declarada → '
          'desconocida (la suma de los demás no lo acota)', () {
        final inst = potenciaInstalacion(
          equipos: const [PotenciaEquipo(frioKw: 5)],
        );
        expect(inst.conocida, isTrue);
        expect(
          regimen(instalacion: inst, equipo: const PotenciaEquipo()),
          isA<RegimenPotenciaDesconocida>(),
        );
      });

      test('con potencia declarada sí se calcula, aunque falten equipos', () {
        final inst = potenciaInstalacion(
          declaradaFrioKw: 30,
          equipos: const [PotenciaEquipo(frioKw: 5), PotenciaEquipo()],
        );
        expect(inst.conocida, isTrue);
        final r = regimen(
          instalacion: inst,
          equipo: const PotenciaEquipo(),
        ) as RegimenTabla31;
        expect(r.pnEstimada, isTrue);
        expect(r.pnEquipoKw, 30);
        expect(r.meses, 12); // fila 12-70 kW, otros usos
      });
    },
  );

  group('Equipo con más potencia que la instalación', () {
    test('equipo de 80 kW no incluido en una instalación de 60 kW → mensual, '
        'sin StateError', () {
      final inst = potenciaInstalacion(declaradaFrioKw: 60, equipos: const []);
      final r = regimen(
        instalacion: inst,
        tipo: TipoEquipo.enfriadora,
        equipo: const PotenciaEquipo(frioKw: 80),
      );
      expect(r, isA<RegimenMensualFueraMvp>());
      final m = r as RegimenMensualFueraMvp;
      expect(m.potenciaInstalacionKw, 80);
      expect(m.avisos.last, contains('se mide con la del equipo'));
    });

    test('equipo de 30 kW en una instalación declarada de 20 kW → se mide con '
        '30 kW', () {
      final inst = potenciaInstalacion(declaradaFrioKw: 20, equipos: const []);
      final r = regimen(
        instalacion: inst,
        equipo: const PotenciaEquipo(frioKw: 30),
      ) as RegimenTabla31;
      expect(r.potenciaInstalacionKw, 30);
      expect(r.meses, 12);
    });
  });

  group('Aviso «régimen RITE a revisar» por magnitud', () {
    test('declarada 50 frío / 80 calor, equipos 60 / 70: avisa del frío con '
        'sus propias cifras', () {
      final inst = potenciaInstalacion(
        declaradaFrioKw: 50,
        declaradaCalorKw: 80,
        equipos: const [PotenciaEquipo(frioKw: 60, calorKw: 70)],
      );
      expect(inst.sumaSuperaDeclarada, isTrue);
      final avisos = inst.avisos.where((a) => a.contains('a revisar'));
      expect(avisos, hasLength(1));
      expect(avisos.single, contains('en frío (60 kW)'));
      expect(avisos.single, contains('en frío (50 kW)'));
      expect(avisos.single, isNot(contains('70 kW')));
    });

    test('solo frío declarado (70) y calor de los equipos 80 → avisa y '
        'mensual', () {
      final inst = potenciaInstalacion(
        declaradaFrioKw: 70,
        equipos: const [PotenciaEquipo(calorKw: 80)],
      );
      expect(inst.kw, 80);
      expect(inst.sumaSuperaDeclarada, isTrue);
      expect(inst.avisos, hasLength(1));
      expect(inst.avisos.single, contains('en calor (80 kW)'));
      expect(inst.avisos.single, contains('70 kW en frío'));
      expect(inst.avisos.single, contains('régimen RITE a revisar'));
      expect(regimen(instalacion: inst), isA<RegimenMensualFueraMvp>());
    });

    test('solo frío declarado (70) y calor de los equipos 50 → sin aviso', () {
      final inst = potenciaInstalacion(
        declaradaFrioKw: 70,
        equipos: const [PotenciaEquipo(calorKw: 50)],
      );
      expect(inst.sumaSuperaDeclarada, isFalse);
      expect(inst.avisos, isEmpty);
    });
  });
}
