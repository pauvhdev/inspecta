import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/env.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import 'providers.dart';

class InspectaApp extends StatelessWidget {
  const InspectaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Env.appName,
      debugShowCheckedModeBanner: false,
      // Sol por defecto (DISEÑO.md §6.0). El cambio a Sótano llegará con los
      // ajustes del aparato (T16); de momento sigue al sistema solo si este
      // pide oscuro.
      theme: InspectaTheme.sol,
      darkTheme: InspectaTheme.sotano,
      themeMode: ThemeMode.light,
      home: const _ArranquePantalla(),
    );
  }
}

/// Pantalla provisional del día 1: comprueba que la base local abre y que la
/// cola de salida responde, en Android y en web. La sustituye «Hoy» (T1).
class _ArranquePantalla extends ConsumerStatefulWidget {
  const _ArranquePantalla();

  @override
  ConsumerState<_ArranquePantalla> createState() => _ArranquePantallaState();
}

class _ArranquePantallaState extends ConsumerState<_ArranquePantalla> {
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
    final modo = ref.watch(appModeProvider);
    final pendientes = ref.watch(pendientesDeSubirProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(Env.appName)),
      body: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Partes e inspecciones de climatización, también sin cobertura.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: Gap.xl),
            Text(
              modo == AppMode.local
                  ? 'Modo local: todo se guarda en este aparato.'
                  : 'Conectado a la nube.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: Gap.md),
            pendientes.when(
              data: (n) => Text(
                'Cambios sin subir: $n',
                key: const Key('pendientes'),
                style: theme.textTheme.bodyLarge,
              ),
              loading: () => Text(
                _tardaDemasiado
                    ? 'La base de datos local no termina de abrir. Este '
                          'navegador puede no ser compatible: prueba con Chrome '
                          'de escritorio o con la app de Android.'
                    : 'Abriendo la base de datos local…',
                key: const Key('cargando'),
                style: _tardaDemasiado
                    ? TextStyle(color: theme.colorScheme.error)
                    : null,
              ),
              error: (e, _) => Text(
                'No se pudo abrir la base de datos local: $e',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
