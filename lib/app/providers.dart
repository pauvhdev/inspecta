import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/env.dart';
import '../data/local/app_database.dart';
import '../data/sync/outbox.dart';

// Providers mínimos del día 1 (DISEÑO.md §8.6).
//
// Se toma el patrón de Forja (modo local / nube), pero el fichero se escribe
// nuevo: el de Forja arrastra 42 imports de funciones propias. Aquí se irán
// añadiendo repositorios, sincronización e IA a medida que existan.

/// Cómo está funcionando la app ahora mismo.
enum AppMode {
  /// Con Supabase: inicio de sesión real y sincronización.
  cloud,

  /// Sin backend configurado: todo vive en el aparato. Es el modo de la demo
  /// pública y, además, la red de seguridad: si Supabase no responde, el
  /// técnico sigue pudiendo hacer el parte.
  local,
}

/// Id ficticio del usuario en modo local. Es un UUID válido para que las filas
/// tengan ya la forma que tendrán en la nube.
const localUserId = '00000000-0000-4000-8000-000000000001';

final appModeProvider = Provider<AppMode>(
  (ref) => Env.isConfigured ? AppMode.cloud : AppMode.local,
);

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final outboxProvider = Provider<Outbox>(
  (ref) => Outbox(ref.watch(databaseProvider)),
);

/// Cambios pendientes de subir (sin contar los bloqueados). Alimenta la
/// píldora «Sin conexión · N sin subir».
final pendientesDeSubirProvider = StreamProvider<int>(
  (ref) => ref.watch(outboxProvider).watchPendingCount(),
);
