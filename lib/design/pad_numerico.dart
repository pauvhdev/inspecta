import 'package:flutter/material.dart';

import '../core/formato.dart' as fmt;
import 'tokens.dart';

// Teclado numérico propio (§6.0: «sin teclado del sistema para números»).
// Teclas de 72 dp. El +/− fino y grueso y el rango plausible de T6 llegan el
// día 4 sobre esta misma pieza.

/// Lo que devuelve [pedirNumero].
sealed class ResultadoNumero {
  const ResultadoNumero();
}

/// Un valor.
final class NumeroElegido extends ResultadoNumero {
  const NumeroElegido(this.valor);
  final double valor;
}

/// «Sin dato»: vacía el campo.
final class NumeroBorrado extends ResultadoNumero {
  const NumeroBorrado();
}

/// Abre el teclado en una hoja inferior. Null si se cierra sin elegir.
Future<ResultadoNumero?> pedirNumero(
  BuildContext context, {
  required String titulo,
  String? unidad,
  double? inicial,
  double? rangoMin,
  double? rangoMax,
  String? referencia,
}) => showModalBottomSheet<ResultadoNumero>(
  context: context,
  isScrollControlled: true,
  builder: (_) => PadNumerico(
    titulo: titulo,
    unidad: unidad,
    inicial: inicial,
    rangoMin: rangoMin,
    rangoMax: rangoMax,
    referencia: referencia,
  ),
);

class PadNumerico extends StatefulWidget {
  const PadNumerico({
    super.key,
    required this.titulo,
    this.unidad,
    this.inicial,
    this.rangoMin,
    this.rangoMax,
    this.referencia,
  });

  final String titulo;
  final String? unidad;
  final double? inicial;

  /// Rango plausible (T6): fuera de él avisa, no bloquea.
  final double? rangoMin;
  final double? rangoMax;

  /// «Última vez: 24,5 °C (15/12/2025)», de `estado_equipo`.
  final String? referencia;

  @override
  State<PadNumerico> createState() => _PadNumericoState();
}

class _PadNumericoState extends State<PadNumerico> {
  late String _texto = widget.inicial == null
      ? ''
      : fmt.numero(widget.inicial!, decimales: 3);

  /// +/− fino y grueso (base `set_pad.dart` de Forja) y cambio de signo.
  void _sumar(double d) => setState(() {
    final v = (_valor ?? 0) + d;
    _texto = fmt.numero((v * 1000).roundToDouble() / 1000, decimales: 3);
  });

  void _pulsar(String t) {
    setState(() {
      if (t == '±') {
        _texto = _texto.startsWith('-')
            ? _texto.substring(1)
            : (_texto.isEmpty ? '-' : '-$_texto');
      } else if (t == '⌫') {
        if (_texto.isNotEmpty) _texto = _texto.substring(0, _texto.length - 1);
      } else if (t == ',') {
        if (!_texto.contains(',')) {
          _texto = _texto.isEmpty || _texto == '-' ? '${_texto}0,' : '$_texto,';
        }
      } else if (_texto.length < 8) {
        _texto = _texto == '0'
            ? t
            : _texto == '-0'
            ? '-$t'
            : '$_texto$t';
      }
    });
  }

  double? get _valor => _texto.isEmpty || _texto == '-' || _texto.endsWith(',')
      ? null
      : double.tryParse(_texto.replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    Widget tecla(String t) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xs),
        child: SizedBox(
          height: Touch.primary,
          child: OutlinedButton(
            key: Key('tecla_$t'),
            onPressed: () => _pulsar(t),
            child: Text(t, style: const TextStyle(fontSize: 28)),
          ),
        ),
      ),
    );
    Widget paso(String t, double d) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xs),
        child: SizedBox(
          height: Touch.min,
          child: OutlinedButton(
            key: Key('paso_$t'),
            onPressed: () => _sumar(d),
            child: Text(t),
          ),
        ),
      ),
    );
    final v = _valor;
    final min = widget.rangoMin, max = widget.rangoMax;
    final fuera =
        v != null && min != null && max != null && (v < min || v > max);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.titulo, style: tema.textTheme.titleLarge),
            const SizedBox(height: Gap.md),
            Text(
              _texto.isEmpty ? '—' : '$_texto ${widget.unidad ?? ''}'.trim(),
              key: const Key('pad_valor'),
              textAlign: TextAlign.center,
              style: tema.textTheme.displaySmall?.copyWith(
                fontFeatures: tabularFigures,
              ),
            ),
            if (widget.referencia != null)
              Text(widget.referencia!, textAlign: TextAlign.center),
            if (fuera)
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm),
                child: Text(
                  'Fuera del rango habitual (${fmt.numero(min)} a '
                  '${fmt.numero(max)} ${widget.unidad ?? ''}): compruébalo. '
                  'Se puede guardar igual.',
                  key: const Key('pad_fuera_rango'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tema.colorScheme.error),
                ),
              ),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                paso('−1', -1),
                paso('−0,1', -0.1),
                paso('+0,1', 0.1),
                paso('+1', 1),
              ],
            ),
            for (final fila in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['±', '0', ','],
              ['⌫'],
            ])
              Row(children: [for (final t in fila) tecla(t)]),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: Touch.primary,
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, const NumeroBorrado()),
                      child: const Text('Sin dato'),
                    ),
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: Touch.primary,
                    child: FilledButton(
                      key: const Key('pad_aceptar'),
                      onPressed: _valor == null
                          ? null
                          : () =>
                                Navigator.pop(context, NumeroElegido(_valor!)),
                      child: const Text(
                        'Aceptar',
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
