import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/inspeccion_repository.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';

/// Abre T10 para una incidencia nueva (de un ítem o general) o existente.
Future<void> abrirIncidencia(
  BuildContext context, {
  required ChecklistEquipo ch,
  ItemPlantilla? item,
  Incidencia? incidencia,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => IncidenciaPantalla(
      inspeccionEquipoId: ch.inspeccionEquipo.id,
      item: item,
      incidencia: incidencia,
    ),
  ),
);

/// Gravedad con su explicación (§6.1, T10). Sin valor por defecto: la elige
/// el técnico (§9.1). [A VERIFICAR] los textos con el técnico de la llamada.
const gravedades = <(String, String, String)>[
  (
    'leve',
    'Leve',
    'No afecta a la seguridad ni al funcionamiento inmediato: se corrige en '
        'el siguiente mantenimiento.',
  ),
  (
    'grave',
    'Grave',
    'Afecta al rendimiento o puede empeorar: hay que corregirla en un plazo '
        'corto.',
  ),
  (
    'muy_grave',
    'Muy grave',
    'Riesgo para las personas, el equipo o el medio ambiente: se corrige ya o '
        'se para el equipo.',
  ),
];

/// T10 Incidencia (DISEÑO.md §6.1).
class IncidenciaPantalla extends ConsumerStatefulWidget {
  const IncidenciaPantalla({
    super.key,
    required this.inspeccionEquipoId,
    this.item,
    this.incidencia,
  });

  final String inspeccionEquipoId;
  final ItemPlantilla? item;
  final Incidencia? incidencia;

  @override
  ConsumerState<IncidenciaPantalla> createState() => _IncidenciaPantallaState();
}

class _IncidenciaPantallaState extends ConsumerState<IncidenciaPantalla> {
  late final _descripcion = TextEditingController(
    text: widget.incidencia?.descripcion ?? widget.item?.texto,
  );
  late final _accion = TextEditingController(
    text: widget.incidencia?.accionRecomendada,
  );
  late String? _gravedad = widget.incidencia?.gravedad;
  late int? _plazo = widget.incidencia?.plazoDias;
  late bool _parar = widget.incidencia?.paraEquipo ?? false;
  bool _guardando = false;

  @override
  void dispose() {
    _descripcion.dispose();
    _accion.dispose();
    super.dispose();
  }

  String? get _motivo {
    if (_descripcion.text.trim().isEmpty) return 'Describe el defecto.';
    if (_gravedad == null) return 'Elige la gravedad.';
    return null;
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    await ref
        .read(inspeccionRepositoryProvider)!
        .guardarIncidencia(
          id: widget.incidencia?.id,
          inspeccionEquipoId: widget.inspeccionEquipoId,
          itemId: widget.item?.id,
          descripcion: _descripcion.text,
          gravedad: _gravedad!,
          accionRecomendada: _accion.text,
          plazoDias: _plazo,
          paraEquipo: _parar,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.incidencia == null ? 'Nueva incidencia' : 'Incidencia',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          if (widget.item != null)
            Text(
              'Del ítem: ${widget.item!.texto}',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: Gap.md),
          TextField(
            key: const Key('incidencia_descripcion'),
            controller: _descripcion,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Descripción del defecto',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const Seccion('Gravedad'),
          for (final (wire, texto, explicacion) in gravedades)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: _BotonGravedad(
                key: Key('gravedad_$wire'),
                texto: texto,
                explicacion: explicacion,
                elegida: _gravedad == wire,
                color: switch (wire) {
                  'leve' => InspectaColors.observacion,
                  _ => InspectaColors.defecto,
                },
                onPressed: () => setState(() => _gravedad = wire),
              ),
            ),
          const Seccion('Acción recomendada'),
          TextField(
            controller: _accion,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Qué hay que hacer'),
          ),
          const Seccion('Plazo propuesto'),
          Opciones<int?>(
            opciones: const [
              Opcion(90, '3 meses'),
              Opcion(180, '6 meses'),
              Opcion(null, 'Sin plazo'),
            ],
            seleccionada: _plazo,
            onChanged: (v) => setState(() => _plazo = v),
          ),
          const Seccion('¿Obliga a parar el equipo?'),
          Opciones<bool>(
            opciones: const [Opcion(true, 'Sí, parar'), Opcion(false, 'No')],
            seleccionada: _parar,
            onChanged: (v) => setState(() => _parar = v),
          ),
          const SizedBox(height: Gap.xl),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: BotonPrimario(
            key: const Key('guardar_incidencia'),
            texto: 'Guardar incidencia',
            icono: Icons.save_outlined,
            onPressed: _motivo != null || _guardando ? null : _guardar,
            motivoInactivo: _motivo,
          ),
        ),
      ),
    );
  }
}

class _BotonGravedad extends StatelessWidget {
  const _BotonGravedad({
    super.key,
    required this.texto,
    required this.explicacion,
    required this.elegida,
    required this.color,
    required this.onPressed,
  });

  final String texto;
  final String explicacion;
  final bool elegida;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(Touch.primary),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.all(Gap.md),
      side: BorderSide(color: color, width: elegida ? 3 : 1),
      backgroundColor: elegida ? color.withValues(alpha: 0.12) : null,
    ),
    child: Row(
      children: [
        Icon(
          elegida ? Icons.radio_button_checked : Icons.radio_button_off,
          color: color,
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                texto,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              Text(explicacion, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ),
  );
}
