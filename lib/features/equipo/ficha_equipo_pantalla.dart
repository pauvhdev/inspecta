import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/formato.dart' as fmt;
import '../../data/local/app_database.dart';
import '../../data/repositories/inspeccion_repository.dart';
import '../../design/pad_numerico.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../dominio/fgas.dart';
import '../../dominio/normativa.dart';
import '../../dominio/tipos.dart';
import '../textos.dart';
import 'calculos_ficha.dart';

/// T3 Ficha del equipo (DISEÑO.md §6.1): identidad, categoría F-gas, bloque
/// F-gas, próxima revisión RITE, aviso de potencia y últimos valores.
class FichaEquipoPantalla extends ConsumerWidget {
  const FichaEquipoPantalla({
    super.key,
    required this.equipoId,
    this.soloLectura = false,
  });

  final String equipoId;
  final bool soloLectura;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ficha = ref.watch(fichaProvider(equipoId));
    final normativa = ref.watch(normativaProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ficha del equipo')),
      body: switch ((ficha, normativa)) {
        (AsyncData(value: final f?), AsyncData(value: final n)) => _Editor(
          key: ValueKey(f.equipo.id),
          ficha: f,
          normativa: n,
          soloLectura: soloLectura,
        ),
        (AsyncData(value: null), _) => const Padding(
          padding: EdgeInsets.all(Gap.xl),
          child: Text('Este equipo ya no existe en el aparato.'),
        ),
        (AsyncError(:final error), _) ||
        (_, AsyncError(:final error)) => Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Text('No se pudo abrir la ficha: $error'),
        ),
        _ => const Padding(
          padding: EdgeInsets.all(Gap.xl),
          child: Text('Abriendo la ficha…'),
        ),
      },
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({
    super.key,
    required this.ficha,
    required this.normativa,
    required this.soloLectura,
  });

  final FichaEquipo ficha;
  final Normativa normativa;
  final bool soloLectura;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late Equipo _e = _conCategoria(widget.ficha.equipo);
  late final _marca = TextEditingController(text: _e.marca);
  late final _modelo = TextEditingController(text: _e.modelo);
  late final _serie = TextEditingController(text: _e.nSerie);
  late final _ubicacion = TextEditingController(text: _e.ubicacion);
  bool _cambios = false;

  /// La categoría llega rellena con la que deduce `fgas.dart` del tipo; el
  /// técnico la confirma al guardar o la cambia.
  static Equipo _conCategoria(Equipo e) => e.categoriaFgas != null
      ? e
      : e.copyWith(
          categoriaFgas: Value(deducirCategoriaFgas(e.tipo).categoria),
        );

  @override
  void dispose() {
    for (final c in [_marca, _modelo, _serie, _ubicacion]) {
      c.dispose();
    }
    super.dispose();
  }

  void _cambiar(Equipo e) => setState(() {
    _e = e;
    _cambios = true;
  });

