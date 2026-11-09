import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/formato.dart' as fmt;
import '../../data/repositories/inspeccion_repository.dart';
import '../../design/pad_numerico.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../dominio/plantillas.dart' as dom;
import '../../dominio/rite.dart';
import '../../dominio/tipos.dart';
import '../textos.dart';

/// Sugerencia de plantilla para un equipo nuevo en [v] (F2.2): la misma
/// regla que O2, con la potencia de la instalación contando ya el equipo.
dom.SugerenciaPlantillas sugerirParaEquipoNuevo({
  required VistaVisita v,
  required double umbralKw,
  required List<dom.Plantilla> plantillas,
  required TipoEquipo tipo,
  double? frioKw,
  double? calorKw,
}) {
  final pot = potenciaInstalacion(
    declaradaFrioKw: v.instalacion.potenciaFrioKw,
    declaradaCalorKw: v.instalacion.potenciaCalorKw,
    equipos: [
      for (final e in v.equiposInstalacion)
        PotenciaEquipo(frioKw: e.potenciaFrioKw, calorKw: e.potenciaCalorKw),
      PotenciaEquipo(frioKw: frioKw, calorKw: calorKw),
    ],
  );
  final mayor = frioKw == null && calorKw == null
      ? null
      : math.max(frioKw ?? 0, calorKw ?? 0);
  return dom.sugerirPlantillas(
    umbralRegimenMensualKw: umbralKw,
    tipo: tipo,
    potenciaEquipoKw: mayor,
    potenciaInstalacionKw: pot.kw,
    uso: v.instalacion.usoEdificio,
    intervencion: v.tipo,
    plantillas: plantillas,
  );
}

/// **Añadir equipo** (F2.2): tipo y potencia con botones y teclado propio, y
/// la plantilla sugerida para confirmar. Devuelve el id del equipo creado.
class AnadirEquipoPantalla extends ConsumerStatefulWidget {
  const AnadirEquipoPantalla({super.key, required this.visita});
  final VistaVisita visita;

  @override
  ConsumerState<AnadirEquipoPantalla> createState() =>
      _AnadirEquipoPantallaState();
}

class _AnadirEquipoPantallaState extends ConsumerState<AnadirEquipoPantalla> {
  TipoEquipo? _tipo;
  double? _frio;
  double? _calor;
  String? _plantillaId;
  bool _guardando = false;

  Future<void> _potencia(bool frio) async {
    final r = await pedirNumero(
      context,
      titulo: frio ? 'Potencia de frío' : 'Potencia de calor',
      unidad: 'kW',
      inicial: frio ? _frio : _calor,
    );
    if (r == null) return;
    setState(() {
      final v = r is NumeroElegido ? r.valor : null;
      frio ? _frio = v : _calor = v;
      _plantillaId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final normativa = ref.watch(normativaProvider).value;
    final plantillas = ref.watch(plantillasBaseProvider).value;
    final sugerencia = _tipo == null || normativa == null || plantillas == null
        ? null
        : sugerirParaEquipoNuevo(
            v: widget.visita,
            umbralKw: normativa.rite.umbralRegimenMensualKw,
            plantillas: plantillas,
            tipo: _tipo!,
            frioKw: _frio,
            calorKw: _calor,
          );
    final elegida = _plantillaId ?? sugerencia?.recomendada?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Añadir equipo')),
      body: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          const Seccion('Tipo'),
          Opciones<TipoEquipo>(
            opciones: [
              for (final t in TipoEquipo.values) Opcion(t, textoTipoEquipo(t)),
            ],
            seleccionada: _tipo,
            onChanged: (t) => setState(() {
              _tipo = t;
              _plantillaId = null;
            }),
          ),
          const Seccion('Potencia (de la placa)'),
          Row(
            children: [
              Expanded(
                child: BotonSecundario(
                  key: const Key('potencia_frio'),
                  texto: 'Frío: ${fmt.kw(_frio)}',
                  icono: Icons.ac_unit,
                  onPressed: () => _potencia(true),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: BotonSecundario(
                  key: const Key('potencia_calor'),
                  texto: 'Calor: ${fmt.kw(_calor)}',
                  icono: Icons.local_fire_department_outlined,
                  onPressed: () => _potencia(false),
                ),
              ),
            ],
          ),
          if (sugerencia != null) ...[
            const Seccion('Plantilla'),
            for (final a in sugerencia.avisos)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Aviso(a.texto),
              ),
            if (sugerencia.plantillas.isNotEmpty)
              Opciones<String>(
                opciones: [
                  for (final (i, p) in sugerencia.plantillas.indexed)
                    Opcion(p.id, i == 0 ? '${p.titulo} (sugerida)' : p.titulo),
                ],
                seleccionada: elegida,
                onChanged: (id) => setState(() => _plantillaId = id),
              ),
          ],
          const SizedBox(height: Gap.xl),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: BotonPrimario(
            key: const Key('confirmar_equipo'),
            texto: 'Añadir a la visita',
            icono: Icons.check,
            onPressed: _tipo == null || elegida == null || _guardando
                ? null
                : () async {
                    setState(() => _guardando = true);
                    final id = await ref
                        .read(inspeccionRepositoryProvider)!
                        .anadirEquipo(
                          inspeccionId: widget.visita.inspeccion!.id,
                          tipo: _tipo!,
                          plantillaId: elegida,
                          potenciaFrioKw: _frio,
                          potenciaCalorKw: _calor,
                        );
                    if (context.mounted) Navigator.of(context).pop(id);
                  },
            motivoInactivo: _tipo == null
                ? 'Elige el tipo de equipo.'
                : 'No hay plantilla para este equipo en esta orden.',
          ),
        ),
      ),
    );
  }
}
