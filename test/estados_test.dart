import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/dominio/estados.dart';

void main() {
  group('estadoOrdenLocal', () {
    EstadoOrden e(EstadoOrden s, List<EstadoInspeccion> i) =>
        estadoOrdenLocal(estadoServidor: s, inspecciones: i);

    test('sin inspecciones manda el servidor', () {
      expect(e(EstadoOrden.pendiente, []), EstadoOrden.pendiente);
      expect(e(EstadoOrden.enCurso, []), EstadoOrden.enCurso);
    });
    test('empezar la visita la pone en curso sin esperar al servidor', () {
      expect(
        e(EstadoOrden.pendiente, [EstadoInspeccion.enCurso]),
        EstadoOrden.enCurso,
      );
      expect(
        e(EstadoOrden.pendiente, [EstadoInspeccion.lista]),
        EstadoOrden.enCurso,
      );
    });
    test('firmada en local → firmada aunque no haya subido', () {
      expect(
        e(EstadoOrden.enCurso, [EstadoInspeccion.firmada]),
        EstadoOrden.firmada,
      );
    });
    test('cancelada por la oficina gana a todo', () {
      expect(
        e(EstadoOrden.cancelada, [EstadoInspeccion.enCurso]),
        EstadoOrden.cancelada,
      );
    });
    test('solo descartadas → vuelve a pendiente', () {
      expect(
        e(EstadoOrden.enCurso, [EstadoInspeccion.descartada]),
        EstadoOrden.pendiente,
      );
    });
    test('lo firmado en el servidor no vuelve atrás', () {
      expect(
        e(EstadoOrden.firmada, [EstadoInspeccion.descartada]),
        EstadoOrden.firmada,
      );
    });
    test('descartada y otra en curso → en curso', () {
      expect(
        e(EstadoOrden.pendiente, [
          EstadoInspeccion.descartada,
          EstadoInspeccion.enCurso,
        ]),
        EstadoOrden.enCurso,
      );
    });
  });

  group('aplicarFirma (estado_equipo en local)', () {
    final t1 = DateTime.utc(2025, 1, 10, 10);
    final t2 = DateTime.utc(2026, 1, 10, 10);
    final viejo = DateTime.utc(2023, 6, 1);

    test('primera firma de un preventivo', () {
      final h = aplicarFirma(
        HechosEquipo.vacio,
        FirmaDeEquipo(
          inspeccionId: 'i1',
          firmadaAt: t1,
          esPreventivo: true,
          valores: const [
            ValorMedido(clave: 'temp_retorno', valor: 24, unidad: '°C'),
          ],
          incidenciasNuevas: const [
            IncidenciaNueva(
              id: 'inc1',
              descripcion: 'Aislamiento',
              gravedad: 'leve',
            ),
          ],
        ),
      );
      expect(h.ultimoPreventivoAt, t1);
      expect(h.ultimaInspeccionId, 'i1');
      expect(h.ultimosValores['temp_retorno']!.valor, 24);
      expect(h.ultimosValores['temp_retorno']!.fecha, t1);
      expect(h.incidenciasAbiertas.single.id, 'inc1');
      expect(h.ultimoControlFugasAt, isNull);
    });

    test('conserva la historia larga que no está en local', () {
      // Lo que bajó del servidor: un preventivo de hace años y una
      // incidencia de una visita fuera de la ventana de 60 días.
      final servidor = HechosEquipo(
        ultimoPreventivoAt: viejo,
        ultimaInspeccionId: 'antigua',
        ultimosValores: {
          'presion_alta': UltimoValor(
            valor: 20,
            unidad: 'bar (man.)',
            fecha: viejo,
          ),
        },
        incidenciasAbiertas: [
          IncidenciaAbierta(
            id: 'vieja',
            descripcion: 'x',
            gravedad: 'grave',
            fecha: viejo,
          ),
        ],
      );
      final h = aplicarFirma(
        servidor,
        FirmaDeEquipo(
          inspeccionId: 'i2',
          firmadaAt: t2,
          esPreventivo: false,
          resultadoFugas: 'sin_fuga',
          valores: const [ValorMedido(clave: 'presion_baja', valor: 8)],
        ),
      );
      expect(
        h.ultimoPreventivoAt,
        viejo,
        reason: 'un control no es preventivo',
      );
      expect(h.ultimoControlFugasAt, t2);
      expect(h.ultimoResultadoFugas, 'sin_fuga');
      expect(
        h.ultimosValores.keys,
        containsAll(['presion_alta', 'presion_baja']),
      );
      expect(h.incidenciasAbiertas.single.id, 'vieja');
      expect(h.ultimaInspeccionId, 'i2');
    });

    test('«Resuelta en esta visita» cierra la incidencia y la nueva entra', () {
      final antes = HechosEquipo(
        incidenciasAbiertas: [
          IncidenciaAbierta(
            id: 'a',
            descripcion: 'A',
            gravedad: 'leve',
            fecha: t1,
          ),
          IncidenciaAbierta(
            id: 'b',
            descripcion: 'B',
            gravedad: 'grave',
            fecha: t1,
          ),
        ],
      );
      final h = aplicarFirma(
        antes,
        FirmaDeEquipo(
          inspeccionId: 'i2',
          firmadaAt: t2,
          esPreventivo: true,
          incidenciasResueltas: const {'a'},
          incidenciasNuevas: const [
            IncidenciaNueva(id: 'c', descripcion: 'C', gravedad: 'muy_grave'),
          ],
        ),
      );
      expect([for (final i in h.incidenciasAbiertas) i.id], ['b', 'c']);
    });

    test('un valor más antiguo no pisa uno más reciente', () {
      final antes = HechosEquipo(
        ultimoPreventivoAt: t2,
        ultimosValores: {'x': UltimoValor(valor: 2, fecha: t2)},
      );
      final h = aplicarFirma(
        antes,
        FirmaDeEquipo(
          inspeccionId: 'vieja',
          firmadaAt: t1,
          esPreventivo: true,
          valores: const [ValorMedido(clave: 'x', valor: 1)],
        ),
      );
      expect(h.ultimosValores['x']!.valor, 2);
      expect(h.ultimoPreventivoAt, t2);
    });

    test('ida y vuelta por las columnas jsonb', () {
      final h = HechosEquipo(
        ultimosValores: {'b': UltimoValor(valor: 1.5, unidad: 'A', fecha: t1)},
        incidenciasAbiertas: [
          IncidenciaAbierta(
            id: 'i',
            descripcion: 'd',
            gravedad: null,
            fecha: t2,
          ),
        ],
      );
      final vuelta = HechosEquipo.desdeColumnas(
        ultimosValoresJson: h.ultimosValoresJson,
        incidenciasAbiertasJson: h.incidenciasAbiertasJson,
      );
      expect(vuelta.ultimosValores['b']!.valor, 1.5);
      expect(vuelta.ultimosValores['b']!.unidad, 'A');
      expect(vuelta.ultimosValores['b']!.fecha, t1);
      expect(vuelta.incidenciasAbiertas.single.fecha, t2);
      expect(vuelta.incidenciasAbiertas.single.gravedad, isNull);
    });

    test('un jsonb mal formado falla en vez de inventar «sin incidencias»', () {
      expect(
        () => HechosEquipo.desdeColumnas(
          ultimosValoresJson: '{}',
          incidenciasAbiertasJson: '{"no":"es una lista"}',
        ),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