  String? _texto(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _numero(
    String titulo,
    String unidad,
    double? actual,
    Equipo Function(double?) aplicar,
  ) async {
    final r = await pedirNumero(
      context,
      titulo: titulo,
      unidad: unidad,
      inicial: actual,
    );
    if (r == null) return;
    _cambiar(aplicar(r is NumeroElegido ? r.valor : null));
  }

  Future<void> _guardar() async {
    final fila = _e.copyWith(
      marca: Value(_texto(_marca)),
      modelo: Value(_texto(_modelo)),
      nSerie: Value(_texto(_serie)),
      ubicacion: Value(_texto(_ubicacion)),
    );
    await ref.read(inspeccionRepositoryProvider)!.guardarEquipo(fila);
    if (!mounted) return;
    setState(() => _cambios = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ficha guardada en el aparato.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.normativa;
    final f = widget.ficha;
    final ro = widget.soloLectura;
    final deducida = deducirCategoriaFgas(_e.tipo);
    final fgas = bloqueFgas(n, _e, f.hechos);
    final avisos = avisosPotencia(f.instalacion, f.equiposInstalacion, _e);
    final theme = Theme.of(context);

    Widget campoTexto(String etiqueta, TextEditingController c) => Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: TextField(
        controller: c,
        readOnly: ro,
        decoration: InputDecoration(labelText: etiqueta),
        onChanged: (_) => setState(() => _cambios = true),
      ),
    );

    Widget siNo(String titulo, bool? valor, Equipo Function(bool?) aplicar) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Seccion(titulo),
            Opciones<bool?>(
              opciones: const [
                Opcion(true, 'Sí'),
                Opcion(false, 'No'),
                Opcion(null, 'No consta'),
              ],
              seleccionada: valor,
              onChanged: ro ? null : (v) => _cambiar(aplicar(v)),
            ),
          ],
        );

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              if (ro)
                const Padding(
                  padding: EdgeInsets.only(bottom: Gap.md),
                  child: Aviso('Informe cerrado: la ficha es de solo lectura.'),
                ),
              Card(
                key: const Key('bloque_fgas'),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(Gap.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('F-gas', style: theme.textTheme.titleMedium),
                      const SizedBox(height: Gap.xs),
                      Text(fgas.titular, style: theme.textTheme.titleLarge),
                      for (final d in fgas.detalle)
                        Text(d, style: theme.textTheme.bodyMedium),
                      const Divider(height: Gap.xl),
                      Text(
                        textoRite(
                          n,
                          e: _e,
                          instalacion: f.instalacion,
                          equiposInstalacion: f.equiposInstalacion,
                          hechos: f.hechos,
                        ),
                        key: const Key('texto_rite'),
                      ),
                    ],
                  ),
                ),
              ),
              for (final a in avisos)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.md),
                  child: Aviso(a, key: const Key('aviso_potencia')),
                ),
              if (f.hechos != null) _UltimaVisita(f),
              const Seccion('Identificación'),
              campoTexto('Marca', _marca),
              campoTexto('Modelo', _modelo),
              campoTexto('N.º de serie', _serie),
              campoTexto('Ubicación', _ubicacion),
              BotonSecundario(
                texto: 'Leer placa',
                icono: Icons.document_scanner_outlined,
                onPressed: null,
              ),
              const Text(
                'Leer la placa con la IA necesita la cámara: llega en una '
                'próxima versión.',
              ),
              const Seccion('Tipo'),
              Opciones<TipoEquipo>(
                opciones: [
                  for (final t in TipoEquipo.values)
                    Opcion(t, textoTipoEquipo(t)),
                ],
                seleccionada: _e.tipo,
                onChanged: ro
                    ? null
                    : (t) => _cambiar(
                        _e.copyWith(
                          tipo: t,
                          categoriaFgas: Value(
                            deducirCategoriaFgas(t).categoria,
                          ),
                        ),
                      ),
              ),
              const Seccion('Categoría F-gas'),
              Opciones<CategoriaFgas>(
                opciones: [
                  for (final c in CategoriaFgas.values)
                    Opcion(c, textoCategoria(c)),
                ],
                seleccionada: _e.categoriaFgas,
                onChanged: ro
                    ? null
                    : (c) => _cambiar(_e.copyWith(categoriaFgas: Value(c))),
              ),
              if (deducida.dudosa || widget.ficha.equipo.categoriaFgas == null)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(
                    '${deducida.motivo}. '
                    '${widget.ficha.equipo.categoriaFgas == null ? 'Se confirma al guardar.' : ''}',
                  ),
                ),
              const Seccion('Potencia'),
              Row(
                children: [
                  Expanded(
                    child: BotonSecundario(
                      key: const Key('ficha_frio'),
                      texto: 'Frío: ${fmt.kw(_e.potenciaFrioKw)}',
                      icono: Icons.ac_unit,
                      onPressed: ro
                          ? null
                          : () => _numero(
                              'Potencia de frío',
                              'kW',
                              _e.potenciaFrioKw,
                              (v) => _e.copyWith(potenciaFrioKw: Value(v)),
                            ),
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: BotonSecundario(
                      key: const Key('ficha_calor'),
                      texto: 'Calor: ${fmt.kw(_e.potenciaCalorKw)}',
                      icono: Icons.local_fire_department_outlined,
                      onPressed: ro
                          ? null
                          : () => _numero(
                              'Potencia de calor',
                              'kW',
                              _e.potenciaCalorKw,
                              (v) => _e.copyWith(potenciaCalorKw: Value(v)),
                            ),
                    ),
                  ),
                ],
              ),
              const Seccion('Refrigerante'),
              Opciones<String>(
                opciones: [
                  for (final r in n.refrigerantes) Opcion(r.codigo, r.codigo),
                ],
                seleccionada: _e.refrigerante == null
                    ? null
                    : n.refrigerante(_e.refrigerante!)?.codigo ??
                          _e.refrigerante,
                onChanged: ro
                    ? null
                    : (c) => _cambiar(_e.copyWith(refrigerante: Value(c))),
              ),
              const Seccion('Carga de refrigerante'),
              BotonSecundario(
                key: const Key('ficha_carga'),
                texto: _e.cargaKg == null
                    ? 'Carga: —'
                    : 'Carga: ${fmt.numero(_e.cargaKg!, decimales: 3)} kg',
                icono: Icons.scale_outlined,
                onPressed: ro
                    ? null
                    : () => _numero(
                        'Carga de refrigerante',
                        'kg',
                        _e.cargaKg,
                        (v) => _e.copyWith(cargaKg: Value(v)),
                      ),
              ),
              siNo(
                'Hermético y etiquetado',
                _e.hermeticoEtiquetado,
                (v) => _e.copyWith(hermeticoEtiquetado: Value(v)),
              ),
              siNo(
                'Sistema de detección de fugas',
                _e.deteccionFugas,
                (v) => _e.copyWith(deteccionFugas: Value(v)),
              ),
              const SizedBox(height: Gap.xl),
            ],
          ),
        ),
        if (!ro)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: BotonPrimario(
                key: const Key('guardar_ficha'),
                texto: _cambios || widget.ficha.equipo.categoriaFgas == null
                    ? 'Guardar y confirmar'
                    : 'Confirmar datos',
                icono: Icons.save_outlined,
                onPressed: _guardar,
              ),
            ),
          ),
      ],
    );
  }
}

