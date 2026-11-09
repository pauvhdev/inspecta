import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/inspeccion_repository.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../informe/calculo_informe.dart';
import '../../informe/generar.dart';
import '../checklist/checklist_pantalla.dart';
import 'firma_pantalla.dart';
import 'informe_pantalla.dart';

/// T12 Revisar y firmar (DISEÑO.md §6.1, F4.1): pendientes pulsables que
/// bloquean, resumen determinista editable y próximos vencimientos.
class RevisarPantalla extends ConsumerStatefulWidget {
  const RevisarPantalla({super.key, required this.ordenId});
  final String ordenId;

  @override
  ConsumerState<RevisarPantalla> createState() => _RevisarPantallaState();
}

class _RevisarPantallaState extends ConsumerState<RevisarPantalla> {
  final _resumen = TextEditingController();
  bool _resumenTocado = false;
  bool _firmando = false;

  @override
  void dispose() {
    _resumen.dispose();
    super.dispose();
  }

  Future<void> _firmar(RevisionVisita rv) async {
    final repo = ref.read(inspeccionRepositoryProvider)!;
    final n = ref.read(normativaProvider).value!;
    final serie = ref.read(serieAparatoProvider);
    if (serie == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este aparato aún no tiene serie de numeración.'),
        ),
      );
      return;
    }
    final v = rv.visita;
    final cliente = await Navigator.of(context).push<FirmaCapturada>(
      MaterialPageRoute(
        builder: (_) =>
            FirmaClientePantalla(nombreInicial: v.cliente?.contactoNombre),
      ),
    );
    if (cliente == null || !mounted) return;
    final miembro = await repo.miembroActual();
    if (!mounted) return;
    final tecnico = await Navigator.of(context).push<FirmaCapturada>(
      MaterialPageRoute(
        builder: (_) => FirmaPantalla(
          titulo: 'Firma del técnico',
          explicacion:
              'Firmo como ${miembro?.nombre ?? 'técnico'}'
              '${miembro?.carneRite == null ? '' : ' (carné n.º ${miembro!.carneRite})'}.',
          nombre: miembro?.nombre ?? 'Técnico',
        ),
      ),
    );
    if (tecnico == null || !mounted) return;
    setState(() => _firmando = true);
    final ahora = ref.read(relojProvider)();
    final controles = {
      for (final ch in rv.checklists)
        ch.equipo.id: ch.controles.isEmpty ? null : ch.controles.last.resultado,
    };
    final insp = await repo.firmar(
      inspeccionId: v.inspeccion!.id,
      resumen: _resumen.text,
      cliente: cliente,
      tecnico: tecnico,
      normativaVersion: n.version,
      serie: serie.$1,
      letra: serie.$2,
      datosEquipo: (e, h) => datosEquipoParaInforme(
        n,
        equipo: e,
        instalacion: v.instalacion,
        equiposInstalacion: v.equiposInstalacion,
        hechos: h,
        esPreventivo: esPreventivo(v),
        resultadoFugas: controles[e.id],
        firmadaAt: ahora,
      ),
    );
    await repo.completarCierre(
      insp.id,
      esDemo: ref.read(esDemoProvider),
      generarPdf: generarPdfInforme,
    );
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => InformePantalla(inspeccionId: insp.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rv = ref.watch(revisionProvider(widget.ordenId)).value;
    final n = ref.watch(normativaProvider).value;
    if (rv == null || n == null) {
      return const Scaffold(
        body: Center(child: Text('Preparando la revisión…')),
      );
    }
    if (!_resumenTocado) {
      _resumen.text = resumenDeterminista(rv.visita, rv.checklists);
    }
    final ahora = ref.watch(relojProvider)();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar y firmar'),
        bottom: barraSync(),
      ),
      body: _firmando
          ? const Padding(
              padding: EdgeInsets.all(Gap.xl),
              child: Text(
                'Firmando y generando el PDF en el aparato…',
                key: Key('generando_pdf'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(Gap.lg),
              children: [
                Seccion(
                  rv.pendientes.isEmpty
                      ? 'Todo respondido'
                      : 'Falta para firmar (${rv.pendientes.length})',
                ),
                if (rv.pendientes.isEmpty)
                  const Text('No falta nada obligatorio.'),
                for (final p in rv.pendientes.take(30))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.all(Gap.md),
                        ),
                        onPressed: p.inspeccionEquipoId == null
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ChecklistPantalla(
                                    inspeccionEquipoId: p.inspeccionEquipoId!,
                                    indiceInicial: p.indiceItem,
                                  ),
                                ),
                              ),
                        child: Text(
                          '${p.equipo}: ${p.texto}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (rv.pendientes.length > 30)
                  Text('… y ${rv.pendientes.length - 30} más.'),
                const Seccion('Resumen (editable)'),
                TextField(
                  key: const Key('resumen'),
                  controller: _resumen,
                  maxLines: 6,
                  onChanged: (_) => _resumenTocado = true,
                ),
                const Seccion('Próximos vencimientos tras esta visita'),
                for (final ch in rv.checklists)
                  Builder(
                    builder: (_) {
                      final d = datosEquipoParaInforme(
                        n,
                        equipo: ch.equipo,
                        instalacion: rv.visita.instalacion,
                        equiposInstalacion: rv.visita.equiposInstalacion,
                        hechos: ch.hechos,
                        esPreventivo: esPreventivo(rv.visita),
                        resultadoFugas: ch.controles.isEmpty
                            ? null
                            : ch.controles.last.resultado,
                        firmadaAt: ahora,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: Gap.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${d['nombre']}',
                              style: theme.textTheme.titleSmall,
                            ),
                            Text('F-gas: ${(d['fgas']! as Map)['titular']}'),
                            Text('RITE: ${d['rite']}'),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: Gap.xl),
              ],
            ),
      bottomNavigationBar: _firmando
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: BotonPrimario(
                  key: const Key('ir_a_firmar'),
                  texto: 'Firmar',
                  icono: Icons.draw,
                  onPressed: rv.pendientes.isEmpty && rv.visita.editable
                      ? () => _firmar(rv)
                      : null,
                  motivoInactivo: rv.pendientes.isEmpty
                      ? 'La visita no se puede firmar.'
                      : 'Completa lo que falta para firmar.',
                ),
              ),
            ),
    );
  }
}
