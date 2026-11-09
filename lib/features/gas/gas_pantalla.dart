import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/formato.dart' as fmt;
import '../../data/repositories/inspeccion_repository.dart';
import '../../design/pad_numerico.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../dominio/fgas.dart';
import '../../dominio/normativa.dart';
import '../../dominio/tipos.dart';

/// T11 Registro de gas y control de fugas (DISEÑO.md §6.1, F2.7).
class GasPantalla extends ConsumerWidget {
  const GasPantalla({super.key, required this.inspeccionEquipoId});
  final String inspeccionEquipoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ch = ref.watch(checklistProvider(inspeccionEquipoId)).value;
    final n = ref.watch(normativaProvider).value;
    if (ch == null || n == null) {
      return const Scaffold(body: Center(child: Text('Abriendo…')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Gas y control de fugas')),
      body: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          const Seccion('Movimientos de gas'),
          if (ch.movimientos.isEmpty) const Text('Ninguno en esta visita.'),
          for (final m in ch.movimientos)
            Text(
              '${_tipoTexto(m.tipo)} · ${fmt.numero(m.kg, decimales: 3)} kg '
              '${m.refrigerante}'
              '${m.origenGas == null ? '' : ' · ${m.origenGas}'}'
              '${m.reglaAplicada == ReglaAplicada.art133Aviso.wire ? ' · aviso art. 13.3' : ''}',
            ),
          const SizedBox(height: Gap.md),
          BotonSecundario(
            key: const Key('nuevo_movimiento'),
            texto: 'Registrar carga o recuperación',
            icono: Icons.add,
            onPressed: ch.editable
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MovimientoGasPantalla(ch: ch),
                    ),
                  )
                : null,
          ),
          const Seccion('Controles de fugas'),
          if (ch.controles.isEmpty) const Text('Ninguno en esta visita.'),
          for (final c in ch.controles)
            Text(
              [
                c.resultado == 'fuga' ? 'Fuga' : 'Sin fuga',
                if (c.localizacion != null) c.localizacion!,
                if (c.reparada == true) 'reparada',
                if (c.recontrolDesde != null && c.recontrolHasta != null)
                  'nuevo control entre el ${fmt.fecha(c.recontrolDesde!)} y el '
                      '${fmt.fecha(c.recontrolHasta!)}',
              ].join(' · '),
              key: Key('control_${c.id}'),
            ),
          const SizedBox(height: Gap.md),
          BotonSecundario(
            key: const Key('nuevo_control'),
            texto: 'Registrar control de fugas',
            icono: Icons.search,
            onPressed: ch.editable
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ControlFugasPantalla(ch: ch, normativa: n),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  static String _tipoTexto(String t) => switch (t) {
    'carga' => 'Carga',
    'recuperacion' => 'Recuperación',
    _ => 'Desmantelamiento',
  };
}

/// Formulario de un movimiento de gas, con el bloqueo del art. 13.4 a
/// pantalla completa y el aviso del 13.3 (§3.2).
class MovimientoGasPantalla extends ConsumerStatefulWidget {
  const MovimientoGasPantalla({super.key, required this.ch});
  final ChecklistEquipo ch;

  @override
  ConsumerState<MovimientoGasPantalla> createState() => _MovimientoGasState();
}

class _MovimientoGasState extends ConsumerState<MovimientoGasPantalla> {
  TipoMovimientoGas _tipo = TipoMovimientoGas.carga;
  late String? _refrigerante = widget.ch.equipo.refrigerante;
  double? _kg;
  OrigenGas? _origen;
  final _lote = TextEditingController();
  RecuperadoPor? _recuperadoPor;
  bool _declaracion = false;
  final _gestor = TextEditingController();
  final _gestorDoc = TextEditingController();
  String _motivo = 'mantenimiento';
  bool _guardando = false;

  @override
  void dispose() {
    for (final c in [_lote, _gestor, _gestorDoc]) {
      c.dispose();
    }
    super.dispose();
  }

  CategoriaFgas get _categoria =>
      widget.ch.equipo.categoriaFgas ??
      deducirCategoriaFgas(widget.ch.equipo.tipo).categoria;

  MovimientoGasNuevo? _datos() {
    final r = _refrigerante, kg = _kg;
    if (r == null || kg == null || kg <= 0) return null;
    if (_tipo == TipoMovimientoGas.carga && _origen == null) return null;
    return MovimientoGasNuevo(
      tipo: _tipo,
      refrigerante: r,
      kg: kg,
      origen: _origen,
      datos: DatosOrigenGas(
        regeneradoLote: _lote.text,
        // La foto de la etiqueta del art. 12.7 llega con la cámara (día 5).
        regeneradoEtiquetaFotoId: null,
        recicladoRecuperadoPor: _recuperadoPor,
        recicladoDeclaracion: _declaracion,
      ),
      gestorNombre: _gestor.text.trim().isEmpty ? null : _gestor.text.trim(),
      gestorDocumento: _gestorDoc.text.trim().isEmpty
          ? null
          : _gestorDoc.text.trim(),
      motivo: _motivo,
    );
  }

  ValidacionCarga? _validar(Normativa n, MovimientoGasNuevo m) {
    final gas = n.refrigerante(m.refrigerante);
    if (gas == null) return null;
    return validarCargaGas(
      n,
      tipo: m.tipo,
      refrigerante: gas,
      categoria: _categoria,
      origen: m.origen ?? OrigenGas.virgen,
      fecha: ref.read(relojProvider)().toUtc(),
      datos: m.datos,
    );
  }

  Future<void> _guardar(Normativa n) async {
    final m = _datos()!;
    final v = _validar(n, m)!;
    if (v is CargaBloqueada) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => BloqueoCargaPantalla(bloqueo: v),
        ),
      );
      return;
    }
    setState(() => _guardando = true);
    await ref
        .read(inspeccionRepositoryProvider)!
        .registrarMovimientoGas(
          inspeccionEquipoId: widget.ch.inspeccionEquipo.id,
          m: m,
          validacion: v,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final n = ref.watch(normativaProvider).value!;
    final m = _datos();
    final v = m == null ? null : _validar(n, m);
    final esCarga = _tipo == TipoMovimientoGas.carga;
    return Scaffold(
      appBar: AppBar(title: const Text('Movimiento de gas')),
      body: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          const Seccion('Tipo'),
          Opciones<TipoMovimientoGas>(
            opciones: const [
              Opcion(TipoMovimientoGas.carga, 'Carga'),
              Opcion(TipoMovimientoGas.recuperacion, 'Recuperación'),
              Opcion(TipoMovimientoGas.desmantelamiento, 'Desmantelamiento'),
            ],
            seleccionada: _tipo,
            onChanged: (t) => setState(() => _tipo = t),
          ),
          const Seccion('Refrigerante'),
          Opciones<String>(
            opciones: [
              for (final r in n.refrigerantes) Opcion(r.codigo, r.codigo),
            ],
            seleccionada: _refrigerante == null
                ? null
                : n.refrigerante(_refrigerante!)?.codigo,
            onChanged: (c) => setState(() => _refrigerante = c),
          ),
          const Seccion('Cantidad'),
          BotonSecundario(
            key: const Key('gas_kg'),
            texto: _kg == null
                ? 'Kilos: —'
                : 'Kilos: ${fmt.numero(_kg!, decimales: 3)} kg',
            icono: Icons.scale_outlined,
            onPressed: () async {
              final r = await pedirNumero(
                context,
                titulo: 'Kilos',
                unidad: 'kg',
                inicial: _kg,
              );
              if (r != null) {
                setState(() => _kg = r is NumeroElegido ? r.valor : null);
              }
            },
          ),
          if (esCarga) ...[
            const Seccion('Origen del gas'),
            Opciones<OrigenGas>(
              opciones: const [
                Opcion(OrigenGas.virgen, 'Virgen'),
                Opcion(OrigenGas.reciclado, 'Reciclado'),
                Opcion(OrigenGas.regenerado, 'Regenerado'),
              ],
              seleccionada: _origen,
              onChanged: (o) => setState(() => _origen = o),
            ),
            if (_origen == OrigenGas.regenerado) ...[
              const SizedBox(height: Gap.md),
              TextField(
                controller: _lote,
                decoration: const InputDecoration(
                  labelText: 'Lote de la etiqueta (art. 12.7)',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Gap.sm),
              const Text(
                'Falta la foto de la etiqueta: la cámara llega en una próxima '
                'versión, así que hoy una carga regenerada que la necesite '
                'queda bloqueada.',
              ),
            ],
            if (_origen == OrigenGas.reciclado) ...[
              const Seccion('Recuperado por'),
              Opciones<RecuperadoPor>(
                opciones: const [
                  Opcion(RecuperadoPor.propiaEmpresa, 'Nuestra empresa'),
                  Opcion(RecuperadoPor.paraEstaEmpresa, 'Otra, para nosotros'),
                ],
                seleccionada: _recuperadoPor,
                onChanged: (r) => setState(() => _recuperadoPor = r),
              ),
              const SizedBox(height: Gap.md),
              CheckboxListTile(
                value: _declaracion,
                onChanged: (b) => setState(() => _declaracion = b ?? false),
                title: const Text(
                  'Declaro que se recuperó de un aparato de aire acondicionado o '
                  'bomba de calor durante su mantenimiento',
                ),
              ),
            ],
          ],
          const Seccion('Motivo'),
          Opciones<String>(
            opciones: const [
              Opcion('mantenimiento', 'Mantenimiento'),
              Opcion('fuga', 'Reparación de fuga'),
            ],
            seleccionada: _motivo,
            onChanged: (x) => setState(() => _motivo = x),
          ),
          const Seccion('Gestor del residuo (si se recuperó)'),
          TextField(
            controller: _gestor,
            decoration: const InputDecoration(labelText: 'Gestor'),
          ),
          const SizedBox(height: Gap.sm),
          TextField(
            controller: _gestorDoc,
            decoration: const InputDecoration(
              labelText: 'Documento de entrega',
            ),
          ),
          if (v is CargaConAviso) ...[
            const SizedBox(height: Gap.lg),
            Aviso('${v.articulo}: ${v.motivo}', key: const Key('aviso_carga')),
          ],
          if (v is CargaBloqueada) ...[
            const SizedBox(height: Gap.lg),
            Aviso(
              'Esta carga no se puede guardar: ${v.articulo}.',
              grave: true,
              key: const Key('aviso_bloqueo'),
            ),
          ],
          if (m != null && v == null)
            const Aviso(
              'Refrigerante fuera del catálogo: no se puede validar.',
            ),
          const SizedBox(height: Gap.xl),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: BotonPrimario(
            key: const Key('guardar_movimiento'),
            texto: v is CargaBloqueada ? 'Ver por qué no se puede' : 'Guardar',
            icono: v is CargaBloqueada ? Icons.block : Icons.save_outlined,
            onPressed: m == null || v == null || _guardando
                ? null
                : () => _guardar(n),
            motivoInactivo: _refrigerante == null
                ? 'Elige el refrigerante.'
                : _kg == null
                ? 'Indica los kilos.'
                : 'Elige el origen del gas.',
          ),
        ),
      ),
    );
  }
}

