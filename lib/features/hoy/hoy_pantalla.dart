import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/formato.dart' as fmt;
import '../../data/repositories/inspeccion_repository.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../textos.dart';
import '../visita/visita_pantalla.dart';

/// T1 Hoy (DISEÑO.md §6.1): las órdenes del día en tarjetas de 88 dp o más.
class HoyPantalla extends ConsumerStatefulWidget {
  const HoyPantalla({super.key});

  @override
  ConsumerState<HoyPantalla> createState() => _HoyPantallaState();
}

class _HoyPantallaState extends ConsumerState<HoyPantalla> {
  /// Nunca un «cargando» infinito (DISEÑO.md §13): en navegadores sin
  /// SharedWorker la base web puede no abrir nunca, y hay que decirlo.
  static const _tiempoMaximo = Duration(seconds: 10);

  Timer? _reloj;
  bool _tardaDemasiado = false;

  @override
  void initState() {
    super.initState();
    _reloj = Timer(_tiempoMaximo, () {
      if (mounted) setState(() => _tardaDemasiado = true);
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ordenes = ref.watch(ordenesHoyProvider);
    final theme = Theme.of(context);
    final hoy = fmt.fecha(ref.watch(relojProvider)());

    return Scaffold(
      appBar: AppBar(title: Text('Hoy · $hoy'), bottom: barraSync()),
      body: ordenes.when(
        data: (lista) => lista.isEmpty
            ? _Vacio(sesion: ref.watch(sesionProvider) != null)
            : ListView.separated(
                padding: const EdgeInsets.all(Gap.lg),
                itemCount: lista.length,
                separatorBuilder: (_, _) => const SizedBox(height: Gap.md),
                itemBuilder: (_, i) => _TarjetaOrden(lista[i]),
              ),
        loading: () => Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Text(
            _tardaDemasiado
                ? 'La base de datos local no termina de abrir. Este '
                      'navegador puede no ser compatible: prueba con Chrome '
                      'de escritorio o con la app de Android.'
                : 'Abriendo la base de datos local…',
            key: const Key('cargando'),
            style: _tardaDemasiado
                ? TextStyle(color: theme.colorScheme.error)
                : theme.textTheme.bodyLarge,
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Text(
            'No se pudo abrir la base de datos local: $e',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({required this.sesion});
  final bool sesion;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Gap.xl),
    child: Text(
      sesion
          ? 'No tienes órdenes para hoy.'
          : 'Modo local sin datos. Para ver la demo, arranca con '
                '--dart-define=INSPECTA_DEMO=true.',
      key: const Key('hoy_vacio'),
      style: Theme.of(context).textTheme.bodyLarge,
    ),
  );
}

class _TarjetaOrden extends StatelessWidget {
  const _TarjetaOrden(this.t);
  final TarjetaOrden t;

  Future<void> _abrirMapa(String direccion) async {
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': direccion,
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inst = t.instalacion;
    final detalle = [
      '${t.nEquipos} ${t.nEquipos == 1 ? 'equipo' : 'equipos'}',
      textoIntervencion(t.tipo),
      if (!t.esDeHoy && t.orden.fechaPrevista != null)
        'prevista el ${fmt.soloFecha(t.orden.fechaPrevista!)}',
      if (t.inspeccion != null && t.inspeccion!.firmadaAt == null)
        'empezada a las ${fmt.hora(t.inspeccion!.iniciadaAt)}',
    ].join(' · ');
    return Card(
      key: Key('orden_${t.orden.id}'),
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: Radii.brMd,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VisitaPantalla(ordenId: t.orden.id),
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Touch.captura),
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                etiquetaEstadoOrden(t.estado, sinSubir: t.sinSubir),
                const SizedBox(height: Gap.sm),
                Text(
                  t.cliente?.razonSocial ?? 'Cliente desconocido',
                  style: theme.textTheme.titleLarge,
                ),
                if (inst != null) Text(inst.nombre),
                const SizedBox(height: Gap.xs),
                Text(detalle, style: theme.textTheme.bodyMedium),
                if (inst?.direccion != null) ...[
                  const SizedBox(height: Gap.sm),
                  BotonSecundario(
                    texto: inst!.direccion!,
                    icono: Icons.map_outlined,
                    onPressed: () => _abrirMapa(inst.direccion!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
