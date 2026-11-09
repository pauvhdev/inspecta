import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'tokens.dart';

// Piezas comunes de la app del técnico (DISEÑO.md §6.0): objetivos de 56 dp o
// más, acciones primarias de 72 dp, estado con icono + texto + color, y
// botones inactivos que dicen por qué.

/// Acción primaria a todo el ancho (72 dp). Si [onPressed] es null, se
/// enseña inactiva con [motivoInactivo] escrito debajo: nunca se oculta.
class BotonPrimario extends StatelessWidget {
  const BotonPrimario({
    super.key,
    required this.texto,
    required this.onPressed,
    this.icono,
    this.motivoInactivo,
  });

  final String texto;
  final VoidCallback? onPressed;
  final IconData? icono;
  final String? motivoInactivo;

  @override
  Widget build(BuildContext context) {
    final boton = SizedBox(
      width: double.infinity,
      height: Touch.primary,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icono ?? Icons.arrow_forward),
        label: Text(texto, style: const TextStyle(fontSize: 20)),
      ),
    );
    if (onPressed != null || motivoInactivo == null) return boton;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        boton,
        const SizedBox(height: Gap.xs),
        Text(
          motivoInactivo!,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

/// Botón secundario de 56 dp.
class BotonSecundario extends StatelessWidget {
  const BotonSecundario({
    super.key,
    required this.texto,
    required this.onPressed,
    this.icono,
  });

  final String texto;
  final VoidCallback? onPressed;
  final IconData? icono;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: Touch.min,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icono ?? Icons.chevron_right),
      label: Text(texto),
    ),
  );
}

/// Una opción de [Opciones].
class Opcion<T> {
  const Opcion(this.valor, this.texto);
  final T valor;
  final String texto;
}

/// Selección con botones grandes en vez de desplegables (§6.0). La opción
/// elegida lleva icono ✓ además del color.
class Opciones<T> extends StatelessWidget {
  const Opciones({
    super.key,
    required this.opciones,
    required this.seleccionada,
    required this.onChanged,
  });

  final List<Opcion<T>> opciones;
  final T? seleccionada;

  /// Null = solo lectura.
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Wrap(
      spacing: Gap.md,
      runSpacing: Gap.md,
      children: [
        for (final o in opciones)
          SizedBox(
            height: Touch.min,
            child: o.valor == seleccionada
                ? FilledButton.icon(
                    onPressed: onChanged == null
                        ? null
                        : () => onChanged!(o.valor),
                    icon: const Icon(Icons.check),
                    label: Text(o.texto),
                  )
                : OutlinedButton(
                    onPressed: onChanged == null
                        ? null
                        : () => onChanged!(o.valor),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: esquema.onSurface,
                      minimumSize: const Size(Touch.min, Touch.min),
                    ),
                    child: Text(o.texto),
                  ),
          ),
      ],
    );
  }
}

/// Etiqueta de estado: icono + texto + color, nunca solo color.
class Etiqueta extends StatelessWidget {
  const Etiqueta({
    super.key,
    required this.texto,
    required this.icono,
    required this.color,
    required this.fondo,
  });

  final String texto;
  final IconData icono;
  final Color color;
  final Color fondo;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
    decoration: BoxDecoration(color: fondo, borderRadius: Radii.brSm),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 18, color: color),
        const SizedBox(width: Gap.xs),
        Flexible(
          child: Text(
            texto,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// Aviso en una caja (texto siempre visible, con icono).
class Aviso extends StatelessWidget {
  const Aviso(this.texto, {super.key, this.grave = false});
  final String texto;
  final bool grave;

  @override
  Widget build(BuildContext context) {
    final color = grave ? InspectaColors.defecto : InspectaColors.observacion;
    final fondo = grave
        ? InspectaColors.defectoBg
        : InspectaColors.observacionBg;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(color: fondo, borderRadius: Radii.brMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(grave ? Icons.error_outline : Icons.warning_amber, color: color),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(color: Color(0xFF0B0D12)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Título de sección.
class Seccion extends StatelessWidget {
  const Seccion(this.texto, {super.key});
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Gap.xl, bottom: Gap.sm),
    child: Text(texto, style: Theme.of(context).textTheme.titleLarge),
  );
}

/// La píldora debajo de la barra superior, a todo el ancho: en la fila del
/// título no cabe con letra grande en un móvil de 360 dp.
PreferredSizeWidget barraSync() => const PreferredSize(
  preferredSize: Size.fromHeight(_altoBarraSync),
  // Alto fijo: si la píldora ocupara más de lo declarado, la barra de
  // título encogería y la flecha de volver bajaría de 56 dp.
  child: SizedBox(
    height: _altoBarraSync,
    child: Padding(
      padding: EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(fit: BoxFit.scaleDown, child: PildoraSync()),
      ),
    ),
  ),
);

const _altoBarraSync = 48.0;

/// Píldora fija «Modo local · N sin subir» (§6.0, «Sin cobertura»). La parte
/// de la conexión y la de la IA llegan con el `SyncEngine` y la cola de IA.
class PildoraSync extends ConsumerWidget {
  const PildoraSync({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modo = ref.watch(appModeProvider);
    final n = ref.watch(pendientesDeSubirProvider).value;
    final texto = [
      modo == AppMode.local ? 'Modo local' : 'Nube',
      if (n != null) '$n sin subir',
    ].join(' · ');
    return Etiqueta(
      key: const Key('pildora_sync'),
      texto: texto,
      icono: n == null || n == 0
          ? Icons.cloud_done_outlined
          : Icons.cloud_upload_outlined,
      color: InspectaColors.pending,
      fondo: InspectaColors.pendingBg,
    );
  }
}

/// «Marcado como Defecto · Deshacer» durante 5 s (§6.0: deshacer con botón
/// grande en vez de diálogos). El botón mide 56 dp, no el de `SnackBarAction`.
void mostrarDeshacer(
  BuildContext context, {
  required String texto,
  required VoidCallback onDeshacer,
}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 5),
      content: Row(
        children: [
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 18))),
          const SizedBox(width: Gap.md),
          SizedBox(
            height: Touch.min,
            child: FilledButton(
              key: const Key('deshacer'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(Touch.min * 2, Touch.min),
              ),
              onPressed: () {
                m.hideCurrentSnackBar();
                onDeshacer();
              },
              child: const Text('Deshacer'),
            ),
          ),
        ],
      ),
    ),
  );
}