/// Bloqueo del art. 13.4 a pantalla completa, no un toast (§6.1, T11).
class BloqueoCargaPantalla extends StatelessWidget {
  const BloqueoCargaPantalla({super.key, required this.bloqueo});
  final CargaBloqueada bloqueo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('bloqueo_13_4'),
      backgroundColor: InspectaColors.defectoBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Gap.xl),
          children: [
            const Icon(Icons.block, size: 96, color: InspectaColors.defecto),
            const SizedBox(height: Gap.lg),
            Text(
              'Carga no permitida',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: InspectaColors.defecto,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Gap.md),
            Text(
              bloqueo.articulo,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: InspectaColors.textLight,
              ),
            ),
            const SizedBox(height: Gap.lg),
            Text(
              bloqueo.motivo,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: InspectaColors.textLight,
              ),
            ),
            const SizedBox(height: Gap.xl),
            BotonPrimario(
              texto: 'Volver y corregir',
              icono: Icons.arrow_back,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formulario de control de fugas; si se repara, enseña la ventana del nuevo
/// control del art. 4.5 calculada por `fgas.dart`.
class ControlFugasPantalla extends ConsumerStatefulWidget {
  const ControlFugasPantalla({
    super.key,
    required this.ch,
    required this.normativa,
  });
  final ChecklistEquipo ch;
  final Normativa normativa;

  @override
  ConsumerState<ControlFugasPantalla> createState() => _ControlFugasState();
}

class _ControlFugasState extends ConsumerState<ControlFugasPantalla> {
  String? _metodo;
  final _detector = TextEditingController();
  String? _resultado;
  final _localizacion = TextEditingController();
  bool? _reparada;
  bool _guardando = false;

  @override
  void dispose() {
    _detector.dispose();
    _localizacion.dispose();
    super.dispose();
  }

  NuevoControl? _nuevoControl(DateTime ahora) {
    final e = widget.ch.equipo;
    final gas = e.refrigerante == null
        ? null
        : widget.normativa.refrigerante(e.refrigerante!);
    if (gas == null || e.cargaKg == null) return null;
    final sujecion = evaluarControlFugas(
      widget.normativa,
      refrigerante: gas,
      cargaKg: e.cargaKg!,
      conDeteccion: e.deteccionFugas ?? false,
      hermeticoEtiquetado: e.hermeticoEtiquetado ?? false,
    );
    return nuevoControlTrasReparacion(
      widget.normativa,
      sujecion: sujecion,
      reparadaAt: ahora,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ahora = ref.watch(relojProvider)();
    final reparada = _resultado == 'fuga' && _reparada == true;
    final nc = reparada ? _nuevoControl(ahora) : null;
    final ventana = switch (nc) {
      NuevoControlObligatorio(:final ventana) => ventana,
      NuevoControlARevisar(:final ventana) => ventana,
      _ => null,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Control de fugas')),
      body: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          const Seccion('Método'),
          Opciones<String>(
            opciones: const [
              Opcion(
                'Detector electrónico (método indirecto)',
                'Detector electrónico',
              ),
              Opcion('Agua jabonosa o espuma', 'Espuma'),
              Opcion('Medición de parámetros', 'Parámetros'),
            ],
            seleccionada: _metodo,
            onChanged: (m) => setState(() => _metodo = m),
          ),
          const SizedBox(height: Gap.md),
          TextField(
            controller: _detector,
            decoration: const InputDecoration(labelText: 'Modelo del detector'),
          ),
          const Seccion('Resultado'),
          Opciones<String>(
            opciones: const [
              Opcion('sin_fuga', 'Sin fuga'),
              Opcion('fuga', 'Fuga'),
            ],
            seleccionada: _resultado,
            onChanged: (r) => setState(() => _resultado = r),
          ),
          if (_resultado == 'fuga') ...[
            const SizedBox(height: Gap.md),
            TextField(
              controller: _localizacion,
              decoration: const InputDecoration(
                labelText: 'Dónde está la fuga',
              ),
            ),
            const Seccion('¿Reparada ahora?'),
            Opciones<bool>(
              opciones: const [Opcion(true, 'Sí'), Opcion(false, 'No')],
              seleccionada: _reparada,
              onChanged: (b) => setState(() => _reparada = b),
            ),
          ],
          if (nc != null) ...[
            const SizedBox(height: Gap.lg),
            Aviso(switch (nc) {
              NuevoControlObligatorio(:final ventana) =>
                'Nuevo control obligatorio (art. 4.5) entre el '
                    '${fmt.fecha(ventana.desde)} y el ${fmt.fecha(ventana.hasta)}.',
              NuevoControlARevisar(:final ventana, :final motivo) =>
                'Nuevo control a revisar entre el ${fmt.fecha(ventana.desde)} y el '
                    '${fmt.fecha(ventana.hasta)}: $motivo',
              NuevoControlNoExigido(:final motivo) => motivo,
            }, key: const Key('aviso_nuevo_control')),
          ],
          const SizedBox(height: Gap.xl),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: BotonPrimario(
            key: const Key('guardar_control'),
            texto: 'Guardar control',
            icono: Icons.save_outlined,
            onPressed:
                _resultado == null ||
                    (_resultado == 'fuga' && _reparada == null) ||
                    _guardando
                ? null
                : () async {
                    setState(() => _guardando = true);
                    await ref
                        .read(inspeccionRepositoryProvider)!
                        .registrarControlFugas(
                          inspeccionEquipoId: widget.ch.inspeccionEquipo.id,
                          metodo: _metodo,
                          detectorModelo: _detector.text.trim().isEmpty
                              ? null
                              : _detector.text.trim(),
                          resultado: _resultado!,
                          localizacion: _localizacion.text.trim().isEmpty
                              ? null
                              : _localizacion.text.trim(),
                          reparada: _reparada,
                          ventana: ventana,
                        );
                    if (context.mounted) Navigator.of(context).pop();
                  },
            motivoInactivo: _resultado == null
                ? 'Elige el resultado.'
                : '¿Se ha reparado?',
          ),
        ),
      ),
    );
  }
}
