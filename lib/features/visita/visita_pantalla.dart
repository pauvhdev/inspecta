import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/formato.dart' as fmt;
import '../../data/repositories/inspeccion_repository.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../dominio/tipos.dart';
import '../checklist/checklist_pantalla.dart';
import '../equipo/ficha_equipo_pantalla.dart';
import '../textos.dart';
import 'anadir_equipo_pantalla.dart';

/// T2 Visita (DISEÑO.md §6.1): contexto de la orden, equipos con su
/// progreso, incidencias abiertas de visitas anteriores y las acciones.
class VisitaPantalla extends ConsumerWidget {
  const VisitaPantalla({super.key, required this.ordenId});
  final String ordenId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visita = ref.watch(visitaProvider(ordenId));
    return Scaffold(
      appBar: AppBar(title: const Text('Visita'), bottom: barraSync()),
      body: visita.when(
        data: (v) => v == null
            ? const Padding(
                padding: EdgeInsets.all(Gap.xl),
                child: Text('Esta orden ya no existe en el aparato.'),
              )
            : _Contenido(v),
        loading: () => const Padding(
          padding: EdgeInsets.all(Gap.xl),
          child: Text('Abriendo la visita…'),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Text('No se pudo abrir la visita: $e'),
        ),
      ),
      bottomNavigationBar: visita.value == null
          ? null
          : _Acciones(visita.value!),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido(this.v);
  final VistaVisita v;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final inst = v.instalacion;
    final pot = v.potencia;
    final umbral = ref
        .watch(normativaProvider)
        .value
        ?.rite
        .umbralRegimenMensualKw;
    final c = v.cliente;
    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        Row(
          children: [
            etiquetaEstadoOrden(v.estado),
            const SizedBox(width: Gap.sm),
            Expanded(child: Text(textoIntervencion(v.tipo))),
          ],
        ),
        if (v.inspeccion != null && v.inspeccion!.firmadaAt == null)
          Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: Text(
              'Visita empezada a las ${fmt.hora(v.inspeccion!.iniciadaAt)}',
              key: const Key('hora_inicio'),
            ),
          ),
        if (v.orden.notasOficina != null) ...[
          const SizedBox(height: Gap.sm),
          Aviso('Oficina: ${v.orden.notasOficina}'),
        ],
        const Seccion('Cliente'),
        Text(
          c?.razonSocial ?? 'Cliente desconocido',
          style: theme.textTheme.titleMedium,
        ),
        if (c?.contactoNombre != null) Text(c!.contactoNombre!),
        if (c?.contactoTelefono != null) Text('Tel. ${c!.contactoTelefono}'),
        const Seccion('Instalación'),
        Text(inst.nombre, style: theme.textTheme.titleMedium),
        if (inst.direccion != null) Text(inst.direccion!),
        Text('Uso: ${textoUso(inst.usoEdificio)}'),
        Text(
          'Potencia declarada: ${fmt.kw(inst.potenciaFrioKw)} frío · '
          '${fmt.kw(inst.potenciaCalorKw)} calor',
        ),
        Text(
          'Suma de equipos: ${fmt.kw(pot.sumaFrioEquiposKw)} frío · '
          '${fmt.kw(pot.sumaCalorEquiposKw)} calor',
        ),
        Text(
          'Contrato de mantenimiento: ${textoSiNo(inst.contratoMantenimiento)} · '
          'Manual: ${textoSiNo(inst.manualDisponible)}',
        ),
        if (umbral != null && pot.kw > umbral) ...[
          const SizedBox(height: Gap.sm),
          Aviso(
            'Instalación de más de ${fmt.numero(umbral)} kW '
            '(${fmt.kw(pot.kw)}): el preventivo RITE es mensual y está fuera '
            'de esta versión. Solo control de fugas.',
            key: const Key('aviso_70kw'),
          ),
        ],
        for (final a in pot.avisos)
          if (pot.sumaSuperaDeclarada)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Aviso(a),
            ),
        Seccion('Equipos (${v.equipos.length})'),
        for (final e in v.equipos) ...[
          _FilaEquipo(v: v, e: e),
          const SizedBox(height: Gap.md),
        ],
        if (v.incidencias.isNotEmpty) ...[
          const Seccion('Incidencias abiertas de visitas anteriores'),
          for (final i in v.incidencias) ...[
            _FilaIncidencia(v: v, i: i),
            const SizedBox(height: Gap.md),
          ],
        ],
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

class _FilaEquipo extends StatelessWidget {
  const _FilaEquipo({required this.v, required this.e});
  final VistaVisita v;
  final EquipoEnVisita e;