/// Lo que se sabe de visitas anteriores (de `estado_equipo`, aunque la
/// última visita tenga años).
class _UltimaVisita extends StatelessWidget {
  const _UltimaVisita(this.f);
  final FichaEquipo f;

  @override
  Widget build(BuildContext context) {
    final h = f.hechos!;
    final claves = h.ultimosValores.keys.toList()..sort();
    return Column(
      key: const Key('ultima_visita'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Seccion('Últimos valores'),
        if (h.ultimoPreventivoAt != null)
          Text('Último preventivo: ${fmt.fecha(h.ultimoPreventivoAt!)}'),
        if (h.ultimoControlFugasAt != null)
          Text(
            'Último control de fugas: ${fmt.fecha(h.ultimoControlFugasAt!)} · '
            '${h.ultimoResultadoFugas == 'fuga' ? 'con fuga' : 'sin fuga'}',
          ),
        for (final k in claves)
          Text(
            '${f.textosItem[k] ?? k}: '
            '${fmt.numero(h.ultimosValores[k]!.valor)} '
            '${h.ultimosValores[k]!.unidad ?? ''} '
            '(${fmt.fecha(h.ultimosValores[k]!.fecha)})',
          ),
        if (claves.isEmpty) const Text('Sin valores medidos anteriores.'),
      ],
    );
  }
}
