import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/formato.dart' as fmt;
import '../../data/local/app_database.dart';
import '../../data/repositories/inspeccion_repository.dart';
import '../../design/pad_numerico.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../captura/fotos.dart';
import '../equipo/ficha_equipo_pantalla.dart';
import '../gas/gas_pantalla.dart';
import '../incidencia/incidencia_pantalla.dart';
import '../textos.dart';

/// Los cuatro estados de un ítem, con icono + texto + color (§6.0).
enum EstadoItem {
  ok('ok', 'OK', Icons.check, InspectaColors.ok, InspectaColors.okBg),
  observacion(
    'observacion',
    'Observación',
    Icons.priority_high,
    InspectaColors.observacion,
    InspectaColors.observacionBg,
  ),
  defecto(
    'defecto',
    'Defecto',
    Icons.close,
    InspectaColors.defecto,
    InspectaColors.defectoBg,
  ),
  na(
    'na',
    'N.A.',
    Icons.remove,
    InspectaColors.noAplica,
    InspectaColors.noAplicaBg,
  );

  const EstadoItem(this.wire, this.texto, this.icono, this.color, this.fondo);
  final String wire;
  final String texto;
  final IconData icono;
  final Color color;
  final Color fondo;

  static EstadoItem? desde(String? w) {
    for (final e in values) {
      if (e.wire == w) return e;
    }
    return null;
  }
}

/// T5 Checklist en modo guantes (DISEÑO.md §6.1, F2.3): un ítem por
/// pantalla, cuatro botones grandes, avance automático y «Deshacer» 5 s. El
/// progreso vive en Drift: al volver (o tras cerrar la app) se reanuda en el
/// primer ítem sin responder.
class ChecklistPantalla extends ConsumerStatefulWidget {
  const ChecklistPantalla({
    super.key,
    required this.inspeccionEquipoId,
    this.indiceInicial,
  });
  final String inspeccionEquipoId;

  /// Ítem con el que abrir (desde un pendiente de T12).
  final int? indiceInicial;

  @override
  ConsumerState<ChecklistPantalla> createState() => _ChecklistPantallaState();
}

class _ChecklistPantallaState extends ConsumerState<ChecklistPantalla> {
  late int? _indice = widget.indiceInicial;

  void _ir(int i, int total) => setState(() => _indice = i.clamp(0, total - 1));

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(checklistProvider(widget.inspeccionEquipoId));
    return c.when(
      loading: () =>
          const Scaffold(body: Center(child: Text('Abriendo el checklist…'))),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('No se pudo abrir: $e'))),
      data: (ch) {
        if (ch == null || ch.items.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Este equipo no tiene checklist.')),
          );
        }
        final i = (_indice ??= ch.primeroPendiente).clamp(
          0,
          ch.items.length - 1,
        );
        final total = ch.items.length;
        final eq = ch.equipo;
        return Scaffold(
          appBar: AppBar(
            title: Text('${textoTipoEquipo(eq.tipo)} · ${i + 1}/$total'),
            bottom: barraSync(),
          ),
          body: ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              Text(
                '${ch.respondidos} de $total respondidos'
                '${eq.ubicacion == null ? '' : ' · ${eq.ubicacion}'}',
                key: const Key('progreso_checklist'),
              ),
              const SizedBox(height: Gap.sm),
              LinearProgressIndicator(
                value: ch.respondidos / total,
                minHeight: 8,
              ),
              const SizedBox(height: Gap.lg),
              _TarjetaItem(
                key: ValueKey(ch.items[i].item.id),
                ch: ch,
                ic: ch.items[i],
                alResponder: (avanzar) {
                  if (avanzar && i < total - 1) _ir(i + 1, total);
                },
              ),
              const SizedBox(height: Gap.lg),
              Wrap(
                spacing: Gap.md,
                runSpacing: Gap.md,
                children: [
                  BotonSecundario(
                    texto: 'Ficha',
                    icono: Icons.badge_outlined,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FichaEquipoPantalla(
                          equipoId: eq.id,
                          soloLectura: !ch.editable,
                        ),
                      ),
                    ),
                  ),
                  BotonSecundario(
                    key: const Key('abrir_gas'),
                    texto:
                        'Gas y fugas'
                        '${ch.movimientos.length + ch.controles.length > 0 ? ' (${ch.movimientos.length + ch.controles.length})' : ''}',
                    icono: Icons.propane_tank_outlined,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => GasPantalla(
                          inspeccionEquipoId: ch.inspeccionEquipo.id,
                        ),
                      ),
                    ),
                  ),
                  BotonSecundario(
                    texto: 'Incidencias (${ch.incidencias.length})',
                    icono: Icons.report_outlined,
                    onPressed: ch.editable
                        ? () => abrirIncidencia(context, ch: ch)
                        : null,
                  ),
                ],
              ),
              for (final inc in ch.incidencias) ...[
                const SizedBox(height: Gap.md),
                _FilaIncidencia(ch: ch, inc: inc),
              ],
              const SizedBox(height: Gap.xl),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: Touch.primary,
                      child: OutlinedButton.icon(
                        key: const Key('item_anterior'),
                        onPressed: i == 0 ? null : () => _ir(i - 1, total),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Anterior'),
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: SizedBox(
                      height: Touch.primary,
                      child: FilledButton.icon(
                        key: const Key('item_siguiente'),
                        onPressed: i == total - 1
                            ? () => Navigator.of(context).pop()
                            : () => _ir(i + 1, total),
                        icon: Icon(
                          i == total - 1 ? Icons.done_all : Icons.arrow_forward,
                        ),
                        label: Text(i == total - 1 ? 'Terminar' : 'Siguiente'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FilaIncidencia extends StatelessWidget {
  const _FilaIncidencia({required this.ch, required this.inc});
  final ChecklistEquipo ch;
  final Incidencia inc;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      borderRadius: Radii.brMd,
      onTap: ch.editable
          ? () => abrirIncidencia(context, ch: ch, incidencia: inc)
          : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Touch.min),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Text(
            '${textoGravedad(inc.gravedad)} · ${inc.descripcion}'
            '${inc.paraEquipo ? ' · obliga a parar' : ''}',
          ),
        ),
      ),
    ),
  );
}

