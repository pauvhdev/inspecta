import 'package:flutter/material.dart';

import '../core/env.dart';
import '../design/theme.dart';
import '../features/hoy/hoy_pantalla.dart';

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
      home: const HoyPantalla(),
    );
  }
}
