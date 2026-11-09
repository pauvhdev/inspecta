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
}) => showModalBottomSheet<ResultadoNumero>(
  context: context,
  isScrollControlled: true,
  builder: (_) => PadNumerico(titulo: titulo, unidad: unidad, inicial: inicial),
);

class PadNumerico extends StatefulWidget {
  const PadNumerico({
    super.key,
    required this.titulo,
    this.unidad,
    this.inicial,
  });

  final String titulo;
  final String? unidad;
  final double? inicial;

  @override
  State<PadNumerico> createState() => _PadNumericoState();
}

class _PadNumericoState extends State<PadNumerico> {
  late String _texto = widget.inicial == null
      ? ''
      : fmt.numero(widget.inicial!, decimales: 3);

  void _pulsar(String t) {
    setState(() {
      if (t == '⌫') {
        if (_texto.isNotEmpty) _texto = _texto.substring(0, _texto.length - 1);
      } else if (t == ',') {
        if (!_texto.contains(',')) _texto = _texto.isEmpty ? '0,' : '$_texto,';
      } else if (_texto.length < 8) {
        _texto = _texto == '0' ? t : '$_texto$t';
      }
    });
  }

  double? get _valor => _texto.isEmpty || _texto.endsWith(',')
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
    return SafeArea(
      child: Padding(
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
            const SizedBox(height: Gap.md),
            for (final fila in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              [',', '0', '⌫'],
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
