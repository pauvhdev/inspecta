import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signature/signature.dart';

import '../../data/repositories/inspeccion_repository.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';

// T13 Firma (DISEÑO.md §6.1): a pantalla completa, apaisada en el móvil y
// fuera de cualquier lista con scroll. Solo se guarda el PNG (§10).

/// Paso previo de la firma del cliente: nombre y cargo.
class FirmaClientePantalla extends StatefulWidget {
  const FirmaClientePantalla({super.key, this.nombreInicial});
  final String? nombreInicial;

  @override
  State<FirmaClientePantalla> createState() => _FirmaClienteState();
}

class _FirmaClienteState extends State<FirmaClientePantalla> {
  late final _nombre = TextEditingController(
    text: widget.nombreInicial?.replaceAll(RegExp(r'\s*\(.*\)$'), ''),
  );
  final _cargo = TextEditingController();

  @override
  void dispose() {
    _nombre.dispose();
    _cargo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Firma del cliente')),
    body: ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        TextField(
          key: const Key('firma_nombre'),
          controller: _nombre,
          decoration: const InputDecoration(labelText: 'Nombre de quien firma'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Gap.md),
        TextField(
          key: const Key('firma_cargo'),
          controller: _cargo,
          decoration: const InputDecoration(labelText: 'Cargo'),
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: BotonPrimario(
          key: const Key('firma_continuar'),
          texto: 'Pasar el móvil al cliente',
          icono: Icons.draw,
          onPressed: _nombre.text.trim().isEmpty
              ? null
              : () async {
                  final f = await Navigator.of(context).push<FirmaCapturada>(
                    MaterialPageRoute(
                      builder: (_) => FirmaPantalla(
                        titulo: 'Firma del cliente',
                        explicacion:
                            '${_nombre.text.trim()}'
                            '${_cargo.text.trim().isEmpty ? '' : ', ${_cargo.text.trim()}'}. '
                            'Firma electrónica simple. El titular conservará '
                            'este informe al menos 5 años.',
                        nombre: _nombre.text.trim(),
                        cargo: _cargo.text.trim(),
                      ),
                    ),
                  );
                  if (f != null && context.mounted) {
                    Navigator.of(context).pop(f);
                  }
                },
          motivoInactivo: 'Escribe el nombre de quien firma.',
        ),
      ),
    ),
  );
}

/// El lienzo de la firma.
class FirmaPantalla extends StatefulWidget {
  const FirmaPantalla({
    super.key,
    required this.titulo,
    required this.explicacion,
    required this.nombre,
    this.cargo,
  });

  final String titulo;
  final String explicacion;
  final String nombre;
  final String? cargo;

  @override
  State<FirmaPantalla> createState() => _FirmaPantallaState();
}

class _FirmaPantallaState extends State<FirmaPantalla> {
  final _c = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  @override
  void initState() {
    super.initState();
    // Apaisada en el móvil; la web y las pruebas lo ignoran.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _c.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const []);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.titulo)),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.explicacion, key: const Key('firma_explicacion')),
            const SizedBox(height: Gap.sm),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: InspectaColors.borderLight,
                    width: 2,
                  ),
                  borderRadius: Radii.brMd,
                ),
                child: ClipRRect(
                  borderRadius: Radii.brMd,
                  child: Signature(
                    key: const Key('lienzo_firma'),
                    controller: _c,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: Touch.primary,
                    child: OutlinedButton.icon(
                      onPressed: _c.isEmpty ? null : _c.clear,
                      icon: const Icon(Icons.backspace_outlined),
                      label: const Text('Borrar'),
                    ),
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: Touch.primary,
                    child: FilledButton.icon(
                      key: const Key('firma_confirmar'),
                      onPressed: _c.isEmpty
                          ? null
                          : () async {
                              final png = await _c.toPngBytes();
                              if (png == null || !context.mounted) return;
                              Navigator.of(context).pop(
                                FirmaCapturada(
                                  nombre: widget.nombre,
                                  cargo: widget.cargo,
                                  png: png,
                                ),
                              );
                            },
                      icon: const Icon(Icons.check),
                      label: const Text('Confirmar'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
