import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../app/providers.dart';
import '../../core/formato.dart' as fmt;
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../informe/generar.dart';

/// T14 Informe (DISEÑO.md §6.1): número, versión, hash corto, estado de
/// subida, ver el PDF y compartirlo. El PDF ya existe: se generó una vez al
/// firmar y no se regenera (§7.10.6).
class InformePantalla extends ConsumerStatefulWidget {
  const InformePantalla({super.key, required this.inspeccionId});
  final String inspeccionId;

  @override
  ConsumerState<InformePantalla> createState() => _InformePantallaState();
}

class _InformePantallaState extends ConsumerState<InformePantalla> {
  bool _completando = false;

  /// Si la app se cerró entre la firma y el PDF, se termina aquí.
  Future<void> _completar() async {
    if (_completando) return;
    _completando = true;
    await ref
        .read(inspeccionRepositoryProvider)!
        .completarCierre(
          widget.inspeccionId,
          esDemo: ref.read(esDemoProvider),
          generarPdf: generarPdfInforme,
        );
  }

  Future<Uint8List> _pdf() async => (await ref
      .read(inspeccionRepositoryProvider)!
      .bytesDe(widget.inspeccionId))!;

  @override
  Widget build(BuildContext context) {
    final informe = ref.watch(informeProvider(widget.inspeccionId)).value;
    if (informe == null) {
      return const Scaffold(body: Center(child: Text('Abriendo el informe…')));
    }
    final (i, sinSubir) = informe;
    if (i.firmadaAt != null && i.pdfSha256 == null) {
      _completar();
      return const Scaffold(
        body: Center(child: Text('Terminando el PDF en el aparato…')),
      );
    }
    final theme = Theme.of(context);
    final nombre = 'informe_${i.numero ?? i.id}.pdf';
    return Scaffold(
      appBar: AppBar(title: const Text('Informe'), bottom: barraSync()),
      body: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          Text('Informe n.º', style: theme.textTheme.bodyMedium),
          Text(
            i.numero ?? '—',
            key: const Key('numero_informe'),
            style: theme.textTheme.headlineMedium,
          ),
          Text(
            'Versión ${i.version} · firmado el ${fmt.fecha(i.firmadaAt!)} a las ${fmt.hora(i.firmadaAt!)}',
          ),
          const SizedBox(height: Gap.md),
          sinSubir
              ? const Etiqueta(
                  texto: 'Firmado · pendiente de subir',
                  icono: Icons.cloud_upload_outlined,
                  color: InspectaColors.pending,
                  fondo: InspectaColors.pendingBg,
                )
              : const Etiqueta(
                  texto: 'Firmado y subido',
                  icono: Icons.cloud_done_outlined,
                  color: InspectaColors.ok,
                  fondo: InspectaColors.okBg,
                ),
          const Seccion('Huellas'),
          Text(
            'Contenido: ${i.contenidoSha256?.substring(0, 16) ?? '—'}…',
            style: const TextStyle(fontFeatures: tabularFigures),
          ),
          Text(
            'PDF: ${i.pdfSha256?.substring(0, 16) ?? '—'}…',
            style: const TextStyle(fontFeatures: tabularFigures),
          ),
          const SizedBox(height: Gap.sm),
          const Text(
            'Lo firmado ya no se puede cambiar: ni el contenido, ni el PDF, ni '
            'el número.',
          ),
          const SizedBox(height: Gap.xl),
          BotonPrimario(
            key: const Key('ver_pdf'),
            texto: kIsWeb ? 'Abrir PDF' : 'Ver PDF',
            icono: Icons.picture_as_pdf_outlined,
            onPressed: () async {
              final bytes = await _pdf();
              await Printing.layoutPdf(
                onLayout: (_) async => bytes,
                name: nombre,
              );
            },
          ),
          const SizedBox(height: Gap.md),
          BotonPrimario(
            key: const Key('compartir_pdf'),
            texto: kIsWeb ? 'Descargar PDF' : 'Compartir',
            icono: kIsWeb ? Icons.download : Icons.share,
            onPressed: () async {
              final bytes = await _pdf();
              await Printing.sharePdf(bytes: bytes, filename: nombre);
              // En la web es una descarga; en Android, la hoja de compartir
              // no dice qué app se eligió y no se inventa el canal.
              if (kIsWeb) {
                await ref
                    .read(inspeccionRepositoryProvider)!
                    .anotarComparticion(i.id, 'descarga');
              }
            },
          ),
        ],
      ),
    );
  }
}