  @override
  Widget build(BuildContext context) {
    final eq = e.equipo;
    final titulo = [
      textoTipoEquipo(eq.tipo),
      if (eq.ubicacion != null) eq.ubicacion!,
    ].join(' · ');
    final progreso = v.empezada
        ? '${e.respondidas}/${e.totalItems} respondidos'
        : '${e.totalItems} ítems';
    return Card(
      key: Key('equipo_${eq.id}'),
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: Radii.brMd,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => e.inspeccionEquipoId != null
                ? ChecklistPantalla(inspeccionEquipoId: e.inspeccionEquipoId!)
                : FichaEquipoPantalla(
                    equipoId: eq.id,
                    soloLectura: v.empezada && !v.editable,
                  ),
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Touch.primary),
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        [
                          progreso,
                          e.plantilla?.titulo ?? 'sin plantilla',
                          if (e.anadidoEnCampo) 'añadido en esta visita',
                        ].join(' · '),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilaIncidencia extends ConsumerWidget {
  const _FilaIncidencia({required this.v, required this.i});
  final VistaVisita v;
  final IncidenciaEnVisita i;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(inspeccionRepositoryProvider)!;
    final resuelta = i.resolucionId != null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${textoTipoEquipo(i.equipo.tipo)} · ${i.equipo.ubicacion ?? ''}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(i.incidencia.descripcion),
            Text(
              '${textoGravedad(i.incidencia.gravedad)} · desde el '
              '${fmt.fecha(i.incidencia.fecha)}',
            ),
            const SizedBox(height: Gap.sm),
            if (resuelta)
              Wrap(
                spacing: Gap.md,
                runSpacing: Gap.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Etiqueta(
                    texto: 'Resuelta en esta visita',
                    icono: Icons.check,
                    color: InspectaColors.ok,
                    fondo: InspectaColors.okBg,
                  ),
                  if (v.editable)
                    SizedBox(
                      height: Touch.min,
                      child: TextButton(
                        onPressed: () async {
                          final ok = await repo.deshacerResolucion(
                            i.resolucionId!,
                          );
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Ya se subió: no se puede deshacer desde aquí.',
                                ),
                              ),
                            );
                          }
                        },
                        child: const Text('Deshacer'),
                      ),
                    ),
                ],
              )
            else
              BotonSecundario(
                key: Key('resolver_${i.incidencia.id}'),
                texto: 'Resuelta en esta visita',
                icono: Icons.task_alt,
                onPressed: v.editable
                    ? () => repo.resolverIncidencia(
                        inspeccionId: v.inspeccion!.id,
                        equipoId: i.equipo.id,
                        incidenciaId: i.incidencia.id,
                      )
                    : null,
              ),
            if (!v.empezada && !resuelta)
              const Padding(
                padding: EdgeInsets.only(top: Gap.xs),
                child: Text('Empieza la visita para marcarla como resuelta.'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Acciones extends ConsumerWidget {
  const _Acciones(this.v);
  final VistaVisita v;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(inspeccionRepositoryProvider)!;
    final children = <Widget>[];
    if (!v.empezada) {
      children.add(
        BotonPrimario(
          key: const Key('empezar_visita'),
          texto: 'Empezar visita',
          icono: Icons.play_arrow,
          onPressed: v.orden.estado == 'cancelada'
              ? null
              : () => repo.empezarVisita(v.orden.id),
          motivoInactivo: 'La orden está cancelada.',
        ),
      );
    } else if (v.editable) {
      children
        ..add(
          SizedBox(
            width: double.infinity,
            child: BotonSecundario(
              key: const Key('anadir_equipo'),
              texto: 'Añadir equipo',
              icono: Icons.add,
              onPressed: () async {
                final id = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => AnadirEquipoPantalla(visita: v),
                  ),
                );
                if (id != null && context.mounted) {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FichaEquipoPantalla(equipoId: id),
                    ),
                  );
                }
              },
            ),
          ),
        )
        ..add(const SizedBox(height: Gap.md))
        ..add(
          BotonPrimario(
            texto: 'Revisar y firmar',
            icono: Icons.draw_outlined,
            onPressed: null,
            motivoInactivo: v.obligatoriosPendientes > 0
                ? 'Faltan ${v.obligatoriosPendientes} respuestas obligatorias.'
                : 'Revisar y firmar llega en una próxima versión.',
          ),
        );
    } else {
      children.add(
        const Text(
          'Informe cerrado: solo lectura.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// Para [AnadirEquipoPantalla] y pruebas: los tipos en el orden de la rejilla.
const tiposEnRejilla = TipoEquipo.values;
