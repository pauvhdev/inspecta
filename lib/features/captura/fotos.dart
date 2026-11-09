import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../data/local/app_database.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';

// T7 Foto, versión mínima (DISEÑO.md §6.1 y §8.3): cámara del sistema (en la
// web, el selector de archivos), archivo y, en la demo, «Usar foto de
// ejemplo». Pendiente del día 5 completo: miniatura y variante de 1.000 px en
// un isolate, aviso de foto borrosa u oscura, GPS y `retrieveLostData()`.

/// Fotos de ejemplo generadas (`tool/generar_fotos_demo.py`).
const fotosDeEjemplo = <(String, String)>[
  ('assets/demo/etiqueta_fgas.jpg', 'Etiqueta F-gas'),
  ('assets/demo/placa.jpg', 'Placa del equipo'),
  ('assets/demo/filtro.jpg', 'Filtro sucio'),
];

/// Pide una foto y la guarda en la visita. Devuelve el id o null.
Future<String?> tomarFoto(
  BuildContext context,
  WidgetRef ref, {
  required String inspeccionEquipoId,
  String? itemId,
}) async {
  final demo = ref.read(esDemoProvider);
  final origen = await showModalBottomSheet<Object>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          BotonPrimario(
            texto: 'Cámara',
            icono: Icons.photo_camera,
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          const SizedBox(height: Gap.md),
          BotonSecundario(
            texto: 'Elegir un archivo',
            icono: Icons.photo_library_outlined,
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          if (demo) ...[
            const Seccion('Fotos de ejemplo (generadas, no reales)'),
            for (final (ruta, texto) in fotosDeEjemplo)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.md),
                child: BotonSecundario(
                  key: Key('ejemplo_$texto'),
                  texto: 'Usar foto de ejemplo: $texto',
                  icono: Icons.image_outlined,
                  onPressed: () => Navigator.pop(ctx, ruta),
                ),
              ),
          ],
        ],
      ),
    ),
  );
  if (origen == null || !context.mounted) return null;
  Uint8List bytes;
  var mime = 'image/jpeg';
  if (origen is String) {
    bytes = (await rootBundle.load(origen)).buffer.asUint8List();
  } else {
    final x = await ImagePicker().pickImage(
      source: origen as ImageSource,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (x == null) return null;
    bytes = await x.readAsBytes();
    if (x.name.toLowerCase().endsWith('.png')) mime = 'image/png';
  }
  return ref
      .read(inspeccionRepositoryProvider)!
      .guardarFoto(
        inspeccionEquipoId: inspeccionEquipoId,
        itemId: itemId,
        bytes: bytes,
        mime: mime,
      );
}

/// Miniatura de una foto guardada; con [editable], tocarla ofrece borrarla
/// (confirmación explícita, §6.0).
class MiniaturaFoto extends ConsumerWidget {
  const MiniaturaFoto({super.key, required this.foto, required this.editable});
  final Foto foto;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(inspeccionRepositoryProvider)!;
    return SizedBox(
      width: Touch.captura,
      height: Touch.captura,
      child: InkWell(
        borderRadius: Radii.brSm,
        onTap: !editable
            ? null
            : () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('¿Borrar esta foto?'),
                    content: const Text('No saldrá en el informe.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Borrar'),
                      ),
                    ],
                  ),
                );
                if (ok == true) await repo.borrarFoto(foto.id);
              },
        child: ClipRRect(
          borderRadius: Radii.brSm,
          child: FutureBuilder<Uint8List?>(
            future: repo.bytesDe(foto.id),
            builder: (_, s) => s.data == null
                ? const ColoredBox(color: InspectaColors.surfaceHighLight)
                : Image.memory(
                    s.data!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
          ),
        ),
      ),
    );
  }
}
