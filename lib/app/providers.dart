import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/env.dart';
import '../data/local/app_database.dart';
import '../data/local/siembra.dart';
import '../data/repositories/demo_datos.dart';
import '../data/repositories/inspeccion_repository.dart';
import '../data/sync/outbox.dart';
import '../dominio/normativa.dart';
import '../dominio/plantillas.dart' as dom;

// Providers de la app (DISEÑO.md §8.6).
//
// Se toma el patrón de Forja (modo local / nube), pero el fichero se escribe
// nuevo: el de Forja arrastra 42 imports de funciones propias. Aquí se irán
// añadiendo sincronización e IA a medida que existan.

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

/// Demo pública: modo local compilado con `INSPECTA_DEMO=true` (§11.1).
final esDemoProvider = Provider<bool>(
  (ref) => Env.demo && ref.watch(appModeProvider) == AppMode.local,
);

/// El reloj, para poder fijarlo en las pruebas.
final relojProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final outboxProvider = Provider<Outbox>(
  (ref) => Outbox(ref.watch(databaseProvider)),
);

/// Cambios pendientes de subir (sin contar los bloqueados). Alimenta la
/// píldora «N sin subir».
final pendientesDeSubirProvider = StreamProvider<int>(
  (ref) => ref.watch(outboxProvider).watchPendingCount(),
);

/// La normativa versionada del bundle (§7.3). Funciona sin red.
final normativaProvider = FutureProvider<Normativa>((ref) => cargarNormativa());

/// Las plantillas base del bundle (§7.4).
final plantillasBaseProvider = FutureProvider<List<dom.Plantilla>>(
  (ref) => dom.cargarPlantillasBase(),
);

/// Quién usa la app. En la demo, el técnico ficticio; en la nube saldrá de
/// la sesión de Supabase y su fila de `miembros` (día 9). En modo local sin
/// demo no hay nadie: Hoy lo explica.
final sesionProvider = Provider<Sesion?>(
  (ref) => ref.watch(esDemoProvider) ? DemoDatos.sesion : null,
);

/// Lo que hay que hacer antes de enseñar Hoy: en modo local, las plantillas
/// base en Drift; en la demo, además, sus datos (solo la primera vez).
final arranqueProvider = FutureProvider<void>((ref) async {
  if (ref.watch(appModeProvider) != AppMode.local) return;
  final db = ref.watch(databaseProvider);
  final plantillas = await ref.watch(plantillasBaseProvider.future);
  await sembrarPlantillasBase(db, plantillas);
  if (ref.watch(esDemoProvider)) {
    await DemoDatos.sembrarSiFalta(
      db,
      normativa: await ref.watch(normativaProvider.future),
      plantillas: plantillas,
      ahora: ref.watch(relojProvider)(),
    );
  }
});

final inspeccionRepositoryProvider = Provider<InspeccionRepository?>((ref) {
  final sesion = ref.watch(sesionProvider);
  if (sesion == null) return null;
  return InspeccionRepository(
    ref.watch(databaseProvider),
    ref.watch(outboxProvider),
    sesion: sesion,
    ahora: ref.watch(relojProvider),
  );
});

/// T1 Hoy. Lista vacía si no hay sesión.
final ordenesHoyProvider = StreamProvider<List<TarjetaOrden>>((ref) async* {
  await ref.watch(arranqueProvider.future);
  final repo = ref.watch(inspeccionRepositoryProvider);
  if (repo == null) {
    yield const [];
    return;
  }
  yield* repo.watchHoy();
});

/// T2 Visita de una orden.
final visitaProvider = StreamProvider.family<VistaVisita?, String>(
  (ref, ordenId) =>
      ref.watch(inspeccionRepositoryProvider)!.watchVisita(ordenId),
);

/// T3 Ficha de un equipo.
final fichaProvider = StreamProvider.family<FichaEquipo?, String>(
  (ref, equipoId) =>
      ref.watch(inspeccionRepositoryProvider)!.watchFicha(equipoId),
);

/// T5 Checklist de un `inspeccion_equipos`.
final checklistProvider = StreamProvider.family<ChecklistEquipo?, String>(
  (ref, ieId) => ref.watch(inspeccionRepositoryProvider)!.watchChecklist(ieId),
);