class _TarjetaItem extends ConsumerWidget {
  const _TarjetaItem({
    super.key,
    required this.ch,
    required this.ic,
    required this.alResponder,
  });

  final ChecklistEquipo ch;
  final ItemConRespuesta ic;

  /// Tras guardar: `true` si hay que pasar al siguiente ítem.
  final void Function(bool avanzar) alResponder;

  String? get _referencia {
    final u = ch.hechos?.ultimosValores[ic.item.clave];
    if (u == null) return null;
    return 'Última vez: ${fmt.numero(u.valor)} ${u.unidad ?? ''} '
        '(${fmt.fecha(u.fecha)})';
  }

  Future<void> _guardar(
    BuildContext context,
    WidgetRef ref, {
    required String? estado,
    required double? valor,
    required String? observacion,
    required bool avanzar,
  }) async {
    final repo = ref.read(inspeccionRepositoryProvider)!;
    final previa = await repo.responder(
      inspeccionEquipoId: ch.inspeccionEquipo.id,
      itemId: ic.item.id,
      estado: estado,
      valor: valor,
      observacion: observacion,
    );
    alResponder(avanzar);
    final e = EstadoItem.desde(estado);
    if (!context.mounted || e == null || estado == ic.respuesta?.estado) return;
    mostrarDeshacer(
      context,
      texto: 'Marcado como ${e.texto}',
      onDeshacer: () => repo.deshacerRespuesta(previa),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ic.item;
    final r = ic.respuesta;
    final theme = Theme.of(context);
    final tipo = item.tipoRespuesta;
    final llevaValor = tipo == 'estado_valor' || tipo == 'solo_valor';
    final llevaEstado = tipo == 'estado' || tipo == 'estado_valor';
    final editable = ch.editable;
    final actual = EstadoItem.desde(r?.estado);

    Future<void> medir() async {
      final res = await pedirNumero(
        context,
        titulo: item.texto,
        unidad: item.unidad,
        inicial: r?.valorNum,
        rangoMin: item.rangoMin,
        rangoMax: item.rangoMax,
        referencia: _referencia,
      );
      if (res == null || !context.mounted) return;
      final v = res is NumeroElegido ? res.valor : null;
      await _guardar(
        context,
        ref,
        estado: r?.estado,
        valor: v,
        observacion: r?.observacion,
        // Solo valor: ya está respondido. Con estado: falta elegirlo.
        avanzar: tipo == 'solo_valor' && v != null,
      );
    }

    Future<void> observar() async {
      final ctrl = TextEditingController(text: r?.observacion);
      final texto = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Observación'),
          content: TextField(controller: ctrl, maxLines: 4, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
      if (texto == null || !context.mounted) return;
      await _guardar(
        context,
        ref,
        estado: r?.estado,
        valor: r?.valorNum,
        observacion: texto,
        avanzar: false,
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              [
                item.seccion,
                item.codigoNormativo,
              ].whereType<String>().join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Gap.sm),
            Text(
              item.texto,
              key: const Key('texto_item'),
              style: theme.textTheme.headlineSmall,
            ),
            if (item.obligatorio)
              const Padding(
                padding: EdgeInsets.only(top: Gap.xs),
                child: Text('Obligatorio'),
              ),
            if (item.fotoObligatoria && actual != EstadoItem.na)
              const Padding(
                padding: EdgeInsets.only(top: Gap.xs),
                child: Text('Pide foto (salvo si es N.A.).'),
              ),
            if (llevaValor) ...[
              const SizedBox(height: Gap.lg),
              if (_referencia != null)
                Text(_referencia!, key: const Key('referencia')),
              const SizedBox(height: Gap.sm),
              SizedBox(
                height: Touch.primary,
                child: OutlinedButton.icon(
                  key: const Key('medir'),
                  onPressed: editable ? medir : null,
                  icon: const Icon(Icons.dialpad),
                  label: Text(
                    r?.valorNum == null
                        ? 'Medir (${item.unidad ?? ''})'
                        : '${fmt.numero(r!.valorNum!, decimales: 3)} ${item.unidad ?? ''}',
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
            ],
            if (llevaEstado) ...[
              const SizedBox(height: Gap.lg),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: Gap.md,
                crossAxisSpacing: Gap.md,
                childAspectRatio: 2.2,
                children: [
                  for (final e in EstadoItem.values)
                    _BotonEstado(
                      e: e,
                      elegido: actual == e,
                      onPressed: !editable
                          ? null
                          : () {
                              final faltaValor =
                                  tipo == 'estado_valor' &&
                                  r?.valorNum == null &&
                                  e != EstadoItem.na;
                              _guardar(
                                context,
                                ref,
                                estado: e.wire,
                                valor: e == EstadoItem.na ? null : r?.valorNum,
                                observacion: r?.observacion,
                                avanzar: !faltaValor && e != EstadoItem.defecto,
                              );
                            },
                    ),
                ],
              ),
              if (tipo == 'estado_valor' &&
                  r?.valorNum == null &&
                  actual != null &&
                  actual != EstadoItem.na)
                const Padding(
                  padding: EdgeInsets.only(top: Gap.sm),
                  child: Text('Falta el valor medido.'),
                ),
            ],
            if (tipo == 'si_no') ...[
              // [A VERIFICAR] Ninguna plantilla base usa `si_no`; se guarda
              // Sí como `ok` y No como `defecto`.
              const SizedBox(height: Gap.lg),
              Opciones<String>(
                opciones: const [Opcion('ok', 'Sí'), Opcion('defecto', 'No')],
                seleccionada: r?.estado,
                onChanged: editable
                    ? (v) => _guardar(
                        context,
                        ref,
                        estado: v,
                        valor: null,
                        observacion: r?.observacion,
                        avanzar: true,
                      )
                    : null,
              ),
            ],
            if (actual == EstadoItem.defecto && editable) ...[
              const SizedBox(height: Gap.md),
              BotonPrimario(
                key: const Key('registrar_incidencia'),
                texto: 'Registrar incidencia',
                icono: Icons.report_outlined,
                onPressed: () => abrirIncidencia(context, ch: ch, item: item),
              ),
            ],
            const SizedBox(height: Gap.md),
            Wrap(
              spacing: Gap.md,
              runSpacing: Gap.md,
              children: [
                for (final f in ch.fotosDe(item.id))
                  MiniaturaFoto(foto: f, editable: editable),
                SizedBox(
                  width: Touch.captura,
                  height: Touch.captura,
                  child: OutlinedButton(
                    key: const Key('foto_item'),
                    onPressed: editable
                        ? () => tomarFoto(
                            context,
                            ref,
                            inspeccionEquipoId: ch.inspeccionEquipo.id,
                            itemId: item.id,
                          )
                        : null,
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_camera, size: 32),
                        Text('Foto'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            BotonSecundario(
              texto: r?.observacion == null
                  ? 'Añadir observación'
                  : 'Observación: ${r!.observacion}',
              icono: Icons.edit_note,
              onPressed: editable ? observar : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _BotonEstado extends StatelessWidget {
  const _BotonEstado({
    required this.e,
    required this.elegido,
    required this.onPressed,
  });
  final EstadoItem e;
  final bool elegido;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: Touch.primary,
    child: OutlinedButton.icon(
      key: Key('estado_${e.wire}'),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: elegido ? e.color : e.fondo,
        foregroundColor: elegido ? Colors.white : e.color,
        side: BorderSide(color: e.color, width: elegido ? 3 : 1),
      ),
      icon: Icon(elegido ? Icons.check_circle : e.icono),
      label: Text(e.texto, style: const TextStyle(fontSize: 18)),
    ),
  );
}
