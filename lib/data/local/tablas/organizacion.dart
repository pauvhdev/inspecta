import 'package:drift/drift.dart';

import '../conversores.dart';
import 'comunes.dart';

// DISEÑO.md §7.1 Organización.

/// La empresa mantenedora. Sin `deleted_at`: una empresa no la borra la
/// oficina.
@DataClassName('Empresa')
class Empresas extends Table with FilaSincronizada {
  /// Igual a `id`. Está para que `empresas` siga la convención de §7 («todas
  /// las tablas sincronizadas llevan `id`, `empresa_id`…»), la regla 6 de
  /// docs/REGLAS.md y la política base de §8.5 (`empresa_id = any(mis_empresas())`),
  /// y así el filtro genérico del pull y de `_idsEnServidor` de reconcile
  /// (§8.2, «el mismo filtro que el pull») le sirva sin excepción. Sin ella,
  /// `empresas` sería la única tabla que necesita filtro y política por `id`,
  /// y olvidar esa excepción dejaría al técnico sin la cabecera del PDF o
  /// haría que reconcile podara la empresa. [A VERIFICAR] §7.1 no la lista:
  /// hay que añadirla allí y en `schema.sql` (día 9) como columna normal, no
  /// generada (el upsert la manda), con `check (empresa_id = id)`.
  TextColumn get empresaId => text()();
  TextColumn get razonSocial => text()();
  TextColumn get cif => text().nullable()();
  TextColumn get nHabilitacionRite => text().nullable()();
  TextColumn get ccaa => text().nullable()();
  TextColumn get nCertificadoFgasEmpresa => text().nullable()();

  /// En el MVP solo la usa la demo (logo como asset); en la nube, null.
  TextColumn get logoRuta => text().nullable()();
  BoolColumn get esDemo => boolean().withDefault(const Constant(false))();
}

/// Personas de la empresa. Sin `deleted_at`: la baja es `activo = false`
/// (§10) y los informes firmados siguen apuntando al técnico.
@DataClassName('Miembro')
class Miembros extends Table with FilaSincronizada {
  TextColumn get empresaId => text()();

  /// `auth.users`. Nulo en la demo local, que no tiene sesión.
  TextColumn get userId => text().nullable()();

  /// `admin|oficina|tecnico`.
  TextColumn get rol => text()();
  TextColumn get nombre => text()();
  TextColumn get carneRite => text().nullable()();

  /// Texto configurable (A1, A2, E, I.1, I.2…), no enum.
  TextColumn get certFgasTipo => text().nullable()();
  TextColumn get certFgasNumero => text().nullable()();
  DateTimeColumn get certFgasCaduca =>
      dateTime().map(const SoloFecha()).nullable()();

  /// «JLM». Nula en quien no firma informes (oficina, admin). La unicidad
  /// por empresa la impone el servidor (ver `comunes.dart`).
  TextColumn get serieInformes => text().nullable()();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();
}

/// Una fila por instalación de la app y usuario (§7.1, §7.9). Solo baja: la
/// crea la RPC `registrar_dispositivo()` y el móvil nunca la sube.
@DataClassName('Dispositivo')
@TableIndex(name: 'dispositivos_miembro', columns: {#miembroId})
class Dispositivos extends Table with FilaSincronizada {
  TextColumn get empresaId => text()();
  TextColumn get miembroId => text()();

  /// A, B, C…: la asigna el servidor.
  TextColumn get letra => text()();
  DateTimeColumn get registradoAt => dateTime()();

  /// Lo mantiene un trigger al recibir un cierre.
  IntColumn get ultimoNumero => integer().withDefault(const Constant(0))();

  /// La pone la RPC `latido()`.
  DateTimeColumn get ultimaSyncAt => dateTime().nullable()();
}
